import { supabase } from '@/lib/supabase'
import { calcularCobroConFranja } from '@/domain/cobro'
import { generarProximosPeriodos } from '@/domain/periodo'

// Cache en memoria para catálogos maestros con TTL de 60 segundos
const cacheCatalogo = {
  tipos: new Map(),
  metodos: new Map(),
  planes: new Map(),
  tarifas: new Map(),
  ttl: 60000
}

function getCache(map, key) {
  const item = map.get(key)
  if (item && Date.now() - item.time < cacheCatalogo.ttl) {
    return item.data
  }
  return null
}

function setCache(map, key, data) {
  map.set(key, { data, time: Date.now() })
}

export function invalidarCacheCatalogos(pqId) {
  if (pqId) {
    cacheCatalogo.tipos.delete(pqId)
    cacheCatalogo.metodos.delete(pqId)
    cacheCatalogo.planes.delete(pqId)
    cacheCatalogo.tarifas.delete(pqId)
  } else {
    cacheCatalogo.tipos.clear()
    cacheCatalogo.metodos.clear()
    cacheCatalogo.planes.clear()
    cacheCatalogo.tarifas.clear()
  }
}

export const ajustesService = {
  // --- DATOS DEL NEGOCIO (HU-06) ---
  async obtenerDatosNegocio(parqueaderoId) {
    const { data, error } = await supabase
      .from('parqueaderos')
      .select('*')
      .eq('id', parqueaderoId)
      .single()
    if (error) throw error
    return data
  },

  async guardarDatosNegocio(parqueaderoId, datos) {
    const { data, error } = await supabase
      .from('parqueaderos')
      .update({
        nombre: datos.nombre?.trim(),
        nit: datos.nit?.trim(),
        direccion: datos.direccion?.trim(),
        telefono: datos.telefono?.trim(),
        zona_horaria: datos.zona_horaria || 'America/Bogota',
        moneda: datos.moneda || 'COP',
        dias_aviso_vencimiento: datos.dias_aviso_vencimiento || 5,
        texto_pie_comprobante: datos.texto_pie_comprobante?.trim(),
        modo_ticket: datos.modo_ticket || 'qr',
        ancho_ticket_mm: datos.ancho_ticket_mm || 80
      })
      .eq('id', parqueaderoId)
      .select()
      .single()
    if (error) throw error
    return data
  },

  // --- TIPOS DE VEHÍCULO (HU-07) CON CACHÉ DE ALTO RENDIMIENTO ---
  async listarTiposVehiculo(parqueaderoId) {
    const enCache = getCache(cacheCatalogo.tipos, parqueaderoId)
    if (enCache) return enCache

    const { data, error } = await supabase
      .from('tipos_vehiculo')
      .select('*')
      .eq('parqueadero_id', parqueaderoId)
      .order('orden', { ascending: true })
    if (error) throw error
    const resultado = data || []
    setCache(cacheCatalogo.tipos, parqueaderoId, resultado)
    return resultado
  },

  async guardarTipoVehiculo(parqueaderoId, tipo) {
    invalidarCacheCatalogos(parqueaderoId)
    if (tipo.id) {
      const { data, error } = await supabase
        .from('tipos_vehiculo')
        .update({
          nombre: tipo.nombre.trim(),
          icono: tipo.icono || 'car',
          capacidad: parseInt(tipo.capacidad, 10) || 0,
          orden: parseInt(tipo.orden, 10) || 0,
          activo: tipo.activo !== false
        })
        .eq('id', tipo.id)
        .eq('parqueadero_id', parqueaderoId)
        .select()
        .single()
      if (error) throw error
      return data
    } else {
      const { data, error } = await supabase
        .from('tipos_vehiculo')
        .insert({
          parqueadero_id: parqueaderoId,
          nombre: tipo.nombre.trim(),
          icono: tipo.icono || 'car',
          capacidad: parseInt(tipo.capacidad, 10) || 0,
          orden: parseInt(tipo.orden, 10) || 0,
          activo: true
        })
        .select()
        .single()
      if (error) throw error
      return data
    }
  },

  // --- TARIFAS (HU-08) CON CACHÉ ---
  async listarTarifas(parqueaderoId) {
    const enCache = getCache(cacheCatalogo.tarifas, parqueaderoId)
    if (enCache) return enCache

    const { data, error } = await supabase
      .from('tarifas')
      .select('*, tipos_vehiculo(nombre)')
      .eq('parqueadero_id', parqueaderoId)
      .order('created_at', { ascending: true })
    if (error) throw error
    const resultado = data || []
    setCache(cacheCatalogo.tarifas, parqueaderoId, resultado)
    return resultado
  },

  async guardarTarifa(parqueaderoId, tarifa) {
    invalidarCacheCatalogos(parqueaderoId)
    const payload = {
      parqueadero_id: parqueaderoId,
      tipo_vehiculo_id: tarifa.tipo_vehiculo_id,
      nombre: tarifa.nombre.trim(),
      modalidad: tarifa.modalidad,
      valor: parseInt(tarifa.valor, 10),
      minutos_fraccion: parseInt(tarifa.minutos_fraccion || 15, 10),
      minutos_gracia: parseInt(tarifa.minutos_gracia || 0, 10),
      tope_por_24h: tarifa.tope_por_24h ? parseInt(tarifa.tope_por_24h, 10) : null,
      es_predeterminada: !!tarifa.es_predeterminada,
      franja_inicio: tarifa.franja_inicio || null,
      franja_fin: tarifa.franja_fin || null,
      activa: tarifa.activa !== false
    }

    if (payload.es_predeterminada) {
      await supabase
        .from('tarifas')
        .update({ es_predeterminada: false })
        .eq('parqueadero_id', parqueaderoId)
        .eq('tipo_vehiculo_id', payload.tipo_vehiculo_id)
    }

    if (tarifa.id) {
      const { data, error } = await supabase
        .from('tarifas')
        .update(payload)
        .eq('id', tarifa.id)
        .select()
        .single()
      if (error) throw error
      return data
    } else {
      const { data, error } = await supabase
        .from('tarifas')
        .insert(payload)
        .select()
        .single()
      if (error) throw error
      return data
    }
  },

  // --- PLANES MENSUALES (HU-09) CON CACHÉ ---
  async listarPlanesMensuales(parqueaderoId) {
    const enCache = getCache(cacheCatalogo.planes, parqueaderoId)
    if (enCache) return enCache

    const { data, error } = await supabase
      .from('planes_mensuales')
      .select('*, tipos_vehiculo(nombre)')
      .eq('parqueadero_id', parqueaderoId)
      .order('created_at', { ascending: true })
    if (error) throw error
    const resultado = data || []
    setCache(cacheCatalogo.planes, parqueaderoId, resultado)
    return resultado
  },

  async guardarPlanMensual(parqueaderoId, plan) {
    invalidarCacheCatalogos(parqueaderoId)
    const payload = {
      parqueadero_id: parqueaderoId,
      tipo_vehiculo_id: plan.tipo_vehiculo_id,
      nombre: plan.nombre.trim(),
      valor: parseInt(plan.valor, 10),
      tipo_periodo: plan.tipo_periodo,
      duracion_dias: plan.tipo_periodo === 'dias_fijos' ? parseInt(plan.duracion_dias, 10) : null,
      dias_gracia_pago: parseInt(plan.dias_gracia_pago || 0, 10),
      activo: plan.activo !== false
    }

    if (plan.id) {
      const { data, error } = await supabase
        .from('planes_mensuales')
        .update(payload)
        .eq('id', plan.id)
        .select()
        .single()
      if (error) throw error
      return data
    } else {
      const { data, error } = await supabase
        .from('planes_mensuales')
        .insert(payload)
        .select()
        .single()
      if (error) throw error
      return data
    }
  },

  // --- MÉTODOS DE PAGO (HU-06) CON CACHÉ ---
  async listarMetodosPago(parqueaderoId) {
    const enCache = getCache(cacheCatalogo.metodos, parqueaderoId)
    if (enCache) return enCache

    const { data, error } = await supabase
      .from('metodos_pago')
      .select('*')
      .eq('parqueadero_id', parqueaderoId)
      .order('orden', { ascending: true })
    if (error) throw error
    const resultado = data || []
    setCache(cacheCatalogo.metodos, parqueaderoId, resultado)
    return resultado
  },

  async guardarMetodoPago(parqueaderoId, metodo) {
    invalidarCacheCatalogos(parqueaderoId)
    const payload = {
      parqueadero_id: parqueaderoId,
      nombre: metodo.nombre.trim(),
      es_efectivo: !!metodo.es_efectivo,
      orden: parseInt(metodo.orden || 0, 10),
      activo: metodo.activo !== false
    }

    if (metodo.id) {
      const { data, error } = await supabase
        .from('metodos_pago')
        .update(payload)
        .eq('id', metodo.id)
        .select()
        .single()
      if (error) throw error
      return data
    } else {
      const { data, error } = await supabase
        .from('metodos_pago')
        .insert(payload)
        .select()
        .single()
      if (error) throw error
      return data
    }
  },

  // --- SIMULADORES (Lógica Pura de Dominio) ---
  simularCobroTarifa({ entradaAt, salidaAt, tarifaGeneral, tarifaNocturna = null }) {
    return calcularCobroConFranja({ entradaAt, salidaAt, tarifaGeneral, tarifaNocturna })
  },

  simularPeriodosPlan({ tipoPeriodo, duracionDias, fechaInicio, cantidad = 3 }) {
    return generarProximosPeriodos({ tipoPeriodo, duracionDias, fechaInicio, cantidad })
  }
}
