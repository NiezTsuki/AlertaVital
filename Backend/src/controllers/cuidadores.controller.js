// src/controllers/cuidadores.controller.js
import jwt from 'jsonwebtoken';
import {
  getUserById,
  getUserByCorreo,
  assertUserRole,
  vincularCuidador,
  desvincularCuidador,
  listarCuidadoresDeAdulto,
  listarAdultosDeCuidador,
} from '../services/cuidadores.service.js';

const { JWT_SECRET = 'change_me' } = process.env;

// Permisos básicos: ADMIN, el propio adulto o el propio cuidador
function canAct(reqUser, ids = []) {
  if (!reqUser) return false;
  if (reqUser.rol === 'ADMIN') return true;
  return ids.includes(reqUser.sub);
}

/**
 * POST /api/cuidadores/solicitar
 * body:
 *  - adultoId | adultoCorreo
 *  - cuidadorId | cuidadorCorreo
 * Emite token corto para que la contraparte acepte.
 */
export async function postSolicitarVinculo(req, res) {
  try {
    let { adultoId, adultoCorreo, cuidadorId, cuidadorCorreo } = req.body || {};

    if (!adultoId && adultoCorreo) {
      const a = await getUserByCorreo(adultoCorreo);
      if (!a) return res.status(404).json({ error: 'Adulto no encontrado por correo' });
      adultoId = a.id;
    }
    if (!cuidadorId && cuidadorCorreo) {
      const c = await getUserByCorreo(cuidadorCorreo);
      if (!c) return res.status(404).json({ error: 'Cuidador no encontrado por correo' });
      cuidadorId = c.id;
    }

    if (!adultoId || !cuidadorId) {
      return res.status(400).json({ error: 'Faltan adultoId/cuidadorId o sus correos' });
    }
    if (!canAct(req.user, [adultoId, cuidadorId])) {
      return res.status(403).json({ error: 'No autorizado' });
    }

    await assertUserRole(adultoId, 'ADULTO_MAYOR');
    await assertUserRole(cuidadorId, 'CUIDADOR');
    if (adultoId === cuidadorId) {
      return res.status(400).json({ error: 'No puedes vincular el mismo usuario' });
    }

    const issuerId = req.user.sub;
    const issuerRol = req.user.rol;

    const token = jwt.sign(
      { tipo: 'VINCULACION', adultoId, cuidadorId, issuerId, issuerRol },
      JWT_SECRET,
      { expiresIn: 60 * 60 * 24 } // 24h
    );

    const deepLink = `alertavital://vincular?token=${encodeURIComponent(token)}`;

    return res.status(201).json({
      ok: true,
      message: 'Solicitud creada. Comparte el código o link con la contraparte para aceptar.',
      token,
      deepLink,
      expiresIn: 60 * 60 * 24,
    });
  } catch (e) {
    console.error(e);
    return res.status(500).json({ error: 'Error al generar solicitud' });
  }
}

/**
 * POST /api/cuidadores/aceptar
 * body: { token }
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
 * POST /api/cuidadores/vincular (flujo directo, ya existente)
 * body: { adultoId, cuidadorId }
 */
export async function postVincular(req, res) {
  try {
    const { adultoId, cuidadorId } = req.body || {};
    if (!adultoId || !cuidadorId) {
      return res.status(400).json({ error: 'Faltan adultoId y/o cuidadorId' });
    }
    if (!canAct(req.user, [adultoId, cuidadorId])) {
      return res.status(403).json({ error: 'No autorizado' });
    }
    await assertUserRole(adultoId, 'ADULTO_MAYOR');
    await assertUserRole(cuidadorId, 'CUIDADOR');
    if (adultoId === cuidadorId) {
      return res.status(400).json({ error: 'No puedes vincular el mismo usuario' });
    }
    await vincularCuidador({ adultoId, cuidadorId });
    return res.status(201).json({ ok: true, message: 'Vinculado correctamente' });
  } catch (e) {
    if (e.message === 'USER_NOT_FOUND') return res.status(404).json({ error: 'Usuario no encontrado' });
    if (e.message === 'WRONG_ROLE') return res.status(400).json({ error: 'Rol incompatible para vinculación' });
    console.error(e);
    return res.status(500).json({ error: 'Error al vincular' });
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
