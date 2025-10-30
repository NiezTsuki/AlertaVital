import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { conversarConGemini } from '../services/asistente.service.js';

const router = Router();

router.post('/conversar', auth, async (req, res) => {
    try {
        const { texto, historial = [] } = req.body;
        if (!texto) {
            return res.status(400).json({ error: 'El texto es requerido.' });
        }

        let respuesta = await conversarConGemini(texto, historial);
        
        // Limpieza de caracteres extraños antes de enviar (buena práctica)
        if (typeof respuesta === 'string') {
            respuesta = respuesta.replace(/[*#_`]/g, '');
            respuesta = respuesta.replace(/[\x00-\x1F\x7F-\x9F]/g, '');
            respuesta = respuesta.replace(/[\n\r]/g, ' ').trim();
        }

        res.json({ respuesta });

    } catch (e) {
        console.error("Error al procesar la solicitud con Gemini:", e.message); 
        res.status(500).json({ error: `Error al procesar la solicitud: ${e.message}` });
    }
});

export default router;