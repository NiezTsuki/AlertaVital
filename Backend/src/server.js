import http from 'http';
import express from 'express';
import morgan from 'morgan';
import cors from 'cors';
import helmet from 'helmet';
import { Server } from 'socket.io';

import { config } from './config/env.js';
import authRoutes from './routes/auth.routes.js';
import cuidadoresRoutes from './routes/cuidadores.routes.js';
import alertasRoutes from './routes/alertas.routes.js';
import { authMiddlewareSocket } from './middleware/auth-socket.js';
import { setAlertsIO } from './services/alertas.service.js';
import ubicacionesRoutes from './routes/ubicaciones.routes.js';
import alertasPosRoutes from './routes/alertas_posiciones.routes.js';

// 1. Configura la aplicación Express como antes
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
app.get('/health', (_req, res) => res.json({ ok: true }));
app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

// 2. Crea el servidor HTTP y el servidor de Socket.IO
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET','POST'] },
  transports: ['websocket'],
  //allowEIO3: false
});

// 3. Aplica el middleware y la lógica de Socket.IO
io.use(authMiddlewareSocket);

io.on('connection', (socket) => {
  const user = socket.user;
  if (!user) return socket.disconnect(true);

  if (user.rol === 'ADULTO_MAYOR') socket.join(`adulto:${user.sub}`);
  if (user.rol === 'CUIDADOR')     socket.join(`cuidador:${user.sub}`);

  socket.on('join_alerta', ({ alertaId }) => {
    if (alertaId) socket.join(`adulto_alerta:${alertaId}`);
  });
});

setAlertsIO(io);

// 4. ELIMINA server.listen(...) Y EXPORTA EL SERVIDOR
// Vercel tomará este objeto y lo manejará correctamente.
export default server;