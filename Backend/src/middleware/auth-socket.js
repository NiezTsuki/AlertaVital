// src/middleware/auth-socket.js
// Middleware de autenticación para Socket.IO compatible con:
// - Authorization: Bearer <jwt>  (Android/iOS/Desktop)
// - handshake.auth.token          (Flutter Web)
// - query.token                   (fallback opcional)
import jwt from 'jsonwebtoken';
import { config } from '../config/env.js'; // asegúrate de exponer config.jwtSecret

export function authMiddlewareSocket(socket, next) {
  try {
    let token = null;

    // 1) Header Authorization
    const h = socket.handshake.headers?.authorization || socket.handshake.headers?.Authorization;
    if (h && typeof h === 'string' && h.startsWith('Bearer ')) {
      token = h.slice(7).trim();
    }

    // 2) handshake.auth.token (WEB)
    if (!token && socket.handshake?.auth?.token) {
      token = socket.handshake.auth.token;
    }

    // 3) query.token (fallback)
    if (!token && socket.handshake?.query?.token) {
      token = socket.handshake.query.token;
    }

    if (!token) return next(new Error('No token'));

    const payload = jwt.verify(token, config.jwtSecret);
    // Esperamos que el JWT lleve { sub, rol }
    socket.user = { sub: payload.sub, rol: payload.rol };
    return next();
  } catch (e) {
    return next(new Error('Unauthorized'));
  }
}
