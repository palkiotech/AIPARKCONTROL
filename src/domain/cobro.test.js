import { describe, it, expect } from 'vitest'
import { calcularCobroBase, calcularCobroConFranja } from './cobro'

describe('Motor de cobro - calcularCobroBase (TDD)', () => {
  it('aplica minutos de gracia retornando 0', () => {
    const cobro = calcularCobroBase({
      minutos: 5,
      modalidad: 'por_hora',
      valor: 3000,
      minutosGracia: 5
    })
    expect(cobro).toBe(0)
  })

  it('calcula cobro por hora con redondeo superior', () => {
    const cobro = calcularCobroBase({
      minutos: 70,
      modalidad: 'por_hora',
      valor: 3000,
      minutosGracia: 5
    })
    expect(cobro).toBe(6000)
  })

  it('calcula cobro por fracción de 15 minutos', () => {
    const cobro = calcularCobroBase({
      minutos: 25,
      modalidad: 'por_fraccion',
      valor: 1000,
      minutosFraccion: 15
    })
    expect(cobro).toBe(2000)
  })

  it('aplica el tope de 24 horas', () => {
    const cobro = calcularCobroBase({
      minutos: 600,
      modalidad: 'por_hora',
      valor: 3000,
      tope24h: 25000
    })
    expect(cobro).toBe(25000)
  })
})

describe('Motor de cobro - calcularCobroConFranja (Tarifa Nocturna / Tramos)', () => {
  it('cobra solo con tarifa general cuando no hay tarifa nocturna configurada', () => {
    const resultado = calcularCobroConFranja({
      entradaAt: '2026-11-10T17:00:00',
      salidaAt: '2026-11-10T20:00:00',
      tarifaGeneral: {
        modalidad: 'por_hora',
        valor: 3000,
        minutosGracia: 0
      },
      tarifaNocturna: null
    })

    expect(resultado.minutosTotal).toBe(180)
    expect(resultado.valorTotal).toBe(9000)
    expect(resultado.desglose.length).toBe(1)
  })

  it('calcula estancia mixta diurna + nocturna plena + diurna (ejemplo del PLAN_V2.md: $21.000)', () => {
    // Entrada: 17:00, Salida: 08:00 día siguiente
    // Franja nocturna: 19:00 a 07:00 con tarifa plena de $12.000
    // General: $3.000 por hora
    const resultado = calcularCobroConFranja({
      entradaAt: '2026-11-10T17:00:00',
      salidaAt: '2026-11-11T08:00:00',
      tarifaGeneral: {
        modalidad: 'por_hora',
        valor: 3000,
        minutosGracia: 0
      },
      tarifaNocturna: {
        modalidad: 'plena',
        valor: 12000,
        franjaInicio: '19:00',
        franjaFin: '07:00'
      }
    })

    expect(resultado.minutosTotal).toBe(900) // 15 horas
    expect(resultado.valorTotal).toBe(21000) // $6.000 + $12.000 + $3.000
    expect(resultado.desglose).toEqual([
      { tipo: 'general', minutos: 120, valor: 6000 },
      { tipo: 'nocturna', minutos: 720, valor: 12000 },
      { tipo: 'general', minutos: 60, valor: 3000 }
    ])
  })
})
