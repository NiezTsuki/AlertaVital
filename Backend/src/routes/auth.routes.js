// src/routes/auth.routes.js

import { Router } from 'express';
import { register, login, me } from '../controllers/auth.controller.js';
import { auth } from '../middleware/auth.js';
import { findUserByEmail } from '../services/user.service.js';

import Pusher from 'pusher';
import { config } from '../config/env.js';

const pusher = new Pusher({
  appId: config.pusherAppId,
  key: config.pusherKey,
  secret: config.pusherSecret,
  cluster: config.pusherCluster,
  useTLS: true,
});

const router = Router();
router.post('/register', register);
router.post('/login', login);
router.get('/me', auth, me);

router.get('/usuarios/por-correo', auth, async (req, res) => {
  // ... (tu código existente aquí, no cambia)
});


// ESTE ES EL ENDPOINT CON LA CORRECCIÓN
router.post('/pusher/auth', auth, (req, res) => {
  try {
    const socketId = req.body.socket_id;
    const channel = req.body.channel_name;
    const userIdFromToken = req.user.sub; // ID del usuario autenticado por el token JWT

    // ✅ CORRECCIÓN DEFINITIVA:
    // En lugar de usar split().pop(), que se rompe con los guiones del UUID,
    // simplemente reemplazamos el prefijo para obtener el ID completo.
    if (channel.startsWith('private-user-')) {
      const channelUserId = channel.replace('private-user-', '');

      // Medida de seguridad CRÍTICA:
      // Ahora esta comparación funcionará correctamente.
      if (channelUserId !== userIdFromToken) {
        console.warn(`[PUSHER AUTH] Intento denegado: Usuario ${userIdFromToken} intentó acceder al canal ${channel}`);
        return res.status(403).send('Forbidden');
      }
    }
    
    // Para el canal de una alerta ('private-alerta-XYZ'), por ahora permitimos
    // que cualquiera que esté autenticado se suscriba.

    const presenceData = {
      user_id: userIdFromToken,
      user_info: { rol: req.user.rol }
    };
    
    const authResponse = pusher.authorizeChannel(socketId, channel, presenceData);
    res.send(authResponse);
  } catch (error) {
    console.error('[PUSHER AUTH] Error:', error);
    res.status(500).send('Internal Server Error');
  }
});


export default router;