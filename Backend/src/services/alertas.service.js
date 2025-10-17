// src/services/alertas.service.js

import Pusher from 'pusher';
import { pool } from '../db/pool.js';
import { config } from '../config/env.js'; // Asumiendo que aquí tienes tus variables de entorno

// 1. Instancia de Pusher
const pusher = new Pusher({
  appId: config.pusherAppId,
  key: config.pusherKey,
  secret: config.pusherSecret,
  cluster: config.pusherCluster,
  useTLS: true
});

// --- ELIMINADA ---
// let ioRef = null;
// export function setAlertsIO(io) { ioRef = io; }

// ... (toda la lógica de Haversine, pickNearestNow, timers no cambia) ...

// ===== Emergencia SOLO al adulto =====
async function notifyEmergencyToAdult(alertaId) {
  const { rows } = await pool.query(`SELECT usuario_id FROM alertas WHERE id=$1`, [alertaId]);
  const adultoId = rows[0]?.usuario_id;

  await pool.query(
    `INSERT INTO alertas_eventos (alerta_id, evento, metadata)
     VALUES ($1,'EMERGENCY_CALLED',$2::jsonb)`,
    [alertaId, JSON.stringify({ channel: 'in_app' })]
  );
  await pool.query(`UPDATE alertas SET estado='CERRADA' WHERE id=$1`, [alertaId]);

  // ANTES: ioRef.to(...).emit(...)
  // AHORA: pusher.trigger(...)
  // Los "canales privados" aseguran que solo los usuarios autorizados puedan escuchar.
  // Tu cliente se suscribirá a 'private-alerta-ALERTA_ID' y 'private-user-USUARIO_ID'.
  pusher.trigger(`private-alerta-${alertaId}`, 'alerta_emergencia', { alertaId });
  if (adultoId) {
    pusher.trigger(`private-user-${adultoId}`, 'alerta_emergencia', { alertaId });
  }
}

// ===== Crear alerta y notificar al más cercano =====
export async function crearAlertaRT({ /* ... argumentos ... */ }) {
  // ... (toda tu lógica de base de datos no cambia) ...
  // ...
  // Dentro del bloque try, después de client.query('COMMIT');

  // ANTES: ioRef.to(...)
  // AHORA: pusher.trigger(...)
  pusher.trigger(`private-user-${adultoId}`, 'alerta_creada', { alertaId: alerta.id, countdown: alerta.countdown_seg });
  if (nearest) {
    pusher.trigger(`private-user-${nearest.cuidador_id}`, 'alerta_nueva', {
      alertaId: alerta.id,
      orden: 1,
      latitud: alerta.latitud,
      longitud: alerta.longitud,
      precision_metros: alerta.precision_metros,
    });
  } else {
    await notifyEmergencyToAdult(alerta.id);
  }

  if (nearest) startCountdown(alerta.id, alerta.countdown_seg);
  return { /* ... */ };
}


// ===== onCountdownExpired (derivar) =====
async function onCountdownExpired(alertaId) {
  // ... (toda tu lógica de base de datos no cambia) ...
  // ...
  // Dentro del bloque if (nearest), después de client.query('COMMIT');
  
  // ANTES: ioRef.to(...)
  // AHORA: pusher.trigger(...)
  pusher.trigger(`private-user-${nearest.cuidador_id}`, 'alerta_nueva', {
    alertaId,
    orden: nextOrden,
    latitud: adultLat,
    longitud: adultLon,
    precision_metros: null,
  });
  pusher.trigger(`private-alerta-${alertaId}`, 'derivada_siguiente', { alertaId, nextOrden });
  
  startCountdown(alertaId, countdown);
  // ...
}

// ===== Acciones del cuidador =====
export async function aceptarAlerta({ alertaId, cuidadorId }) {
  // ... (lógica de BD sin cambios) ...
  // ANTES: ioRef.to(...)
  // AHORA: pusher.trigger(...)
  pusher.trigger(`private-alerta-${alertaId}`, 'cuidador_en_camino', { alertaId, cuidadorId });
  return true;
}

// ... (derivarAlerta no necesita cambios aquí porque llama a onCountdownExpired) ...

export async function completarAlerta({ alertaId, cuidadorId }) {
  // ... (lógica de BD sin cambios) ...
  // ANTES: ioRef.to(...)
  // AHORA: pusher.trigger(...)
  clearCountdown(alertaId);
  pusher.trigger(`private-alerta-${alertaId}`, 'alerta_completada', { alertaId });
  return true;
}