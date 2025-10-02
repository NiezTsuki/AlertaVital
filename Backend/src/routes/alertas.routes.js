import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { crearAlertaRT, aceptarAlerta, derivarAlerta, completarAlerta } from '../services/alertas.service.js';

const router = Router();

// Adulto mayor emite SOS/CAIDA
router.post('/alertas/sos', auth, async (req, res) => {
  try {
    if (req.user?.rol !== 'ADULTO_MAYOR') {
      return res.status(403).json({ error: 'No autorizado' });
    }
    const { tipo='SOS', descripcion=null, countdown=30 } = req.body || {};
    const data = await crearAlertaRT({ adultoId: req.user.sub, tipo, descripcion, countdownSeg: countdown });
    res.status(201).json({ ok: true, ...data });
  } catch (e) {
    console.error(e); res.status(500).json({ error: 'No se pudo crear la alerta' });
  }
});

// Cuidador: Voy en camino
router.post('/alertas/:id/aceptar', auth, async (req, res) => {
  try {
    if (req.user?.rol !== 'CUIDADOR') {
      return res.status(403).json({ error: 'No autorizado' });
    }
    const ok = await aceptarAlerta({ alertaId: req.params.id, cuidadorId: req.user.sub });
    if (!ok) return res.status(409).json({ error: 'No disponible o ya tomada' });
    res.json({ ok: true });
  } catch (e) {
    console.error(e); res.status(500).json({ error: 'Error al aceptar' });
  }
});

// Cuidador: Derivar
router.post('/alertas/:id/derivar', auth, async (req, res) => {
  try {
    if (req.user?.rol !== 'CUIDADOR') {
      return res.status(403).json({ error: 'No autorizado' });
    }
    const r = await derivarAlerta({ alertaId: req.params.id, cuidadorId: req.user.sub });
    res.json({ ok: true, ...r });
  } catch (e) {
    console.error(e); res.status(500).json({ error: 'Error al derivar' });
  }
});

// Completar/cerrar (opcional)
router.post('/alertas/:id/completar', auth, async (req, res) => {
  try {
    if (req.user?.rol !== 'CUIDADOR') {
      return res.status(403).json({ error: 'No autorizado' });
    }
    const ok = await completarAlerta({ alertaId: req.params.id, cuidadorId: req.user.sub });
    res.json({ ok });
  } catch (e) {
    console.error(e); res.status(500).json({ error: 'Error al completar' });
  }
});

export default router;
