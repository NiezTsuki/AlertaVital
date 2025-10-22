import dotenv from 'dotenv';
dotenv.config();

//conexiones
export const config = {
  port: process.env.PORT || 3000,
  jwtSecret: process.env.JWT_SECRET || 'dev',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '1d',
  databaseUrl: process.env.DATABASE_URL || '',
  nodeEnv: process.env.NODE_ENV || 'development',

//pusher
  pusherAppId:   process.env.PUSHER_APP_ID,
  pusherKey:     process.env.PUSHER_KEY,
  pusherSecret:  process.env.PUSHER_SECRET,
  pusherCluster: process.env.PUSHER_CLUSTER,

  //servicios firebase
  firebaseServiceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON,

  // URL de tu aplicación frontend (para los correos)
  frontendUrl: process.env.FRONTEND_URL,
  
  // URL de reestablecer contraseña
  cambiodUrl: process.env.CAMBIO_URL,

  // API Key para el envío de correos
  resendApiKey: process.env.RESEND_API_KEY
};