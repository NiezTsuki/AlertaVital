// src/services/cuidadores.service.js
import { pool } from '../db/pool.js';

// Helpers
export async function getUserById(id) {
  const { rows } = await pool.query(
    'SELECT id, rol, nombre_completo, correo, telefono FROM usuarios WHERE id=$1',
    [id]
  );
  return rows[0] || null;
}

export async function getUserByCorreo(correo) {
  const { rows } = await pool.query(
    'SELECT id, rol, nombre_completo, correo, telefono FROM usuarios WHERE correo=$1',
    [correo]
  );
  return rows[0] || null;
}

export async function assertUserRole(id, rolEsperado) {
  const u = await getUserById(id);
  if (!u) throw new Error('USER_NOT_FOUND');
  if (u.rol !== rolEsperado) throw new Error('WRONG_ROLE');
  return u;
}

// Vínculo
export async function vincularCuidador({ adultoId, cuidadorId }) {
  await pool.query(
    `INSERT INTO cuidadores (adulto_id, cuidador_id)
     VALUES ($1,$2)
     ON CONFLICT (adulto_id, cuidador_id) DO NOTHING`,
    [adultoId, cuidadorId]
  );
}

export async function desvincularCuidador({ adultoId, cuidadorId }) {
  const { rowCount } = await pool.query(
    `DELETE FROM cuidadores WHERE adulto_id=$1 AND cuidador_id=$2`,
    [adultoId, cuidadorId]
  );
  return rowCount > 0;
}

export async function listarCuidadoresDeAdulto(adultoId) {
  const { rows } = await pool.query(
    `SELECT u.id AS cuidador_id, u.nombre_completo, u.correo, u.telefono, c.creado_en
     FROM cuidadores c
     JOIN usuarios u ON u.id = c.cuidador_id
     WHERE c.adulto_id = $1
     ORDER BY c.creado_en DESC`,
    [adultoId]
  );
  return rows;
}

export async function listarAdultosDeCuidador(cuidadorId) {
  const { rows } = await pool.query(
    `SELECT u.id AS adulto_id, u.nombre_completo, u.correo, u.telefono, c.creado_en
     FROM cuidadores c
     JOIN usuarios u ON u.id = c.adulto_id
     WHERE c.cuidador_id = $1
     ORDER BY c.creado_en DESC`,
    [cuidadorId]
  );
  return rows;
}
