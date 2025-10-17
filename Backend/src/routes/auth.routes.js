// src/routes/auth.routes.js

import { Router } from 'express';
import { register, login, me } from '../controllers/auth.controller.js';
import { auth } from '../middleware/auth.js';
import { findUserByEmail } from '../services/user.service.js';

// ===================== INICIO DEL CÓDIGO NUEVO =====================
import Pusher from 'pusher';
import { config } from '../config/env.js'; // Asegúrate de que este import exista o añádelo

// Instancia de Pusher (necesaria para autorizar)
const pusher = new Pusher({
  appId: config.pusherAppId,
  key: config.pusherKey,
  secret: config.pusherSecret,
  cluster: config.pusherCluster,
  useTLS: true,
});
// ====================== FIN DEL CÓDIGO NUEVO =======================

const router = Router();
router.post('/register', register);
router.post('/login', login);
router.get('/me', auth, me);

router.get('/usuarios/por-correo', auth, async (req, res) => {
  // ... (tu código existente aquí, no cambia)
});

// ===================== INICIO DEL CÓDIGO NUEVO =====================
// ESTE ES EL NUEVO ENDPOINT PARA AUTORIZAR CANALES PRIVADOS DE PUSHER
router.post('/pusher/auth', auth, (req, res) => {
  try {
    const socketId = req.body.socket_id;
    const channel = req.body.channel_name;
    const userIdFromToken = req.user.sub; // ID del usuario autenticado por el token JWT

    // Extraemos el ID del canal (ej. 'private-user-12345')
    const channelUserId = channel.split('-').pop();
    
    // Medida de seguridad CRÍTICA:
    // Aseguramos que un usuario solo pueda suscribirse a su propio canal privado.
    if (channel.startsWith('private-user-') && channelUserId !== userIdFromToken) {
      console.warn(`[PUSHER AUTH] Intento denegado: Usuario ${userIdFromToken} intentó acceder al canal ${channel}`);
      return res.status(403).send('Forbidden');
    }
    
    // Para el canal de una alerta ('private-alerta-XYZ'), por ahora permitimos
    // que cualquiera que esté autenticado se suscriba. Podrías añadir lógica
    // más estricta si fuera necesario (ej. verificar si es el adulto o un cuidador vinculado).

    const presenceData = {
      user_id: userIdFromToken,
      user_info: { rol: req.user.rol } // Puedes añadir más info si es útil
    };
    
    const authResponse = pusher.authorizeChannel(socketId, channel, presenceData);
    res.send(authResponse);
  } catch (error) {
    console.error('[PUSHER AUTH] Error:', error);
    res.status(500).send('Internal Server Error');
  }
});
// ====================== FIN DEL CÓDIGO NUEVO =======================


export default router;