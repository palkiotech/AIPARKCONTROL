/**
 * Registro de cachés en memoria que deben limpiarse al cerrar sesión.
 * Evita que el siguiente usuario del dispositivo vea datos del anterior.
 */
const limpiezas = new Set()

export function registrarLimpieza(fn) {
  limpiezas.add(fn)
  return () => limpiezas.delete(fn)
}

export function limpiarCachesDeSesion() {
  for (const fn of limpiezas) {
    try {
      fn()
    } catch (e) {
      console.warn('Error limpiando caché de sesión:', e)
    }
  }
}

/**
 * Determina si un error es de red (sin conexión) y no de validación del servidor.
 * Solo los errores de red justifican encolar la operación para sincronizar luego.
 */
export function esErrorDeRed(err) {
  if (typeof navigator !== 'undefined' && !navigator.onLine) return true
  if (!err) return false
  const msg = String(err.message || err)
  return err.name === 'TypeError' ||
    msg.includes('Failed to fetch') ||
    msg.includes('NetworkError') ||
    msg.includes('Load failed') ||
    msg.includes('fetch failed')
}

export function estaEnLinea() {
  return typeof navigator === 'undefined' ? true : navigator.onLine
}

/**
 * Convierte un error de Supabase/PostgREST en un mensaje legible para el operador.
 */
export function mensajeDeError(err, porDefecto = 'Ocurrió un error inesperado') {
  if (!err) return porDefecto
  if (esErrorDeRed(err)) return 'Sin conexión con el servidor. Intenta de nuevo.'
  const msg = err.message || err.details || String(err)
  if (msg.includes('duplicate key')) return 'El registro ya existe.'
  if (msg.includes('JWT') || msg.includes('jwt')) return 'Tu sesión expiró. Inicia sesión de nuevo.'
  return msg || porDefecto
}
