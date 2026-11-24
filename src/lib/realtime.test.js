import { describe, it, expect, vi, beforeEach } from 'vitest'

// Supabase simulado: registra canales creados, bindings y estado
const canales = []
vi.mock('@/lib/supabase', () => {
  const supabase = {
    channel(nombre) {
      const canal = {
        nombre,
        bindings: [],
        alEstado: null,
        on(_tipo, filtro, cb) { this.bindings.push({ filtro, cb }); return this },
        subscribe(cb) { this.alEstado = cb; cb('SUBSCRIBED'); return this },
        emitir(payload) { for (const b of this.bindings) b.cb(payload) }
      }
      canales.push(canal)
      return canal
    },
    removeChannel: vi.fn()
  }
  return { supabase }
})

const { escucharTablas } = await import('@/lib/realtime')
const { supabase } = await import('@/lib/supabase')

describe('escucharTablas', () => {
  beforeEach(() => {
    canales.length = 0
    supabase.removeChannel.mockClear()
  })

  it('comparte un solo canal entre varios oyentes y todos reciben el evento', () => {
    const a = vi.fn()
    const b = vi.fn()
    const cancelarA = escucharTablas(['registros'], 'pq1', a)
    const cancelarB = escucharTablas(['registros'], 'pq1', b)
    expect(canales).toHaveLength(1)
    canales[0].emitir({ eventType: 'INSERT', new: { id: 'r1' } })
    expect(a).toHaveBeenCalledTimes(1)
    expect(b).toHaveBeenCalledTimes(1)
    cancelarA()
    cancelarB()
  })

  it('cerrar un oyente no corta a los demás; el canal se cierra con el último', () => {
    const a = vi.fn()
    const b = vi.fn()
    const cancelarA = escucharTablas(['registros'], 'pq2', a)
    const cancelarB = escucharTablas(['registros'], 'pq2', b)
    cancelarA()
    expect(supabase.removeChannel).not.toHaveBeenCalled()
    canales[0].emitir({ eventType: 'UPDATE', new: { id: 'r1' } })
    expect(b).toHaveBeenCalledTimes(1)
    expect(a).not.toHaveBeenCalled()
    cancelarB()
    expect(supabase.removeChannel).toHaveBeenCalledTimes(1)
  })

  it('avisa { reconectado: true } solo cuando vuelve a suscribirse', () => {
    const a = vi.fn()
    const cancelar = escucharTablas(['turnos_caja'], 'pq3', a)
    expect(a).not.toHaveBeenCalled()
    canales[0].alEstado('CHANNEL_ERROR')
    canales[0].alEstado('SUBSCRIBED')
    expect(a).toHaveBeenCalledWith({ reconectado: true })
    cancelar()
  })

  it('usa un nombre de canal único y filtra por parqueadero', () => {
    const cancelar = escucharTablas(['mensualidades', 'avisos_mensualidad'], 'pq4', () => {})
    expect(canales[0].nombre).toMatch(/^mensualidades\+avisos_mensualidad-pq4-/)
    expect(canales[0].bindings.map(b => b.filtro.table)).toEqual(['mensualidades', 'avisos_mensualidad'])
    expect(canales[0].bindings.every(b => b.filtro.filter === 'parqueadero_id=eq.pq4')).toBe(true)
    cancelar()
  })
})
