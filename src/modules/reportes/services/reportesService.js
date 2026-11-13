import { supabase } from '@/lib/supabase'
import * as XLSX from 'xlsx'
import { rangoDiaUtc, sumarDias, formatearFechaHora } from '@/utils/fecha'

/**
 * Reportes e ingresos (HU-25). Fechas en la zona horaria del parqueadero.
 * Los errores se propagan: antes un fallo mostraba $0 como si no hubiera ingresos.
 */
export const reportesService = {
  /**
   * Totales por día, tipo, método, origen y anulados (RPC agregada, solo admin).
   * fechaDesde/fechaHasta: 'YYYY-MM-DD' en la zona del parqueadero.
   */
  async obtenerReporteIngresos(fechaDesde, fechaHasta) {
    const { data, error } = await supabase.rpc('obtener_reporte_ingresos', {
      p_fecha_desde: fechaDesde,
      p_fecha_hasta: fechaHasta
    })
    if (error) throw error
    return data
  },

  /**
   * Detalle de registros del rango para exportar (incluye anulados en su estado).
   */
  async obtenerDetalleRegistros({ parqueaderoId, fechaDesde, fechaHasta, zonaHoraria }) {
    const desde = rangoDiaUtc(fechaDesde, zonaHoraria).desde
    const hasta = rangoDiaUtc(sumarDias(fechaHasta, 0), zonaHoraria).hasta
    const { data, error } = await supabase
      .from('registros')
      .select('placa, entrada_at, salida_at, minutos, valor, valor_servidor, requiere_revision, estado, motivo_anulacion, es_mensual, hora_origen, tipos_vehiculo(nombre), metodos_pago(nombre), tarifas(nombre)')
      .eq('parqueadero_id', parqueaderoId)
      .gte('entrada_at', desde)
      .lt('entrada_at', hasta)
      .order('entrada_at', { ascending: true })
      .limit(10000)
    if (error) throw error
    return (data || []).map(r => ({
      Placa: r.placa,
      Tipo: r.tipos_vehiculo?.nombre || '',
      Entrada: formatearFechaHora(r.entrada_at, zonaHoraria, { year: 'numeric' }),
      Salida: r.salida_at ? formatearFechaHora(r.salida_at, zonaHoraria, { year: 'numeric' }) : '',
      Minutos: r.minutos ?? null,
      Tarifa: r.tarifas?.nombre || '',
      Valor: r.valor ?? 0,
      'Valor servidor': r.valor_servidor ?? null,
      'Requiere revisión': r.requiere_revision ? 'Sí' : 'No',
      'Método de pago': r.metodos_pago?.nombre || '',
      Mensual: r.es_mensual ? 'Sí' : 'No',
      Estado: r.estado,
      'Motivo anulación': r.motivo_anulacion || '',
      'Hora origen': r.hora_origen
    }))
  },

  /**
   * Conflictos de sincronización para revisión del admin (HU-26).
   */
  async listarConflictosSync(parqueaderoId, limite = 200) {
    const { data, error } = await supabase
      .from('operaciones_sync')
      .select('*, profiles(nombre)')
      .eq('parqueadero_id', parqueaderoId)
      .neq('resultado', 'ok')
      .order('procesada_at', { ascending: false })
      .limit(limite)
    if (error) throw error
    return data || []
  },

  /**
   * Exporta varias hojas a Excel (.xlsx). Los montos deben llegar como números.
   * @param {string} nombreArchivo
   * @param {Object<string, Array<Object>>} hojas
   */
  exportarAExcel(nombreArchivo, hojas) {
    const wb = XLSX.utils.book_new()
    for (const [nombreHoja, datos] of Object.entries(hojas)) {
      const ws = XLSX.utils.json_to_sheet(datos.length ? datos : [{ 'Sin datos': '' }])
      XLSX.utils.book_append_sheet(wb, ws, nombreHoja.slice(0, 31))
    }
    XLSX.writeFile(wb, `${nombreArchivo}.xlsx`)
  },

  exportarACSV(nombreArchivo, datos) {
    const ws = XLSX.utils.json_to_sheet(datos)
    const csv = XLSX.utils.sheet_to_csv(ws)
    const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' })
    const link = document.createElement('a')
    link.href = URL.createObjectURL(blob)
    link.download = `${nombreArchivo}.csv`
    link.click()
    setTimeout(() => URL.revokeObjectURL(link.href), 1000)
  }
}
