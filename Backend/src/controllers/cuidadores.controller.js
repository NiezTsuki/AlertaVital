// src/controllers/cuidadores.controller.js
import jwt from 'jsonwebtoken';
// 1. Importar Resend
import { Resend } from 'resend';

import {
  getUserByCorreo,
  assertUserRole,
  vincularCuidador,
  desvincularCuidador,
  listarCuidadoresDeAdulto,
  listarAdultosDeCuidador,
} from '../services/cuidadores.service.js';

// 2. Añadir RESEND_API_KEY desde las variables de entorno
const { JWT_SECRET = 'change_me', RESEND_API_KEY } = process.env;

// 3. Crear una instancia de Resend
// Asegúrate de haber añadido RESEND_API_KEY en Vercel
const resend = new Resend(RESEND_API_KEY);

// Permisos básicos: ADMIN, el propio adulto o el propio cuidador
function canAct(reqUser, ids = []) {
  if (!reqUser) return false;
  if (reqUser.rol === 'ADMIN') return true;
  return ids.includes(reqUser.sub);
}

/**
 * POST /api/cuidadores/solicitar
 * Emite un token y envía un correo electrónico a la contraparte.
 */
export async function postSolicitarVinculo(req, res) {
  try {
    let { adultoCorreo, cuidadorCorreo } = req.body || {};
    let adulto, cuidador;

    // Lógica existente para encontrar usuarios
    if (adultoCorreo) adulto = await getUserByCorreo(adultoCorreo);
    if (cuidadorCorreo) cuidador = await getUserByCorreo(cuidadorCorreo);

    if (!adulto) return res.status(404).json({ error: 'Adulto no encontrado por correo' });
    if (!cuidador) return res.status(404).json({ error: 'Cuidador no encontrado por correo' });

    // Lógica de validación
    if (!canAct(req.user, [adulto.id, cuidador.id])) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    await assertUserRole(adulto.id, 'ADULTO_MAYOR');
    await assertUserRole(cuidador.id, 'CUIDADOR');
    if (adulto.id === cuidador.id) {
      return res.status(400).json({ error: 'No puedes vincular el mismo usuario' });
    }

    // Creación del token de invitación
    const token = jwt.sign(
      { tipo: 'VINCULACION', adultoId: adulto.id, cuidadorId: cuidador.id, issuerId: req.user.sub },
      JWT_SECRET,
      { expiresIn: 60 * 60 * 24 } // 24h
    );

    // ✅ 4. Lógica para enviar el correo electrónico
    const emisor = req.user.rol === 'ADULTO_MAYOR' ? adulto : cuidador;
    const receptor = req.user.rol === 'ADULTO_MAYOR' ? cuidador : adulto;

    try {
      await resend.emails.send({
        // IMPORTANTE: Reemplaza con tu dominio verificado en Resend
        from: 'AlertaVital <onboarding@resend.dev>>', 
        to: [receptor.correo],
        subject: `💌 Tienes una invitación para vincularte en AlertaVital`,
        html: `
          <div style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: auto; border: 1px solid #ddd; border-radius: 8px; overflow: hidden;">
            <div style="background-color: #f4f7f6; padding: 20px;">
              <h1 style="color: #0056b3; text-align: center;">Invitación de Vínculo</h1>
            </div>
            <div style="padding: 20px;">
              <h2 style="color: #333;">¡Hola, ${receptor.nombre_completo}!</h2>
              <p>Has recibido una invitación de <strong>${emisor.nombre_completo}</strong> para conectar en la aplicación <strong>AlertaVital</strong>.</p>
              <p>Para aceptar esta invitación y completar el vínculo, por favor, abre la aplicación, ve a la sección <strong>"Aceptar Invitación"</strong> y pega el siguiente código:</p>
              <div style="background-color: #eef2f7; border-radius: 8px; padding: 20px; text-align: center; margin: 25px 0;">
                <p style="font-size: 20px; font-weight: bold; letter-spacing: 3px; margin: 0; color: #0056b3;">${token}</p>
              </div>
              <p>Este código es personal y tiene una validez de 24 horas.</p>
              <p style="margin-top: 30px;">Gracias,<br>El equipo de AlertaVital</p>
            </div>
            <div style="background-color: #f4f7f6; padding: 15px; text-align: center; font-size: 12px; color: #777;">
              <p>Si no esperabas esta invitación, puedes ignorar este correo de forma segura.</p>
            </div>
          </div>
        `,
      });
      console.log(`Correo de invitación enviado exitosamente a ${receptor.correo}`);
    } catch (emailError) {
      console.error("Error al enviar el correo con Resend:", emailError);
      // Opcional: Podrías devolver un error aquí si el envío de correo es crítico,
      // pero por ahora, solo lo registraremos y la API continuará.
    }

    return res.status(201).json({
      ok: true,
      message: 'Solicitud creada. Se ha enviado un correo a la contraparte para que acepte.',
      token, // Aún se devuelve el token por si necesitan compartirlo manualmente
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Error al generar la solicitud de vínculo' });
  }
}

/**
 * POST /api/cuidadores/aceptar
 * Valida token y crea vínculo (idempotente).
 */
export async function postAceptarVinculo(req, res) {
  try {
    const { token } = req.body || {};
    if (!token) return res.status(400).json({ error: 'Token requerido' });

    let payload;
    try {
      payload = jwt.verify(token, JWT_SECRET);
    } catch {
      return res.status(400).json({ error: 'Token inválido o expirado' });
    }
    const { tipo, adultoId, cuidadorId, issuerId } = payload || {};
    if (tipo !== 'VINCULACION') {
      return res.status(400).json({ error: 'Token no corresponde a vinculación' });
    }

    if (req.user.sub === issuerId) {
      return res.status(400).json({ error: 'El emisor no puede aceptar su propia solicitud' });
    }
    const esContraparte = (req.user.sub === adultoId) || (req.user.sub === cuidadorId);
    if (!esContraparte) return res.status(403).json({ error: 'No autorizado para aceptar este vínculo' });

    await assertUserRole(adultoId, 'ADULTO_MAYOR');
    await assertUserRole(cuidadorId, 'CUIDADOR');

    await vincularCuidador({ adultoId, cuidadorId });

    return res.status(201).json({ ok: true, message: 'Vinculación aceptada y creada' });
  } catch (e) {
    if (e.message === 'USER_NOT_FOUND') return res.status(404).json({ error: 'Usuario no encontrado' });
    if (e.message === 'WRONG_ROLE') return res.status(400).json({ error: 'Roles incompatibles' });
    console.error(e);
    return res.status(500).json({ error: 'Error al aceptar vinculación' });
  }
}

/**
 * DELETE /api/cuidadores/:adultoId/:cuidadorId
 */
export async function deleteDesvincular(req, res) {
  try {
    const { adultoId, cuidadorId } = req.params || {};
    if (!adultoId || !cuidadorId) return res.status(400).json({ error: 'Parámetros inválidos' });
    if (!canAct(req.user, [adultoId, cuidadorId])) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    const ok = await desvincularCuidador({ adultoId, cuidadorId });
    return res.json({ ok, message: ok ? 'Desvinculado' : 'No existía el vínculo' });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Error al desvincular' });
  }
}

/**
 * GET /api/cuidadores/de-adulto/:adultoId
 */
export async function getCuidadoresDeAdulto(req, res) {
  try {
    const { adultoId } = req.params || {};
    if (!adultoId) return res.status(400).json({ error: 'adultoId requerido' });

    if (!(req.user?.rol === 'ADMIN' || req.user?.sub === adultoId)) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    await assertUserRole(adultoId, 'ADULTO_MAYOR');

    const data = await listarCuidadoresDeAdulto(adultoId);
    return res.json(data);
  } catch (e) {
    if (e.message === 'USER_NOT_FOUND') return res.status(404).json({ error: 'Adulto no encontrado' });
    if (e.message === 'WRONG_ROLE') return res.status(400).json({ error: 'El id no corresponde a un ADULTO_MAYOR' });
    console.error(e);
    return res.status(500).json({ error: 'Error al listar cuidadores' });
  }
}

/**
 * GET /api/cuidadores/de-cuidador/:cuidadorId
 */
export async function getAdultosDeCuidador(req, res) {
  try {
    const { cuidadorId } = req.params || {};
    if (!cuidadorId) return res.status(400).json({ error: 'cuidadorId requerido' });

    if (!(req.user?.rol === 'ADMIN' || req.user?.sub === cuidadorId)) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    await assertUserRole(cuidadorId, 'CUIDADOR');

    const data = await listarAdultosDeCuidador(cuidadorId);
    return res.json(data);
  } catch (e) {
    if (e.message === 'USER_NOT_FOUND') return res.status(404).json({ error: 'Cuidador no encontrado' });
    if (e.message === 'WRONG_ROLE') return res.status(400).json({ error: 'El id no corresponde a un CUIDADOR' });
    console.error(e);
    return res.status(500).json({ error: 'Error al listar adultos' });
  }
}