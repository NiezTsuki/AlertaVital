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

// 🛑 INICIO: CORRECCIÓN DE CORS (HTTP) 🛑
// 1. Se define la lista de orígenes permitidos (Frontend local y el de Vercel)
const allowedOrigins = [
  'http://localhost:64069', // 👈 Tu frontend local (el puerto puede variar)
  'http://localhost:8080',  // Puertos comunes de desarrollo
  'http://localhost:3000',
  'https://alerta-vital-nine.vercel.app', // Tu dominio de Vercel
];

app.use(cors({ 
  origin: (origin, callback) => {
    // Permitir si el origen está en la lista o si no hay origen (ej: Postman, o si es la misma Vercel)
    if (!origin || allowedOrigins.includes(origin)) {
      callback(null, true);
    } else {
      // Devolver un error específico de CORS para el log
      callback(new Error('Not allowed by CORS')); 
    }
  },
  methods: ['GET','POST','PUT','DELETE','PATCH'],
  credentials: true, 
}));
// 🛑 FIN: CORRECCIÓN DE CORS (HTTP) 🛑

app.use(express.json());
app.use(morgan('dev'));

// Rutas HTTP (NO SE MODIFICARON)
app.use('/api', cuidadoresRoutes);
app.use('/api', authRoutes);
app.use('/auth', authRoutes);
// Ubicaciones
app.use('/api', ubicacionesRoutes);
app.use('/api', alertasPosRoutes);
// NUEVO: alertas (SOS, aceptar, derivar, completar)
app.use('/api', alertasRoutes);

app.get('/health', (_req, res) => res.json({ ok: true }));

app.use((_req, res) => res.status(404).json({ error: 'Not found' }));

// HTTP server + Socket.IO
const server = http.createServer(app);
const io = new Server(server, {
  // 🛑 INICIO: CORRECCIÓN DE CORS (Socket.IO) 🛑
  cors: { 
    origin: allowedOrigins, // Usamos la misma lista de orígenes
    methods: ['GET','POST'], 
    credentials: true,
  },
  // 🛑 FIN: CORRECCIÓN DE CORS (Socket.IO) 🛑
});

// Auth JWT para sockets (usa tu middleware)
io.use(authMiddlewareSocket);

// Salas por rol y por alerta
io.on('connection', (socket) => {
  const user = socket.user; // { sub, rol }
  if (!user) return socket.disconnect(true);

  // Salas por usuario
  if (user.rol === 'ADULTO_MAYOR') socket.join(`adulto:${user.sub}`);
  if (user.rol === 'CUIDADOR') socket.join(`cuidador:${user.sub}`);

  // Salas de alertas (para notificaciones en tiempo real)
  socket.on('join_alerta', (data) => {
    if (data.alertaId) {
      socket.join(`alerta:${data.alertaId}`);
      // Notificar al adulto si el cuidador se une
      if (user.rol === 'CUIDADOR') {
        io.to(`adulto:${user.sub}`).emit('cuidador_en_camino', { cuidadorId: user.sub });
      }
    }
  });

  socket.on('disconnect', () => {
    // Manejo de desconexión
  });
});

// Se debe configurar el servicio para emitir alertas
setAlertsIO(io);

// Inicio del servidor
server.listen(config.port, () => {
  console.log(`Server listening on port ${config.port}`);
});