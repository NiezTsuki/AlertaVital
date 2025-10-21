import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { prisma } from '../db/prisma.js';
import Pusher from 'pusher';
import { config } from '../config/env.js';

const router = Router();

const pusher = new Pusher({
  appId: config.pusherAppId,
  key: config.pusherKey,
  secret: config.pusherSecret,
  cluster: config.pusherCluster,
  useTLS: true,
});

// Guardar punto de traza asociado a una alerta (adulto/cuidador)
router.post('/alertas/:id/posicion', auth, async (req, res) => {
  try {
    const alertaId = req.params.id;
    const userId = req.user.sub;
    const rol = req.user.rol;
    const { latitud, longitud, precision_metros } = req.body || {};
    
    if (typeof latitud !== 'number' || typeof longitud !== 'number') {
      return res.status(400).json({ error: 'latitud y longitud numéricos requeridos' });
    }

    await prisma.alertas_posiciones.create({
      data: {
        alerta_id: alertaId,
        usuario_id: userId,
        rol: rol,
        latitud: latitud,
        longitud: longitud,
        precision_metros: precision_metros,
      },
    });

    // Notificar en tiempo real al mapa (sin cambios)
    await pusher.trigger(`private-alerta-${alertaId}`, 'posicion_actualizada', {
      usuario_id: userId,
      rol: rol,
      latitud: latitud,
      longitud: longitud,
      precision_metros: precision_metros,
      capturada_en: new Date().toISOString(),
    });

    res.json({ ok: true });
  } catch (e) {
    console.error(`[ERROR /api/alertas/:id/posicion]`, e);
    res.status(500).json({ error: 'No se pudo guardar la posición' });
  }
});

// Obtener últimos puntos (para pintar ruta)
router.get('/alertas/:id/posiciones', auth, async (req, res) => {
  try {
    const alertaId = req.params.id;
    const { rol } = req.query;

    const whereClause = {
      alerta_id: alertaId,
    };

    if (rol === 'ADULTO_MAYOR' || rol === 'CUIDADOR') {
      whereClause.rol = rol;
    }
    
    const rows = await prisma.alertas_posiciones.findMany({
      where: whereClause,
      orderBy: {
        capturada_en: 'desc',
      },
      take: 500, // 'take' es el equivalente de 'LIMIT'
      select: { // Seleccionamos solo los campos necesarios
        usuario_id: true,
        rol: true,
        latitud: true,
        longitud: true,
        precision_metros: true,
        capturada_en: true,
      },
    });
    
    res.json(rows);
  } catch (e) {
    console.error(`[ERROR /api/alertas/:id/posiciones]`, e);
    res.status(500).json({ error: 'No se pudo obtener las posiciones' });
  }
});

export default router;