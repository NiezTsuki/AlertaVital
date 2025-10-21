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
};