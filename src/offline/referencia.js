import { db } from './db'

/**
 * Copia local (IndexedDB) de datos de referencia para operar sin conexión
 * (decisión #3 del plan): tarifas, tipos, métodos de pago, mensualidades,
 * vehículos dentro y turno abierto. Sobrevive a recargar o cerrar el navegador.
 */

function clave(parqueaderoId, nombre) {
  return `${parqueaderoId}:${nombre}`
}

export async function guardarReferencia(parqueaderoId, nombre, datos) {
  if (!parqueaderoId) return
  try {
    await db.cache_referencia.put({
      clave: clave(parqueaderoId, nombre),
      datos,
      actualizado_at: new Date().toISOString()
    })
  } catch (e) {
    console.warn('No se pudo guardar la copia local:', nombre, e)
  }
}

export async function leerReferencia(parqueaderoId, nombre) {
  if (!parqueaderoId) return null
  try {
    const fila = await db.cache_referencia.get(clave(parqueaderoId, nombre))
    return fila ? fila.datos : null
  } catch (e) {
    return null
  }
}

export async function antiguedadReferenciaHoras(parqueaderoId, nombre) {
  try {
    const fila = await db.cache_referencia.get(clave(parqueaderoId, nombre))
    if (!fila) return null
    return (Date.now() - new Date(fila.actualizado_at).getTime()) / 3600000
  } catch (e) {
    return null
  }
}

export async function borrarReferencias() {
  try {
    await db.cache_referencia.clear()
  } catch (e) {}
}
