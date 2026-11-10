/**
 * Motor de Cobro (JavaScript puro)
 * Paridad con la función SQL calcular_cobro
 * Desarrollado con TDD
 */

/**
 * Calcula el cobro base según modalidad
 * @param {Object} params
 * @param {number} params.minutos
 * @param {string} params.modalidad - 'por_minuto' | 'por_hora' | 'por_fraccion' | 'plena'
 * @param {number} params.valor
 * @param {number} [params.minutosGracia=0]
 * @param {number} [params.minutosFraccion=15]
 * @param {number} [params.tope24h]
 * @returns {number} Valor en pesos enteros
 */
export function calcularCobroBase({
  minutos,
  modalidad,
  valor,
  minutosGracia = 0,
  minutosFraccion = 15,
  tope24h = null
}) {
  if (minutos <= minutosGracia) {
    return 0
  }

  let total = 0

  switch (modalidad) {
    case 'por_minuto':
      total = minutos * valor
      break

    case 'por_hora':
      total = Math.ceil(minutos / 60) * valor
      break

    case 'por_fraccion':
      total = Math.ceil(minutos / minutosFraccion) * valor
      break

    case 'plena':
      total = valor
      break

    default:
      throw new Error(`Modalidad no soportada: ${modalidad}`)
  }

  // Aplicación de tope por 24 horas si aplica
  if (tope24h && minutos <= 1440 && total > tope24h) {
    total = tope24h
  }

  return Math.round(total)
}
