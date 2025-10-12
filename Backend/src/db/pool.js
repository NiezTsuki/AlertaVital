import pkg from 'pg';
const { Pool } = pkg;

// CAMBIO 1: Usamos DATABASE_URL, que es la variable estándar y la que ya tienes en Vercel.
const connString = process.env.DATABASE_URL;
let pool;

if (connString) {
  // Si la variable de conexión existe (como en Vercel), la usamos.
  pool = new Pool({
    connectionString: connString,
    // CAMBIO 2: Añadimos SSL. Es OBLIGATORIO para bases de datos en la nube como Vercel Postgres.
    ssl: {
      rejectUnauthorized: false,
    },
  });
} else {
  // Este bloque ahora solo se usará para desarrollo local si no tienes un .env
  console.warn("ADVERTENCIA: No se encontró DATABASE_URL. Conectando a la base de datos local.");
  pool = new Pool({
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'AlertaVital',
    port: parseInt(process.env.DB_PORT || '5432', 10),
  });
}

export { pool };