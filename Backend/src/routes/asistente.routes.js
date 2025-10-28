import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { conversarConGemini } from '../services/asistente.service.js';

const router = Router();

// CAMBIO: La ruta debe ser solo '/conversar'. El prefijo '/api/asistente' se añade en server.js
router.post('/conversar', auth, async (req, res) => {
    try {
        const { texto, historial = [] } = req.body;
        if (!texto) return res.status(400).json({ error: 'El texto es requerido.' });

        const respuesta = await conversarConGemini(texto, historial);
        res.json({ respuesta });

    } catch (e) {
        // Dejamos el log aquí para ver el error en Vercel si falla Gemini
        console.error("Error al procesar la solicitud con Gemini:", e); 
        res.status(500).json({ error: 'Error al procesar la solicitud con Gemini.' });
    }
});

export default router;
