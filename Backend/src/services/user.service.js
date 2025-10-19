import argon2 from 'argon2';
import jwt from 'jsonwebtoken';
import { pool } from '../db/pool.js';
import { config } from '../config/env.js';

export async function createUser({ rol, nombre_completo, correo, telefono, contrasena }) {
  const hash = await argon2.hash(contrasena, { type: argon2.argon2id });
  const q = `INSERT INTO usuarios (rol, nombre_completo, correo, telefono, contrasena_hash)
             VALUES ($1,$2,$3,$4,$5)
             RETURNING id, rol, nombre_completo, correo, telefono, creado_en`;
  const { rows } = await pool.query(q, [rol, nombre_completo, correo, telefono, hash]);
  return rows[0];
}

export async function findUserByEmail(correo) {
  const { rows } = await pool.query('SELECT * FROM usuarios WHERE correo=$1', [correo]);
  return rows[0] || null;
}

export async function verifyPassword(hash, plain) {
  return argon2.verify(hash, plain);
}

export function issueToken(user) {
  const payload = { sub: user.id, rol: user.rol, nombre: user.nombre_completo };
  return jwt.sign(payload, config.jwtSecret, { expiresIn: config.jwtExpiresIn });
}

export async function getUserById(id) {
  const { rows } = await pool.query(
    'SELECT id, rol, nombre_completo, correo, telefono, creado_en, ultimo_login FROM usuarios WHERE id=$1',
    [id]
  );
  return rows[0] || null;
}

export async function setLastLogin(id) {
  await pool.query('UPDATE usuarios SET ultimo_login=NOW() WHERE id=$1', [id]);
}

// ✅ NUEVA FUNCIÓN AÑADIDA
// Esta función recibe el ID de un usuario y un token de Firebase (FCM)
// y lo guarda en la columna 'fcm_token' de la base de datos.
export async function updateFcmToken(userId, fcmToken) {
  await pool.query(
    `UPDATE usuarios SET fcm_token = $1 WHERE id = $2`,
    [fcmToken, userId]
  );
}