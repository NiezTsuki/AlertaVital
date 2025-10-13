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

const app = express();
app.use(helmet());
app.use(cors({ origin: '*', methods: ['GET','POST','PUT','DELETE','PATCH'] }));
app.use(express.json());
app.use(morgan('dev'));

// Rutas HTTP
app.use('/api', cuidadoresRoutes);
app.use('/api', authRoutes);
app.use('/auth', authRoutes);
// Ubicaciones
app.use('/api', ubicacionesRoutes);
app.use('/api', alertasPosRoutes);
// NUEVO: alertas (SOS, aceptar, derivar, completar)
app.use('/api', alertasRoutes);

app.get('/health', (_req, res) => res.json({ ok: true }));

// Nota: evitamos duplicar /auth (ya está en /api)
// app.use('/auth', authRoutes);

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

// HTTP server + Socket.IO
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: '*', methods: ['GET','POST'] },
  // ===================== INICIO DE LA SOLUCIÓN =====================
  // AÑADIDO: Especifica explícitamente los transportes permitidos.
  // Esto soluciona el error "Transport unknown" en Vercel.
  transports: ['polling', 'websocket']
  // ====================== FIN DE LA SOLUCIÓN =======================
});

// Auth JWT para sockets (usa tu middleware)
io.use(authMiddlewareSocket);

// Salas por rol y por alerta
io.on('connection', (socket) => {
  const user = socket.user; // { sub, rol }
  if (!user) return socket.disconnect(true);

  // Salas por usuario
  if (user.rol === 'ADULTO_MAYOR') socket.join(`adulto:${user.sub}`);
  if (user.rol === 'CUIDADOR')     socket.join(`cuidador:${user.sub}`);

  // Sala por alerta cuando el adulto abre el detalle
  socket.on('join_alerta', ({ alertaId }) => {
    if (alertaId) socket.join(`adulto_alerta:${alertaId}`);
  });
});

// Inyecta io al servicio de alertas
setAlertsIO(io);

server.listen(config.port, () =>
  console.log(`API + Sockets escuchando en http://localhost:${config.port}`)
);