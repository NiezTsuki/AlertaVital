import Pusher from 'pusher';
import admin from 'firebase-admin';
import { pool } from '../db/pool.js';
import { config } from '../config/env.js';

// INICIALIZA FIREBASE ADMIN SDK
if (!admin.apps.length && config.firebaseServiceAccountJson) {
  try {
    const serviceAccount = JSON.parse(config.firebaseServiceAccountJson);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    console.log(`[FCM] Firebase Admin SDK inicializado para proyecto: ${serviceAccount.project_id}`);
  } catch (e) {
    console.error('[FCM] Error al inicializar Firebase Admin SDK. Revisa la variable de entorno FIREBASE_SERVICE_ACCOUNT_JSON.', e.message);
  }
} else if (!config.firebaseServiceAccountJson) {
    console.warn('[FCM] La variable de entorno FIREBASE_SERVICE_ACCOUNT_JSON no fue encontrada. No se enviarán notificaciones push.');
}


const pusher = new Pusher({
  appId: config.pusherAppId,
  key: config.pusherKey,
  secret: config.pusherSecret,
  cluster: config.pusherCluster,
  useTLS: true
});

async function sendPushNotification(userId, title, body, data) {
  if (!admin.apps.length) {
    console.warn('[FCM] Firebase Admin no está inicializado. No se enviará la notificación.');
    return;
  }

  try {
    // 1) Consultar token con manejo de errores y guardando el tiempo
    const start = Date.now();
    const res = await pool.query({
      text: 'SELECT fcm_token FROM usuarios WHERE id = $1',
      values: [userId],
      // Opcional: statement_timeout si soporta tu cliente / configuración
    });
    const duration = Date.now() - start;
    console.log(`[FCM] Consulta token para ${userId} en ${duration}ms, filas=${res.rowCount}`);

    const token = res.rows[0]?.fcm_token;
    if (!token) {
      console.log(`[FCM] Usuario ${userId} no tiene token FCM.`);
      return;
    }

    // 2) Intentar enviar a FCM con reintentos simples (por si es error de red temporal)
    const maxAttempts = 3;
    let attempt = 0;
    while (attempt < maxAttempts) {
      try {
        attempt++;
        console.log(`[FCM] Enviando notificación (intento ${attempt}) a usuario ${userId}`);
        await admin.messaging().send({
          token,
          notification: { title, body },
          data,
          android: { priority: 'high' },
          apns: { payload: { aps: { 'content-available': 1, sound: 'default' } } }
        });
        console.log('[FCM] Notificación enviada exitosamente.');
        break; // éxito -> salir del loop
      } catch (fcmErr) {
        console.error(`[FCM] Error envío intento ${attempt} a ${userId}:`, fcmErr.code ?? fcmErr.message ?? fcmErr);
        // si no quedan intentos, re-lanzar o manejar
        if (attempt >= maxAttempts) {
          console.error('[FCM] Fallaron todos los intentos de envío.');
        } else {
          // espera exponencial simple antes del siguiente intento
          await new Promise(r => setTimeout(r, 200 * attempt));
        }
      }
    }
  } catch (error) {
    // Diferenciar errores de PG y otros
    if (error.code) {
      console.error(`[FCM] Error en DB al buscar token para ${userId}:`, error.code, error.message);
    } else {
      console.error(`[FCM] Error inesperado al enviar a ${userId}:`, error);
    }
  }
}



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
    
    if (lastAssigned && lastAssigned.cuidador_id) {
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
      
      sendPushNotification(
        nextCuidador.cuidador_id,
        'Emergencia Asignada',
        'Se requiere tu ayuda para una alerta de AlertaVital.',
        { alertaId: alerta.id.toString(), click_action: 'FLUTTER_NOTIFICATION_CLICK' }
      );

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
export async function crearAlertaRT({ adultoId, tipo, descripcion, latitud, longitud, precision_metros }) {
  // ✅ COUNTDOWN AJUSTADO A 90 SEGUNDOS
  const countdownSeg = 90;
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
      pusher.trigger(`private-user-${nearest.cuidador_id}`, 'alerta_nueva', {
        alertaId: alerta.id, orden: 1, latitud: alerta.latitud, longitud: alerta.longitud, precision_metros: alerta.precision_metros
      });
      
      sendPushNotification(
        nearest.cuidador_id,
        '¡Nueva Alerta de Emergencia!',
        'Un adulto mayor necesita tu ayuda urgentemente.',
        { alertaId: alerta.id.toString(), click_action: 'FLUTTER_NOTIFICATION_CLICK' }
      );

      startCountdown(alerta.id, countdownSeg);
    } else {
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

// ✅ FUNCIÓN CORREGIDA
export async function aceptarAlerta({ alertaId, cuidadorId }) {
  clearCountdown(alertaId);
  
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // Actualiza la asignación al estado correcto ('EN_CAMINO')
    await client.query(
      `UPDATE alertas_asignaciones SET estado='EN_CAMINO', respondida_en=NOW() WHERE alerta_id=$1 AND cuidador_id=$2`,
      [alertaId, cuidadorId]
    );
    
    // Obtiene el ID del adulto y el nombre del cuidador para las notificaciones
    const resAlerta = await client.query(`SELECT usuario_id FROM alertas WHERE id = $1`, [alertaId]);
    const adultoId = resAlerta.rows[0]?.usuario_id;
    const resCuidador = await client.query(`SELECT nombre_completo FROM usuarios WHERE id = $1`, [cuidadorId]);
    const cuidadorNombre = resCuidador.rows[0]?.nombre_completo || 'Un cuidador';

    await client.query('COMMIT');

    // Notifica a través de Pusher
    pusher.trigger(`private-alerta-${alertaId}`, 'cuidador_en_camino', { alertaId, cuidadorId, cuidadorNombre });

    // Envía notificación push silenciosa de vuelta al adulto mayor
    if (adultoId) {
      await sendPushNotification(
        adultoId,
        null, // Sin título
        null, // Sin cuerpo
        {
          tipo: 'ALERTA_ACEPTADA',
          mensaje: `${cuidadorNombre} va en camino.`,
          alertaId: alertaId.toString(),
          cuidadorId: cuidadorId.toString()
        }
      );
    }
    return true;
  } catch (e) {
    await client.query('ROLLBACK');
    console.error(`[aceptarAlerta] Error en transacción: ${e.message}`);
    throw e;
  } finally {
    client.release();
  }
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