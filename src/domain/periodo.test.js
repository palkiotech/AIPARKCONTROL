import { describe, it, expect } from 'vitest'
import { calcularPeriodo, generarProximosPeriodos } from './periodo'

describe('Motor de Periodos - calcularPeriodo (TDD)', () => {
  it('calcula periodo mensual estándar de mes completo (ej. 20 nov -> 20 dic)', () => {
    const periodo = calcularPeriodo({
      tipoPeriodo: 'mensual',
      diaCorte: 20,
      desdeFecha: '2026-11-20'
    })

    expect(periodo.desde).toBe('2026-11-20')
    expect(periodo.hasta).toBe('2026-12-20')
  })

  it('calcula periodo mensual cruzando cambio de año (ej. 3 dic -> 3 ene)', () => {
    const periodo = calcularPeriodo({
      tipoPeriodo: 'mensual',
      diaCorte: 3,
      desdeFecha: '2026-12-03'
    })

    expect(periodo.desde).toBe('2026-12-03')
    expect(periodo.hasta).toBe('2027-01-03')
  })

  it('maneja meses cortos recortando al último día del mes (ej. 31 ene -> 28 feb en año no bisiesto)', () => {
    const periodo = calcularPeriodo({
      tipoPeriodo: 'mensual',
      diaCorte: 31,
      desdeFecha: '2027-01-31'
    })

    expect(periodo.desde).toBe('2027-01-31')
    expect(periodo.hasta).toBe('2027-02-28')
  })

  it('recupera el día de corte original tras un mes corto (ej. desde 28 feb con dia_corte 31 -> 31 mar)', () => {
    const periodo = calcularPeriodo({
      tipoPeriodo: 'mensual',
      diaCorte: 31,
      desdeFecha: '2027-02-28'
    })

    expect(periodo.desde).toBe('2027-02-28')
    expect(periodo.hasta).toBe('2027-03-31')
  })

  it('calcula periodo para plan de días fijos (ej. quincena de 15 días)', () => {
    const periodo = calcularPeriodo({
      tipoPeriodo: 'dias_fijos',
      duracionDias: 15,
      desdeFecha: '2026-11-03'
    })

    expect(periodo.desde).toBe('2026-11-03')
    expect(periodo.hasta).toBe('2026-11-18')
  })

  it('genera múltiples periodos consecutivos para el simulador de Ajustes', () => {
    const periodos = generarProximosPeriodos({
      tipoPeriodo: 'mensual',
      diaCorte: 31,
      fechaInicio: '2027-01-31',
      cantidad: 3
    })

    expect(periodos.length).toBe(3)
    expect(periodos[0]).toEqual({ desde: '2027-01-31', hasta: '2027-02-28' })
    expect(periodos[1]).toEqual({ desde: '2027-02-28', hasta: '2027-03-31' })
    expect(periodos[2]).toEqual({ desde: '2027-03-31', hasta: '2027-04-30' })
  })
})
