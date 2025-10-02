//Ejecutar en la terminal:
//npx knex migrate:latest --knexfile knexfile.cjs
//npx knex migrate:rollback --knexfile knexfile.cjs

exports.up = async function up(knex) {
  // 1) Extensiones necesarias
  await knex.raw('CREATE EXTENSION IF NOT EXISTS "uuid-ossp";');
  await knex.raw('CREATE EXTENSION IF NOT EXISTS citext;');

  // 2) ENUMS (crear solo si no existen)
  await knex.raw(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('ADULTO_MAYOR','CUIDADOR','ADMIN');
      END IF;
    END$$;
  `);

  await knex.raw(`
    DO $$
    BEGIN
      IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'asignacion_estado') THEN
        CREATE TYPE asignacion_estado AS ENUM
          ('PENDIENTE','NOTIFICADA','EN_CAMINO','RECHAZADA','EXPIRADA','COMPLETADA');
      END IF;
    END$$;
  `);

  // 3) Tablas base
  const hasUsuarios = await knex.schema.hasTable('usuarios');
  if (!hasUsuarios) {
    await knex.schema.createTable('usuarios', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.specificType('rol', 'user_role').notNullable();
      t.text('nombre_completo').notNullable();
      t.specificType('correo', 'CITEXT').unique();
      t.text('telefono');
      t.text('contrasena_hash').notNullable();
      t.timestamp('correo_verificado_en');
      t.timestamp('creado_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
      t.timestamp('ultimo_login', { useTz: true });
    });
  }

  const hasCuidadores = await knex.schema.hasTable('cuidadores');
  if (!hasCuidadores) {
    await knex.schema.createTable('cuidadores', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('adulto_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.uuid('cuidador_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.timestamp('creado_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
      t.unique(['adulto_id', 'cuidador_id']);
      t.index(['adulto_id']);
      t.index(['cuidador_id']);
    });
  }

  const hasUbicaciones = await knex.schema.hasTable('ubicaciones');
  if (!hasUbicaciones) {
    await knex.schema.createTable('ubicaciones', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('usuario_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.double('latitud').notNullable();
      t.double('longitud').notNullable();
      t.double('precision_metros');
      t.timestamp('detectado_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
      t.index(['usuario_id', 'detectado_en']);
    });
  }

  // 4) ALERTAS (padre)
  const hasAlertas = await knex.schema.hasTable('alertas');
  if (!hasAlertas) {
    await knex.schema.createTable('alertas', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('usuario_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE'); // adulto mayor que emite
      t.text('tipo').notNullable(); // 'CAIDA','SOS','ZONA_SEGURA'
      t.text('descripcion');
      t.timestamp('creada_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
      t.boolean('atendida').notNullable().defaultTo(false);

      // Campos operativos para el flujo (countdown/estado)
      t.integer('countdown_seg').defaultTo(30);
      t.text('estado').defaultTo('ABIERTA'); // 'ABIERTA','CANCELADA','CERRADA'
    });

    // Checks e índices
    await knex.raw(
      `ALTER TABLE alertas
         ADD CONSTRAINT alertas_tipo_check
         CHECK (tipo IN ('CAIDA','SOS','ZONA_SEGURA'));`
    );
    await knex.raw(
      `ALTER TABLE alertas
         ADD CONSTRAINT alertas_estado_chk
         CHECK (estado IN ('ABIERTA','CANCELADA','CERRADA'));`
    );
    await knex.schema.alterTable('alertas', (t) => {
      t.index(['usuario_id'], 'alertas_usuario_idx');
      t.index(['creada_en'], 'alertas_creada_idx');
      t.index(['estado'], 'alertas_estado_idx');
      t.index(['tipo'], 'alertas_tipo_idx');
    });
  }

  // 5) ASIGNACIONES de alertas (depende de alertas)
  const hasAsign = await knex.schema.hasTable('alertas_asignaciones');
  if (!hasAsign) {
    await knex.schema.createTable('alertas_asignaciones', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('alerta_id').notNullable()
        .references('id').inTable('alertas').onDelete('CASCADE');
      t.uuid('cuidador_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.integer('orden').notNullable().defaultTo(1); // 1,2,3...
      t.specificType('estado', 'asignacion_estado').notNullable().defaultTo('PENDIENTE');
      t.timestamp('notificada_en', { useTz: true });
      t.timestamp('respondida_en', { useTz: true });
      t.decimal('distancia_m', 12, 3);
      t.decimal('ml_score', 10, 6);
      t.text('ml_model');
      t.text('ml_version');
      t.integer('eta_seg');

      t.unique(['alerta_id', 'cuidador_id', 'orden'], 'uniq_alerta_cuidador_orden');
    });

    await knex.schema.alterTable('alertas_asignaciones', (t) => {
      t.index(['alerta_id', 'orden'], 'asig_alerta_orden_idx');
      t.index(['cuidador_id'], 'asig_cuidador_idx');
      t.index(['estado'], 'asig_estado_idx');
    });
  }

  // 6) EVENTOS / HISTORIAL de alertas
  const hasEventos = await knex.schema.hasTable('alertas_eventos');
  if (!hasEventos) {
    await knex.schema.createTable('alertas_eventos', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('alerta_id').notNullable()
        .references('id').inTable('alertas').onDelete('CASCADE');
      t.text('evento').notNullable(); // CREATED, NOTIFIED, ACCEPTED, FORWARDED, EXPIRED, COMPLETED, EMERGENCY_CALLED
      t.jsonb('metadata');
      t.timestamp('creado_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
    });
    await knex.schema.alterTable('alertas_eventos', (t) => {
      t.index(['alerta_id', 'creado_en'], 'eventos_alerta_creado_idx');
      t.index(['evento'], 'eventos_evento_idx');
    });
  }

  // 7) Zonas seguras
  const hasZonas = await knex.schema.hasTable('zonas_seguras');
  if (!hasZonas) {
    await knex.schema.createTable('zonas_seguras', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('usuario_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.text('nombre').notNullable();
      t.double('latitud').notNullable();
      t.double('longitud').notNullable();
      t.double('radio_metros').notNullable();
      t.timestamp('creado_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
    });
    await knex.raw(`ALTER TABLE zonas_seguras
                    ADD CONSTRAINT zonas_seguras_radio_check
                    CHECK (radio_metros > 0);`);
    await knex.schema.alterTable('zonas_seguras', (t) => {
      t.index(['usuario_id']);
    });
  }

  // 8) Historial médico
  const hasHistMed = await knex.schema.hasTable('historial_medico');
  if (!hasHistMed) {
    await knex.schema.createTable('historial_medico', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('usuario_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.text('condicion').notNullable();
      t.text('descripcion');
      t.text('medicamentos');
      t.text('alergias');
      t.date('fecha_registro').notNullable().defaultTo(knex.fn.now());
    });
    await knex.schema.alterTable('historial_medico', (t) => {
      t.index(['usuario_id', 'fecha_registro'], 'hist_med_usuario_fecha_idx');
    });
  }
};

exports.down = async function down(knex) {
  // Bajar en orden inverso por dependencias
  const dropIf = (name) => knex.schema.hasTable(name).then((exists) => exists && knex.schema.dropTable(name));

  await dropIf('historial_medico');
  await dropIf('zonas_seguras');
  await dropIf('alertas_eventos');
  await dropIf('alertas_asignaciones');
  await dropIf('alertas');
  await dropIf('ubicaciones');
  await dropIf('cuidadores');
  await dropIf('usuarios');

  // Borrar ENUMS solo si ya no hay columnas usándolos
  await knex.raw(`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'asignacion_estado') THEN
        DROP TYPE asignacion_estado;
      END IF;
    END$$;
  `);

  await knex.raw(`
    DO $$
    BEGIN
      IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        DROP TYPE user_role;
      END IF;
    END$$;
  `);

  await knex.raw('DROP EXTENSION IF EXISTS citext;');
  await knex.raw('DROP EXTENSION IF EXISTS "uuid-ossp";');
};
