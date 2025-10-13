import dotenv from 'dotenv';
dotenv.config();

// ===================== INICIO CÓDIGO DE DEPURACIÓN =====================
console.log("--- INICIANDO SERVIDOR ---");
console.log("SECRET LEÍDO DESDE VERCEL (process.env.JWT_SECRET):", process.env.JWT_SECRET);
// ====================== FIN CÓDIGO DE DEPURACIÓN =======================

export const config = {
  port: process.env.PORT || 3000,
  jwtSecret: process.env.JWT_SECRET || 'dev',
  jwtExpiresIn: process.env.JWT_EXPIRES_IN || '1d',
  databaseUrl: process.env.DATABASE_URL || '',
  nodeEnv: process.env.NODE_ENV || 'development',
};