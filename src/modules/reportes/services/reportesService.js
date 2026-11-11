import { supabase } from '@/lib/supabase'
import * as XLSX from 'xlsx'

export const reportesService = {
  /**
   * Obtiene los totales agregados de ingresos en un rango de fechas (HU-25)
   */
  async obtenerReporteIngresos(fechaDesde, fechaHasta) {
    const vacio = {
      total_hora: 0,
      total_mensualidades: 0,
      gran_total: 0,
      por_tipo: [],
      por_metodo: []
    }

    try {
      const { data, error } = await supabase.rpc('obtener_reporte_ingresos', {
        p_fecha_desde: fechaDesde,
        p_fecha_hasta: fechaHasta
      })
      if (error) throw error
      return data || vacio
    } catch (err) {
      return vacio
    }
  },

  /**
   * Exporta filas a formato Excel (.xlsx) con montos numéricos reales
   */
  exportarAExcel(nombreArchivo, hojas) {
    const wb = XLSX.utils.book_new()

    for (const [nombreHoja, datos] of Object.entries(hojas)) {
      const ws = XLSX.utils.json_to_sheet(datos)
      XLSX.utils.book_append_sheet(wb, ws, nombreHoja)
    }

    XLSX.writeFile(wb, `${nombreArchivo}.xlsx`)
  },

  /**
   * Exporta a formato CSV nativo
   */
  exportarACSV(nombreArchivo, datos) {
    const ws = XLSX.utils.json_to_sheet(datos)
    const csv = XLSX.utils.sheet_to_csv(ws)
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
    const link = document.createElement('a')
    link.href = URL.createObjectURL(blob)
    link.download = `${nombreArchivo}.csv`
    link.click()
  }
}
