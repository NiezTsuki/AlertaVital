//npx knex seed:run

// Backend/db/seeds/001_sample_usuario.js
import bcrypt from 'bcryptjs';

export async function seed(knex) {
  await knex('usuarios').del();

  const hashedPassword = await bcrypt.hash('password123', 10);
  const now = new Date();

  await knex('usuarios').insert([
    {
      rol: 'ADMIN',
      nombre_completo: 'Administrador Principal',
      correo: 'admin@cuidamientomayor.com',
      telefono: '+56912345678',
      contrasena_hash: hashedPassword,
      correo_verificado_en: now,
      creado_en: now,
      ultimo_login: now
    },
    {
      rol: 'ADULTO_MAYOR',
      nombre_completo: 'María González López',
      correo: 'maria.gonzalez@email.com',
      telefono: '+56987654321',
      contrasena_hash: hashedPassword,
      correo_verificado_en: now,
      creado_en: now,
      ultimo_login: now
    },
    {
      rol: 'ADULTO_MAYOR',
      nombre_completo: 'Carlos Rodríguez Pérez',
      correo: 'carlos.rodriguez@email.com',
      telefono: '+56955556666',
      contrasena_hash: hashedPassword,
      correo_verificado_en: now,
      creado_en: now
    },
    {
      rol: 'CUIDADOR',
      nombre_completo: 'Ana Silva Martínez',
      correo: 'ana.silva@email.com',
      telefono: '+56977778888',
      contrasena_hash: hashedPassword,
      correo_verificado_en: now,
      creado_en: now,
      ultimo_login: now
    },
    {
      rol: 'CUIDADOR',
      nombre_completo: 'Pedro López García',
      correo: 'pedro.lopez@email.com',
      telefono: '+56999990000',
      contrasena_hash: hashedPassword,
      correo_verificado_en: now,
      creado_en: now
    }
  ]);
}