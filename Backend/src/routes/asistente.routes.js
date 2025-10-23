import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { conversarConGemini } from '../services/asistente.service.js';

const router = Router();

router.post('/asistente/conversar', auth, async (req, res) => {
  try {
    const { texto, historial = [] } = req.body;
    if (!texto) return res.status(400).json({ error: 'El texto es requerido.' });

    const respuesta = await conversarConGemini(texto, historial);
    res.json({ respuesta });

  } catch (e) {
    res.status(500).json({ error: 'Error al procesar la solicitud.' });
  }
});

export default router;