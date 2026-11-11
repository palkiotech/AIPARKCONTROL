import { describe, it, expect } from 'vitest'
import { clasificarEstadoMensualidad } from './estadoMensualidad'

describe('Motor de Mensualidades - clasificarEstadoMensualidad (TDD)', () => {
  it('clasifica como al_dia cuando faltan más días que el umbral de aviso', () => {
    // Vence en 15 días, aviso a los 5 días
    const estado = clasificarEstadoMensualidad({
      fechaFin: '2026-11-25',
      fechaReferencia: '2026-11-10',
      diasAviso: 5,
      diasGracia: 0
    })

    expect(estado.estado).toBe('al_dia')
    expect(estado.diasRestantes).toBe(15)
    expect(estado.color).toBe('verde')
  })

  it('clasifica como por_vencer cuando faltan 5 días o menos', () => {
    // Vence en 3 días
    const estado = clasificarEstadoMensualidad({
      fechaFin: '2026-11-13',
      fechaReferencia: '2026-11-10',
      diasAviso: 5,
      diasGracia: 0
    })

    expect(estado.estado).toBe('por_vencer')
    expect(estado.diasRestantes).toBe(3)
    expect(estado.esHoy).toBe(false)
    expect(estado.color).toBe('amarillo')
  })

  it('detecta si vence hoy exactamente', () => {
    const estado = clasificarEstadoMensualidad({
      fechaFin: '2026-11-10',
      fechaReferencia: '2026-11-10',
      diasAviso: 5,
      diasGracia: 0
    })

    expect(estado.estado).toBe('por_vencer')
    expect(estado.diasRestantes).toBe(0)
    expect(estado.esHoy).toBe(true)
    expect(estado.color).toBe('amarillo')
  })

  it('clasifica como vencida cuando ya pasó la fecha de corte y los días de gracia', () => {
    // Venció hace 4 días con 0 días de gracia
    const estado = clasificarEstadoMensualidad({
      fechaFin: '2026-11-06',
      fechaReferencia: '2026-11-10',
      diasAviso: 5,
      diasGracia: 0
    })

    expect(estado.estado).toBe('vencida')
    expect(estado.diasRestantes).toBe(-4)
    expect(estado.diasMora).toBe(4)
    expect(estado.color).toBe('rojo')
  })

  it('respeta días de gracia de pago antes de declarar vencida', () => {
    // Venció hace 2 días pero tiene 3 días de gracia: sigue en periodo de cobro / por vencer
    const estado = clasificarEstadoMensualidad({
      fechaFin: '2026-11-08',
      fechaReferencia: '2026-11-10',
      diasAviso: 5,
      diasGracia: 3
    })

    expect(estado.estado).toBe('por_vencer')
    expect(estado.color).toBe('amarillo')
  })
})
