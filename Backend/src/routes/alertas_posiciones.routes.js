import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';
import Pusher from 'pusher';
import { config } from '../config/env.js';

const router = Router();

// Instancia de Pusher
const pusher = new Pusher({
  appId: config.pusherAppId,
  key: config.pusherKey,
  secret: config.pusherSecret,
  cluster: config.pusherCluster,
  useTLS: true,
});

// Guardar punto de traza asociado a una alerta (adulto/cuidador)
router.post('/alertas/:id/posicion', auth, async (req, res) => {
  try {
    const alertaId = req.params.id;
    const userId = req.user.sub;
    const rol = req.user.rol;
    const { latitud, longitud, precision_metros } = req.body || {};
    if (typeof latitud !== 'number' || typeof longitud !== 'number') {
      return res.status(400).json({ error: 'latitud y longitud numéricos requeridos' });
    }
    await pool.query(
      `INSERT INTO alertas_posiciones (alerta_id, usuario_id, rol, latitud, longitud, precision_metros, capturada_en)
       VALUES ($1,$2,$3,$4,$5,$6,NOW())`,
      [alertaId, userId, rol, latitud, longitud, precision_metros ?? null]
    );

    // ✅ NOTIFICAR EN TIEMPO REAL AL MAPA
    // Se emite un evento en el canal de la alerta con la nueva posición.
    await pusher.trigger(`private-alerta-${alertaId}`, 'posicion_actualizada', {
      usuario_id: userId,
      rol: rol,
      latitud: latitud,
      longitud: longitud,
      precision_metros: precision_metros,
      capturada_en: new Date().toISOString(),
    });

    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'No se pudo guardar la posición' });
  }
});

// Obtener últimos puntos (para pintar ruta)
router.get('/alertas/:id/posiciones', auth, async (req, res) => {
  try {
    const alertaId = req.params.id;
    const { rol } = req.query;
    const params = [alertaId];
    let where = 'WHERE alerta_id = $1';
    if (rol === 'ADULTO_MAYOR' || rol === 'CUIDADOR') {
      where += ' AND rol = $2';
      params.push(rol);
    }
    const { rows } = await pool.query(
      `SELECT usuario_id, rol, latitud, longitud, precision_metros, capturada_en
         FROM alertas_posiciones
        ${where}
        ORDER BY capturada_en DESC
        LIMIT 500`,
      params
    );
    res.json(rows);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'No se pudo obtener posiciones' });
  }
});

export default router;