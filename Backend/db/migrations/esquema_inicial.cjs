// Ejecutar:
// npx knex migrate:latest --knexfile knexfile.cjs
// npx knex migrate:rollback --knexfile knexfile.cjs

exports.up = async function up(knex) {
  // 1) Extensiones
  await knex.raw('CREATE EXTENSION IF NOT EXISTS "uuid-ossp";');
  await knex.raw('CREATE EXTENSION IF NOT EXISTS citext;');

  // 2) ENUMS
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

  // 3) USUARIOS
  if (!(await knex.schema.hasTable('usuarios'))) {
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

  // 4) CUIDADORES (vínculos)
  if (!(await knex.schema.hasTable('cuidadores'))) {
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

  // 5) UBICACIONES (última conocida por usuario)
  if (!(await knex.schema.hasTable('ubicaciones'))) {
    await knex.schema.createTable('ubicaciones', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('usuario_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.specificType('latitud', 'double precision').notNullable();
      t.specificType('longitud', 'double precision').notNullable();
      t.specificType('precision_metros', 'double precision');
      t.timestamp('detectado_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
      t.index(['usuario_id', 'detectado_en']);
    });
  }

  // 6) ALERTAS (incluye snapshot de coords del adulto)
  if (!(await knex.schema.hasTable('alertas'))) {
    await knex.schema.createTable('alertas', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('usuario_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE'); // adulto emisor
      t.text('tipo').notNullable(); // 'CAIDA','SOS','ZONA_SEGURA'
      t.text('descripcion');
      t.timestamp('creada_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
      t.boolean('atendida').notNullable().defaultTo(false);
      t.integer('countdown_seg').defaultTo(30);
      t.text('estado').defaultTo('ABIERTA'); // 'ABIERTA','CANCELADA','CERRADA'

      // coords snapshot
      t.specificType('latitud', 'double precision');
      t.specificType('longitud', 'double precision');
      t.specificType('precision_metros', 'double precision');
    });

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
    await knex.raw(`CREATE INDEX IF NOT EXISTS alertas_lat_lon_idx ON alertas (latitud, longitud);`);
  }

  // 7) ASIGNACIONES (orden y estado por cuidador)
  if (!(await knex.schema.hasTable('alertas_asignaciones'))) {
    await knex.schema.createTable('alertas_asignaciones', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('alerta_id').notNullable()
        .references('id').inTable('alertas').onDelete('CASCADE');
      t.uuid('cuidador_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.integer('orden').notNullable().defaultTo(1);
      t.specificType('estado', 'asignacion_estado').notNullable().defaultTo('PENDIENTE');
      t.timestamp('notificada_en', { useTz: true });
      t.timestamp('respondida_en', { useTz: true });

      // features / métricas
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

  // 8) EVENTOS (historial)
  if (!(await knex.schema.hasTable('alertas_eventos'))) {
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

  // 9) TRAZAS por alerta (para mapas y ML)
  if (!(await knex.schema.hasTable('alertas_posiciones'))) {
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

  // 10) ZONAS SEGURAS
  if (!(await knex.schema.hasTable('zonas_seguras'))) {
    await knex.schema.createTable('zonas_seguras', (t) => {
      t.uuid('id').primary().defaultTo(knex.raw('uuid_generate_v4()'));
      t.uuid('usuario_id').notNullable()
        .references('id').inTable('usuarios').onDelete('CASCADE');
      t.text('nombre').notNullable();
      t.specificType('latitud', 'double precision').notNullable();
      t.specificType('longitud', 'double precision').notNullable();
      t.specificType('radio_metros', 'double precision').notNullable();
      t.timestamp('creado_en', { useTz: true }).notNullable().defaultTo(knex.fn.now());
    });
    await knex.raw(`ALTER TABLE zonas_seguras
                    ADD CONSTRAINT zonas_seguras_radio_check
                    CHECK (radio_metros > 0);`);
    await knex.schema.alterTable('zonas_seguras', (t) => {
      t.index(['usuario_id']);
    });
  }

  // 11) HISTORIAL MÉDICO
  if (!(await knex.schema.hasTable('historial_medico'))) {
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
  const dropIf = (name) =>
    knex.schema.hasTable(name).then((exists) => exists && knex.schema.dropTable(name));

  await dropIf('historial_medico');
  await dropIf('zonas_seguras');
  await dropIf('alertas_posiciones');
  await dropIf('alertas_eventos');
  await dropIf('alertas_asignaciones');
  await dropIf('alertas');
  await dropIf('ubicaciones');
  await dropIf('cuidadores');
  await dropIf('usuarios');

  // Borrar ENUMS
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
