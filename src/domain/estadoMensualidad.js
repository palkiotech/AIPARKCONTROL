/**
 * Clasificador del estado de vencimiento de mensualidades
 * Desarrollado con TDD
 */

function calcularDiferenciaDias(fechaA, fechaB) {
  const [yA, mA, dA] = fechaA.split('-').map(Number)
  const [yB, mB, dB] = fechaB.split('-').map(Number)

  const utcA = Date.UTC(yA, mA - 1, dA)
  const utcB = Date.UTC(yB, mB - 1, dB)

  return Math.round((utcA - utcB) / (1000 * 60 * 60 * 24))
}

/**
 * Determina el estado del semáforo para una mensualidad
 * @param {Object} params
 * @param {string} params.fechaFin - Fecha de vencimiento (YYYY-MM-DD)
 * @param {string} [params.fechaReferencia] - Fecha actual/base (YYYY-MM-DD)
 * @param {number} [params.diasAviso=5] - Días de anticipación para estado 'por_vencer'
 * @param {number} [params.diasGracia=0] - Días de gracia antes de marcar 'vencida'
 * @returns {{ estado: 'al_dia'|'por_vencer'|'vencida', diasRestantes: number, diasMora: number, esHoy: boolean, color: 'verde'|'amarillo'|'rojo' }}
 */
export function clasificarEstadoMensualidad({
  fechaFin,
  fechaReferencia = new Date().toISOString().slice(0, 10),
  diasAviso = 5,
  diasGracia = 0
}) {
  const diasRestantes = calcularDiferenciaDias(fechaFin, fechaReferencia)
  const esHoy = diasRestantes === 0

  if (diasRestantes > diasAviso) {
    return {
      estado: 'al_dia',
      diasRestantes,
      diasMora: 0,
      esHoy: false,
      color: 'verde'
    }
  }

  // Si venció pero está dentro de los días de gracia
  if (diasRestantes < 0 && Math.abs(diasRestantes) > diasGracia) {
    const diasMora = Math.abs(diasRestantes) - diasGracia
    return {
      estado: 'vencida',
      diasRestantes,
      diasMora,
      esHoy: false,
      color: 'rojo'
    }
  }

  return {
    estado: 'por_vencer',
    diasRestantes,
    diasMora: 0,
    esHoy,
    color: 'amarillo'
  }
}
