// Backend/db/seeds/02_cuidadores.js
export async function seed(knex) {
  await knex('cuidadores').del();

  // Obtener los IDs de los usuarios recién creados
  const maria = await knex('usuarios').where('correo', 'maria.gonzalez@email.com').first();
  const carlos = await knex('usuarios').where('correo', 'carlos.rodriguez@email.com').first();
  const ana = await knex('usuarios').where('correo', 'ana.silva@email.com').first();
  const pedro = await knex('usuarios').where('correo', 'pedro.lopez@email.com').first();

  await knex('cuidadores').insert([
    {
      adulto_id: maria.id,
      cuidador_id: ana.id
    },
    {
      adulto_id: maria.id,
      cuidador_id: pedro.id
    },
    {
      adulto_id: carlos.id,
      cuidador_id: ana.id
    }
  ]);
}