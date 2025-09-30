// src/routes/cuidadores.routes.js
import { Router } from 'express';
import { auth } from '../middleware/auth.js';
import {
  postSolicitarVinculo,
  postAceptarVinculo,
  postVincular,
  deleteDesvincular,
  getCuidadoresDeAdulto,
  getAdultosDeCuidador,
} from '../controllers/cuidadores.controller.js';

const router = Router();

// Flujo de invitación (bidireccional)
router.post('/cuidadores/solicitar', auth, postSolicitarVinculo);
router.post('/cuidadores/aceptar', auth, postAceptarVinculo);

// Flujo directo (opcional)
router.post('/cuidadores/vincular', auth, postVincular);
router.delete('/cuidadores/:adultoId/:cuidadorId', auth, deleteDesvincular);

// Listados
router.get('/cuidadores/de-adulto/:adultoId', auth, getCuidadoresDeAdulto);
router.get('/cuidadores/de-cuidador/:cuidadorId', auth, getAdultosDeCuidador);

export default router;
