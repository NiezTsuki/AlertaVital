import Pusher from 'pusher';
import admin from 'firebase-admin';
import { prisma } from '../db/prisma.js'; 
import { config } from '../config/env.js';

// Inicialización Firebase y Pusher 
if (!admin.apps.length && config.firebaseServiceAccountJson) {
  try {
    const serviceAccount = JSON.parse(config.firebaseServiceAccountJson);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    console.log(`[FCM] Firebase Admin SDK inicializado para proyecto: ${serviceAccount.project_id}`);
  } catch (e) {
    console.error('[FCM] Error al inicializar Firebase Admin SDK.', e.message);
  }
} else if (!config.firebaseServiceAccountJson) {
    console.warn('[FCM] La variable de entorno FIREBASE_SERVICE_ACCOUNT_JSON no fue encontrada.');
}

const pusher = new Pusher({
  appId: config.pusherAppId,
  key: config.pusherKey,
  secret: config.pusherSecret,
  cluster: config.pusherCluster,
  useTLS: true
});


async function sendPushNotification(userId, title, body, data) {
    
    if (!admin.apps.length) { console.warn('[FCM] Firebase Admin no está inicializado.'); return; }
    try {
        const user = await prisma.usuarios.findUnique({ where: { id: userId }, select: { fcm_token: true } });
        const token = user?.fcm_token;
        if (token) {
            console.log(`[FCM] Enviando notificación a usuario ${userId}`);
            await admin.messaging().send({ token, notification: { title, body }, data, android: { priority: 'high' }, apns: { payload: { aps: { 'content-available': 1, sound: 'default' } } } });
            console.log('[FCM] Notificación enviada exitosamente.');
        } else {
            console.log(`[FCM] Usuario ${userId} no tiene token FCM.`);
        }
    } catch (error) {
        console.error(`[FCM] Error al enviar notificación a ${userId}:`, error);
    }
}

const activeTimers = new Map();

function clearCountdown(alertaId) { if (activeTimers.has(alertaId)) { clearTimeout(activeTimers.get(alertaId)); activeTimers.delete(alertaId); } }
function startCountdown(alertaId, seconds) { clearCountdown(alertaId); const timer = setTimeout(() => onCountdownExpired(alertaId), seconds * 1000); activeTimers.set(alertaId, timer); }
function haversineDistance(lat1, lon1, lat2, lon2) { const R = 6371; const dLat = (lat2 - lat1) * Math.PI / 180; const dLon = (lon2 - lon1) * Math.PI / 180; const a = Math.sin(dLat / 2) * Math.sin(dLat / 2) + Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) * Math.sin(dLon / 2); const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a)); return R * c; }


async function pickNearestNow(prismaTx, { alertaId, adultoId, lat, lon }) {
  const assignedCaregiverIds = await prismaTx.alertas_asignaciones.findMany({
    where: { alerta_id: alertaId },
    select: { cuidador_id: true }
  });

  const availableCaregivers = await prismaTx.cuidadores.findMany({
    where: {
      adulto_id: adultoId,
      cuidador_id: { notIn: assignedCaregiverIds.map(c => c.cuidador_id) }
    },
    select: { cuidador_id: true }
  });

  if (availableCaregivers.length === 0) return null;

  const caregiverIds = availableCaregivers.map(c => c.cuidador_id);
  
  const locations = await prismaTx.ubicaciones.findMany({
    where: { usuario_id: { in: caregiverIds } },
    distinct: ['usuario_id'],
    orderBy: { detectado_en: 'desc' }
  });

  if (locations.length === 0) return null;

  const nearest = locations.reduce((closest, current) => {
    const distance = haversineDistance(lat, lon, current.latitud, current.longitud);
    if (distance < closest.distance) {
      return { distance, cuidador_id: current.usuario_id };
    }
    return closest;
  }, { distance: Infinity, cuidador_id: null });

  return nearest.cuidador_id ? nearest : null;
}

async function notifyEmergencyToAdult(alertaId) {
  const alerta = await prisma.alertas.update({
    where: { id: alertaId },
    data: { estado: 'CERRADA' },
    select: { usuario_id: true }
  });
  if (alerta.usuario_id) {
    pusher.trigger(`private-user-${alerta.usuario_id}`, 'alerta_emergencia', { alertaId });
  }
}

async function onCountdownExpired(alertaId) {
  try {
    await prisma.$transaction(async (prismaTx) => {
      const alerta = await prismaTx.alertas.findUnique({ where: { id: alertaId } });
      if (!alerta) return;

      const lastAssigned = await prismaTx.alertas_asignaciones.update({
        where: { alerta_id_estado: { alerta_id: alertaId, estado: 'PENDIENTE' } }, 
        data: { estado: 'EXPIRADA' }
      });

      if (lastAssigned?.cuidador_id) {
        pusher.trigger(`private-user-${lastAssigned.cuidador_id}`, 'asignacion_expirada', { alertaId });
      }

      const nextCuidador = await pickNearestNow(prismaTx, { alertaId, adultoId: alerta.usuario_id, lat: alerta.latitud, lon: alerta.longitud });

      if (nextCuidador?.cuidador_id) {
        const nextOrden = (lastAssigned?.orden || 0) + 1;
        await prismaTx.alertas_asignaciones.create({
          data: {
            alerta_id: alertaId,
            cuidador_id: nextCuidador.cuidador_id,
            orden: nextOrden,
            estado: 'PENDIENTE'
          }
        });

        pusher.trigger(`private-user-${nextCuidador.cuidador_id}`, 'alerta_nueva', { alertaId, orden: nextOrden, latitud: alerta.latitud, longitud: alerta.longitud });
        sendPushNotification(nextCuidador.cuidador_id, 'Emergencia Asignada', 'Se requiere tu ayuda para una alerta de AlertaVital.', { alertaId: alerta.id.toString(), click_action: 'FLUTTER_NOTIFICATION_CLICK' });
        pusher.trigger(`private-alerta-${alertaId}`, 'derivada_siguiente', { alertaId, nextOrden });
        startCountdown(alertaId, alerta.countdown_seg);
      } else {
        await notifyEmergencyToAdult(alertaId);
      }
    });
  } catch(e) { 
    console.error("Error en onCountdownExpired:", e);
  }
}

export async function crearAlertaRT({ adultoId, tipo, descripcion, latitud, longitud, precision_metros }) {
  const countdownSeg = 90;
  
  try {
    const alerta = await prisma.alertas.create({
      data: {
        usuario_id: adultoId,
        tipo,
        descripcion,
        countdown_seg: countdownSeg,
        latitud,
        longitud,
        precision_metros,
      }
    });

    const nearest = await pickNearestNow(prisma, { alertaId: alerta.id, adultoId, lat: alerta.latitud, lon: alerta.longitud });

    if (nearest?.cuidador_id) {
      await prisma.alertas_asignaciones.create({
        data: {
          alerta_id: alerta.id,
          cuidador_id: nearest.cuidador_id,
          orden: 1,
          estado: 'PENDIENTE'
        }
      });
      
      pusher.trigger(`private-user-${nearest.cuidador_id}`, 'alerta_nueva', { alertaId: alerta.id, orden: 1, latitud: alerta.latitud, longitud: alerta.longitud, precision_metros: alerta.precision_metros });
      sendPushNotification(nearest.cuidador_id, '¡Nueva Alerta de Emergencia!', 'Un adulto mayor necesita tu ayuda urgentemente.', { alertaId: alerta.id.toString(), click_action: 'FLUTTER_NOTIFICATION_CLICK' });
      startCountdown(alerta.id, countdownSeg);
    } else {
      await notifyEmergencyToAdult(alerta.id);
    }
    
    pusher.trigger(`private-user-${adultoId}`, 'alerta_creada', { alertaId: alerta.id, countdown: countdownSeg });
    return { alertaId: alerta.id, countdown: countdownSeg };
  } catch (e) { 
    console.error("Error en crearAlertaRT:", e);
    throw e;
  }
}

export async function aceptarAlerta({ alertaId, cuidadorId }) {
  clearCountdown(alertaId);
  try {
    const { alerta, cuidador } = await prisma.$transaction(async (prismaTx) => {
      await prismaTx.alertas_asignaciones.update({
        where: { alerta_id_cuidador_id: { alerta_id: alertaId, cuidador_id: cuidadorId } }, 
        data: { estado: 'EN_CAMINO', respondida_en: new Date() }
      });
      const alerta = await prismaTx.alertas.findUnique({ where: { id: alertaId }, select: { usuario_id: true } });
      const cuidador = await prismaTx.usuarios.findUnique({ where: { id: cuidadorId }, select: { nombre_completo: true } });
      return { alerta, cuidador };
    });

    const cuidadorNombre = cuidador?.nombre_completo || 'Un cuidador';
    pusher.trigger(`private-alerta-${alertaId}`, 'cuidador_en_camino', { alertaId, cuidadorId, cuidadorNombre });

    if (alerta?.usuario_id) {
      await sendPushNotification(alerta.usuario_id, null, null, { tipo: 'ALERTA_ACEPTADA', mensaje: `${cuidadorNombre} va en camino.`, alertaId: alertaId.toString(), cuidadorId: cuidadorId.toString() });
    }
    return true;
  } catch (e) {
    console.error(`[aceptarAlerta] Error: ${e.message}`);
    throw e;
  }
}

export async function derivarAlerta({ alertaId, cuidadorId }) {
  const assignment = await prisma.alertas_asignaciones.findFirst({
    where: { alerta_id: alertaId, cuidador_id: cuidadorId, estado: 'PENDIENTE' }
  });
  if (!assignment) return { ok: false, message: 'No tienes esta alerta asignada.' };
  
  clearCountdown(alertaId);
  await onCountdownExpired(alertaId);
  return { ok: true };
}

export async function completarAlerta({ alertaId, cuidadorId }) {
  clearCountdown(alertaId);
  await prisma.alertas.update({
    where: { id: alertaId },
    data: { estado: 'CERRADA' }
  });
  pusher.trigger(`private-alerta-${alertaId}`, 'alerta_completada', { alertaId });
  return true;
}

export async function getAlertasPendientesDeCuidador(cuidadorId) {
  const assignments = await prisma.alertas_asignaciones.findMany({
    where: { cuidador_id: cuidadorId, estado: 'PENDIENTE' },
    include: {
      alertas: {
        select: { id: true, latitud: true, longitud: true, precision_metros: true }
      }
    },
    orderBy: { alertas: { creada_en: 'desc' } }
  });

  return assignments.map(a => ({
    alertaId: a.alertas.id,
    orden: a.orden,
    latitud: a.alertas.latitud,
    longitud: a.alertas.longitud,
    precision_metros: a.alertas.precision_metros
  }));
}