/**
 * Motor de Cobro (JavaScript puro)
 * Paridad con la función SQL calcular_cobro
 * Desarrollado con TDD
 */

/**
 * Calcula el cobro base según modalidad
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

function parseHoraMinutos(horaStr) {
  const [h, m] = horaStr.split(':')
  return parseInt(h, 10) * 60 + parseInt(m || '0', 10)
}

function estaEnFranja(fecha, franjaInicioStr, franjaFinStr) {
  const minDia = fecha.getHours() * 60 + fecha.getMinutes()
  const inicio = parseHoraMinutos(franjaInicioStr)
  const fin = parseHoraMinutos(franjaFinStr)

  if (inicio > fin) {
    // Cruza la medianoche (ej. 19:00 a 07:00)
    return minDia >= inicio || minDia < fin
  }
  return minDia >= inicio && minDia < fin
}

/**
 * Calcula el cobro partiendo la estancia en tramos diurnos y nocturnos si aplica
 */
export function calcularCobroConFranja({
  entradaAt,
  salidaAt,
  tarifaGeneral,
  tarifaNocturna = null
}) {
  const inicio = new Date(entradaAt)
  const fin = new Date(salidaAt)
  const msTotal = fin.getTime() - inicio.getTime()

  if (msTotal < 0) {
    throw new Error('La fecha de salida no puede ser anterior a la de entrada')
  }

  const minutosTotal = Math.round(msTotal / (1000 * 60))

  // Si no hay tarifa nocturna con franja configurada, cobrar todo con la general
  if (!tarifaNocturna || !tarifaNocturna.franjaInicio || !tarifaNocturna.franjaFin) {
    const valor = calcularCobroBase({
      minutos: minutosTotal,
      ...tarifaGeneral
    })
    return {
      minutosTotal,
      valorTotal: valor,
      desglose: [{ tipo: 'general', minutos: minutosTotal, valor }]
    }
  }

  // Generar puntos de corte entre entrada y salida
  const puntos = [inicio]
  const diaCursor = new Date(inicio)
  diaCursor.setHours(0, 0, 0, 0)

  const finDia = new Date(fin)
  finDia.setDate(finDia.getDate() + 1)

  while (diaCursor <= finDia) {
    const [hIni, mIni] = tarifaNocturna.franjaInicio.split(':').map(Number)
    const [hFin, mFin] = tarifaNocturna.franjaFin.split(':').map(Number)

    const pInicio = new Date(diaCursor)
    pInicio.setHours(hIni, mIni, 0, 0)
    if (pInicio > inicio && pInicio < fin) puntos.push(pInicio)

    const pFin = new Date(diaCursor)
    pFin.setHours(hFin, mFin, 0, 0)
    if (pFin > inicio && pFin < fin) puntos.push(pFin)

    diaCursor.setDate(diaCursor.getDate() + 1)
  }

  puntos.push(fin)
  puntos.sort((a, b) => a.getTime() - b.getTime())

  // Crear tramos
  const tramos = []
  for (let i = 0; i < puntos.length - 1; i++) {
    const p1 = puntos[i]
    const p2 = puntos[i + 1]
    const duracion = Math.round((p2.getTime() - p1.getTime()) / (1000 * 60))
    if (duracion <= 0) continue

    const medio = new Date(p1.getTime() + (p2.getTime() - p1.getTime()) / 2)
    const esNoche = estaEnFranja(medio, tarifaNocturna.franjaInicio, tarifaNocturna.franjaFin)

    const tipo = esNoche ? 'nocturna' : 'general'

    // Si el último tramo es del mismo tipo, fusionar
    if (tramos.length > 0 && tramos[tramos.length - 1].tipo === tipo) {
      tramos[tramos.length - 1].minutos += duracion
    } else {
      tramos.push({ tipo, minutos: duracion })
    }
  }

  // Calcular valor por cada tramo
  let valorTotal = 0
  const desglose = tramos.map(tramo => {
    let valorTramo = 0
    if (tramo.tipo === 'nocturna') {
      if (tarifaNocturna.modalidad === 'plena') {
        valorTramo = tarifaNocturna.valor
      } else {
        valorTramo = calcularCobroBase({
          minutos: tramo.minutos,
          ...tarifaNocturna
        })
      }
    } else {
      valorTramo = calcularCobroBase({
        minutos: tramo.minutos,
        ...tarifaGeneral
      })
    }

    valorTotal += valorTramo
    return {
      tipo: tramo.tipo,
      minutos: tramo.minutos,
      valor: valorTramo
    }
  })

  return {
    minutosTotal,
    valorTotal,
    desglose
  }
}
