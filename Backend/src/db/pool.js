import pkg from 'pg';
const { Pool } = pkg;

// CORRECCIÓN: Usa la variable con la URL directa, no la de Prisma Accelerate.
const connString = process.env.alertavital_POSTGRES_URL;
let pool;

if (connString) {
  pool = new Pool({
    connectionString: connString,
    ssl: {
      rejectUnauthorized: false,
    },
  });
} else {
  // Este bloque es para desarrollo local si la variable no existe.
  console.warn("ADVERTENCIA: No se encontró la variable de conexión. Conectando a local.");
  pool = new Pool({
    host: 'localhost',
    user: 'postgres',
    password: '',
    database: 'AlertaVital',
    port: 5432,
  });
}

export { pool };