// src/routes/usuarios.routes.js
import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { updateFcmToken } from '../services/user.service.js';

const router = Router();

// Esta ruta recibe el token FCM desde la app y lo guarda en la base de datos
router.post('/usuarios/fcm-token', auth, async (req, res) => {
  try {
    const { fcm_token } = req.body;
    if (!fcm_token) {
      return res.status(400).json({ error: 'fcm_token es requerido' });
    }
    // Llama al servicio para actualizar el token del usuario logueado
    await updateFcmToken(req.user.sub, fcm_token);
    res.json({ ok: true });
  } catch (e) {
    console.error('Error al guardar fcm_token:', e);
    res.status(500).json({ error: 'Error interno del servidor' });
  }
});

export default router;