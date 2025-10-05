import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import { pool } from '../db/pool.js';

const router = Router();

// Registrar ubicación actual (app la envía cada N segundos)
router.post('/ubicaciones', auth, async (req, res) => {
  try {
    const userId = req.user.sub;
    const { latitud, longitud, precision_metros } = req.body || {};
    if (typeof latitud !== 'number' || typeof longitud !== 'number') {
      return res.status(400).json({ error: 'latitud y longitud numéricos requeridos' });
    }
    await pool.query(
      `INSERT INTO ubicaciones (usuario_id, latitud, longitud, precision_metros, detectado_en)
       VALUES ($1,$2,$3,$4,NOW())`,
      [userId, latitud, longitud, precision_metros ?? null]
    );
    res.json({ ok: true });
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'No se pudo guardar la ubicación' });
  }
});

// Última ubicación conocida
router.get('/ubicaciones/ultima/:usuarioId', auth, async (req, res) => {
  try {
    const { usuarioId } = req.params;
    const { rows } = await pool.query(
      `SELECT latitud, longitud, precision_metros, detectado_en
         FROM ubicaciones
        WHERE usuario_id=$1
        ORDER BY detectado_en DESC
        LIMIT 1`,
      [usuarioId]
    );
    res.json(rows[0] ?? null);
  } catch (e) {
    console.error(e);
    res.status(500).json({ error: 'No se pudo obtener la ubicación' });
  }
});

export default router;
