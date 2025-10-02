import pkg from 'pg';
import { config } from '../config/env.js';
const { Pool } = pkg;

const connString = config.databaseUrl;
let pool;

if (connString) {
  pool = new Pool({ connectionString: connString });
} else {
  pool = new Pool({
    host: process.env.DB_HOST || 'localhost',
    user: process.env.DB_USER || 'postgres',
    password: process.env.DB_PASSWORD || '',
    database: process.env.DB_NAME || 'AlertaVital',
    port: parseInt(process.env.DB_PORT || '5432', 10),
  });
}

export { pool };
