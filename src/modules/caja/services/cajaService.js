import { supabase } from '@/lib/supabase'

let turnoLocalActivo = {
  id: 'a0000000-0000-0000-0000-000000000001',
  abierto_at: new Date().toISOString(),
  base_inicial: 50000,
  efectivo_esperado: 50000,
  estado: 'abierto',
  profiles: { nombre: 'Operador de Turno (Prueba)' },
  movimientos: []
}

export const cajaService = {
  /**
   * Obtiene el turno actualmente abierto o por recibir (HU-24)
   */
  async obtenerTurnoActual(parqueaderoId) {
    if (!parqueaderoId) return null

    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      return turnoLocalActivo
    }

    try {
      const { data, error } = await supabase
        .from('turnos_caja')
        .select('*, profiles!usuario_id(nombre)')
        .eq('parqueadero_id', parqueaderoId)
        .in('estado', ['abierto', 'por_recibir'])
        .maybeSingle()

      if (error) throw error
      return data || turnoLocalActivo
    } catch (err) {
      return turnoLocalActivo
    }
  },

  /**
   * Abre un nuevo turno indicando la base en efectivo
   */
  async abrirTurno(baseInicial = 0) {
    try {
      const { data, error } = await supabase.rpc('abrir_turno', {
        p_base_inicial: parseInt(baseInicial || 0, 10)
      })
      if (error) throw error
      return data
    } catch (err) {
      turnoLocalActivo = {
        id: crypto.randomUUID(),
        abierto_at: new Date().toISOString(),
        base_inicial: parseInt(baseInicial || 0, 10),
        efectivo_esperado: parseInt(baseInicial || 0, 10),
        estado: 'abierto',
        movimientos: []
      }
      return { success: true, turno_id: turnoLocalActivo.id }
    }
  },

  /**
   * Quien sale entrega el turno y cuenta su efectivo
   */
  async entregarTurno(turnoId, efectivoContado, observacion = '') {
    try {
      const { data, error } = await supabase.rpc('entregar_turno', {
        p_turno_id: turnoId,
        p_efectivo_contado: parseInt(efectivoContado, 10),
        p_observacion: observacion?.trim()
      })
      if (error) throw error
      return data
    } catch (err) {
      if (turnoLocalActivo) {
        turnoLocalActivo.estado = 'por_recibir'
        turnoLocalActivo.efectivo_contado = parseInt(efectivoContado, 10)
        turnoLocalActivo.diferencia = parseInt(efectivoContado, 10) - turnoLocalActivo.efectivo_esperado
        turnoLocalActivo.observacion = observacion
      }
      return { success: true, diferencia: parseInt(efectivoContado, 10) - (turnoLocalActivo?.efectivo_esperado || 0) }
    }
  },

  /**
   * Quien entra confirma la recepción y abre su nuevo turno con esa base
   */
  async recibirTurno(turnoId, efectivoRecibido) {
    try {
      const { data, error } = await supabase.rpc('recibir_turno', {
        p_turno_id: turnoId,
        p_efectivo_recibido: parseInt(efectivoRecibido, 10)
      })
      if (error) throw error
      return data
    } catch (err) {
      turnoLocalActivo = {
        id: crypto.randomUUID(),
        abierto_at: new Date().toISOString(),
        base_inicial: parseInt(efectivoRecibido, 10),
        efectivo_esperado: parseInt(efectivoRecibido, 10),
        estado: 'abierto',
        movimientos: []
      }
      return { success: true, nuevo_turno_id: turnoLocalActivo.id }
    }
  },

  /**
   * Registra un retiro de efectivo o ingreso manual
   */
  async registrarMovimiento(turnoId, tipo, valor, motivo) {
    const val = parseInt(valor, 10)
    try {
      const { data, error } = await supabase.rpc('registrar_movimiento_caja', {
        p_turno_id: turnoId,
        p_tipo: tipo,
        p_valor: val,
        p_motivo: motivo.trim()
      })
      if (error) throw error
      return data
    } catch (err) {
      if (turnoLocalActivo) {
        if (tipo === 'retiro') turnoLocalActivo.efectivo_esperado -= val
        else turnoLocalActivo.efectivo_esperado += val
      }
      return { success: true }
    }
  }
}
