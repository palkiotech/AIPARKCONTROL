import { supabase } from '@/lib/supabase'
import { calcularCobroConFranja } from '@/domain/cobro'
import { generarProximosPeriodos } from '@/domain/periodo'

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

  // --- TIPOS DE VEHÍCULO (HU-07) ---
  async listarTiposVehiculo(parqueaderoId) {
    const { data, error } = await supabase
      .from('tipos_vehiculo')
      .select('*')
      .eq('parqueadero_id', parqueaderoId)
      .order('orden', { ascending: true })
    if (error) throw error
    return data || []
  },

  async guardarTipoVehiculo(parqueaderoId, tipo) {
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

  // --- TARIFAS (HU-08) ---
  async listarTarifas(parqueaderoId) {
    const { data, error } = await supabase
      .from('tarifas')
      .select('*, tipos_vehiculo(nombre)')
      .eq('parqueadero_id', parqueaderoId)
      .order('created_at', { ascending: true })
    if (error) throw error
    return data || []
  },

  async guardarTarifa(parqueaderoId, tarifa) {
    const payload = {
      parqueadero_id: parqueaderoId,
      tipo_vehiculo_id: tarifa.tipo_vehiculo_id,
      nombre: tarifa.nombre.trim(),
      modalidad: tarifa.modalidad,
      valor: parseInt(tarifa.valor, 10),
      minutos_fraccion: tarifa.modalidad === 'por_fraccion' ? parseInt(tarifa.minutos_fraccion, 10) : null,
      minutos_gracia: parseInt(tarifa.minutos_gracia || 0, 10),
      tope_por_24h: tarifa.tope_por_24h ? parseInt(tarifa.tope_por_24h, 10) : null,
      es_predeterminada: !!tarifa.es_predeterminada,
      franja_inicio: tarifa.tiene_franja ? tarifa.franja_inicio : null,
      franja_fin: tarifa.tiene_franja ? tarifa.franja_fin : null,
      activa: tarifa.activa !== false
    }

    // Si se marca como predeterminada, desmarcar las otras del mismo tipo
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

  // --- PLANES MENSUALES (HU-09) ---
  async listarPlanesMensuales(parqueaderoId) {
    const { data, error } = await supabase
      .from('planes_mensuales')
      .select('*, tipos_vehiculo(nombre)')
      .eq('parqueadero_id', parqueaderoId)
      .order('created_at', { ascending: true })
    if (error) throw error
    return data || []
  },

  async guardarPlanMensual(parqueaderoId, plan) {
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

  // --- MÉTODOS DE PAGO (HU-06) ---
  async listarMetodosPago(parqueaderoId) {
    const { data, error } = await supabase
      .from('metodos_pago')
      .select('*')
      .eq('parqueadero_id', parqueaderoId)
      .order('orden', { ascending: true })
    if (error) throw error
    return data || []
  },

  async guardarMetodoPago(parqueaderoId, metodo) {
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

  // --- SIMULADORES EN VIVO (HU-08 y HU-09) ---
  simularCobroTarifa(params) {
    return calcularCobroConFranja(params)
  },

  simularPeriodosPlan(params) {
    return generarProximosPeriodos(params)
  }
}
