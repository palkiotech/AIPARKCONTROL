import { supabase } from '@/lib/supabase'
import { normalizarPlaca } from '@/utils/placa'
import { getAdjustedNowISO } from '@/offline/clockDrift'
import { encolarOperacion } from '@/offline/cola'

// Caché reactivo en memoria local para renderizado inmediato
const patioLocal = []
let cacheVehiculos = null

export const ocupacionService = {
  /**
   * Retorna los vehículos actualmente en caché de memoria para renderizado instantáneo (0ms)
   */
  obtenerVehiculosDentroCache() {
    return cacheVehiculos
  },

  /**
   * Registra la entrada de un vehículo en patio (HU-11)
   * Si no hay conexión, se encola en IndexedDB (HU-26)
   */
  async registrarEntrada({ placa, tipoVehiculoId, tarifaId = null }) {
    const placaLimpia = normalizarPlaca(placa)
    const timestampAjustado = getAdjustedNowISO()

    // Operación sin conexión (HU-26)
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      const op = await encolarOperacion('entrada', {
        placa: placaLimpia,
        tipoVehiculoId,
        tarifaId
      })

      const entradaOffline = {
        id: op.id,
        placa: placaLimpia,
        tipo_vehiculo_id: tipoVehiculoId,
        tarifa_id: tarifaId,
        entrada_at: timestampAjustado,
        hora_origen: 'dispositivo',
        estado: 'abierto'
      }
      patioLocal.unshift(entradaOffline)
      if (cacheVehiculos) cacheVehiculos.unshift(entradaOffline)
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
      // Si el error es de base de datos o validación, propagarlo
      const esErrorRed = !navigator.onLine || err.message?.includes('fetch') || err.name === 'TypeError'
      if (!esErrorRed && err.message) {
        throw err
      }

      // Respaldo de contingencia offline: encolar en Dexie e IndexedDB
      const op = await encolarOperacion('entrada', {
        placa: placaLimpia,
        tipoVehiculoId,
        tarifaId
      })
      const entradaRespaldo = {
        id: op.id,
        placa: placaLimpia,
        tipo_vehiculo_id: tipoVehiculoId,
        tarifa_id: tarifaId,
        entrada_at: timestampAjustado,
        hora_origen: 'dispositivo',
        estado: 'abierto'
      }
      patioLocal.unshift(entradaRespaldo)
      if (cacheVehiculos) cacheVehiculos.unshift(entradaRespaldo)
      return { success: true, ...entradaRespaldo }
    }
  },

  /**
   * Obtiene los vehículos presentes en patio (HU-12)
   */
  async obtenerVehiculosDentro(parqueaderoId) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      const resOffline = patioLocal.filter(v => v.estado === 'abierto')
      cacheVehiculos = resOffline
      return resOffline
    }

    try {
      const { data, error } = await supabase
        .from('registros')
        .select('*, tipos_vehiculo(nombre, icono), tarifas(nombre, valor, modalidad, minutos_gracia)')
        .eq('parqueadero_id', parqueaderoId)
        .eq('estado', 'abierto')
        .order('entrada_at', { ascending: false })

      if (error) throw error
      const resultado = data || []
      cacheVehiculos = resultado
      return resultado
    } catch (err) {
      const fallback = patioLocal.filter(v => v.estado === 'abierto')
      cacheVehiculos = fallback
      return fallback
    }
  },

  /**
   * Registra la salida y cobro de un vehículo (HU-13)
   * Si no hay conexión, se encola en IndexedDB (HU-26)
   */
  async registrarSalida({ registroId, metodoPagoId, tarifaId, valorCobrado }) {
    if (cacheVehiculos) {
      cacheVehiculos = cacheVehiculos.filter(v => v.id !== registroId)
    }

    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      await encolarOperacion('salida', {
        registroId,
        metodoPagoId,
        tarifaId,
        valorCobrado
      })

      const item = patioLocal.find(v => v.id === registroId)
      if (item) {
        item.estado = 'cerrado'
        item.salida_at = getAdjustedNowISO()
        item.valor = valorCobrado
      }
      return { success: true, valor: valorCobrado }
    }

    try {
      const { data, error } = await supabase.rpc('registrar_salida', {
        p_registro_id: registroId,
        p_metodo_pago_id: metodoPagoId,
        p_tarifa_id: tarifaId,
        p_valor_cobrado: valorCobrado
      })
      if (error) throw error
      return data
    } catch (err) {
      await encolarOperacion('salida', {
        registroId,
        metodoPagoId,
        tarifaId,
        valorCobrado
      })
      const item = patioLocal.find(v => v.id === registroId)
      if (item) {
        item.estado = 'cerrado'
        item.salida_at = getAdjustedNowISO()
        item.valor = valorCobrado
      }
      return { success: true, valor: valorCobrado }
    }
  },

  /**
   * Anula un registro con motivo justificado (HU-15)
   */
  async anularRegistro(registroId, motivo) {
    if (cacheVehiculos) {
      cacheVehiculos = cacheVehiculos.filter(v => v.id !== registroId)
    }
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
