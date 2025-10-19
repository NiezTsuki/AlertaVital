// src/server.js
import express from 'express';
import morgan from 'morgan';
import cors from 'cors';
import helmet from 'helmet';

import authRoutes from './routes/auth.routes.js';
import cuidadoresRoutes from './routes/cuidadores.routes.js';
import alertasRoutes from './routes/alertas.routes.js';
import ubicacionesRoutes from './routes/ubicaciones.routes.js';
import alertasPosRoutes from './routes/alertas_posiciones.routes.js';
import usuariosRoutes from './routes/usuarios.routes.js'; 

const app = express();
app.use(helmet());
app.use(cors({ origin: '*', methods: ['GET','POST','PUT','DELETE','PATCH'] }));
app.use(express.json());
app.use(morgan('dev'));

// Rutas HTTP
app.use('/api', cuidadoresRoutes);
app.use('/api', authRoutes);
app.use('/auth', authRoutes);
app.use('/api', ubicacionesRoutes);
app.use('/api', alertasPosRoutes);
app.use('/api', alertasRoutes);
app.use('/api', usuariosRoutes); 
app.get('/health', (_req, res) => res.json({ ok: true }));
app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

export default app;