import { supabase } from '@/lib/supabase'
import { clasificarEstadoMensualidad } from '@/domain/estadoMensualidad'
import { encolarOperacion } from '@/offline/cola'
import { guardarReferencia, leerReferencia } from '@/offline/referencia'
import { registrarLimpieza, esErrorDeRed, estaEnLinea } from '@/lib/sesionCaches'
import { hoyEnZona } from '@/utils/fecha'

/**
 * Mensualidades (HU-16 a HU-19). Sin datos de demostración: si no hay
 * mensualidades, la lista queda vacía; si hay un error, se propaga.
 */

let cacheMensualidades = null
registrarLimpieza(() => { cacheMensualidades = null })

const SELECT_MENSUALIDAD = `*,
  clientes(id, nombre, documento, telefono, email),
  vehiculos(id, placa, marca, color, tipo_vehiculo_id, tipos_vehiculo(nombre)),
  planes_mensuales(id, nombre, valor, tipo_periodo, duracion_dias, dias_gracia_pago),
  avisos_mensualidad(id, medio, nota, periodo_hasta, created_at, profiles(nombre))`

/**
 * Agrega la clasificación del semáforo y el último aviso del periodo actual.
 * Los avisos cuentan por periodo (HU-19): al pagar, fecha_fin cambia y la
 * mensualidad vuelve a aparecer "Sin avisar".
 */
export function clasificar(mensualidades, { diasAviso = 5, zonaHoraria = 'America/Bogota' } = {}) {
  const hoy = hoyEnZona(zonaHoraria)
  return mensualidades.map(m => {
    const clasificacion = clasificarEstadoMensualidad({
      fechaFin: m.fecha_fin,
      fechaReferencia: hoy,
      diasAviso,
      diasGracia: m.planes_mensuales?.dias_gracia_pago || 0
    })
    const avisosPeriodo = (m.avisos_mensualidad || [])
      .filter(a => a.periodo_hasta === m.fecha_fin)
      .sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
    return { ...m, clasificacion, ultimoAviso: avisosPeriodo[0] || null }
  })
}

export const mensualidadesService = {
  obtenerMensualidadesCache() {
    return cacheMensualidades
  },

  /**
   * Lista las mensualidades activas clasificadas (HU-17).
   * @param {string} parqueaderoId
   * @param {{diasAviso:number, zonaHoraria:string, incluirInactivas:boolean}} opciones
   */
  async listarMensualidades(parqueaderoId, { diasAviso = 5, zonaHoraria = 'America/Bogota', incluirInactivas = false } = {}) {
    if (!parqueaderoId) return []

    let filas = null
    if (estaEnLinea()) {
      try {
        let consulta = supabase
          .from('mensualidades')
          .select(SELECT_MENSUALIDAD)
          .eq('parqueadero_id', parqueaderoId)
          .order('fecha_fin', { ascending: true })
        if (!incluirInactivas) consulta = consulta.eq('activa', true)
        const { data, error } = await consulta
        if (error) throw error
        filas = data || []
        if (!incluirInactivas) await guardarReferencia(parqueaderoId, 'mensualidades', filas)
      } catch (err) {
        if (!esErrorDeRed(err)) throw err
      }
    }

    if (filas === null) {
      // Sin conexión: copia local (lectura, HU-26)
      filas = (await leerReferencia(parqueaderoId, 'mensualidades')) || []
    }

    const resultado = clasificar(filas, { diasAviso, zonaHoraria })
    if (!incluirInactivas) cacheMensualidades = resultado
    return resultado
  },

  async listarPagos(mensualidadId) {
    const { data, error } = await supabase
      .from('pagos_mensualidad')
      .select('*, metodos_pago(nombre), profiles!pagos_mensualidad_usuario_id_fkey(nombre)')
      .eq('mensualidad_id', mensualidadId)
      .order('periodo_desde', { ascending: false })
    if (error) throw error
    return data || []
  },

  /**
   * Crea la mensualidad con cliente, vehículo y primer pago (HU-16). Requiere conexión.
   * Devuelve { mensualidad_id, pago_id, fecha_inicio, fecha_fin, valor }.
   */
  async crearMensualidad(datos) {
    const { data, error } = await supabase.rpc('crear_mensualidad', {
      p_cliente_nombre: datos.nombre.trim(),
      p_cliente_documento: datos.documento.trim(),
      p_cliente_telefono: datos.telefono?.trim() || '',
      p_cliente_email: datos.email?.trim() || '',
      p_placa: datos.placa.trim(),
      p_tipo_vehiculo_id: datos.tipoVehiculoId,
      p_plan_id: datos.planId,
      p_fecha_inicio: datos.fechaInicio,
      p_metodo_pago_id: datos.metodoPagoId || null,
      p_registrar_primer_pago: datos.registrarPrimerPago !== false
    })
    if (error) throw error
    cacheMensualidades = null
    return data
  },

  /**
   * Registra un pago y renueva (HU-18). El valor lo pone el plan en el servidor
   * (solo un admin puede enviar un valor distinto). reiniciar=true cambia el día
   * de cobro a hoy. Sin conexión se encola y se sincroniza después.
   * Devuelve { pago_id, periodo_desde, periodo_hasta, valor, offline }.
   */
  async registrarPago({ mensualidadId, metodoPagoId, valor = null, reiniciar = false, desdeFecha = null }) {
    const pagoId = crypto.randomUUID()
    if (estaEnLinea()) {
      try {
        const { data, error } = await supabase.rpc('registrar_pago_mensualidad', {
          p_mensualidad_id: mensualidadId,
          p_metodo_pago_id: metodoPagoId,
          p_valor: valor,
          p_desde_fecha: desdeFecha,
          p_reiniciar: !!reiniciar,
          p_id: pagoId
        })
        if (error) throw error
        cacheMensualidades = null
        return { ...data, offline: false }
      } catch (err) {
        if (!esErrorDeRed(err)) throw err
      }
    }

    const op = await encolarOperacion('pago_mensualidad', { mensualidadId, metodoPagoId, valor, reiniciar: !!reiniciar, desdeFecha })
    return { success: true, pago_id: op.id, offline: true }
  },

  async anularPago(pagoId, motivo) {
    const { data, error } = await supabase.rpc('anular_pago_mensualidad', { p_pago_id: pagoId, p_motivo: (motivo || '').trim() })
    if (error) throw error
    cacheMensualidades = null
    return data
  },

  async desactivarMensualidad(mensualidadId) {
    const { data, error } = await supabase.rpc('desactivar_mensualidad', { p_mensualidad_id: mensualidadId })
    if (error) throw error
    cacheMensualidades = null
    return data
  },

  /**
   * Registra un aviso de vencimiento (HU-19). Funciona sin conexión.
   */
  async registrarAviso({ mensualidadId, medio, nota = '', periodoHasta = null }) {
    if (estaEnLinea()) {
      try {
        const { data, error } = await supabase.rpc('registrar_aviso_mensualidad', {
          p_mensualidad_id: mensualidadId,
          p_medio: medio,
          p_nota: nota,
          p_periodo_hasta: periodoHasta
        })
        if (error) throw error
        cacheMensualidades = null
        return { ...data, offline: false }
      } catch (err) {
        if (!esErrorDeRed(err)) throw err
      }
    }
    await encolarOperacion('aviso', { mensualidadId, medio, nota, periodoHasta })
    return { success: true, offline: true }
  },

  suscribirCambios(parqueaderoId, onCambio) {
    if (!parqueaderoId) return () => {}
    const canal = supabase
      .channel(`mensualidades-${parqueaderoId}`)
      .on('postgres_changes', { event: '*', schema: 'public', table: 'mensualidades', filter: `parqueadero_id=eq.${parqueaderoId}` }, () => onCambio())
      .on('postgres_changes', { event: '*', schema: 'public', table: 'avisos_mensualidad', filter: `parqueadero_id=eq.${parqueaderoId}` }, () => onCambio())
      .subscribe()
    return () => { supabase.removeChannel(canal) }
  }
}
