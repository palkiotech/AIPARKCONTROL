/**
 * Módulo de detección y compensación de desfase horario (Clock Drift)
 * Recomendación #1 y Decisión de Arquitectura #8
 */

const MAX_ALLOWED_DRIFT_MS = 5 * 60 * 1000 // 5 minutos
const DRIFT_STORAGE_KEY = 'parkcontrol_clock_offset_ms'

let currentOffsetMs = 0

// Recuperar offset previo si existía en almacenamiento local
try {
  const saved = localStorage.getItem(DRIFT_STORAGE_KEY)
  if (saved !== null) {
    currentOffsetMs = parseInt(saved, 10) || 0
  }
} catch (e) {}

/**
 * Actualiza el offset a partir de una fecha recibida del servidor
 * @param {Date|number|string} serverDate 
 */
export function syncServerTime(serverDate) {
  const serverTime = new Date(serverDate).getTime()
  if (isNaN(serverTime)) return

  const deviceTime = Date.now()
  currentOffsetMs = serverTime - deviceTime

  try {
    localStorage.setItem(DRIFT_STORAGE_KEY, currentOffsetMs.toString())
  } catch (e) {}
}

/**
 * Devuelve la diferencia actual en milisegundos (serverTime - deviceTime)
 */
export function getClockOffsetMs() {
  return currentOffsetMs
}

/**
 * Determina si el desajuste horario supera los 5 minutos permitidos
 */
export function isClockDriftCritical() {
  return Math.abs(currentOffsetMs) > MAX_ALLOWED_DRIFT_MS
}

/**
 * Devuelve la fecha y hora actual corregida con el offset del servidor
 */
export function getAdjustedNow() {
  return new Date(Date.now() + currentOffsetMs)
}

/**
 * Devuelve la hora corregida en formato ISO string
 */
export function getAdjustedNowISO() {
  return getAdjustedNow().toISOString()
}
