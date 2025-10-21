-- CreateEnum
CREATE TYPE "asignacion_estado" AS ENUM ('PENDIENTE', 'NOTIFICADA', 'EN_CAMINO', 'RECHAZADA', 'EXPIRADA', 'COMPLETADA');

-- CreateEnum
CREATE TYPE "user_role" AS ENUM ('ADULTO_MAYOR', 'CUIDADOR', 'ADMIN');

-- Enable case-insensitive text for emails
CREATE EXTENSION IF NOT EXISTS "citext";

-- CreateTable
CREATE TABLE "alertas" (
    "id" UUID NOT NULL,
    "usuario_id" UUID NOT NULL,
    "tipo" TEXT NOT NULL,
    "descripcion" TEXT,
    "creada_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "atendida" BOOLEAN NOT NULL DEFAULT false,
    "countdown_seg" INTEGER DEFAULT 30,
    "estado" TEXT DEFAULT 'ABIERTA',
    "latitud" DOUBLE PRECISION,
    "longitud" DOUBLE PRECISION,
    "precision_metros" DOUBLE PRECISION,

    CONSTRAINT "alertas_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "alertas_asignaciones" (
    "id" UUID NOT NULL,
    "alerta_id" UUID NOT NULL,
    "cuidador_id" UUID NOT NULL,
    "orden" INTEGER NOT NULL DEFAULT 1,
    "estado" "asignacion_estado" NOT NULL DEFAULT 'PENDIENTE',
    "notificada_en" TIMESTAMPTZ(6),
    "respondida_en" TIMESTAMPTZ(6),
    "distancia_m" DECIMAL(12,3),
    "ml_score" DECIMAL(10,6),
    "ml_model" TEXT,
    "ml_version" TEXT,
    "eta_seg" INTEGER,

    CONSTRAINT "alertas_asignaciones_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "alertas_eventos" (
    "id" UUID NOT NULL,
    "alerta_id" UUID NOT NULL,
    "evento" TEXT NOT NULL,
    "metadata" JSONB,
    "creado_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "alertas_eventos_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "alertas_posiciones" (
    "id" UUID NOT NULL,
    "alerta_id" UUID NOT NULL,
    "usuario_id" UUID NOT NULL,
    "rol" TEXT NOT NULL,
    "latitud" DOUBLE PRECISION NOT NULL,
    "longitud" DOUBLE PRECISION NOT NULL,
    "precision_metros" DOUBLE PRECISION,
    "capturada_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "alertas_posiciones_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "cuidadores" (
    "id" UUID NOT NULL,
    "adulto_id" UUID NOT NULL,
    "cuidador_id" UUID NOT NULL,
    "creado_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "cuidadores_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "historial_medico" (
    "id" UUID NOT NULL,
    "usuario_id" UUID NOT NULL,
    "condicion" TEXT NOT NULL,
    "descripcion" TEXT,
    "medicamentos" TEXT,
    "alergias" TEXT,
    "fecha_registro" DATE NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "historial_medico_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "ubicaciones" (
    "id" UUID NOT NULL,
    "usuario_id" UUID NOT NULL,
    "latitud" DOUBLE PRECISION NOT NULL,
    "longitud" DOUBLE PRECISION NOT NULL,
    "precision_metros" DOUBLE PRECISION,
    "detectado_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ubicaciones_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "usuarios" (
    "id" UUID NOT NULL,
    "rol" "user_role" NOT NULL,
    "nombre_completo" TEXT NOT NULL,
    "correo" CITEXT,
    "telefono" TEXT,
    "contrasena_hash" TEXT NOT NULL,
    "correo_verificado_en" TIMESTAMPTZ(6),
    "creado_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "ultimo_login" TIMESTAMPTZ(6),
    "fcm_token" TEXT,

    CONSTRAINT "usuarios_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "zonas_seguras" (
    "id" UUID NOT NULL,
    "usuario_id" UUID NOT NULL,
    "nombre" TEXT NOT NULL,
    "latitud" DOUBLE PRECISION NOT NULL,
    "longitud" DOUBLE PRECISION NOT NULL,
    "radio_metros" DOUBLE PRECISION NOT NULL,
    "creado_en" TIMESTAMPTZ(6) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "zonas_seguras_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "alertas_creada_en_idx" ON "alertas"("creada_en");

-- CreateIndex
CREATE INDEX "alertas_estado_idx" ON "alertas"("estado");

-- CreateIndex
CREATE INDEX "alertas_latitud_longitud_idx" ON "alertas"("latitud", "longitud");

-- CreateIndex
CREATE INDEX "alertas_tipo_idx" ON "alertas"("tipo");

-- CreateIndex
CREATE INDEX "alertas_usuario_id_idx" ON "alertas"("usuario_id");

-- CreateIndex
CREATE INDEX "alertas_asignaciones_alerta_id_orden_idx" ON "alertas_asignaciones"("alerta_id", "orden");

-- CreateIndex
CREATE INDEX "alertas_asignaciones_cuidador_id_idx" ON "alertas_asignaciones"("cuidador_id");

-- CreateIndex
CREATE INDEX "alertas_asignaciones_estado_idx" ON "alertas_asignaciones"("estado");

-- CreateIndex
CREATE UNIQUE INDEX "alertas_asignaciones_alerta_id_cuidador_id_orden_key" ON "alertas_asignaciones"("alerta_id", "cuidador_id", "orden");

-- CreateIndex
CREATE UNIQUE INDEX "alertas_asignaciones_alerta_id_estado_key" ON "alertas_asignaciones"("alerta_id", "estado");

-- CreateIndex
CREATE INDEX "alertas_eventos_alerta_id_creado_en_idx" ON "alertas_eventos"("alerta_id", "creado_en");

-- CreateIndex
CREATE INDEX "alertas_eventos_evento_idx" ON "alertas_eventos"("evento");

-- CreateIndex
CREATE INDEX "alertas_posiciones_alerta_id_capturada_en_idx" ON "alertas_posiciones"("alerta_id", "capturada_en");

-- CreateIndex
CREATE INDEX "alertas_posiciones_rol_idx" ON "alertas_posiciones"("rol");

-- CreateIndex
CREATE INDEX "alertas_posiciones_usuario_id_capturada_en_idx" ON "alertas_posiciones"("usuario_id", "capturada_en");

-- CreateIndex
CREATE INDEX "cuidadores_adulto_id_idx" ON "cuidadores"("adulto_id");

-- CreateIndex
CREATE INDEX "cuidadores_cuidador_id_idx" ON "cuidadores"("cuidador_id");

-- CreateIndex
CREATE UNIQUE INDEX "cuidadores_adulto_id_cuidador_id_key" ON "cuidadores"("adulto_id", "cuidador_id");

-- CreateIndex
CREATE INDEX "historial_medico_usuario_id_fecha_registro_idx" ON "historial_medico"("usuario_id", "fecha_registro");

-- CreateIndex
CREATE INDEX "ubicaciones_usuario_id_detectado_en_idx" ON "ubicaciones"("usuario_id", "detectado_en");

-- CreateIndex
CREATE UNIQUE INDEX "usuarios_correo_key" ON "usuarios"("correo");

-- CreateIndex
CREATE INDEX "zonas_seguras_usuario_id_idx" ON "zonas_seguras"("usuario_id");

-- AddForeignKey
ALTER TABLE "alertas" ADD CONSTRAINT "alertas_usuario_id_fkey" FOREIGN KEY ("usuario_id") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "alertas_asignaciones" ADD CONSTRAINT "alertas_asignaciones_alerta_id_fkey" FOREIGN KEY ("alerta_id") REFERENCES "alertas"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "alertas_asignaciones" ADD CONSTRAINT "alertas_asignaciones_cuidador_id_fkey" FOREIGN KEY ("cuidador_id") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "alertas_eventos" ADD CONSTRAINT "alertas_eventos_alerta_id_fkey" FOREIGN KEY ("alerta_id") REFERENCES "alertas"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "alertas_posiciones" ADD CONSTRAINT "alertas_posiciones_alerta_id_fkey" FOREIGN KEY ("alerta_id") REFERENCES "alertas"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "alertas_posiciones" ADD CONSTRAINT "alertas_posiciones_usuario_id_fkey" FOREIGN KEY ("usuario_id") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "cuidadores" ADD CONSTRAINT "cuidadores_adulto_id_fkey" FOREIGN KEY ("adulto_id") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "cuidadores" ADD CONSTRAINT "cuidadores_cuidador_id_fkey" FOREIGN KEY ("cuidador_id") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "historial_medico" ADD CONSTRAINT "historial_medico_usuario_id_fkey" FOREIGN KEY ("usuario_id") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "ubicaciones" ADD CONSTRAINT "ubicaciones_usuario_id_fkey" FOREIGN KEY ("usuario_id") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE NO ACTION;

-- AddForeignKey
ALTER TABLE "zonas_seguras" ADD CONSTRAINT "zonas_seguras_usuario_id_fkey" FOREIGN KEY ("usuario_id") REFERENCES "usuarios"("id") ON DELETE CASCADE ON UPDATE NO ACTION;
