import { describe, it, expect } from 'vitest'
import { calcularCobroBase } from './cobro'

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
    // 70 minutos a $3.000/h = 2 horas = $6.000
    const cobro = calcularCobroBase({
      minutos: 70,
      modalidad: 'por_hora',
      valor: 3000,
      minutosGracia: 5
    })
    expect(cobro).toBe(6000)
  })

  it('calcula cobro por fracción de 15 minutos', () => {
    // 25 minutos en fracciones de 15 = 2 fracciones = $2.000
    const cobro = calcularCobroBase({
      minutos: 25,
      modalidad: 'por_fraccion',
      valor: 1000,
      minutosFraccion: 15
    })
    expect(cobro).toBe(2000)
  })

  it('aplica el tope de 24 horas', () => {
    // 10 horas a $3.000/h = $30.000, pero tope es $25.000
    const cobro = calcularCobroBase({
      minutos: 600,
      modalidad: 'por_hora',
      valor: 3000,
      tope24h: 25000
    })
    expect(cobro).toBe(25000)
  })
})
