import { supabase } from '@/lib/supabase'
import { normalizarPlaca } from '@/utils/placa'
import { getAdjustedNowISO } from '@/offline/clockDrift'
import { encolarOperacion } from '@/offline/cola'
import { guardarReferencia, leerReferencia } from '@/offline/referencia'
import { registrarLimpieza, esErrorDeRed, estaEnLinea } from '@/lib/sesionCaches'
import { calcularCobroConFranja, resolverTarifas } from '@/domain/cobro'

// Caché en memoria para pintar al instante (SWR); la copia durable está en IndexedDB
let cacheVehiculos = null
registrarLimpieza(() => { cacheVehiculos = null })

const SELECT_REGISTRO = '*, tipos_vehiculo(nombre, icono), tarifas(id, nombre, valor, modalidad, minutos_gracia, minutos_fraccion, tope_por_24h, franja_inicio, franja_fin)'

async function persistirPatio(parqueaderoId) {
  if (cacheVehiculos) await guardarReferencia(parqueaderoId, 'vehiculos_dentro', cacheVehiculos)
}

export const ocupacionService = {
  obtenerVehiculosDentroCache() {
    return cacheVehiculos
  },

  /**
   * Registra la entrada de un vehículo (HU-11).
   * En línea la hora la pone el servidor. Sin conexión (o con error de red) se
   * encola con la hora del dispositivo corregida por el desfase (HU-26).
   * Los errores de validación del servidor se propagan a la vista.
   */
  async registrarEntrada({ parqueaderoId, placa, tipoVehiculoId, tarifaId = null, tipoNombre = '' }) {
    const placaLimpia = normalizarPlaca(placa)

    if (estaEnLinea()) {
      try {
        const { data, error } = await supabase.rpc('registrar_entrada', {
          p_id: crypto.randomUUID(),
          p_placa: placaLimpia,
          p_tipo_vehiculo_id: tipoVehiculoId,
          p_tarifa_id: tarifaId,
          p_hora_dispositivo: null
        })
        if (error) throw error
        return { ...data, offline: false }
      } catch (err) {
        if (!esErrorDeRed(err)) throw err
      }
    }

    // Sin conexión: validar contra la copia local que la placa no esté dentro
    const dentro = cacheVehiculos || (await leerReferencia(parqueaderoId, 'vehiculos_dentro')) || []
    const yaDentro = dentro.find(v => v.placa === placaLimpia && v.estado === 'abierto')
    if (yaDentro) {
      throw new Error(`Este vehículo ya está dentro (registrado ${new Date(yaDentro.entrada_at).toLocaleTimeString('es-CO', { hour: '2-digit', minute: '2-digit' })})`)
    }

    const op = await encolarOperacion('entrada', { placa: placaLimpia, tipoVehiculoId, tarifaId })
    const tarifas = (await leerReferencia(parqueaderoId, 'tarifas')) || []
    const tarifa = tarifas.find(t => t.id === tarifaId) ||
      resolverTarifas(tarifas.filter(t => t.tipo_vehiculo_id === tipoVehiculoId)).general
    const entrada = {
      id: op.id,
      placa: placaLimpia,
      tipo_vehiculo_id: tipoVehiculoId,
      tipos_vehiculo: { nombre: tipoNombre },
      tarifa_id: tarifa?.id || tarifaId,
      tarifas: tarifa || null,
      entrada_at: op.creada_en_dispositivo_at,
      hora_origen: 'dispositivo',
      estado: 'abierto',
      es_mensual: false,
      pendiente_sync: true
    }
    cacheVehiculos = [entrada, ...dentro]
    await persistirPatio(parqueaderoId)
    return { success: true, registro_id: op.id, placa: placaLimpia, entrada_at: entrada.entrada_at, offline: true }
  },

  /**
   * Vehículos dentro (HU-12). Sin conexión devuelve la copia local (IndexedDB).
   */
  async obtenerVehiculosDentro(parqueaderoId) {
    if (!parqueaderoId) return []

    if (estaEnLinea()) {
      try {
        const { data, error } = await supabase
          .from('registros')
          .select(SELECT_REGISTRO)
          .eq('parqueadero_id', parqueaderoId)
          .eq('estado', 'abierto')
          .order('entrada_at', { ascending: false })
        if (error) throw error

        // Conservar las entradas offline que aún no se han sincronizado
        const pendientes = (cacheVehiculos || []).filter(v => v.pendiente_sync && !data.some(d => d.id === v.id))
        cacheVehiculos = [...pendientes, ...(data || [])]
        await persistirPatio(parqueaderoId)
        return cacheVehiculos
      } catch (err) {
        if (!esErrorDeRed(err)) throw err
      }
    }

    cacheVehiculos = cacheVehiculos || (await leerReferencia(parqueaderoId, 'vehiculos_dentro')) || []
    return cacheVehiculos
  },

  /**
   * Cotiza el cobro de salida (HU-13). En línea lo calcula el servidor
   * (calcular_cobro); sin conexión, el motor local con la misma regla.
   */
  async cotizarSalida({ parqueaderoId, registro, tarifaId = null, zonaHoraria = 'America/Bogota' }) {
    if (estaEnLinea() && !registro.pendiente_sync) {
      try {
        const { data, error } = await supabase.rpc('calcular_cobro', {
          p_registro_id: registro.id,
          p_tarifa_id: tarifaId
        })
        if (error) throw error
        return { ...data, offline: false }
      } catch (err) {
        if (!esErrorDeRed(err)) throw err
      }
    }
    return this.cotizarSalidaLocal({ parqueaderoId, registro, tarifaId, zonaHoraria })
  },

  async cotizarSalidaLocal({ parqueaderoId, registro, tarifaId = null, zonaHoraria = 'America/Bogota' }) {
    const tarifas = (await leerReferencia(parqueaderoId, 'tarifas')) || []
    const delTipo = tarifas.filter(t => t.tipo_vehiculo_id === registro.tipo_vehiculo_id)
    const { general, nocturna } = resolverTarifas(delTipo.length ? delTipo : [registro.tarifas].filter(Boolean), tarifaId || registro.tarifa_id)
    const salidaAt = getAdjustedNowISO()

    if (registro.es_mensual) {
      return { valor: 0, minutos: 0, es_mensual: true, desglose: [], salida_at: salidaAt, offline: true }
    }
    if (!general) {
      throw new Error('No hay una tarifa disponible sin conexión para este tipo de vehículo')
    }
    const r = calcularCobroConFranja({
      entradaAt: registro.entrada_at,
      salidaAt: new Date(Math.max(new Date(salidaAt).getTime(), new Date(registro.entrada_at).getTime())),
      tarifaGeneral: general,
      tarifaNocturna: nocturna,
      zonaHoraria
    })
    return {
      valor: r.valorTotal,
      minutos: r.minutosTotal,
      desglose: r.desglose,
      es_mensual: false,
      tarifa_id: general.id,
      tarifa_nombre: general.nombre,
      salida_at: salidaAt,
      offline: true
    }
  },

  /**
   * Registra la salida y cobro (HU-13). El valor lo decide el servidor; el
   * valor local solo viaja cuando el cobro se hizo sin conexión.
   */
  async registrarSalida({ parqueaderoId, registroId, metodoPagoId, tarifaId = null, valorCobradoOffline = null, salidaAtOffline = null }) {
    const quitarDelPatio = async () => {
      if (cacheVehiculos) cacheVehiculos = cacheVehiculos.filter(v => v.id !== registroId)
      await persistirPatio(parqueaderoId)
    }

    if (estaEnLinea()) {
      try {
        const { data, error } = await supabase.rpc('registrar_salida', {
          p_registro_id: registroId,
          p_metodo_pago_id: metodoPagoId || null,
          p_tarifa_id: tarifaId,
          p_valor_cobrado: null,
          p_salida_dispositivo: null
        })
        if (error) throw error
        await quitarDelPatio()
        return { ...data, offline: false }
      } catch (err) {
        if (!esErrorDeRed(err)) throw err
      }
    }

    await encolarOperacion('salida', {
      registroId,
      metodoPagoId,
      tarifaId,
      valorCobrado: valorCobradoOffline,
      salidaAt: salidaAtOffline || getAdjustedNowISO()
    })
    await quitarDelPatio()
    return { success: true, registro_id: registroId, valor: valorCobradoOffline, offline: true }
  },

  /**
   * Anula un registro con motivo (HU-15). Solo admin; requiere conexión.
   */
  async anularRegistro(registroId, motivo) {
    const { data, error } = await supabase.rpc('anular_registro', {
      p_registro_id: registroId,
      p_motivo: (motivo || '').trim()
    })
    if (error) throw error
    if (cacheVehiculos) cacheVehiculos = cacheVehiculos.filter(v => v.id !== registroId)
    return data
  },

  /**
   * Historial por placa y rango de fechas (HU-14), paginado de 20 en 20.
   * desde/hasta son instantes ISO (UTC) ya calculados en la zona del parqueadero.
   */
  async buscarHistorial({ parqueaderoId, placa = '', desde = null, hasta = null, pagina = 0, tamano = 20 }) {
    let consulta = supabase
      .from('registros')
      .select('*, tipos_vehiculo(nombre), metodos_pago(nombre), tarifas(nombre), entrada:profiles!registros_usuario_entrada_fkey(nombre), salida:profiles!registros_usuario_salida_fkey(nombre)', { count: 'exact' })
      .eq('parqueadero_id', parqueaderoId)
      .order('entrada_at', { ascending: false })
      .range(pagina * tamano, pagina * tamano + tamano - 1)

    const placaNorm = normalizarPlaca(placa || '')
    if (placaNorm) consulta = consulta.ilike('placa', `%${placaNorm}%`)
    if (desde) consulta = consulta.gte('entrada_at', desde)
    if (hasta) consulta = consulta.lt('entrada_at', hasta)

    const { data, error, count } = await consulta
    if (error) throw error
    return { filas: data || [], total: count || 0 }
  },

  /**
   * Suscripción Realtime a cambios del patio (entradas/salidas en otros dispositivos).
   * Devuelve una función para cancelar la suscripción.
   */
  suscribirCambios(parqueaderoId, onCambio) {
    if (!parqueaderoId) return () => {}
    const canal = supabase
      .channel(`patio-${parqueaderoId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'registros', filter: `parqueadero_id=eq.${parqueaderoId}` }, () => onCambio())
      .subscribe()
    return () => { supabase.removeChannel(canal) }
  }
}
