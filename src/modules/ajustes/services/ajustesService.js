import { supabase } from '@/lib/supabase'
import { calcularCobroConFranja } from '@/domain/cobro'
import { generarProximosPeriodos } from '@/domain/periodo'
import { guardarReferencia, leerReferencia } from '@/offline/referencia'
import { registrarLimpieza, esErrorDeRed, estaEnLinea } from '@/lib/sesionCaches'

// Caché en memoria para catálogos maestros con TTL de 60 segundos.
// La copia durable (IndexedDB) permite cobrar sin conexión.
const cacheCatalogo = {
  tipos: new Map(),
  metodos: new Map(),
  planes: new Map(),
  tarifas: new Map(),
  ttl: 60000
}

function getCache(map, key) {
  const item = map.get(key)
  if (item && Date.now() - item.time < cacheCatalogo.ttl) return item.data
  return null
}

function setCache(map, key, data) {
  map.set(key, { data, time: Date.now() })
}

export function invalidarCacheCatalogos(pqId) {
  for (const map of [cacheCatalogo.tipos, cacheCatalogo.metodos, cacheCatalogo.planes, cacheCatalogo.tarifas]) {
    if (pqId) map.delete(pqId)
    else map.clear()
  }
}
registrarLimpieza(() => invalidarCacheCatalogos())

/**
 * Lee un catálogo: memoria → servidor (y copia local) → copia local si no hay red.
 */
async function leerCatalogo({ map, nombre, parqueaderoId, consulta }) {
  const enCache = getCache(map, parqueaderoId)
  if (enCache) return enCache

  if (estaEnLinea()) {
    try {
      const { data, error } = await consulta()
      if (error) throw error
      const resultado = data || []
      setCache(map, parqueaderoId, resultado)
      await guardarReferencia(parqueaderoId, nombre, resultado)
      return resultado
    } catch (err) {
      if (!esErrorDeRed(err)) throw err
    }
  }
  return (await leerReferencia(parqueaderoId, nombre)) || []
}

function traducirError(error) {
  const msg = error?.message || ''
  if (msg.includes('tipos_vehiculo_nombre_unique')) return new Error('Ya existe un tipo de vehículo con ese nombre')
  if (msg.includes('tarifas_franja_activa_idx')) return new Error('Solo puede haber una tarifa con franja horaria activa por tipo de vehículo')
  if (msg.includes('tarifas_predeterminada_idx')) return new Error('Ya hay otra tarifa predeterminada para este tipo')
  return error
}

export const ajustesService = {
  // --- DATOS DEL NEGOCIO (HU-06) ---
  async obtenerDatosNegocio(parqueaderoId) {
    const { data, error } = await supabase.from('parqueaderos').select('*').eq('id', parqueaderoId).single()
    if (error) throw error
    return data
  },

  async guardarDatosNegocio(parqueaderoId, datos) {
    if (!datos.nombre?.trim()) throw new Error('El nombre es obligatorio')
    if (!datos.nit?.trim()) throw new Error('El NIT es obligatorio')
    const dias = parseInt(datos.dias_aviso_vencimiento, 10)
    if (Number.isNaN(dias) || dias < 0 || dias > 60) throw new Error('Los días de aviso deben estar entre 0 y 60')

    const { data, error } = await supabase
      .from('parqueaderos')
      .update({
        nombre: datos.nombre.trim(),
        nit: datos.nit.trim(),
        direccion: datos.direccion?.trim() || null,
        telefono: datos.telefono?.trim() || null,
        zona_horaria: datos.zona_horaria || 'America/Bogota',
        moneda: datos.moneda || 'COP',
        dias_aviso_vencimiento: dias,
        texto_pie_comprobante: datos.texto_pie_comprobante?.trim() || null,
        modo_ticket: datos.modo_ticket || 'qr',
        ancho_ticket_mm: parseInt(datos.ancho_ticket_mm, 10) === 58 ? 58 : 80
      })
      .eq('id', parqueaderoId)
      .select()
      .single()
    if (error) throw error
    return data
  },

  /**
   * Sube el logo (PNG/JPG, máx. 1 MB) al bucket "logos" y guarda su URL.
   */
  async subirLogo(parqueaderoId, archivo) {
    if (!archivo) throw new Error('Selecciona un archivo')
    if (!['image/png', 'image/jpeg'].includes(archivo.type)) throw new Error('El logo debe ser PNG o JPG')
    if (archivo.size > 1024 * 1024) throw new Error('El logo no puede superar 1 MB')
    const ext = archivo.type === 'image/png' ? 'png' : 'jpg'
    const ruta = `${parqueaderoId}/logo.${ext}`
    const { error } = await supabase.storage.from('logos').upload(ruta, archivo, { upsert: true, contentType: archivo.type })
    if (error) throw error
    const { data } = supabase.storage.from('logos').getPublicUrl(ruta)
    const url = `${data.publicUrl}?v=${Date.now()}`
    const { error: e2 } = await supabase.from('parqueaderos').update({ logo_url: url }).eq('id', parqueaderoId)
    if (e2) throw e2
    return url
  },

  // --- TIPOS DE VEHÍCULO (HU-07) ---
  async listarTiposVehiculo(parqueaderoId) {
    return leerCatalogo({
      map: cacheCatalogo.tipos,
      nombre: 'tipos',
      parqueaderoId,
      consulta: () => supabase.from('tipos_vehiculo').select('*').eq('parqueadero_id', parqueaderoId).order('orden', { ascending: true })
    })
  },

  /**
   * Cuántos vehículos dentro y mensualidades activas usan un tipo (HU-07:
   * no se puede desactivar un tipo en uso).
   */
  async contarUsoTipo(parqueaderoId, tipoId) {
    const [{ count: dentro, error: e1 }, { data: mens, error: e2 }] = await Promise.all([
      supabase.from('registros').select('id', { count: 'exact', head: true })
        .eq('parqueadero_id', parqueaderoId).eq('tipo_vehiculo_id', tipoId).eq('estado', 'abierto'),
      supabase.from('mensualidades').select('id, vehiculos!inner(tipo_vehiculo_id)')
        .eq('parqueadero_id', parqueaderoId).eq('activa', true).eq('vehiculos.tipo_vehiculo_id', tipoId)
    ])
    if (e1) throw e1
    if (e2) throw e2
    return { dentro: dentro || 0, mensualidades: (mens || []).length }
  },

  async guardarTipoVehiculo(parqueaderoId, tipo) {
    if (!tipo.nombre?.trim()) throw new Error('El nombre es obligatorio')
    const capacidad = parseInt(tipo.capacidad, 10)
    if (Number.isNaN(capacidad) || capacidad < 0) throw new Error('La capacidad debe ser 0 o mayor')

    if (tipo.id && tipo.activo === false) {
      const uso = await this.contarUsoTipo(parqueaderoId, tipo.id)
      if (uso.dentro || uso.mensualidades) {
        throw new Error(`No se puede desactivar: hay ${uso.dentro} vehículo(s) dentro y ${uso.mensualidades} mensualidad(es) activa(s) de este tipo`)
      }
    }

    invalidarCacheCatalogos(parqueaderoId)
    const payload = {
      nombre: tipo.nombre.trim(),
      icono: tipo.icono || 'car',
      capacidad,
      orden: parseInt(tipo.orden, 10) || 0,
      activo: tipo.activo !== false
    }
    const q = tipo.id
      ? supabase.from('tipos_vehiculo').update(payload).eq('id', tipo.id).eq('parqueadero_id', parqueaderoId)
      : supabase.from('tipos_vehiculo').insert({ ...payload, parqueadero_id: parqueaderoId })
    const { data, error } = await q.select().single()
    if (error) throw traducirError(error)
    return data
  },

  // --- TARIFAS (HU-08) ---
  async listarTarifas(parqueaderoId) {
    return leerCatalogo({
      map: cacheCatalogo.tarifas,
      nombre: 'tarifas',
      parqueaderoId,
      consulta: () => supabase.from('tarifas').select('*, tipos_vehiculo(nombre)').eq('parqueadero_id', parqueaderoId).order('created_at', { ascending: true })
    })
  },

  async contarVehiculosConTarifa(parqueaderoId, tarifaId) {
    const { count, error } = await supabase.from('registros').select('id', { count: 'exact', head: true })
      .eq('parqueadero_id', parqueaderoId).eq('tarifa_id', tarifaId).eq('estado', 'abierto')
    if (error) throw error
    return count || 0
  },

  async guardarTarifa(parqueaderoId, tarifa) {
    const valor = parseInt(tarifa.valor, 10)
    const fraccion = parseInt(tarifa.minutos_fraccion || 15, 10)
    const conFranja = !!(tarifa.franja_inicio && tarifa.franja_fin)
    if (!tarifa.tipo_vehiculo_id) throw new Error('Selecciona el tipo de vehículo')
    if (!tarifa.nombre?.trim()) throw new Error('El nombre es obligatorio')
    if (!['por_minuto', 'por_hora', 'por_fraccion', 'plena'].includes(tarifa.modalidad)) throw new Error('Modalidad inválida')
    if (!(valor > 0)) throw new Error('El valor debe ser un entero mayor que 0')
    if (tarifa.modalidad === 'por_fraccion' && !(fraccion >= 1 && fraccion <= 1440)) throw new Error('Los minutos por fracción deben estar entre 1 y 1440')
    if (tarifa.franja_inicio && tarifa.franja_fin && tarifa.franja_inicio === tarifa.franja_fin) throw new Error('La franja debe tener horas distintas')
    if (conFranja && tarifa.es_predeterminada) throw new Error('Una tarifa nocturna (con franja) no puede ser la predeterminada')

    const payload = {
      parqueadero_id: parqueaderoId,
      tipo_vehiculo_id: tarifa.tipo_vehiculo_id,
      nombre: tarifa.nombre.trim(),
      modalidad: tarifa.modalidad,
      valor,
      minutos_fraccion: fraccion,
      minutos_gracia: Math.max(0, parseInt(tarifa.minutos_gracia || 0, 10)),
      tope_por_24h: tarifa.tope_por_24h ? parseInt(tarifa.tope_por_24h, 10) : null,
      es_predeterminada: !!tarifa.es_predeterminada && !conFranja,
      franja_inicio: conFranja ? tarifa.franja_inicio : null,
      franja_fin: conFranja ? tarifa.franja_fin : null,
      activa: tarifa.activa !== false
    }

    invalidarCacheCatalogos(parqueaderoId)

    // Exactamente una predeterminada por tipo: al marcar una, la anterior deja de serlo
    if (payload.es_predeterminada) {
      let q = supabase.from('tarifas').update({ es_predeterminada: false })
        .eq('parqueadero_id', parqueaderoId).eq('tipo_vehiculo_id', payload.tipo_vehiculo_id).eq('es_predeterminada', true)
      if (tarifa.id) q = q.neq('id', tarifa.id)
      const { error } = await q
      if (error) throw traducirError(error)
    }

    const q = tarifa.id
      ? supabase.from('tarifas').update(payload).eq('id', tarifa.id).eq('parqueadero_id', parqueaderoId)
      : supabase.from('tarifas').insert(payload)
    const { data, error } = await q.select().single()
    if (error) throw traducirError(error)
    return data
  },

  // --- PLANES MENSUALES (HU-09) ---
  async listarPlanesMensuales(parqueaderoId) {
    return leerCatalogo({
      map: cacheCatalogo.planes,
      nombre: 'planes',
      parqueaderoId,
      consulta: () => supabase.from('planes_mensuales').select('*, tipos_vehiculo(nombre)').eq('parqueadero_id', parqueaderoId).order('created_at', { ascending: true })
    })
  },

  async guardarPlanMensual(parqueaderoId, plan) {
    const valor = parseInt(plan.valor, 10)
    if (!plan.tipo_vehiculo_id) throw new Error('Selecciona el tipo de vehículo')
    if (!plan.nombre?.trim()) throw new Error('El nombre es obligatorio')
    if (!(valor > 0)) throw new Error('El valor debe ser un entero mayor que 0')
    if (!['mensual', 'dias_fijos'].includes(plan.tipo_periodo)) throw new Error('Tipo de periodo inválido')
    const duracion = parseInt(plan.duracion_dias, 10)
    if (plan.tipo_periodo === 'dias_fijos' && !(duracion > 0)) throw new Error('Indica cuántos días dura el periodo')

    invalidarCacheCatalogos(parqueaderoId)
    const payload = {
      parqueadero_id: parqueaderoId,
      tipo_vehiculo_id: plan.tipo_vehiculo_id,
      nombre: plan.nombre.trim(),
      valor,
      tipo_periodo: plan.tipo_periodo,
      duracion_dias: plan.tipo_periodo === 'dias_fijos' ? duracion : null,
      dias_gracia_pago: Math.max(0, parseInt(plan.dias_gracia_pago || 0, 10)),
      activo: plan.activo !== false
    }
    const q = plan.id
      ? supabase.from('planes_mensuales').update(payload).eq('id', plan.id).eq('parqueadero_id', parqueaderoId)
      : supabase.from('planes_mensuales').insert(payload)
    const { data, error } = await q.select().single()
    if (error) throw traducirError(error)
    return data
  },

  // --- MÉTODOS DE PAGO (HU-06) ---
  async listarMetodosPago(parqueaderoId) {
    return leerCatalogo({
      map: cacheCatalogo.metodos,
      nombre: 'metodos',
      parqueaderoId,
      consulta: () => supabase.from('metodos_pago').select('*').eq('parqueadero_id', parqueaderoId).order('orden', { ascending: true })
    })
  },

  async guardarMetodoPago(parqueaderoId, metodo) {
    if (!metodo.nombre?.trim()) throw new Error('El nombre es obligatorio')

    // Debe quedar siempre al menos un método activo marcado como efectivo
    const actuales = await this.listarMetodosPago(parqueaderoId)
    const resultantes = actuales
      .filter(m => m.id !== metodo.id)
      .concat([{ ...metodo, activo: metodo.activo !== false, es_efectivo: !!metodo.es_efectivo }])
    if (!resultantes.some(m => m.activo !== false && m.es_efectivo)) {
      throw new Error('Debe haber al menos un método de pago activo marcado como efectivo')
    }

    invalidarCacheCatalogos(parqueaderoId)
    const payload = {
      parqueadero_id: parqueaderoId,
      nombre: metodo.nombre.trim(),
      es_efectivo: !!metodo.es_efectivo,
      orden: parseInt(metodo.orden || 0, 10),
      activo: metodo.activo !== false
    }
    const q = metodo.id
      ? supabase.from('metodos_pago').update(payload).eq('id', metodo.id).eq('parqueadero_id', parqueaderoId)
      : supabase.from('metodos_pago').insert(payload)
    const { data, error } = await q.select().single()
    if (error) throw traducirError(error)
    return data
  },

  /**
   * Reordena métodos de pago (lista de ids en el orden deseado).
   */
  async reordenarMetodosPago(parqueaderoId, idsEnOrden) {
    invalidarCacheCatalogos(parqueaderoId)
    for (let i = 0; i < idsEnOrden.length; i++) {
      const { error } = await supabase.from('metodos_pago').update({ orden: i + 1 })
        .eq('id', idsEnOrden[i]).eq('parqueadero_id', parqueaderoId)
      if (error) throw error
    }
  },

  // --- SIMULADORES (misma lógica que el cobro) ---
  simularCobroTarifa({ entradaAt, salidaAt, tarifaGeneral, tarifaNocturna = null, zonaHoraria = 'America/Bogota' }) {
    return calcularCobroConFranja({ entradaAt, salidaAt, tarifaGeneral, tarifaNocturna, zonaHoraria })
  },

  simularPeriodosPlan({ tipoPeriodo, duracionDias, fechaInicio, cantidad = 3 }) {
    return generarProximosPeriodos({ tipoPeriodo, duracionDias, fechaInicio, cantidad })
  }
}
