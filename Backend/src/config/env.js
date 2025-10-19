// src/config/env.js

import dotenv from 'dotenv';
dotenv.config();

// ===================== CÓDIGO DE DEPURACIÓN =====================
// Estas líneas nos ayudarán a confirmar que Vercel está leyendo las variables correctamente.
console.log("--- INICIANDO SERVIDOR ---");
console.log("JWT_SECRET leído:", process.env.JWT_SECRET ? "OK" : "NO ENCONTRADO");
console.log("PUSHER_SECRET leído:", process.env.PUSHER_SECRET ? "OK" : "NO ENCONTRADO");
// ================================================================

export const config = {
  port: process.env.PORT || 3000,
  jwtSecret: process.env.JWT_SECRET || 'dev',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '1d',
  databaseUrl: process.env.DATABASE_URL || '',
  nodeEnv: process.env.NODE_ENV || 'development',

  // ✅ ============ INICIO DE LA CORRECCIÓN ============ ✅
  //
  //      Añade estas cuatro líneas para que tu código lea
  //      las variables de Pusher desde el entorno de Vercel.
  //
  pusherAppId:   process.env.PUSHER_APP_ID,
  pusherKey:     process.env.PUSHER_KEY,
  pusherSecret:  process.env.PUSHER_SECRET,
  pusherCluster: process.env.PUSHER_CLUSTER,
  // ✅ ============= FIN DE LA CORRECCIÓN ============= ✅

  firebaseServiceAccountJson: process.env.FIREBASE_SERVICE_ACCOUNT_JSON,
};