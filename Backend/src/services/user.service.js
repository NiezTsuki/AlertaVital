import argon2 from 'argon2';
import jwt from 'jsonwebtoken';
import { prisma } from '../db/prisma.js'; 
import { config } from '../config/env.js';

export async function createUser({ rol, nombre_completo, correo, telefono, contrasena }) {
  const hash = await argon2.hash(contrasena, { type: argon2.argon2id });


  return await prisma.usuarios.create({
    data: {
      rol,
      nombre_completo,
      correo,
      telefono,
      contrasena_hash: hash,
    },
   
    select: {
      id: true,
      rol: true,
      nombre_completo: true,
      correo: true,
      telefono: true,
      creado_en: true,
    }
  });
}

export async function findUserByEmail(correo) {

  return await prisma.usuarios.findUnique({
    where: { correo: correo },
  });
}

export async function verifyPassword(hash, plain) {
  return argon2.verify(hash, plain);
}

export function issueToken(user) {
  const payload = { sub: user.id, rol: user.rol, nombre: user.nombre_completo };
  return jwt.sign(payload, config.jwtSecret, { expiresIn: config.jwtExpiresIn });
}

export async function getUserById(id) {
  return await prisma.usuarios.findUnique({
    where: { id: id },
    select: {
      id: true,
      rol: true,
      nombre_completo: true,
      correo: true,
      telefono: true,
      creado_en: true,
      ultimo_login: true,
    },
  });
}

export async function setLastLogin(id) {
  await prisma.usuarios.update({
    where: { id: id },
    data: { ultimo_login: new Date() },
  });
}

export async function updateFcmToken(userId, fcmToken) {
  await prisma.usuarios.update({
    where: { id: userId },
    data: { fcm_token: fcmToken },
  });
}

export async function setCorreoVerificado(userId) {
  await prisma.usuarios.update({
    where: { id: userId },
    data: { correo_verificado_en: new Date() },
  });
}