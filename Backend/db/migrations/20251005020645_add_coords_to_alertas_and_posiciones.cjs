// migrations/<timestamp>_add_coords_to_alertas_and_posiciones.cjs
exports.up = async function up(knex) {
  // Añadir columnas a alertas si no existen
  await knex.raw(`ALTER TABLE alertas ADD COLUMN IF NOT EXISTS latitud double precision;`);
  await knex.raw(`ALTER TABLE alertas ADD COLUMN IF NOT EXISTS longitud double precision;`);
  await knex.raw(`ALTER TABLE alertas ADD COLUMN IF NOT EXISTS precision_metros double precision;`);
  await knex.raw(`CREATE INDEX IF NOT EXISTS alertas_lat_lon_idx ON alertas (latitud, longitud);`);

  // Crear tabla de trazas si no existe
  const hasPos = await knex.schema.hasTable('alertas_posiciones');
  if (!hasPos) {
    await knex.schema.createTable('alertas_posiciones', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('alerta_id').notNullable()
        .references('id').inTable('alertas').onDelete('CASCADE');
      t.uuid('usuario_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.text('rol').notNullable(); // 'ADULTO_MAYOR' | 'CUIDADOR'
      t.specificType('latitud', 'double precision').notNullable();
      t.specificType('longitud', 'double precision').notNullable();
      t.specificType('precision_metros', 'double precision');
      t.timestamp('capturada_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
    });

    await knex.raw(`
      ALTER TABLE alertas_posiciones
      ADD CONSTRAINT alertas_posiciones_rol_chk
      CHECK (rol IN ('ADULTO_MAYOR','CUIDADOR'));
    `);

    await knex.schema.alterTable('alertas_posiciones', (t) => {
      t.index(['alerta_id', 'capturada_en'], 'pos_alerta_time_idx');
      t.index(['usuario_id', 'capturada_en'], 'pos_user_time_idx');
      t.index(['rol'], 'pos_rol_idx');
    });
  }
};

exports.down = async function down(knex) {
  const dropIf = (name) => knex.schema.hasTable(name).then((e) => e && knex.schema.dropTable(name));
  await dropIf('alertas_posiciones');

  await knex.raw(`DROP INDEX IF EXISTS alertas_lat_lon_idx;`);
  await knex.raw(`ALTER TABLE alertas DROP COLUMN IF EXISTS precision_metros;`);
  await knex.raw(`ALTER TABLE alertas DROP COLUMN IF EXISTS longitud;`);
  await knex.raw(`ALTER TABLE alertas DROP COLUMN IF EXISTS latitud;`);
};
