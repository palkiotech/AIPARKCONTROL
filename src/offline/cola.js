import { db } from './db'
import { getAdjustedNowISO } from './clockDrift'

/**
 * Valida la estructura básica de una operación antes de encolarla
 */
export function validarEstructuraOperacion(op) {
  if (!op || typeof op !== 'object') return false
  if (!op.tipo || typeof op.tipo !== 'string') return false
  if (!op.payload || typeof op.payload !== 'object') return false
  return true
}

/**
 * Crea el objeto estandarizado de una operación offline
 */
export function crearOperacionOffline({ tipo, payload }) {
  if (!validarEstructuraOperacion({ tipo, payload })) {
    throw new Error('Estructura de operación inválida')
  }

  const id = (typeof crypto !== 'undefined' && crypto.randomUUID) 
    ? crypto.randomUUID() 
    : 'offline-' + Date.now() + '-' + Math.random().toString(36).substring(2, 9)

  return {
    id,
    tipo,
    payload,
    creada_en_dispositivo_at: getAdjustedNowISO(),
    estado: 'pendiente'
  }
}

/**
 * Encola una operación en Dexie (IndexedDB)
 */
export async function encolarOperacion(tipo, payload) {
  const operacion = crearOperacionOffline({ tipo, payload })
  try {
    const localId = await db.cola_operaciones.add(operacion)
    return { ...operacion, localId }
  } catch (err) {
    console.warn('Error guardando en Dexie:', err)
    return operacion
  }
}

/**
 * Devuelve todas las operaciones en estado pendiente ordenadas cronológicamente
 */
export async function obtenerOperacionesPendientes() {
  try {
    return await db.cola_operaciones
      .where('estado')
      .equals('pendiente')
      .sortBy('localId')
  } catch (err) {
    console.warn('Error leyendo Dexie:', err)
    return []
  }
}

/**
 * Cuenta las operaciones pendientes
 */
export async function contarOperacionesPendientes() {
  try {
    return await db.cola_operaciones
      .where('estado')
      .equals('pendiente')
      .count()
  } catch (err) {
    return 0
  }
}

/**
 * Marca como procesadas o elimina las operaciones sincronizadas con éxito
 */
export async function eliminarOperacionesSincronizadas(ids) {
  try {
    await db.cola_operaciones
      .where('id')
      .anyOf(ids)
      .delete()
  } catch (err) {
    console.warn('Error eliminando de Dexie:', err)
  }
}
