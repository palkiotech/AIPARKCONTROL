import { supabase } from '@/lib/supabase'
import { generarPDFComprobante } from '../pdf'
import { estaEnLinea } from '@/lib/sesionCaches'

/**
 * Comprobantes (HU-20 a HU-22).
 * - El consecutivo oficial lo asigna la base de datos; nunca se inventa.
 * - Sin conexión solo se genera un comprobante PROVISIONAL (sin número).
 * - Pedir dos veces el comprobante del mismo cobro devuelve el mismo consecutivo.
 */
export const comprobanteService = {
  /**
   * Emite (o recupera) el comprobante oficial y devuelve los datos para el PDF.
   * @param {{origen:'registro'|'pago_mensualidad', origenId:string, clienteNombre?:string, clienteDocumento?:string}} p
   * @returns {Promise<{comprobante, detalle, parqueadero, existente:boolean}>}
   */
  async emitir({ origen, origenId, clienteNombre, clienteDocumento }) {
    if (!estaEnLinea()) {
      throw new Error('El comprobante oficial requiere conexión. Puedes generar uno provisional.')
    }
    const { data, error } = await supabase.rpc('crear_comprobante', {
      p_origen: origen,
      p_origen_id: origenId,
      p_cliente_nombre: clienteNombre?.trim() || 'Consumidor final',
      p_cliente_documento: clienteDocumento?.trim() || null
    })
    if (error) throw error
    const completo = await this.obtenerDetalle(data.comprobante_id)
    return { ...completo, existente: !!data.existente }
  },

  /**
   * Datos reales del comprobante, su origen y el parqueadero (para re-descargar).
   */
  async obtenerDetalle(comprobanteId) {
    const { data, error } = await supabase.rpc('obtener_detalle_comprobante', { p_comprobante_id: comprobanteId })
    if (error) throw error
    return data
  },

  /**
   * Lista de comprobantes con filtros (HU-22). Solo admin.
   * desde/hasta: 'YYYY-MM-DD' en la zona del parqueadero. busqueda: consecutivo o placa.
   */
  async listarComprobantes({ desde = null, hasta = null, busqueda = '' } = {}) {
    const { data, error } = await supabase.rpc('listar_comprobantes', {
      p_desde: desde || null,
      p_hasta: hasta || null,
      p_busqueda: busqueda || null
    })
    if (error) throw error
    return data || []
  },

  /**
   * Genera el PDF y lo descarga o lo comparte (Web Share API en el celular).
   */
  async descargarPDF({ parqueadero, comprobante, detalle, esCopia = false, formato = null, compartir = false }) {
    const doc = generarPDFComprobante({ parqueadero, comprobante, detalle, esCopia, formato })
    const nombreArchivo = `comprobante-${comprobante.consecutivo || 'provisional'}-${detalle?.placa || 'parqueadero'}.pdf`

    if (compartir && typeof navigator !== 'undefined' && navigator.canShare) {
      try {
        const archivo = new File([doc.output('blob')], nombreArchivo, { type: 'application/pdf' })
        if (navigator.canShare({ files: [archivo] })) {
          await navigator.share({ files: [archivo], title: nombreArchivo })
          return
        }
      } catch (e) {
        if (e?.name === 'AbortError') return
      }
    }
    doc.save(nombreArchivo)
  },

  /**
   * Comprobante provisional sin conexión (sin consecutivo, marcado como tal).
   */
  descargarProvisional({ parqueadero, valor, detalle, clienteNombre, clienteDocumento }) {
    const comprobante = {
      consecutivo: null,
      valor,
      cliente_nombre: clienteNombre || 'Consumidor final',
      cliente_documento: clienteDocumento || null,
      created_at: new Date().toISOString(),
      anulado: false
    }
    return this.descargarPDF({ parqueadero, comprobante, detalle })
  }
}
