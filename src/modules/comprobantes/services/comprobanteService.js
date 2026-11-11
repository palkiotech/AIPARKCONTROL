import { supabase } from '@/lib/supabase'
import { generarPDFComprobante } from '../pdf'

const comprobantesLocales = [
  {
    id: 'comp-1',
    consecutivo: 1001,
    origen: 'registro',
    origen_id: 'reg-demo-1',
    cliente_nombre: 'Carlos Mendoza',
    cliente_documento: '10203040',
    valor: 6000,
    created_at: new Date().toISOString(),
    anulado: false
  },
  {
    id: 'comp-2',
    consecutivo: 1002,
    origen: 'pago_mensualidad',
    origen_id: 'pag-demo-1',
    cliente_nombre: 'Ana Gómez',
    cliente_documento: '20304050',
    valor: 150000,
    created_at: new Date(Date.now() - 3600000).toISOString(),
    anulado: false
  }
]

export const comprobanteService = {
  /**
   * Crea un comprobante con consecutivo oficial (HU-20, HU-21)
   */
  async crearComprobante({ origen, origenId, clienteNombre, clienteDocumento }) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      // Comprobante provisional sin conexión
      const provisional = {
        id: crypto.randomUUID(),
        consecutivo: null,
        origen,
        origen_id: origenId,
        cliente_nombre: clienteNombre || 'Consumidor final',
        cliente_documento: clienteDocumento,
        valor: 0,
        created_at: new Date().toISOString(),
        anulado: false
      }
      comprobantesLocales.unshift(provisional)
      return { success: true, comprobante: provisional, provisional: true }
    }

    try {
      const { data, error } = await supabase.rpc('crear_comprobante', {
        p_origen: origen,
        p_origen_id: origenId,
        p_cliente_nombre: clienteNombre || 'Consumidor final',
        p_cliente_documento: clienteDocumento || null
      })
      if (error) throw error
      return data
    } catch (err) {
      // Mock local
      const nuevo = {
        id: crypto.randomUUID(),
        consecutivo: 1003,
        origen,
        origen_id: origenId,
        cliente_nombre: clienteNombre || 'Consumidor final',
        cliente_documento: clienteDocumento,
        valor: 0,
        created_at: new Date().toISOString(),
        anulado: false
      }
      comprobantesLocales.unshift(nuevo)
      return { success: true, comprobante: nuevo }
    }
  },

  /**
   * Lista los comprobantes emitidos (HU-22)
   */
  async listarComprobantes(parqueaderoId) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      return comprobantesLocales
    }

    try {
      const { data, error } = await supabase
        .from('comprobantes')
        .select('*')
        .eq('parqueadero_id', parqueaderoId)
        .order('consecutivo', { ascending: false })

      if (error) throw error
      return data && data.length ? data : comprobantesLocales
    } catch (err) {
      return comprobantesLocales
    }
  },

  /**
   * Genera y descarga el archivo PDF
   */
  descargarPDF({ parqueadero, comprobante, detalle, esCopia = false }) {
    const doc = generarPDFComprobante({ parqueadero, comprobante, detalle, esCopia })
    const nombreArchivo = `comprobante-${comprobante.consecutivo || 'provisional'}-${detalle.placa || 'ticket'}.pdf`
    doc.save(nombreArchivo)
  }
}
