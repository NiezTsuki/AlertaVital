import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { prisma } from '../db/prisma.js';

const router = Router();

// Registrar ubicación actual (app la envía cada N segundos)
router.post('/ubicaciones', auth, async (req, res) => {
  try {
    const userId = req.user.sub;
    const { latitud, longitud, precision_metros } = req.body || {};
    
    if (typeof latitud !== 'number' || typeof longitud !== 'number') {
      return res.status(400).json({ error: 'latitud y longitud numéricos requeridos' });
    }

    await prisma.ubicaciones.create({
      data: {
        usuario_id: userId,
        latitud: latitud,
        longitud: longitud,
        precision_metros: precision_metros,
      },
    });
    
    res.json({ ok: true });
  } catch (e) {
    console.error(`[ERROR /api/ubicaciones]`, e);
    res.status(500).json({ error: 'No se pudo guardar la ubicación' });
  }
});

// Última ubicación conocida
router.get('/ubicaciones/ultima/:usuarioId', auth, async (req, res) => {
  try {
    const { usuarioId } = req.params;
    const lastLocation = await prisma.ubicaciones.findFirst({
      where: {
        usuario_id: usuarioId,
      },
      orderBy: {
        detectado_en: 'desc',
      },
      select: {
        latitud: true,
        longitud: true,
        precision_metros: true,
        detectado_en: true,
      },
    });
    
    res.json(lastLocation ?? null);
  } catch (e) {
    console.error(`[ERROR /api/ubicaciones/ultima/:usuarioId]`, e);
    res.status(500).json({ error: 'No se pudo obtener la ubicación' });
  }
});

export default router;