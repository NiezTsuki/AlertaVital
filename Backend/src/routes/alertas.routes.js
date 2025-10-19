// src/routes/alertas.routes.js

import { Router } from 'express';
import { auth } from '../middleware/auth.js';
// Se añade la nueva función importada del servicio
import { 
  crearAlertaRT, 
  aceptarAlerta, 
  derivarAlerta, 
  completarAlerta, 
  getAlertasPendientesDeCuidador 
} from '../services/alertas.service.js';

const router = Router();

// ✅ NUEVA RUTA
// Devuelve las alertas que están asignadas al cuidador logueado y en estado 'PENDIENTE'.
router.get('/alertas/pendientes', auth, async (req, res) => {
  try {
    if (req.user?.rol !== 'CUIDADOR') {
      return res.status(403).json({ error: 'No autorizado' });
    }
    
    const alertas = await getAlertasPendientesDeCuidador(req.user.sub);
    res.json(alertas);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'No se pudo obtener las alertas pendientes' });
  }
});

// Adulto mayor emite SOS/CAIDA (con coords si están disponibles)
router.post('/alertas/sos', auth, async (req, res) => {
  try {
    if (req.user?.rol !== 'ADULTO_MAYOR') return res.status(403).json({ error: 'No autorizado' });

    const {
      tipo = 'SOS',
      descripcion = null,
      countdown = 30,
      latitud = null,
      longitud = null,
      precision_metros = null,
    } = req.body || {};

    const data = await crearAlertaRT({
      adultoId: req.user.sub,
      tipo,
      descripcion,
      countdownSeg: countdown,
      latitud,
      longitud,
      precision_metros,
    });

    res.status(201).json({ ok: true, ...data });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'No se pudo crear la alerta' });
  }
});

// Cuidador: Voy en camino
router.post('/alertas/:id/aceptar', auth, async (req, res) => {
  try {
    if (req.user?.rol !== 'CUIDADOR') return res.status(403).json({ error: 'No autorizado' });
    const ok = await aceptarAlerta({ alertaId: req.params.id, cuidadorId: req.user.sub });
    if (!ok) return res.status(409).json({ error: 'No disponible o ya tomada' });
    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Error al aceptar' });
  }
});

// Cuidador: Derivar
router.post('/alertas/:id/derivar', auth, async (req, res) => {
  try {
    if (req.user?.rol !== 'CUIDADOR') return res.status(403).json({ error: 'No autorizado' });
    const r = await derivarAlerta({ alertaId: req.params.id, cuidadorId: req.user.sub });
    res.json({ ok: true, ...r });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Error al derivar' });
  }
});

// Completar/cerrar
router.post('/alertas/:id/completar', auth, async (req, res) => {
  try {
    if (req.user?.rol !== 'CUIDADOR') return res.status(403).json({ error: 'No autorizado' });
    const ok = await completarAlerta({ alertaId: req.params.id, cuidadorId: req.user.sub });
    res.json({ ok });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'Error al completar' });
  }
});

export default router;