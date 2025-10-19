// src/services/alertas.service.js
import Pusher from 'pusher';
import { pool } from '../db/pool.js';
import { config } from '../config/env.js';

const pusher = new Pusher({
  appId: config.pusherAppId,
  key: config.pusherKey,
  secret: config.pusherSecret,
  cluster: config.pusherCluster,
  useTLS: true
});

const activeTimers = new Map();

function clearCountdown(alertaId) {
  if (activeTimers.has(alertaId)) {
    clearTimeout(activeTimers.get(alertaId));
    activeTimers.delete(alertaId);
  }
}

function startCountdown(alertaId, seconds) {
  clearCountdown(alertaId);
  const timer = setTimeout(() => onCountdownExpired(alertaId), seconds * 1000);
  activeTimers.set(alertaId, timer);
}

function haversineDistance(lat1, lon1, lat2, lon2) {
  const R = 6371; // Radio de la Tierra en km
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) * Math.sin(dLon / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return R * c; // Distancia en km
}

async function pickNearestNow(client, { alertaId, adultoId, lat, lon }) {
  const { rows: cuidadores } = await client.query(
    `SELECT c.cuidador_id FROM cuidadores c
     WHERE c.adulto_id = $1
       AND c.cuidador_id NOT IN (
         SELECT aa.cuidador_id FROM alertas_asignaciones aa WHERE aa.alerta_id = $2
       )`,
    [adultoId, alertaId]
  );
  if (cuidadores.length === 0) {
    console.log(`[pickNearestNow] No se encontraron cuidadores vinculados y disponibles para el adulto ${adultoId} en la alerta ${alertaId}`);
    return null;
  }
  const cuidadorIds = cuidadores.map(c => c.cuidador_id);
  const { rows: ubicaciones } = await client.query(
    `SELECT DISTINCT ON (usuario_id) usuario_id, latitud, longitud
     FROM ubicaciones
     WHERE usuario_id = ANY($1::uuid[])
     ORDER BY usuario_id, detectado_en DESC`,
    [cuidadorIds]
  );
  if (ubicaciones.length === 0) {
    console.log(`[pickNearestNow] Ninguno de los cuidadores disponibles (${cuidadorIds.join(', ')}) tiene una ubicación registrada.`);
    return null;
  }
  const nearest = ubicaciones.reduce((closest, current) => {
    const distance = haversineDistance(lat, lon, current.latitud, current.longitud);
    if (distance < closest.distance) {
      return { distance, cuidador_id: current.usuario_id };
    }
    return closest;
  }, { distance: Infinity, cuidador_id: null });
  if (nearest.cuidador_id) {
    console.log(`[pickNearestNow] Cuidador más cercano encontrado: ${nearest.cuidador_id} a ${nearest.distance.toFixed(2)} km.`);
    return nearest;
  }
  return null;
}

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
    const { rows: [alerta] } = await client.query('SELECT * FROM alertas WHERE id=$1', [alertaId]);
    if (!alerta) { await client.query('ROLLBACK'); return; }

    const { rows: [lastAssigned] } = await client.query(`UPDATE alertas_asignaciones SET estado='EXPIRADA' WHERE alerta_id=$1 AND estado='PENDIENTE' RETURNING *`, [alertaId]);
    
    // ✅ MODIFICACIÓN: Notifica al cuidador anterior que su asignación ha expirado.
    if (lastAssigned && lastAssigned.cuidador_id) {
      console.log(`[PUSHER TRIGGER] Notificando expiración a cuidador anterior: ${lastAssigned.cuidador_id}`);
      pusher.trigger(`private-user-${lastAssigned.cuidador_id}`, 'asignacion_expirada', { 
        alertaId: alertaId 
      });
    }
    
    const nextCuidador = await pickNearestNow(client, { alertaId: alerta.id, adultoId: alerta.usuario_id, lat: alerta.latitud, lon: alerta.longitud });
    
    if (nextCuidador && nextCuidador.cuidador_id) {
      const nextOrden = (lastAssigned?.orden || 0) + 1;
      await client.query(`INSERT INTO alertas_asignaciones (alerta_id, cuidador_id, orden, estado) VALUES ($1,$2,$3,'PENDIENTE')`, [alerta.id, nextCuidador.cuidador_id, nextOrden]);
      await client.query('COMMIT');
      
      pusher.trigger(`private-user-${nextCuidador.cuidador_id}`, 'alerta_nueva', { alertaId: alerta.id, orden: nextOrden, latitud: alerta.latitud, longitud: alerta.longitud });
      pusher.trigger(`private-alerta-${alerta.id}`, 'derivada_siguiente', { alertaId: alerta.id, nextOrden });
      startCountdown(alerta.id, alerta.countdown_seg);
    } else {
      await client.query('COMMIT');
      await notifyEmergencyToAdult(alerta.id);
    }
  } catch(e) { 
    await client.query('ROLLBACK'); 
    console.error("Error en onCountdownExpired:", e);
  } finally { 
    client.release(); 
  }
}

export async function crearAlertaRT({ adultoId, tipo, descripcion, countdownSeg, latitud, longitud, precision_metros }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const qAlerta = `INSERT INTO alertas (usuario_id, tipo, descripcion, countdown_seg, latitud, longitud, precision_metros, creada_en) VALUES ($1,$2,$3,$4,$5,$6,$7, NOW()) RETURNING *`;
    const { rows: [alerta] } = await client.query(qAlerta, [adultoId, tipo, descripcion, countdownSeg, latitud, longitud, precision_metros]);
    const nearest = await pickNearestNow(client, { alertaId: alerta.id, adultoId, lat: alerta.latitud, lon: alerta.longitud });
    if (nearest && nearest.cuidador_id) {
      await client.query(`INSERT INTO alertas_asignaciones (alerta_id, cuidador_id, orden, estado) VALUES ($1,$2,1,'PENDIENTE')`, [alerta.id, nearest.cuidador_id]);
    }
    await client.query('COMMIT');
    pusher.trigger(`private-user-${adultoId}`, 'alerta_creada', { alertaId: alerta.id, countdown: countdownSeg });
    if (nearest && nearest.cuidador_id) {
      console.log(`[PUSHER TRIGGER] Intentando enviar 'alerta_nueva' al canal: private-user-${nearest.cuidador_id}`);
      await pusher.trigger(`private-user-${nearest.cuidador_id}`, 'alerta_nueva', {
        alertaId: alerta.id, orden: 1, latitud: alerta.latitud, longitud: alerta.longitud, precision_metros: alerta.precision_metros
      });
      console.log(`[PUSHER TRIGGER] Evento enviado exitosamente.`);
      startCountdown(alerta.id, countdownSeg);
    } else {
      console.log(`[crearAlertaRT] No se encontró cuidador inicial. Notificando emergencia.`);
      await notifyEmergencyToAdult(alerta.id);
    }
    return { alertaId: alerta.id, countdown: countdownSeg };
  } catch (e) { 
    await client.query('ROLLBACK'); 
    console.error("Error en crearAlertaRT:", e);
    throw e; 
  } finally { 
    client.release(); 
  }
}

export async function aceptarAlerta({ alertaId, cuidadorId }) {
  clearCountdown(alertaId);
  await pool.query(`UPDATE alertas_asignaciones SET estado='ACEPTADA' WHERE alerta_id=$1 AND cuidador_id=$2`, [alertaId, cuidadorId]);
  await pool.query(`UPDATE alertas SET estado='EN_CURSO' WHERE id=$1`, [alertaId]);
  pusher.trigger(`private-alerta-${alertaId}`, 'cuidador_en_camino', { alertaId, cuidadorId });
  return true;
}

export async function derivarAlerta({ alertaId, cuidadorId }) {
  const { rows } = await pool.query(`SELECT * FROM alertas_asignaciones WHERE alerta_id=$1 AND cuidador_id=$2 AND estado='PENDIENTE'`, [alertaId, cuidadorId]);
  if (rows.length === 0) return { ok: false, message: 'No tienes esta alerta asignada.' };
  clearCountdown(alertaId);
  await onCountdownExpired(alertaId);
  return { ok: true };
}

export async function completarAlerta({ alertaId, cuidadorId }) {
  clearCountdown(alertaId);
  await pool.query(`UPDATE alertas SET estado='CERRADA' WHERE id=$1`, [alertaId]);
  pusher.trigger(`private-alerta-${alertaId}`, 'alerta_completada', { alertaId });
  return true;
}

export async function getAlertasPendientesDeCuidador(cuidadorId) {
  const q = `
    SELECT
      a.id AS "alertaId",
      aa.orden,
      a.latitud,
      a.longitud,
      a.precision_metros
    FROM alertas_asignaciones aa
    JOIN alertas a ON a.id = aa.alerta_id
    WHERE aa.cuidador_id = $1 AND aa.estado = 'PENDIENTE'
    ORDER BY a.creada_en DESC
  `;
  const { rows } = await pool.query(q, [cuidadorId]);
  return rows;
}