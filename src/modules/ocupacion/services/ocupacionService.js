import { supabase } from '@/lib/supabase'
import { normalizarPlaca } from '@/utils/placa'
import { getAdjustedNowISO } from '@/offline/clockDrift'
import { calcularCobroBase } from '@/domain/cobro'

// Mock en memoria local cuando se ejecuta sin conexión remota
const patioLocal = []

export const ocupacionService = {
  /**
   * Registra la entrada de un vehículo en patio (HU-11)
   */
  async registrarEntrada({ placa, tipoVehiculoId, tarifaId = null, horaDispositivo = null }) {
    const placaLimpia = normalizarPlaca(placa)
    const timestampAjustado = horaDispositivo || getAdjustedNowISO()

    // Si no hay conexión o estamos en modo local sin Supabase activo
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      const entradaOffline = {
        id: crypto.randomUUID(),
        placa: placaLimpia,
        tipo_vehiculo_id: tipoVehiculoId,
        tarifa_id: tarifaId,
        entrada_at: timestampAjustado,
        hora_origen: 'dispositivo',
        estado: 'abierto'
      }
      patioLocal.unshift(entradaOffline)
      return { success: true, ...entradaOffline }
    }

    try {
      const { data, error } = await supabase.rpc('registrar_entrada', {
        p_id: crypto.randomUUID(),
        p_placa: placaLimpia,
        p_tipo_vehiculo_id: tipoVehiculoId,
        p_tarifa_id: tarifaId,
        p_hora_dispositivo: timestampAjustado
      })
      if (error) throw error
      return data
    } catch (err) {
      // Si falla la red, guardar en patio local
      const entradaRespaldo = {
        id: crypto.randomUUID(),
        placa: placaLimpia,
        tipo_vehiculo_id: tipoVehiculoId,
        tarifa_id: tarifaId,
        entrada_at: timestampAjustado,
        hora_origen: 'dispositivo',
        estado: 'abierto'
      }
      patioLocal.unshift(entradaRespaldo)
      return { success: true, ...entradaRespaldo }
    }
  },

  /**
   * Obtiene los vehículos presentes en patio y calcula minutos transcurridos (HU-12)
   */
  async obtenerVehiculosDentro(parqueaderoId) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      return patioLocal.filter(v => v.estado === 'abierto')
    }

    try {
      const { data, error } = await supabase
        .from('registros')
        .select('*, tipos_vehiculo(nombre, icono), tarifas(nombre, valor, modalidad, minutos_gracia)')
        .eq('parqueadero_id', parqueaderoId)
        .eq('estado', 'abierto')
        .order('entrada_at', { ascending: false })

      if (error) throw error
      return data || []
    } catch (err) {
      return patioLocal.filter(v => v.estado === 'abierto')
    }
  },

  /**
   * Registra la salida y cobro de un vehículo (HU-13)
   */
  async registrarSalida({ registroId, metodoPagoId, tarifaId, valorCobrado }) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      const item = patioLocal.find(v => v.id === registroId)
      if (item) {
        item.estado = 'cerrado'
        item.salida_at = getAdjustedNowISO()
        item.valor = valorCobrado
      }
      return { success: true, valor: valorCobrado }
    }

    const { data, error } = await supabase.rpc('registrar_salida', {
      p_registro_id: registroId,
      p_metodo_pago_id: metodoPagoId,
      p_tarifa_id: tarifaId,
      p_valor_cobrado: valorCobrado
    })
    if (error) throw error
    return data
  },

  /**
   * Anula un registro con motivo justificado (HU-15)
   */
  async anularRegistro(registroId, motivo) {
    const { data, error } = await supabase.rpc('anular_registro', {
      p_registro_id: registroId,
      p_motivo: motivo.trim()
    })
    if (error) throw error
    return data
  },

  /**
   * Consulta el historial por placa (HU-14)
   */
  async buscarHistorialPlaca(parqueaderoId, placa) {
    const placaNorm = normalizarPlaca(placa)
    const { data, error } = await supabase
      .from('registros')
      .select('*, tipos_vehiculo(nombre), metodos_pago(nombre)')
      .eq('parqueadero_id', parqueaderoId)
      .eq('placa', placaNorm)
      .order('entrada_at', { ascending: false })
      .limit(20)

    if (error) throw error
    return data || []
  }
}
