/**
 * Motor de Cobro (JavaScript puro)
 *
 * Paridad 1:1 con las funciones SQL public.calcular_cobro_base y
 * public.calcular_cobro_tramos (migración 20261111000000_saneamiento.sql).
 * El servidor tiene la última palabra (decisión #4): este motor se usa para el
 * cobro sin conexión, la estimación en pantalla y el simulador de Ajustes.
 *
 * Reglas (PLAN_V2 · Modalidades de tarifa):
 * - Si los minutos son <= minutos_gracia, el valor es 0.
 * - por_minuto: minutos × valor
 * - por_hora: ceil(minutos / 60) × valor
 * - por_fraccion: ceil(minutos / minutos_fraccion) × valor
 * - plena: valor por cada 24 h o fracción
 * - tope_por_24h: cada bloque completo de 24 h se cobra como máximo el tope, y
 *   el resto (menos de 24 h) también se limita al tope.
 *   Ej.: por_hora $3.000, tope $25.000 → 26 h = $25.000 + $6.000 = $31.000
 */

import { partesEnZona, instanteDesdeLocal, sumarDias } from '@/utils/fecha'

export const MODALIDADES = ['por_minuto', 'por_hora', 'por_fraccion', 'plena']
const MINUTOS_DIA = 1440

/**
 * Normaliza una tarifa venida de la base (snake_case) o del formulario (camelCase).
 */
export function normalizarTarifa(t) {
  if (!t) return null
  return {
    modalidad: t.modalidad,
    valor: Number(t.valor) || 0,
    minutosGracia: Number(t.minutosGracia ?? t.minutos_gracia ?? 0) || 0,
    minutosFraccion: Number(t.minutosFraccion ?? t.minutos_fraccion ?? 15) || 15,
    tope24h: (t.tope24h ?? t.tope_por_24h) ? Number(t.tope24h ?? t.tope_por_24h) : null,
    franjaInicio: (t.franjaInicio ?? t.franja_inicio ?? null) ? String(t.franjaInicio ?? t.franja_inicio).slice(0, 5) : null,
    franjaFin: (t.franjaFin ?? t.franja_fin ?? null) ? String(t.franjaFin ?? t.franja_fin).slice(0, 5) : null
  }
}

function valorSinTope(minutos, modalidad, valor, minutosFraccion) {
  if (minutos <= 0) return 0
  switch (modalidad) {
    case 'por_minuto':
      return minutos * valor
    case 'por_hora':
      return Math.ceil(minutos / 60) * valor
    case 'por_fraccion':
      return Math.ceil(minutos / minutosFraccion) * valor
    case 'plena':
      return Math.ceil(minutos / MINUTOS_DIA) * valor
    default:
      throw new Error(`Modalidad no soportada: ${modalidad}`)
  }
}

/**
 * Calcula el cobro de una cantidad de minutos con una tarifa.
 */
export function calcularCobroBase({
  minutos,
  modalidad,
  valor,
  minutosGracia = 0,
  minutosFraccion = 15,
  tope24h = null
}) {
  if (!MODALIDADES.includes(modalidad)) {
    throw new Error(`Modalidad no soportada: ${modalidad}`)
  }
  const min = Math.max(0, Math.round(minutos || 0))
  if (min <= (minutosGracia || 0)) return 0

  const fraccion = minutosFraccion && minutosFraccion > 0 ? minutosFraccion : 15

  if (modalidad === 'plena' || !tope24h) {
    return Math.round(valorSinTope(min, modalidad, valor, fraccion))
  }

  const bloques = Math.floor(min / MINUTOS_DIA)
  const resto = min % MINUTOS_DIA
  const valorBloque = Math.min(tope24h, valorSinTope(MINUTOS_DIA, modalidad, valor, fraccion))
  const valorResto = Math.min(tope24h, valorSinTope(resto, modalidad, valor, fraccion))
  return Math.round(bloques * valorBloque + valorResto)
}

function minutosDelDia(hhmm) {
  const [h, m] = hhmm.split(':').map(Number)
  return h * 60 + (m || 0)
}

function estaEnFranja(instante, franjaInicio, franjaFin, zona) {
  const p = partesEnZona(instante, zona)
  const min = p.hora * 60 + p.minuto
  const ini = minutosDelDia(franjaInicio)
  const fin = minutosDelDia(franjaFin)
  if (ini > fin) return min >= ini || min < fin // cruza medianoche (19:00–07:00)
  return min >= ini && min < fin
}

/**
 * Calcula el cobro partiendo la estancia en tramos generales y nocturnos.
 *
 * @param {Object} p
 * @param {string|Date} p.entradaAt
 * @param {string|Date} p.salidaAt
 * @param {Object} p.tarifaGeneral - tarifa sin franja (snake_case o camelCase)
 * @param {Object|null} p.tarifaNocturna - tarifa con franja_inicio/franja_fin
 * @param {string} p.zonaHoraria - zona del parqueadero (las franjas son hora local)
 */
export function calcularCobroConFranja({
  entradaAt,
  salidaAt,
  tarifaGeneral,
  tarifaNocturna = null,
  zonaHoraria = 'America/Bogota'
}) {
  const inicio = new Date(entradaAt)
  const fin = new Date(salidaAt)
  const msTotal = fin.getTime() - inicio.getTime()

  if (Number.isNaN(msTotal)) throw new Error('Fechas inválidas')
  if (msTotal < 0) throw new Error('La fecha de salida no puede ser anterior a la de entrada')

  const general = normalizarTarifa(tarifaGeneral)
  const nocturna = normalizarTarifa(tarifaNocturna)
  if (!general) throw new Error('No hay tarifa general configurada')

  const minutosTotal = Math.round(msTotal / 60000)

  // La gracia aplica sobre la estancia completa
  if (minutosTotal <= general.minutosGracia) {
    return {
      minutosTotal,
      valorTotal: 0,
      desglose: [{ tipo: 'general', minutos: minutosTotal, valor: 0 }]
    }
  }

  if (!nocturna || !nocturna.franjaInicio || !nocturna.franjaFin) {
    const valor = calcularCobroBase({ minutos: minutosTotal, ...general, minutosGracia: 0 })
    return {
      minutosTotal,
      valorTotal: valor,
      desglose: [{ tipo: 'general', minutos: minutosTotal, valor }]
    }
  }

  // Puntos de corte: cada inicio y fin de franja (hora local) entre entrada y salida
  const puntos = [inicio, fin]
  const [hIni, mIni] = nocturna.franjaInicio.split(':').map(Number)
  const [hFin, mFin] = nocturna.franjaFin.split(':').map(Number)
  const pIni = partesEnZona(inicio, zonaHoraria)
  const pFin = partesEnZona(fin, zonaHoraria)
  const pad = n => String(n).padStart(2, '0')
  let dia = sumarDias(`${pIni.anio}-${pad(pIni.mes)}-${pad(pIni.dia)}`, -1)
  const ultimoDia = sumarDias(`${pFin.anio}-${pad(pFin.mes)}-${pad(pFin.dia)}`, 1)

  while (dia <= ultimoDia) {
    const [y, m, d] = dia.split('-').map(Number)
    for (const [h, mi] of [[hIni, mIni], [hFin, mFin]]) {
      const corte = instanteDesdeLocal(y, m, d, h, mi, zonaHoraria)
      if (corte > inicio && corte < fin) puntos.push(corte)
    }
    dia = sumarDias(dia, 1)
  }

  puntos.sort((a, b) => a.getTime() - b.getTime())

  const tramos = []
  for (let i = 0; i < puntos.length - 1; i++) {
    const p1 = puntos[i]
    const p2 = puntos[i + 1]
    const duracion = Math.round((p2.getTime() - p1.getTime()) / 60000)
    if (duracion <= 0) continue
    const medio = new Date(p1.getTime() + (p2.getTime() - p1.getTime()) / 2)
    const tipo = estaEnFranja(medio, nocturna.franjaInicio, nocturna.franjaFin, zonaHoraria) ? 'nocturna' : 'general'
    const ultimo = tramos[tramos.length - 1]
    if (ultimo && ultimo.tipo === tipo) ultimo.minutos += duracion
    else tramos.push({ tipo, minutos: duracion })
  }

  let valorTotal = 0
  const desglose = tramos.map(tramo => {
    let valor
    if (tramo.tipo === 'nocturna') {
      // Una tarifa nocturna plena cobra su valor una vez por noche (cada tramo es una noche)
      valor = nocturna.modalidad === 'plena'
        ? nocturna.valor
        : calcularCobroBase({ minutos: tramo.minutos, ...nocturna, minutosGracia: 0 })
    } else {
      valor = calcularCobroBase({ minutos: tramo.minutos, ...general, minutosGracia: 0 })
    }
    valorTotal += valor
    return { tipo: tramo.tipo, minutos: tramo.minutos, valor }
  })

  return { minutosTotal, valorTotal, desglose }
}

/**
 * Elige la tarifa general y la nocturna de un tipo de vehículo.
 * - general: la tarifa elegida si no tiene franja; si no, la predeterminada sin franja.
 * - nocturna: la tarifa activa con franja del tipo (solo puede haber una).
 */
export function resolverTarifas(tarifasDelTipo = [], tarifaElegidaId = null) {
  const activas = tarifasDelTipo.filter(t => t.activa !== false)
  const sinFranja = activas.filter(t => !t.franja_inicio && !t.franjaInicio)
  const elegida = activas.find(t => t.id === tarifaElegidaId)
  const general = (elegida && !elegida.franja_inicio && !elegida.franjaInicio)
    ? elegida
    : (sinFranja.find(t => t.es_predeterminada) || sinFranja[0] || null)
  const nocturna = activas.find(t => t.franja_inicio || t.franjaInicio) || null
  return { general, nocturna }
}
