import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { conversarConGemini } from '../services/asistente.service.js';

const router = Router();

router.post('/conversar', auth, async (req, res) => {
    try {
        const { texto, historial = [] } = req.body;
        if (!texto) return res.status(400).json({ error: 'El texto es requerido.' });

        let respuesta = await conversarConGemini(texto, historial);
        
        if (typeof respuesta === 'string') {
            respuesta = respuesta.replace(/\n/g, ' ').replace(/\r/g, ' ').trim();
        }
        
        res.json({ respuesta });

    } catch (e) {
        // Log para ver el error en Vercel si falla Gemini
        console.error("Error al procesar la solicitud con Gemini:", e); 
        res.status(500).json({ error: 'Error al procesar la solicitud con Gemini.' });
    }
});

export default router;