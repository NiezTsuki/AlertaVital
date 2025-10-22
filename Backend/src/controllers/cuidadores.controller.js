import jwt from 'jsonwebtoken';
import { Resend } from 'resend';

import {
  getUserByCorreo,
  assertUserRole,
  vincularCuidador,
  desvincularCuidador,
  listarCuidadoresDeAdulto,
  listarAdultosDeCuidador,
} from '../services/cuidadores.service.js';

const { JWT_SECRET = 'change_me', RESEND_API_KEY } = process.env;

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

    if (adultoCorreo) adulto = await getUserByCorreo(adultoCorreo);
    if (cuidadorCorreo) cuidador = await getUserByCorreo(cuidadorCorreo);

    if (!adulto) return res.status(404).json({ error: 'Adulto no encontrado por correo' });
    if (!cuidador) return res.status(404).json({ error: 'Cuidador no encontrado por correo' });

    if (!canAct(req.user, [adulto.id, cuidador.id])) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    await assertUserRole(adulto.id, 'ADULTO_MAYOR');
    await assertUserRole(cuidador.id, 'CUIDADOR');
    if (adulto.id === cuidador.id) {
      return res.status(400).json({ error: 'No puedes vincular el mismo usuario' });
    }

    const token = jwt.sign(
      { tipo: 'VINCULACION', adultoId: adulto.id, cuidadorId: cuidador.id, issuerId: req.user.sub },
      JWT_SECRET,
      { expiresIn: 60 * 60 * 24 } // 24h
    );

    const emisor = req.user.rol === 'ADULTO_MAYOR' ? adulto : cuidador;
    const receptor = req.user.rol === 'ADULTO_MAYOR' ? cuidador : adulto;

    try {
      await resend.emails.send({
      from: 'AlertaVital <noreply@alertavital.xyz>',
      to: [receptor.correo],
      subject: `💌 Tienes una invitación para vincularte en AlertaVital`,
      html: `
        <!DOCTYPE html>
        <html lang="es">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <style>
            body { margin: 0; padding: 0; background-color: #f2f0f9; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
            .container { max-width: 600px; margin: 40px auto; background-color: #ffffff; border-radius: 8px; overflow: hidden; box-shadow: 0 4px 15px rgba(0,0,0,0.05); border-top: 5px solid #6A5ACD; }
            .header { text-align: center; padding: 40px 20px 20px 20px; }
            .header img { max-width: 130px; }
            .content { padding: 0 40px 40px 40px; color: #333333; line-height: 1.6; text-align: center; }
            .content h1 { color: #333333; font-size: 24px; margin-bottom: 15px; }
            .content p { margin-bottom: 25px; font-size: 16px; }
            .code-box { background-color: #f2f0f9; border-radius: 8px; padding: 20px; text-align: center; margin: 25px 0; }
            .code { font-size: 20px; font-weight: bold; letter-spacing: 3px; margin: 0; color: #FF6347; /* Rojo/Coral del logo */ word-break: break-all; }
            .footer { padding: 20px; text-align: center; font-size: 12px; color: #777777; background-color: #fafafa; }
          </style>
        </head>
        <body>
          <div class="container">
            <div class="header">
              <img src="https://alerta-vital-ejvs.vercel.app/AlertaVital.png" alt="Logo de AlertaVital">
            </div>
            <div class="content">
              <h1>¡Has recibido una invitación!</h1>
              <p><strong>${emisor.nombre_completo}</strong> te ha invitado a conectar en la aplicación <strong>AlertaVital</strong>.</p>
              <p>Para aceptar, abre la app, ve a "Aceptar Invitación" y pega el siguiente código:</p>
              <div class="code-box">
                <p class="code">${token}</p>
              </div>
              <p style="font-size: 14px; color: #555;">Este código es personal y tiene una validez de 24 horas.</p>
            </div>
            <div class="footer">
              <p>Si no esperabas esta invitación, puedes ignorar este correo de forma segura.</p>
            </div>
          </div>
        </body>
        </html>
      `,
    });
      console.log(`Correo de invitación enviado exitosamente a ${receptor.correo}`);
    } catch (emailError) {
      console.error("Error al enviar el correo con Resend:", emailError);
      return res.status(500).json({ error: 'Se creó la solicitud, pero no se pudo enviar el correo de invitación.' });
    }

    return res.status(201).json({
      ok: true,
      message: 'Solicitud creada. Se ha enviado un correo a la contraparte para que acepte.',
      token,
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