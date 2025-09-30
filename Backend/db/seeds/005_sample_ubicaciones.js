// Backend/db/seeds/05_ubicaciones.js
export async function seed(knex) {
  await knex('ubicaciones').del();

  const maria = await knex('usuarios').where('correo', 'maria.gonzalez@email.com').first();
  const carlos = await knex('usuarios').where('correo', 'carlos.rodriguez@email.com').first();

  await knex('ubicaciones').insert([
    {
      usuario_id: maria.id,
      latitud: -33.4489,
      longitud: -70.6693,
      precision_metros: 10,
      detectado_en: new Date()
    },
    {
      usuario_id: carlos.id,
      latitud: -33.4550,
      longitud: -70.6750,
      precision_metros: 15,
      detectado_en: new Date()
    }
  ]);
}