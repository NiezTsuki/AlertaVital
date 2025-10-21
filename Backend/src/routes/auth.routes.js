import { Router } from 'express';
import { register, login, me } from '../controllers/auth.controller.js';
import { auth } from '../middleware/auth.js';
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

// --- Rutas de Autenticación ---
router.post('/register', register);
router.post('/login', login);
router.get('/me', auth, me);


// --- Ruta de Autorización para Pusher ---
// Este endpoint es crucial para la seguridad de tus canales privados.
router.post('/pusher/auth', auth, (req, res) => {
  try {
    const socketId = req.body.socket_id;
    const channel = req.body.channel_name;
    const userIdFromToken = req.user.sub; // ID del usuario autenticado

    // Se verifica que el usuario solo pueda suscribirse a su propio canal privado.
    if (channel.startsWith('private-user-')) {
      const channelUserId = channel.replace('private-user-', '');

      // Si el ID del token no coincide con el ID del canal, se deniega el acceso.
      if (channelUserId !== userIdFromToken) {
        console.warn(`[PUSHER AUTH] ACCESO DENEGADO: El usuario ${userIdFromToken} intentó acceder al canal privado de otro usuario: ${channel}`);
        return res.status(403).send('Forbidden');
      }
    }
    
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