/**
 * Utilidades para normalización y validación de placas
 */

/**
 * Normaliza una placa: mayúsculas, sin espacios, sin guiones ni caracteres especiales
 * @param {string} placa
 * @returns {string}
 */
export function normalizarPlaca(placa) {
  if (!placa) return ''
  return placa
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '')
    .trim()
}

/**
 * Valida que una placa tenga una longitud mínima y caracteres alfanuméricos
 * @param {string} placa
 * @returns {boolean}
 */
export function esPlacaValida(placa) {
  const normalizada = normalizarPlaca(placa)
  return normalizada.length >= 3 && normalizada.length <= 10
}
