/**
 * Utilidades de fecha y hora en la zona horaria del parqueadero.
 *
 * Regla del plan (decisión #8): todo se guarda en UTC y "hoy" se calcula en la
 * zona del parqueadero (por defecto America/Bogota), nunca en la del navegador
 * ni con toISOString() (que devuelve la fecha UTC y adelanta un día después de
 * las 19:00 en Colombia).
 */

export const ZONA_POR_DEFECTO = 'America/Bogota'

const formateadores = new Map()

function formateador(zona) {
  if (!formateadores.has(zona)) {
    formateadores.set(zona, new Intl.DateTimeFormat('en-US', {
      timeZone: zona,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit'
    }))
  }
  return formateadores.get(zona)
}

/**
 * Devuelve las partes de reloj de pared (año, mes, día, hora, minuto, segundo)
 * de un instante en la zona indicada.
 */
export function partesEnZona(instante, zona = ZONA_POR_DEFECTO) {
  const fecha = instante instanceof Date ? instante : new Date(instante)
  const partes = {}
  for (const p of formateador(zona).formatToParts(fecha)) {
    if (p.type !== 'literal') partes[p.type] = parseInt(p.value, 10)
  }
  return {
    anio: partes.year,
    mes: partes.month,
    dia: partes.day,
    hora: partes.hour,
    minuto: partes.minute,
    segundo: partes.second
  }
}

/**
 * Diferencia en ms entre el reloj de pared de la zona y UTC para un instante.
 */
export function offsetZonaMs(instante, zona = ZONA_POR_DEFECTO) {
  const ms = instante instanceof Date ? instante.getTime() : new Date(instante).getTime()
  const p = partesEnZona(ms, zona)
  const comoUtc = Date.UTC(p.anio, p.mes - 1, p.dia, p.hora, p.minuto, p.segundo)
  return comoUtc - Math.floor(ms / 1000) * 1000
}

/**
 * Construye el instante (Date) correspondiente a una hora de reloj de pared en la zona.
 */
export function instanteDesdeLocal(anio, mes, dia, hora = 0, minuto = 0, zona = ZONA_POR_DEFECTO) {
  const aproximado = Date.UTC(anio, mes - 1, dia, hora, minuto, 0)
  const offset = offsetZonaMs(aproximado, zona)
  return new Date(aproximado - offset)
}

function pad(n) {
  return String(n).padStart(2, '0')
}

/**
 * Fecha 'YYYY-MM-DD' de un instante en la zona del parqueadero.
 */
export function fechaEnZona(instante, zona = ZONA_POR_DEFECTO) {
  const p = partesEnZona(instante, zona)
  return `${p.anio}-${pad(p.mes)}-${pad(p.dia)}`
}

/**
 * "Hoy" ('YYYY-MM-DD') en la zona del parqueadero.
 */
export function hoyEnZona(zona = ZONA_POR_DEFECTO, ahora = new Date()) {
  return fechaEnZona(ahora, zona)
}

/**
 * Suma días a una fecha 'YYYY-MM-DD' sin depender de la zona del navegador.
 */
export function sumarDias(fechaISO, dias) {
  const [y, m, d] = fechaISO.split('-').map(Number)
  const t = new Date(Date.UTC(y, m - 1, d + dias))
  return `${t.getUTCFullYear()}-${pad(t.getUTCMonth() + 1)}-${pad(t.getUTCDate())}`
}

/**
 * Diferencia en días entre dos fechas 'YYYY-MM-DD' (a - b).
 */
export function diferenciaDias(fechaA, fechaB) {
  const [yA, mA, dA] = fechaA.split('-').map(Number)
  const [yB, mB, dB] = fechaB.split('-').map(Number)
  return Math.round((Date.UTC(yA, mA - 1, dA) - Date.UTC(yB, mB - 1, dB)) / 86400000)
}

/**
 * Rango [inicio, fin) en UTC ISO para filtrar un día local completo de la zona.
 */
export function rangoDiaUtc(fechaISO, zona = ZONA_POR_DEFECTO) {
  const [y, m, d] = fechaISO.split('-').map(Number)
  const inicio = instanteDesdeLocal(y, m, d, 0, 0, zona)
  const [y2, m2, d2] = sumarDias(fechaISO, 1).split('-').map(Number)
  const fin = instanteDesdeLocal(y2, m2, d2, 0, 0, zona)
  return { desde: inicio.toISOString(), hasta: fin.toISOString() }
}

/**
 * Formatea fecha y hora legible en la zona del parqueadero (es-CO).
 */
export function formatearFechaHora(instante, zona = ZONA_POR_DEFECTO, opciones = {}) {
  if (!instante) return ''
  return new Intl.DateTimeFormat('es-CO', {
    timeZone: zona,
    day: '2-digit',
    month: 'short',
    hour: '2-digit',
    minute: '2-digit',
    ...opciones
  }).format(new Date(instante))
}

/**
 * Formatea una fecha 'YYYY-MM-DD' (sin hora) como "20 nov 2026".
 */
export function formatearFechaCorta(fechaISO) {
  if (!fechaISO) return ''
  const [y, m, d] = fechaISO.slice(0, 10).split('-').map(Number)
  return new Intl.DateTimeFormat('es-CO', {
    timeZone: 'UTC',
    day: '2-digit',
    month: 'short',
    year: 'numeric'
  }).format(new Date(Date.UTC(y, m - 1, d)))
}
