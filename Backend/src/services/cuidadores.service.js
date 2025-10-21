import { prisma } from '../db/prisma.js';
import { getUserById, findUserByEmail as getUserByCorreo } from './user.service.js'; 

// Exportamos la función importada para mantener la compatibilidad con el controlador
export { getUserByCorreo }; 

export async function assertUserRole(id, rolEsperado) {
  const u = await getUserById(id);
  if (!u) throw new Error('USER_NOT_FOUND');
  if (u.rol !== rolEsperado) throw new Error('WRONG_ROLE');
  return u;
}

// Vínculo
export async function vincularCuidador({ adultoId, cuidadorId }) {
  // 'upsert' de Prisma es la forma segura y eficiente de hacer "INSERT ... ON CONFLICT DO NOTHING".
  // Intenta crear el vínculo, pero si ya existe (basado en la clave única), no hace nada.
  return await prisma.cuidadores.upsert({
    where: {
      // Usamos el nombre de la restricción única definida en tu schema.prisma
      adulto_id_cuidador_id: {
        adulto_id: adultoId,
        cuidador_id: cuidadorId,
      },
    },
    update: {}, // No hacemos nada si el vínculo ya existe
    create: {
      adulto_id: adultoId,
      cuidador_id: cuidadorId,
    },
  });
}

export async function desvincularCuidador({ adultoId, cuidadorId }) {
  try {
    // Prisma.delete intenta eliminar el registro basado en la clave única.
    await prisma.cuidadores.delete({
      where: {
        adulto_id_cuidador_id: {
          adulto_id: adultoId,
          cuidador_id: cuidadorId,
        },
      },
    });
    return true; // Se eliminó con éxito.
  } catch (e) {
    // Prisma lanza un error (código P2025) si el registro a eliminar no se encuentra.
    // Capturamos este error específico para replicar la lógica anterior y devolver 'false'.
    if (e.code === 'P2025') {
      return false; // El vínculo no existía.
    }
    // Si es otro tipo de error, lo lanzamos para que se maneje más arriba.
    throw e;
  }
}

export async function listarCuidadoresDeAdulto(adultoId) {
  const vinculos = await prisma.cuidadores.findMany({
    where: { adulto_id: adultoId },
    // Le decimos que incluya los datos del usuario relacionado a través de la relación del cuidador.
    include: {
      usuarios_cuidadores_cuidador_idTousuarios: {
        select: { id: true, nombre_completo: true, correo: true, telefono: true }
      }
    },
    orderBy: { creado_en: 'desc' }
  });

  // Mapeamos el resultado para que tenga exactamente el mismo formato que esperaba el controlador.
  return vinculos.map(v => ({
    cuidador_id: v.usuarios_cuidadores_cuidador_idTousuarios.id,
    nombre_completo: v.usuarios_cuidadores_cuidador_idTousuarios.nombre_completo,
    correo: v.usuarios_cuidadores_cuidador_idTousuarios.correo,
    telefono: v.usuarios_cuidadores_cuidador_idTousuarios.telefono,
    creado_en: v.creado_en
  }));
}

export async function listarAdultosDeCuidador(cuidadorId) {
  const vinculos = await prisma.cuidadores.findMany({
    where: { cuidador_id: cuidadorId },
    include: {
      usuarios_cuidadores_adulto_idTousuarios: {
        select: { id: true, nombre_completo: true, correo: true, telefono: true }
      }
    },
    orderBy: { creado_en: 'desc' }
  });

  // Mapeamos el resultado para que tenga exactamente el mismo formato que esperaba el controlador.
  return vinculos.map(v => ({
    adulto_id: v.usuarios_cuidadores_adulto_idTousuarios.id,
    nombre_completo: v.usuarios_cuidadores_adulto_idTousuarios.nombre_completo,
    correo: v.usuarios_cuidadores_adulto_idTousuarios.correo,
    telefono: v.usuarios_cuidadores_adulto_idTousuarios.telefono,
    creado_en: v.creado_en
  }));
}