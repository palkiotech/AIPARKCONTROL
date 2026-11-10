/**
 * Motor de Cálculo de Periodos de Mensualidad
 * Desarrollado con TDD (Paridad idéntica con calcular_periodo en SQL)
 */

function formatearFecha(year, month, day) {
  const y = String(year).padStart(4, '0')
  const m = String(month).padStart(2, '0')
  const d = String(day).padStart(2, '0')
  return `${y}-${m}-${d}`
}

function diasEnMes(year, month) {
  // month es 1-indexado (1 = enero, 2 = febrero, etc.)
  return new Date(Date.UTC(year, month, 0)).getUTCDate()
}

/**
 * Calcula el siguiente periodo de cobro
 * @param {Object} params
 * @param {string} params.tipoPeriodo - 'mensual' | 'dias_fijos'
 * @param {number} [params.diaCorte] - Día original de cobro (1 al 31)
 * @param {number} [params.duracionDias=30] - Días fijos si tipoPeriodo es 'dias_fijos'
 * @param {string} params.desdeFecha - Fecha base en formato 'YYYY-MM-DD'
 * @returns {{ desde: string, hasta: string }}
 */
export function calcularPeriodo({
  tipoPeriodo = 'mensual',
  diaCorte = null,
  duracionDias = 30,
  desdeFecha
}) {
  if (!desdeFecha) {
    throw new Error('desdeFecha es requerida')
  }

  const [yStr, mStr, dStr] = desdeFecha.split('-')
  const year = parseInt(yStr, 10)
  const month = parseInt(mStr, 10)
  const day = parseInt(dStr, 10)

  if (tipoPeriodo === 'dias_fijos') {
    const inicioUtc = Date.UTC(year, month - 1, day)
    const finUtc = inicioUtc + (duracionDias * 24 * 60 * 60 * 1000)
    const finDate = new Date(finUtc)

    return {
      desde: desdeFecha,
      hasta: formatearFecha(
        finDate.getUTCFullYear(),
        finDate.getUTCMonth() + 1,
        finDate.getUTCDate()
      )
    }
  }

  if (tipoPeriodo === 'mensual') {
    // Si no se suministra diaCorte, se asume el día de inicio
    const targetDay = diaCorte || day

    let nextYear = year
    let nextMonth = month + 1

    if (nextMonth > 12) {
      nextYear += 1
      nextMonth = 1
    }

    const maxDias = diasEnMes(nextYear, nextMonth)
    const finalDay = Math.min(targetDay, maxDias)

    return {
      desde: desdeFecha,
      hasta: formatearFecha(nextYear, nextMonth, finalDay)
    }
  }

  throw new Error(`Tipo de periodo desconocido: ${tipoPeriodo}`)
}

/**
 * Genera N periodos sucesivos para el simulador interactivo
 */
export function generarProximosPeriodos({
  tipoPeriodo = 'mensual',
  diaCorte = null,
  duracionDias = 30,
  fechaInicio,
  cantidad = 3
}) {
  const periodos = []
  let cursor = fechaInicio

  const corte = diaCorte || parseInt(fechaInicio.split('-')[2], 10)

  for (let i = 0; i < cantidad; i++) {
    const periodo = calcularPeriodo({
      tipoPeriodo,
      diaCorte: corte,
      duracionDias,
      desdeFecha: cursor
    })
    periodos.push(periodo)
    cursor = periodo.hasta
  }

  return periodos
}
