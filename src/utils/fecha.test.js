import { describe, it, expect } from 'vitest'
import { hoyEnZona, fechaEnZona, instanteDesdeLocal, sumarDias, diferenciaDias, rangoDiaUtc } from './fecha'

describe('Utilidades de fecha en la zona del parqueadero', () => {
  it('después de las 19:00 en Bogotá "hoy" sigue siendo el mismo día (no el UTC)', () => {
    // 20:30 del 10 nov en Bogotá = 01:30Z del 11 nov
    expect(hoyEnZona('America/Bogota', new Date('2026-11-11T01:30:00Z'))).toBe('2026-11-10')
  })

  it('convierte hora local a instante UTC', () => {
    expect(instanteDesdeLocal(2026, 11, 10, 19, 0, 'America/Bogota').toISOString()).toBe('2026-11-11T00:00:00.000Z')
  })

  it('fechaEnZona respeta la zona', () => {
    expect(fechaEnZona('2026-11-11T04:59:00Z', 'America/Bogota')).toBe('2026-11-10')
    expect(fechaEnZona('2026-11-11T05:00:00Z', 'America/Bogota')).toBe('2026-11-11')
  })

  it('suma días y calcula diferencias sin depender del navegador', () => {
    expect(sumarDias('2026-12-31', 1)).toBe('2027-01-01')
    expect(diferenciaDias('2027-03-01', '2027-02-27')).toBe(2)
  })

  it('rango de un día local en UTC', () => {
    expect(rangoDiaUtc('2026-11-10', 'America/Bogota')).toEqual({
      desde: '2026-11-10T05:00:00.000Z',
      hasta: '2026-11-11T05:00:00.000Z'
    })
  })
})
