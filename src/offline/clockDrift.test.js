import { describe, it, expect, beforeEach } from 'vitest'
import { syncServerTime, getClockOffsetMs, isClockDriftCritical, getAdjustedNow } from './clockDrift'

describe('clockDrift (Compensación de desfase horario)', () => {
  beforeEach(() => {
    syncServerTime(Date.now())
  })

  it('calcula un offset cercano a 0 cuando el reloj del dispositivo coincide con el servidor', () => {
    syncServerTime(Date.now())
    expect(Math.abs(getClockOffsetMs())).toBeLessThan(50)
    expect(isClockDriftCritical()).toBe(false)
  })

  it('detecta desfase crítico si la hora del servidor difiere por más de 5 minutos', () => {
    const diezMinutosDespues = Date.now() + (10 * 60 * 1000)
    syncServerTime(diezMinutosDespues)

    expect(isClockDriftCritical()).toBe(true)
    expect(getClockOffsetMs()).toBeGreaterThanOrEqual(10 * 60 * 1000 - 50)
  })

  it('getAdjustedNow retorna la hora compensada con el offset', () => {
    const unMinutoAtras = Date.now() - (60 * 1000)
    syncServerTime(unMinutoAtras)

    const adjusted = getAdjustedNow().getTime()
    const rawNow = Date.now()

    expect(adjusted).toBeLessThan(rawNow)
  })
})
