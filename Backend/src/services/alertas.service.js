// src/services/alertas.service.js

import Pusher from 'pusher';
import { pool } from '../db/pool.js';
import { config } from '../config/env.js';

// 1. Instancia de Pusher
const pusher = new Pusher({
  appId: config.pusherAppId,
  key: config.pusherKey,
  secret: config.pusherSecret,
  cluster: config.pusherCluster,
  useTLS: true
});

// 2. Lógica de Timers
const activeTimers = new Map();

function clearCountdown(alertaId) {
  if (activeTimers.has(alertaId)) {
    clearTimeout(activeTimers.get(alertaId));
    activeTimers.delete(alertaId);
  }
}

function startCountdown(alertaId, seconds) {
  clearCountdown(alertaId);
  const timer = setTimeout(() => {
    onCountdownExpired(alertaId);
    activeTimers.delete(alertaId);
  }, seconds * 1000);
  activeTimers.set(alertaId, timer);
}

// 3. Helpers de Geolocalización
function haversineDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Radio de la Tierra en km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distancia en km
}

async function pickNearestNow(client, { adultoId, lat, lon }) {
  // Obtiene cuidadores que no han sido asignados a ESTA alerta aún
  const { rows: cuidadores } = await client.query(
    `SELECT c.cuidador_id
     FROM cuidadores c
     LEFT JOIN alertas_asignaciones aa ON c.cuidador_id = aa.cuidador_id AND aa.alerta_id = (SELECT id FROM alertas WHERE usuario_id = $1 ORDER BY creado_en DESC LIMIT 1)
     WHERE c.adulto_id = $1 AND aa.alerta_id IS NULL`,
    [adultoId]
  );
  if (cuidadores.length === 0) return null;

  const cuidadorIds = cuidadores.map(c => c.cuidador_id);
  // Obtiene la última ubicación de esos cuidadores
  const { rows: ubicaciones } = await client.query(
    `SELECT DISTINCT ON (usuario_id) usuario_id, latitud, longitud
     FROM ubicaciones
     WHERE usuario_id = ANY($1::uuid[])
     ORDER BY usuario_id, detectado_en DESC`,
    [cuidadorIds]
  );
  if (ubicaciones.length === 0) return null;

  // Calcula la distancia para cada uno y encuentra el más cercano
  return ubicaciones.reduce((closest, current) => {
    const distance = haversineDistance(lat, lon, current.latitud, current.longitud);
    if (distance < closest.distance) {
      return { distance, cuidador_id: current.usuario_id };
    }
    return closest;
  }, { distance: Infinity, cuidador_id: null });
}


// 4. Lógica Interna de Alertas (no exportadas)

async function notifyEmergencyToAdult(alertaId) {
  const { rows } = await pool.query(`SELECT usuario_id FROM alertas WHERE id=$1`, [alertaId]);
  const adultoId = rows[0]?.usuario_id;
  await pool.query(`UPDATE alertas SET estado='CERRADA' WHERE id=$1`, [alertaId]);
  if (adultoId) {
    pusher.trigger(`private-user-${adultoId}`, 'alerta_emergencia', { alertaId });
  }
}

async function onCountdownExpired(alertaId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const { rows: [alerta] } = await client.query('SELECT id, usuario_id, latitud, longitud FROM alertas WHERE id=$1', [alertaId]);
    if (!alerta) return;

    const { rows: [lastAssigned] } = await client.query(
      `UPDATE alertas_asignaciones SET estado='EXPIRADA' WHERE alerta_id=$1 AND estado='PENDIENTE' RETURNING cuidador_id, orden`,
      [alertaId]
    );

    const nextCuidador = await pickNearestNow(client, { adultoId: alerta.usuario_id, lat: alerta.latitud, lon: alerta.longitud });

    if (nextCuidador && nextCuidador.cuidador_id) {
      const nextOrden = (lastAssigned?.orden || 0) + 1;
      await client.query(
        `INSERT INTO alertas_asignaciones (alerta_id, cuidador_id, orden, estado) VALUES ($1,$2,$3,'PENDIENTE')`,
        [alertaId, nextCuidador.cuidador_id, nextOrden]
      );
      await client.query('COMMIT');

      pusher.trigger(`private-user-${nextCuidador.cuidador_id}`, 'alerta_nueva', { alertaId, orden: nextOrden, latitud: alerta.latitud, longitud: alerta.longitud });
      pusher.trigger(`private-alerta-${alertaId}`, 'derivada_siguiente', { alertaId, nextOrden });
      startCountdown(alertaId, 30); // Inicia nuevo countdown
    } else {
      await client.query('COMMIT');
      await notifyEmergencyToAdult(alertaId);
    }
  } catch (e) {
    await client.query('ROLLBACK');
    console.error("Error en onCountdownExpired:", e);
  } finally {
    client.release();
  }
}

// 5. Funciones Exportadas para las Rutas

export async function crearAlertaRT({ adultoId, tipo, descripcion, countdownSeg, latitud, longitud, precision_metros }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const qAlerta = `INSERT INTO alertas (usuario_id, tipo, descripcion, countdown_seg, latitud, longitud, precision_metros) VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id, latitud, longitud, precision_metros`;
    const { rows: [alerta] } = await client.query(qAlerta, [adultoId, tipo, descripcion, countdownSeg, latitud, longitud, precision_metros]);

    const nearest = await pickNearestNow(client, { adultoId, lat: alerta.latitud, lon: alerta.longitud });
    if (nearest && nearest.cuidador_id) {
      await client.query(`INSERT INTO alertas_asignaciones (alerta_id, cuidador_id, orden, estado) VALUES ($1,$2,1,'PENDIENTE')`, [alerta.id, nearest.cuidador_id]);
    }

    await client.query('COMMIT');

    pusher.trigger(`private-user-${adultoId}`, 'alerta_creada', { alertaId: alerta.id, countdown: countdownSeg });
    if (nearest && nearest.cuidador_id) {
      pusher.trigger(`private-user-${nearest.cuidador_id}`, 'alerta_nueva', {
        alertaId: alerta.id, orden: 1, latitud: alerta.latitud, longitud: alerta.longitud, precision_metros: alerta.precision_metros
      });
      startCountdown(alerta.id, countdownSeg);
    } else {
      await notifyEmergencyToAdult(alerta.id);
    }

    // ✅ SOLUCIÓN: Devolvemos el ID y el countdown al cliente.
    return { alertaId: alerta.id, countdown: countdownSeg };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

export async function aceptarAlerta({ alertaId, cuidadorId }) {
  clearCountdown(alertaId); // Detenemos el temporizador cuando alguien acepta
  await pool.query(`UPDATE alertas_asignaciones SET estado='ACEPTADA' WHERE alerta_id=$1 AND cuidador_id=$2`, [alertaId, cuidadorId]);
  pusher.trigger(`private-alerta-${alertaId}`, 'cuidador_en_camino', { alertaId, cuidadorId });
  return true;
}

export async function derivarAlerta({ alertaId, cuidadorId }) {
  const { rows } = await pool.query(
    `SELECT orden FROM alertas_asignaciones WHERE alerta_id=$1 AND cuidador_id=$2 AND estado='PENDIENTE'`,
    [alertaId, cuidadorId]
  );
  if (rows.length === 0) {
    return { ok: false, message: 'No tienes esta alerta asignada para derivar.' };
  }
  clearCountdown(alertaId);
  await onCountdownExpired(alertaId);
  return { ok: true, message: 'Alerta derivada al siguiente cuidador.' };
}

export async function completarAlerta({ alertaId, cuidadorId }) {
  clearCountdown(alertaId);
  await pool.query(`UPDATE alertas SET estado='CERRADA' WHERE id=$1`, [alertaId]);
  pusher.trigger(`private-alerta-${alertaId}`, 'alerta_completada', { alertaId });
  return true;
}