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

// ✅ LÓGICA DE TIMERS QUE FALTABA
// Usamos un Map para llevar un registro de los temporizadores activos por alerta.
const activeTimers = new Map();

function clearCountdown(alertaId) {
  if (activeTimers.has(alertaId)) {
    clearTimeout(activeTimers.get(alertaId));
    activeTimers.delete(alertaId);
  }
}

function startCountdown(alertaId, seconds) {
  clearCountdown(alertaId); // Nos aseguramos de que no haya timers duplicados
  const timer = setTimeout(() => {
    onCountdownExpired(alertaId);
    activeTimers.delete(alertaId);
  }, seconds * 1000);
  activeTimers.set(alertaId, timer);
}


// ===== Lógica interna (funciones no exportadas) =====

async function notifyEmergencyToAdult(alertaId) {
  // ... (tu lógica existente no cambia)
}

// ... (tu lógica de Haversine y pickNearestNow no cambia) ...

async function onCountdownExpired(alertaId) {
  // ... (tu lógica existente no cambia) ...
  // Esta función es la que deriva la alerta al siguiente cuidador o llama a emergencia.
}

// ===== Funciones Exportadas (lógica de negocio) =====

export async function crearAlertaRT({ /* ... argumentos ... */ }) {
  // ... (tu lógica existente no cambia) ...
}

export async function aceptarAlerta({ alertaId, cuidadorId }) {
  // ... (tu lógica existente no cambia) ...
  clearCountdown(alertaId); // Detenemos el temporizador cuando alguien acepta
  pusher.trigger(`private-alerta-${alertaId}`, 'cuidador_en_camino', { alertaId, cuidadorId });
  return true;
}

// ✅ ================= INICIO DE LA CORRECCIÓN ================= ✅
//
// Esta es la función que faltaba. Su propósito es permitir que un cuidador
// rechace la alerta, forzando la derivación inmediata al siguiente.
//
export async function derivarAlerta({ alertaId, cuidadorId }) {
  const { rows } = await pool.query(
    `SELECT orden FROM alertas_asignaciones WHERE alerta_id=$1 AND cuidador_id=$2 AND estado='PENDIENTE'`,
    [alertaId, cuidadorId]
  );
  if (rows.length === 0) {
    // Si no hay una asignación pendiente, no puede derivar.
    return { ok: false, message: 'No tienes esta alerta asignada para derivar.' };
  }
  
  // Limpiamos el temporizador actual para forzar la expiración inmediata.
  clearCountdown(alertaId);
  // Llamamos a la función que busca al siguiente en la lista.
  await onCountdownExpired(alertaId);

  return { ok: true, message: 'Alerta derivada al siguiente cuidador.' };
}
// ✅ =================== FIN DE LA CORRECCIÓN =================== ✅

export async function completarAlerta({ alertaId, cuidadorId }) {
  // ... (tu lógica existente no cambia) ...
  clearCountdown(alertaId);
  pusher.trigger(`private-alerta-${alertaId}`, 'alerta_completada', { alertaId });
  return true;
}