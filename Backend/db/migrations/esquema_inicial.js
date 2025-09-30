//Ejecutar en la terminal:
//npx knex migrate:rollback
//npx knex migrate:latest

export function up(knex) {
  return (
    knex.schema
      // Crear extensiones primero
      .raw('CREATE EXTENSION IF NOT EXISTS "uuid-ossp"')
      .raw('CREATE EXTENSION IF NOT EXISTS citext')
      .raw(`
        DO $$
        BEGIN
          IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
            CREATE TYPE user_role AS ENUM ('ADULTO_MAYOR','CUIDADOR','ADMIN');
          END IF;
        END$$
      `)

      // Tabla usuarios
      .createTable("usuarios", (table) => {
        table.uuid("id").primary().defaultTo(knex.raw("uuid_generate_v4()"));
        table.specificType("rol", "user_role").notNullable();
        table.text("nombre_completo").notNullable();
        table.specificType("correo", "CITEXT").unique();
        table.text("telefono");
        table.text("contrasena_hash").notNullable();
        table.timestamp("correo_verificado_en");
        table.timestamp("creado_en").defaultTo(knex.fn.now()).notNullable();
        table.timestamp("ultimo_login");
      })

      // Tabla cuidadores
      .createTable("cuidadores", (table) => {
        table.uuid("id").primary().defaultTo(knex.raw("uuid_generate_v4()"));
        table.uuid("adulto_id").notNullable().references("id").inTable("usuarios").onDelete("CASCADE");
        table.uuid("cuidador_id").notNullable().references("id").inTable("usuarios").onDelete("CASCADE");
        table.timestamp("creado_en").defaultTo(knex.fn.now()).notNullable();
        table.unique(["adulto_id", "cuidador_id"]);
      })

      // Tabla ubicaciones
      .createTable("ubicaciones", (table) => {
        table.uuid("id").primary().defaultTo(knex.raw("uuid_generate_v4()"));
        table.uuid("usuario_id").notNullable().references("id").inTable("usuarios").onDelete("CASCADE");
        table.double("latitud").notNullable();
        table.double("longitud").notNullable();
        table.double("precision_metros");
        table.timestamp("detectado_en").defaultTo(knex.fn.now()).notNullable();
      })

      // Tabla alertas
      .createTable("alertas", (table) => {
        table.uuid("id").primary().defaultTo(knex.raw("uuid_generate_v4()"));
        table.uuid("usuario_id").notNullable().references("id").inTable("usuarios").onDelete("CASCADE");
        table.text("tipo").notNullable();
        table.text("descripcion");
        table.timestamp("creada_en").defaultTo(knex.fn.now()).notNullable();
        table.boolean("atendida").notNullable().defaultTo(false);
      })
      .raw(`ALTER TABLE alertas ADD CONSTRAINT alertas_tipo_check CHECK (tipo IN ('CAIDA','SOS','ZONA_SEGURA'))`)

      // Tabla zonas_seguras
      .createTable("zonas_seguras", (table) => {
        table.uuid("id").primary().defaultTo(knex.raw("uuid_generate_v4()"));
        table.uuid("usuario_id").notNullable().references("id").inTable("usuarios").onDelete("CASCADE");
        table.text("nombre").notNullable();
        table.double("latitud").notNullable();
        table.double("longitud").notNullable();
        table.double("radio_metros").notNullable();
        table.timestamp("creado_en").defaultTo(knex.fn.now()).notNullable();
      })
      .raw(`ALTER TABLE zonas_seguras ADD CONSTRAINT zonas_seguras_radio_check CHECK (radio_metros > 0)`)

      // Tabla historial_medico
      .createTable("historial_medico", (table) => {
        table.uuid("id").primary().defaultTo(knex.raw("uuid_generate_v4()"));
        table.uuid("usuario_id").notNullable().references("id").inTable("usuarios").onDelete("CASCADE");
        table.text("condicion").notNullable();
        table.text("descripcion");
        table.text("medicamentos");
        table.text("alergias");
        table.date("fecha_registro").defaultTo(knex.fn.now()).notNullable();
      })
  );
};

export function down(knex) {
  return knex.schema
    .dropTableIfExists("historial_medico")
    .dropTableIfExists("zonas_seguras")
    .dropTableIfExists("alertas")
    .dropTableIfExists("ubicaciones")
    .dropTableIfExists("cuidadores")
    .dropTableIfExists("usuarios")
    .raw("DROP TYPE IF EXISTS user_role")
    .raw("DROP EXTENSION IF EXISTS citext")
    .raw('DROP EXTENSION IF EXISTS "uuid-ossp"');
};