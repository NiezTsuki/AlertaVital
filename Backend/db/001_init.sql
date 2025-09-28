-- 001_init.sql (correr en tu BD)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS citext;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    CREATE TYPE user_role AS ENUM ('ADULTO_MAYOR','CUIDADOR','ADMIN');
  END IF;
END$$;

CREATE TABLE IF NOT EXISTS usuarios (
  id                   UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  rol                  user_role      NOT NULL,
  nombre_completo      TEXT           NOT NULL,
  correo               CITEXT         UNIQUE,
  telefono             TEXT,
  contrasena_hash      TEXT           NOT NULL,
  correo_verificado_en TIMESTAMPTZ,
  creado_en            TIMESTAMPTZ    NOT NULL DEFAULT NOW(),
  ultimo_login         TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS cuidadores (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  adulto_id    UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  cuidador_id  UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  creado_en    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (adulto_id, cuidador_id)
);

CREATE TABLE IF NOT EXISTS ubicaciones (
  id               UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id       UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  latitud          DOUBLE PRECISION NOT NULL,
  longitud         DOUBLE PRECISION NOT NULL,
  precision_metros DOUBLE PRECISION,
  detectado_en     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS alertas (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id  UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  tipo        TEXT NOT NULL CHECK (tipo IN ('CAIDA','SOS','ZONA_SEGURA')),
  descripcion TEXT,
  creada_en   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atendida    BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS zonas_seguras (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id    UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  nombre        TEXT NOT NULL,
  latitud       DOUBLE PRECISION NOT NULL,
  longitud      DOUBLE PRECISION NOT NULL,
  radio_metros  DOUBLE PRECISION NOT NULL CHECK (radio_metros > 0),
  creado_en     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS historial_medico (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  usuario_id     UUID NOT NULL REFERENCES usuarios(id) ON DELETE CASCADE,
  condicion      TEXT NOT NULL,
  descripcion    TEXT,
  medicamentos   TEXT,
  alergias       TEXT,
  fecha_registro DATE NOT NULL DEFAULT CURRENT_DATE
);
