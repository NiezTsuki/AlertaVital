// Backend/db/seeds/04_zonas_seguras.js
export async function seed(knex) {
  await knex('zonas_seguras').del();

  const maria = await knex('usuarios').where('correo', 'maria.gonzalez@email.com').first();
  const carlos = await knex('usuarios').where('correo', 'carlos.rodriguez@email.com').first();

  await knex('zonas_seguras').insert([
    {
      usuario_id: maria.id,
      nombre: 'Casa de María',
      latitud: -33.4489,
      longitud: -70.6693,
      radio_metros: 100,
      creado_en: new Date()
    },
    {
      usuario_id: maria.id,
      nombre: 'Parque cercano',
      latitud: -33.4500,
      longitud: -70.6700,
      radio_metros: 50,
      creado_en: new Date()
    },
    {
      usuario_id: carlos.id,
      nombre: 'Casa de Carlos',
      latitud: -33.4550,
      longitud: -70.6750,
      radio_metros: 150,
      creado_en: new Date()
    }
  ]);
}