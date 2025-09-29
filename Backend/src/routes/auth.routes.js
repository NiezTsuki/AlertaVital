import { Router } from 'express';
import { register, login, me } from '../controllers/auth.controller.js';
import { auth } from '../middleware/auth.js';
import { findUserByEmail } from '../services/user.service.js';

const router = Router();
router.post('/register', register);
router.post('/login', login);
router.get('/me', auth, me);

router.get('/usuarios/por-correo', auth, async (req, res) => {
  const correo = (req.query.correo || '').toString().toLowerCase().trim();
  if (!correo) return res.status(400).json({ error: 'correo requerido' });
  try {
    const u = await findUserByEmail(correo);
    if (!u) return res.status(404).json({ error: 'no encontrado' });
    const { id, rol, nombre_completo, correo: c, telefono } = u;
    res.json({ id, rol, nombre_completo, correo: c, telefono });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'error interno' });
  }
});

export default router;
