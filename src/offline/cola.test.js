import { describe, it, expect, beforeEach } from 'vitest'
import { crearOperacionOffline, validarEstructuraOperacion } from './cola'
import { syncServerTime } from './clockDrift'

describe('Cola de Operaciones Offline (TDD)', () => {
  beforeEach(() => {
    syncServerTime(Date.now())
  })

  it('genera una operación válida con UUID único y estado pendiente', () => {
    const op = crearOperacionOffline({
      tipo: 'entrada',
      payload: { placa: 'ABC123', tipoVehiculoId: 'tipo-1' }
    })

    expect(op.id).toBeDefined()
    expect(op.id.length).toBeGreaterThanOrEqual(32)
    expect(op.tipo).toBe('entrada')
    expect(op.payload.placa).toBe('ABC123')
    expect(op.estado).toBe('pendiente')
    expect(op.creada_en_dispositivo_at).toBeDefined()
  })

  it('incorpora la compensación de desfase horario en creada_en_dispositivo_at', () => {
    // Si el reloj local está 10 minutos atrasado, la operación debe generarse con la hora corregida del servidor
    const diezMinutosDespues = Date.now() + (10 * 60 * 1000)
    syncServerTime(diezMinutosDespues)

    const op = crearOperacionOffline({
      tipo: 'salida',
      payload: { registroId: 'reg-1', valor: 6000 }
    })

    const opTime = new Date(op.creada_en_dispositivo_at).getTime()
    const rawNow = Date.now()

    expect(opTime).toBeGreaterThanOrEqual(rawNow + (9 * 60 * 1000))
  })

  it('valida que una operación tenga tipo y payload requeridos', () => {
    expect(validarEstructuraOperacion({ tipo: 'entrada', payload: {} })).toBe(true)
    expect(validarEstructuraOperacion({ tipo: '', payload: {} })).toBe(false)
    expect(validarEstructuraOperacion({ payload: {} })).toBe(false)
    expect(validarEstructuraOperacion(null)).toBe(false)
  })
})
