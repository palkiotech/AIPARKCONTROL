import { describe, it, expect } from 'vitest'
import { calcularCobroBase, calcularCobroConFranja, resolverTarifas, normalizarTarifa } from './cobro'

describe('Motor de cobro - calcularCobroBase', () => {
  it('aplica minutos de gracia retornando 0', () => {
    expect(calcularCobroBase({ minutos: 5, modalidad: 'por_hora', valor: 3000, minutosGracia: 5 })).toBe(0)
  })

  it('cobra desde el primer minuto cuando la gracia es 0', () => {
    expect(calcularCobroBase({ minutos: 1, modalidad: 'por_hora', valor: 3000 })).toBe(3000)
  })

  it('calcula cobro por hora con redondeo superior (ejemplo del plan: 1 h 10 min = $6.000)', () => {
    expect(calcularCobroBase({ minutos: 70, modalidad: 'por_hora', valor: 3000, minutosGracia: 5 })).toBe(6000)
  })

  it('calcula cobro por minuto', () => {
    expect(calcularCobroBase({ minutos: 37, modalidad: 'por_minuto', valor: 100 })).toBe(3700)
  })

  it('calcula cobro por fracción de 15 minutos', () => {
    expect(calcularCobroBase({ minutos: 25, modalidad: 'por_fraccion', valor: 1000, minutosFraccion: 15 })).toBe(2000)
  })

  it('respeta fracciones de 30 minutos configuradas', () => {
    expect(calcularCobroBase({ minutos: 61, modalidad: 'por_fraccion', valor: 1500, minutosFraccion: 30 })).toBe(4500)
  })

  it('aplica el tope dentro de las primeras 24 horas', () => {
    expect(calcularCobroBase({ minutos: 600, modalidad: 'por_hora', valor: 3000, tope24h: 25000 })).toBe(25000)
  })

  it('aplica el tope por cada bloque de 24 h (ejemplo del plan: 26 h = $31.000)', () => {
    expect(calcularCobroBase({ minutos: 26 * 60, modalidad: 'por_hora', valor: 3000, minutosGracia: 5, tope24h: 25000 })).toBe(31000)
  })

  it('aplica el tope a varios días completos', () => {
    expect(calcularCobroBase({ minutos: 3 * 1440, modalidad: 'por_hora', valor: 3000, tope24h: 25000 })).toBe(75000)
  })

  it('tarifa plena cobra por cada 24 h o fracción', () => {
    expect(calcularCobroBase({ minutos: 30, modalidad: 'plena', valor: 12000 })).toBe(12000)
    expect(calcularCobroBase({ minutos: 1440, modalidad: 'plena', valor: 12000 })).toBe(12000)
    expect(calcularCobroBase({ minutos: 1441, modalidad: 'plena', valor: 12000 })).toBe(24000)
  })

  it('rechaza modalidades desconocidas (fraccion_15m / pleno no existen)', () => {
    expect(() => calcularCobroBase({ minutos: 10, modalidad: 'pleno', valor: 1 })).toThrow()
    expect(() => calcularCobroBase({ minutos: 10, modalidad: 'fraccion_15m', valor: 1 })).toThrow()
  })
})

describe('Motor de cobro - calcularCobroConFranja (tarifa nocturna en hora de Bogotá)', () => {
  const general = { modalidad: 'por_hora', valor: 3000, minutos_gracia: 0 }
  const nocturna = { modalidad: 'plena', valor: 12000, franja_inicio: '19:00:00', franja_fin: '07:00:00' }

  it('cobra solo con tarifa general cuando no hay tarifa nocturna', () => {
    const r = calcularCobroConFranja({
      entradaAt: '2026-11-10T17:00:00-05:00',
      salidaAt: '2026-11-10T20:00:00-05:00',
      tarifaGeneral: general
    })
    expect(r.minutosTotal).toBe(180)
    expect(r.valorTotal).toBe(9000)
    expect(r.desglose.length).toBe(1)
  })

  it('ejemplo del PLAN_V2: 17:00 → 08:00 = $6.000 + $12.000 + $3.000 = $21.000', () => {
    const r = calcularCobroConFranja({
      entradaAt: '2026-11-10T17:00:00-05:00',
      salidaAt: '2026-11-11T08:00:00-05:00',
      tarifaGeneral: general,
      tarifaNocturna: nocturna,
      zonaHoraria: 'America/Bogota'
    })
    expect(r.minutosTotal).toBe(900)
    expect(r.valorTotal).toBe(21000)
    expect(r.desglose).toEqual([
      { tipo: 'general', minutos: 120, valor: 6000 },
      { tipo: 'nocturna', minutos: 720, valor: 12000 },
      { tipo: 'general', minutos: 60, valor: 3000 }
    ])
  })

  it('las franjas se evalúan en la zona del parqueadero, no en UTC', () => {
    // 00:00Z a 02:00Z = 19:00 a 21:00 en Bogotá → todo nocturno
    const r = calcularCobroConFranja({
      entradaAt: '2026-11-11T00:00:00Z',
      salidaAt: '2026-11-11T02:00:00Z',
      tarifaGeneral: general,
      tarifaNocturna: nocturna,
      zonaHoraria: 'America/Bogota'
    })
    expect(r.desglose).toEqual([{ tipo: 'nocturna', minutos: 120, valor: 12000 }])
  })

  it('cobra la nocturna plena una vez por cada noche', () => {
    const r = calcularCobroConFranja({
      entradaAt: '2026-11-10T18:00:00-05:00',
      salidaAt: '2026-11-12T08:00:00-05:00',
      tarifaGeneral: general,
      tarifaNocturna: nocturna
    })
    // 1 h general + noche + 12 h general + noche + 1 h general
    expect(r.valorTotal).toBe(3000 + 12000 + 36000 + 12000 + 3000)
  })

  it('aplica la gracia sobre la estancia completa', () => {
    const r = calcularCobroConFranja({
      entradaAt: '2026-11-10T10:00:00-05:00',
      salidaAt: '2026-11-10T10:04:00-05:00',
      tarifaGeneral: { ...general, minutos_gracia: 5 }
    })
    expect(r.valorTotal).toBe(0)
  })

  it('rechaza salidas anteriores a la entrada', () => {
    expect(() => calcularCobroConFranja({
      entradaAt: '2026-11-10T10:00:00-05:00',
      salidaAt: '2026-11-10T09:00:00-05:00',
      tarifaGeneral: general
    })).toThrow()
  })
})

describe('resolverTarifas y normalizarTarifa', () => {
  const tarifas = [
    { id: 'a', modalidad: 'por_hora', valor: 3000, es_predeterminada: true, activa: true },
    { id: 'b', modalidad: 'plena', valor: 20000, es_predeterminada: false, activa: true },
    { id: 'n', modalidad: 'plena', valor: 12000, franja_inicio: '19:00', franja_fin: '07:00', activa: true },
    { id: 'x', modalidad: 'por_hora', valor: 1, activa: false }
  ]

  it('usa la predeterminada sin franja como general y detecta la nocturna', () => {
    const { general, nocturna } = resolverTarifas(tarifas)
    expect(general.id).toBe('a')
    expect(nocturna.id).toBe('n')
  })

  it('respeta la tarifa elegida por el operador', () => {
    expect(resolverTarifas(tarifas, 'b').general.id).toBe('b')
  })

  it('normaliza snake_case de la base', () => {
    expect(normalizarTarifa({ modalidad: 'por_fraccion', valor: '1000', minutos_fraccion: 30, tope_por_24h: 9000 }))
      .toMatchObject({ valor: 1000, minutosFraccion: 30, tope24h: 9000, minutosGracia: 0 })
  })
})
