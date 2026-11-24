import { supabase } from '@/lib/supabase'
import { escucharTablas } from '@/lib/realtime'
import { guardarReferencia, leerReferencia } from '@/offline/referencia'
import { registrarLimpieza, esErrorDeRed, estaEnLinea } from '@/lib/sesionCaches'

/**
 * Caja y turnos (HU-24).
 * - No hay turnos de prueba ni apertura automática: si no hay turno, la vista
 *   pide abrirlo con la base que indique el operador.
 * - Los errores del servidor se propagan (antes se tragaban y se mostraba éxito).
 * - Abrir, entregar y recibir requieren conexión en esta versión (ver CAMBIOS).
 */

let cacheTurno // undefined = no consultado; null = no hay turno
registrarLimpieza(() => { cacheTurno = undefined })

export const cajaService = {
  obtenerTurnoCache() {
    return cacheTurno
  },

  /**
   * Turno abierto o por recibir del parqueadero, o null si no hay.
   * Sin conexión devuelve la última copia local (solo lectura).
   */
  async obtenerTurnoActual(parqueaderoId) {
    if (!parqueaderoId) return null

    if (estaEnLinea()) {
      try {
        const { data, error } = await supabase
          .from('turnos_caja')
          .select('*, profiles!turnos_caja_usuario_id_fkey(nombre)')
          .eq('parqueadero_id', parqueaderoId)
          .in('estado', ['abierto', 'por_recibir'])
          .maybeSingle()
        if (error) throw error
        cacheTurno = data || null
        await guardarReferencia(parqueaderoId, 'turno', cacheTurno)
        return cacheTurno
      } catch (err) {
        if (!esErrorDeRed(err)) throw err
      }
    }

    if (cacheTurno === undefined) cacheTurno = await leerReferencia(parqueaderoId, 'turno')
    return cacheTurno || null
  },

  /**
   * Resumen del turno: base, entradas/salidas, cobros y pagos por método,
   * movimientos y vehículos que quedan dentro.
   */
  async obtenerResumen(turnoId = null) {
    const { data, error } = await supabase.rpc('obtener_resumen_turno', { p_turno_id: turnoId })
    if (error) throw error
    return data
  },

  async abrirTurno(baseInicial = 0) {
    const { data, error } = await supabase.rpc('abrir_turno', {
      p_base_inicial: parseInt(baseInicial || 0, 10)
    })
    if (error) throw error
    cacheTurno = undefined
    return data
  },

  async entregarTurno(turnoId, efectivoContado, observacion = '') {
    const { data, error } = await supabase.rpc('entregar_turno', {
      p_turno_id: turnoId,
      p_efectivo_contado: parseInt(efectivoContado, 10),
      p_observacion: observacion?.trim() || null
    })
    if (error) throw error
    cacheTurno = undefined
    return data
  },

  async recibirTurno(turnoId, efectivoRecibido) {
    const { data, error } = await supabase.rpc('recibir_turno', {
      p_turno_id: turnoId,
      p_efectivo_recibido: parseInt(efectivoRecibido, 10)
    })
    if (error) throw error
    cacheTurno = undefined
    return data
  },

  /**
   * Cierre sin relevo (el parqueadero cierra o nadie recibe la caja).
   */
  async cerrarSinRelevo(turnoId, efectivoContado = null, observacion = '') {
    const { data, error } = await supabase.rpc('cerrar_turno_sin_relevo', {
      p_turno_id: turnoId,
      p_efectivo_contado: efectivoContado === null || efectivoContado === '' ? null : parseInt(efectivoContado, 10),
      p_observacion: observacion?.trim() || null
    })
    if (error) throw error
    cacheTurno = undefined
    return data
  },

  async registrarMovimiento(turnoId, tipo, valor, motivo) {
    const { data, error } = await supabase.rpc('registrar_movimiento_caja', {
      p_turno_id: turnoId,
      p_tipo: tipo,
      p_valor: parseInt(valor, 10),
      p_motivo: (motivo || '').trim()
    })
    if (error) throw error
    return data
  },

  /**
   * Historial de turnos cerrados (admin, /caja/turnos).
   * desde/hasta: instantes ISO UTC calculados en la zona del parqueadero.
   */
  async listarTurnos({ parqueaderoId, desde = null, hasta = null, limite = 100 }) {
    let consulta = supabase
      .from('turnos_caja')
      .select('*, entrego:profiles!turnos_caja_usuario_id_fkey(nombre), recibio:profiles!turnos_caja_recibido_por_fkey(nombre)')
      .eq('parqueadero_id', parqueaderoId)
      .order('abierto_at', { ascending: false })
      .limit(limite)
    if (desde) consulta = consulta.gte('abierto_at', desde)
    if (hasta) consulta = consulta.lt('abierto_at', hasta)
    const { data, error } = await consulta
    if (error) throw error
    return data || []
  },

  async agregarNota(turnoId, nota) {
    const { data, error } = await supabase.rpc('agregar_nota_turno', { p_turno_id: turnoId, p_nota: nota })
    if (error) throw error
    return data
  },

  /** Cambios de turno (canal compartido entre el encabezado, Caja y el patio). */
  suscribirCambios(parqueaderoId, onCambio) {
    return escucharTablas(['turnos_caja'], parqueaderoId, onCambio)
  }
}
