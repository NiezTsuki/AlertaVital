// Backend/db/seeds/03_historial_medico.js
export async function seed(knex) {
  await knex('historial_medico').del();

  const maria = await knex('usuarios').where('correo', 'maria.gonzalez@email.com').first();
  const carlos = await knex('usuarios').where('correo', 'carlos.rodriguez@email.com').first();

  await knex('historial_medico').insert([
    {
      usuario_id: maria.id,
      condicion: 'Hipertensión',
      descripcion: 'Controlada con medicación, requiere monitoreo regular',
      medicamentos: 'Losartán 50mg, 1 tableta al día',
      alergias: 'Penicilina',
      fecha_registro: new Date()
    },
    {
      usuario_id: maria.id,
      condicion: 'Diabetes Tipo 2',
      descripcion: 'Controlada con dieta y medicación',
      medicamentos: 'Metformina 850mg, 2 tabletas al día',
      alergias: 'Penicilina',
      fecha_registro: new Date()
    },
    {
      usuario_id: carlos.id,
      condicion: 'Artritis',
      descripcion: 'Dolores articulares en rodillas y manos',
      medicamentos: 'Ibuprofeno 400mg cuando hay dolor',
      alergias: 'Ninguna conocida',
      fecha_registro: new Date()
    }
  ]);
}