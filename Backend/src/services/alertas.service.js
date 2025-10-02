import { pool } from '../db/pool.js';

let ioRef = null;
export function setAlertsIO(io) { ioRef = io; }

// Última ubicación por usuario
const lastLocationCTE = `
WITH ult_ub AS (
  SELECT DISTINCT ON (usuario_id)
         usuario_id, latitud, longitud, precision_metros, detectado_en
  FROM ubicaciones
  ORDER BY usuario_id, detectado_en DESC
)
`;

// Haversine (JS)
function haversine(lat1, lon1, lat2, lon2) {
  const toRad = (x) => (x * Math.PI) / 180;
  const R = 6371000;
  const dLat = toRad(lat2 - lat1);
  const dLon = toRad(lon2 - lon1);
  const a = Math.sin(dLat/2)**2 +
            Math.cos(toRad(lat1))*Math.cos(toRad(lat2))*
            Math.sin(dLon/2)**2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

// Más cercano actual (excluye los ya intentados)
async function pickNearestNow(adultoId, excludedCuidadorIds = []) {
  const adultoLoc = await pool.query(`
    ${lastLocationCTE}
    SELECT u.latitud, u.longitud FROM ult_ub u WHERE u.usuario_id = $1
  `, [adultoId]);

  const adultLat = adultoLoc.rows[0]?.latitud ?? null;
  const adultLon = adultoLoc.rows[0]?.longitud ?? null;

  const params = [adultoId];
  let extra = '';
  if (excludedCuidadorIds.length) {
    params.push(excludedCuidadorIds);
    extra = `AND c.cuidador_id <> ALL($2)`;
  }

  const { rows } = await pool.query(`
    ${lastLocationCTE}
    SELECT c.cuidador_id AS id, uu.latitud AS lat, uu.longitud AS lon
    FROM cuidadores c
    LEFT JOIN ult_ub uu ON uu.usuario_id = c.cuidador_id
    WHERE c.adulto_id = $1 ${extra}
  `, params);

  if (!rows.length) return null;

  const scored = rows.map(r => {
    let d = null;
    if (adultLat != null && adultLon != null && r.lat != null && r.lon != null) {
      d = haversine(adultLat, adultLon, r.lat, r.lon);
    }
    return { cuidador_id: r.id, distancia_m: d };
  }).sort((a,b) => {
    if (a.distancia_m == null && b.distancia_m == null) return 0;
    if (a.distancia_m == null) return 1;
    if (b.distancia_m == null) return -1;
    return a.distancia_m - b.distancia_m;
  });

  return scored[0] || null;
}

// ===== Timers (countdown) =====
const timers = new Map();
function startCountdown(alertaId, seconds) {
  clearCountdown(alertaId);
  const t = setTimeout(() => onCountdownExpired(alertaId).catch(console.error), seconds * 1000);
  timers.set(alertaId, t);
}
function clearCountdown(alertaId) {
  const t = timers.get(alertaId);
  if (t) { clearTimeout(t); timers.delete(alertaId); }
}

// ===== Emergencia SOLO para el adulto =====
async function notifyEmergencyToAdult(alertaId) {
  // obtener adultoId de la alerta
  const { rows } = await pool.query(`SELECT usuario_id FROM alertas WHERE id=$1`, [alertaId]);
  const adultoId = rows[0]?.usuario_id;
  // registrar evento y cerrar alerta
  await pool.query(
    `INSERT INTO alertas_eventos (alerta_id, evento, metadata)
     VALUES ($1,'EMERGENCY_CALLED', $2::jsonb)`,
    [alertaId, JSON.stringify({ channel: 'in_app' })]
  );
  await pool.query(`UPDATE alertas SET estado='CERRADA' WHERE id=$1`, [alertaId]);

  // emitir SOLO al adulto (sala de alerta y sala de usuario)
  if (ioRef) {
    ioRef.to(`adulto_alerta:${alertaId}`).emit('alerta_emergencia', { alertaId });
    if (adultoId) ioRef.to(`adulto:${adultoId}`).emit('alerta_emergencia', { alertaId });
  }
}

// ===== Crear alerta y notificar al más cercano actual =====
export async function crearAlertaRT({ adultoId, tipo='SOS', descripcion=null, countdownSeg=30 }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    const { rows: alertaRows } = await client.query(
      `INSERT INTO alertas (usuario_id, tipo, descripcion, countdown_seg, creada_en, atendida, estado)
       VALUES ($1,$2,$3,$4,NOW(),false,'ABIERTA')
       RETURNING id, countdown_seg`,
      [adultoId, tipo, descripcion, countdownSeg]
    );
    const alerta = alertaRows[0];

    await client.query(
      `INSERT INTO alertas_eventos (alerta_id, evento, metadata)
       VALUES ($1,'CREATED', $2::jsonb)`,
      [alerta.id, JSON.stringify({ adultoId, tipo })]
    );

    const nearest = await pickNearestNow(adultoId, []);

    if (nearest) {
      await client.query(
        `INSERT INTO alertas_asignaciones
         (alerta_id, cuidador_id, orden, estado, distancia_m, notificada_en)
         VALUES ($1,$2,1,'NOTIFICADA',$3,NOW())`,
        [alerta.id, nearest.cuidador_id, nearest.distancia_m]
      );
      await client.query(
        `INSERT INTO alertas_eventos (alerta_id, evento, metadata)
         VALUES ($1,'NOTIFIED', $2::jsonb)`,
        [alerta.id, JSON.stringify({ cuidador_id: nearest.cuidador_id, orden: 1 })]
      );
    }

    await client.query('COMMIT');

    if (ioRef) {
      ioRef.to(`adulto:${adultoId}`).emit('alerta_creada', { alertaId: alerta.id, countdown: alerta.countdown_seg });
      if (nearest) {
        ioRef.to(`cuidador:${nearest.cuidador_id}`).emit('alerta_nueva', { alertaId: alerta.id, orden: 1 });
      } else {
        // sin cuidadores vinculados → emergencia directa (en-app)
        await notifyEmergencyToAdult(alerta.id);
      }
    }

    if (nearest) startCountdown(alerta.id, alerta.countdown_seg);

    return { alertaId: alerta.id, countdown: alerta.countdown_seg, firstAssigned: !!nearest };
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

// ===== Expiración del countdown: derivar al siguiente más cercano =====
async function onCountdownExpired(alertaId) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');

    // expira la asignación activa
    await client.query(
      `UPDATE alertas_asignaciones
         SET estado='EXPIRADA', respondida_en=NOW()
       WHERE alerta_id=$1 AND estado='NOTIFICADA'`,
      [alertaId]
    );

    // datos base
    const { rows: aRows } = await client.query(
      `SELECT usuario_id, countdown_seg FROM alertas WHERE id=$1`,
      [alertaId]
    );
    const adultoId = aRows[0].usuario_id;
    const countdownSeg = aRows[0].countdown_seg;

    // excluidos: todos los ya intentados en esta alerta
    const { rows: excl } = await client.query(
      `SELECT cuidador_id FROM alertas_asignaciones WHERE alerta_id=$1`,
      [alertaId]
    );
    const excluded = excl.map(x => x.cuidador_id);

    const nearest = await pickNearestNow(adultoId, excluded);

    if (nearest) {
      const { rows: ord } = await client.query(
        `SELECT COALESCE(MAX(orden),0)+1 AS next FROM alertas_asignaciones WHERE alerta_id=$1`,
        [alertaId]
      );
      await client.query(
        `INSERT INTO alertas_asignaciones
         (alerta_id, cuidador_id, orden, estado, distancia_m, notificada_en)
         VALUES ($1,$2,$3,'NOTIFICADA',$4,NOW())`,
        [alertaId, nearest.cuidador_id, ord[0].next, nearest.distancia_m]
      );
      await client.query(
        `INSERT INTO alertas_eventos (alerta_id, evento, metadata)
         VALUES ($1,'FORWARDED', $2::jsonb)`,
        [alertaId, JSON.stringify({ to: nearest.cuidador_id, orden: ord[0].next })]
      );

      await client.query('COMMIT');

      if (ioRef) {
        ioRef.to(`cuidador:${nearest.cuidador_id}`).emit('alerta_nueva', { alertaId, orden: ord[0].next });
        ioRef.to(`adulto_alerta:${alertaId}`).emit('derivada_siguiente', { alertaId });
      }
      startCountdown(alertaId, countdownSeg);
    } else {
      await client.query('COMMIT');
      await notifyEmergencyToAdult(alertaId); // en-app y cierre
    }
  } catch (e) {
    await client.query('ROLLBACK');
    throw e;
  } finally {
    client.release();
  }
}

// ===== Acciones del cuidador =====
export async function aceptarAlerta({ alertaId, cuidadorId }) {
  const { rowCount } = await pool.query(
    `UPDATE alertas_asignaciones
       SET estado='EN_CAMINO', respondida_en=NOW()
     WHERE alerta_id=$1 AND cuidador_id=$2 AND estado='NOTIFICADA'`,
    [alertaId, cuidadorId]
  );
  if (!rowCount) return false;

  clearCountdown(alertaId);
  await pool.query(
    `INSERT INTO alertas_eventos (alerta_id, evento, metadata)
     VALUES ($1,'ACCEPTED', $2::jsonb)`,
    [alertaId, JSON.stringify({ cuidador_id: cuidadorId })]
  );
  if (ioRef) ioRef.to(`adulto_alerta:${alertaId}`).emit('cuidador_en_camino', { alertaId, cuidadorId });
  return true;
}

export async function derivarAlerta({ alertaId, cuidadorId }) {
  const { rowCount } = await pool.query(
    `UPDATE alertas_asignaciones
       SET estado='RECHAZADA', respondida_en=NOW()
     WHERE alerta_id=$1 AND cuidador_id=$2 AND estado='NOTIFICADA'`,
    [alertaId, cuidadorId]
  );
  if (!rowCount) return { forwarded: false };
  clearCountdown(alertaId);
  await onCountdownExpired(alertaId); // reusa el flujo
  return { forwarded: true };
}

export async function completarAlerta({ alertaId, cuidadorId }) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`UPDATE alertas SET atendida=true, estado='CERRADA' WHERE id=$1`, [alertaId]);
    await client.query(
      `UPDATE alertas_asignaciones
         SET estado='COMPLETADA', respondida_en=NOW()
       WHERE alerta_id=$1 AND cuidador_id=$2`,
      [alertaId, cuidadorId]
    );
    await client.query(
      `INSERT INTO alertas_eventos (alerta_id, evento, metadata)
       VALUES ($1,'COMPLETED', $2::jsonb)`,
      [alertaId, JSON.stringify({ by: cuidadorId })]
    );
    await client.query('COMMIT');
    clearCountdown(alertaId);
    if (ioRef) ioRef.to(`adulto_alerta:${alertaId}`).emit('alerta_completada', { alertaId });
    return true;
  } catch (e) {
    await client.query('ROLLBACK'); throw e;
  } finally {
    client.release();
  }
}
