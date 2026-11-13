import jsPDF from 'jspdf'
import { numeroALetrasCOP } from '@/utils/numeroALetras'
import { formatearFechaHora, formatearFechaCorta } from '@/utils/fecha'

export function formatearDuracion(minutos) {
  const min = Math.max(0, Math.round(minutos || 0))
  if (min < 60) return `${min} min`
  const h = Math.floor(min / 60)
  const m = min % 60
  return m === 0 ? `${h} h` : `${h} h ${m} min`
}

function pesos(valor) {
  return `$${Number(valor || 0).toLocaleString('es-CO')}`
}

/**
 * Genera el PDF del comprobante (HU-20/21/22). Siempre en tema claro.
 *
 * @param {Object} p
 * @param {Object} p.parqueadero - nombre, nit, direccion, telefono, texto_pie_comprobante,
 *                                 ancho_ticket_mm, modo_ticket, zona_horaria
 * @param {Object} p.comprobante - consecutivo (null = provisional), cliente_nombre,
 *                                 cliente_documento, valor, created_at, anulado
 * @param {Object} p.detalle - formato de obtener_detalle_comprobante:
 *   hora: { tipo:'hora', placa, tipo_vehiculo, entrada_at, salida_at, minutos, tarifa, metodo_pago, usuario }
 *   mensualidad: { tipo:'mensualidad', placa, plan, periodo_desde, periodo_hasta, metodo_pago, usuario }
 * @param {boolean} p.esCopia - re-descarga: mismo consecutivo con la marca "COPIA"
 * @param {'carta'|'termica'} [p.formato] - por defecto según el modo de ticket del parqueadero
 */
export function generarPDFComprobante({ parqueadero, comprobante, detalle, esCopia = false, formato = null }) {
  const zona = parqueadero?.zona_horaria || 'America/Bogota'
  const esTermica = (formato || (parqueadero?.modo_ticket === 'termica' ? 'termica' : 'carta')) === 'termica'
  const ancho = parqueadero?.ancho_ticket_mm === 58 ? 58 : 80

  const doc = esTermica
    ? new jsPDF({ unit: 'mm', format: [ancho, 200] })
    : new jsPDF({ unit: 'mm', format: 'letter' })

  const pageWidth = doc.internal.pageSize.getWidth()
  const margen = esTermica ? 4 : 15
  const centro = pageWidth / 2
  const maxAncho = pageWidth - margen * 2
  let y = 10

  const linea = () => {
    y += 1
    doc.line(margen, y, pageWidth - margen, y)
    y += 5
  }
  const texto = (t, opciones = {}) => {
    const lineas = doc.splitTextToSize(String(t), maxAncho)
    doc.text(lineas, opciones.align === 'center' ? centro : margen, y, opciones)
    y += lineas.length * (esTermica ? 3.6 : 4.5)
  }

  // 1. Encabezado del parqueadero
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(esTermica ? 11 : 15)
  texto(parqueadero?.nombre || 'Parqueadero', { align: 'center' })
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(esTermica ? 7.5 : 9)
  if (parqueadero?.nit) texto(`NIT: ${parqueadero.nit}`, { align: 'center' })
  if (parqueadero?.direccion) texto(parqueadero.direccion, { align: 'center' })
  if (parqueadero?.telefono) texto(`Tel: ${parqueadero.telefono}`, { align: 'center' })
  linea()

  // 2. Título y consecutivo
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(esTermica ? 9.5 : 12)
  texto(comprobante.consecutivo
    ? `COMPROBANTE DE PAGO N° ${String(comprobante.consecutivo).padStart(6, '0')}`
    : 'COMPROBANTE PROVISIONAL (SIN CONEXIÓN)', { align: 'center' })

  if (esCopia || comprobante.anulado || !comprobante.consecutivo) {
    doc.setFontSize(8)
    doc.setTextColor(170, 0, 0)
    if (esCopia) texto('*** COPIA ***', { align: 'center' })
    if (comprobante.anulado) texto('*** ANULADO ***', { align: 'center' })
    if (!comprobante.consecutivo) texto('El comprobante oficial se emite al sincronizar', { align: 'center' })
    doc.setTextColor(0, 0, 0)
  }

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(esTermica ? 7.5 : 9)
  texto(`Fecha de emisión: ${formatearFechaHora(comprobante.created_at || new Date(), zona, { year: 'numeric' })}`)
  texto(`Cliente: ${comprobante.cliente_nombre || 'Consumidor final'}`)
  if (comprobante.cliente_documento) texto(`Documento: ${comprobante.cliente_documento}`)
  linea()

  // 3. Detalle
  doc.setFont('helvetica', 'bold')
  texto('DETALLE DEL SERVICIO')
  doc.setFont('helvetica', 'normal')
  if (detalle?.tipo === 'mensualidad') {
    texto(`Plan: ${detalle.plan || 'Mensualidad'}`)
    texto(`Placa: ${detalle.placa || '-'}`)
    texto(`Periodo pagado: ${formatearFechaCorta(detalle.periodo_desde)} al ${formatearFechaCorta(detalle.periodo_hasta)}`)
  } else {
    texto(`Placa: ${detalle?.placa || '-'}${detalle?.tipo_vehiculo ? ` (${detalle.tipo_vehiculo})` : ''}`)
    texto(`Entrada: ${formatearFechaHora(detalle?.entrada_at, zona, { year: 'numeric' })}`)
    texto(`Salida: ${formatearFechaHora(detalle?.salida_at, zona, { year: 'numeric' })}`)
    texto(`Tiempo: ${formatearDuracion(detalle?.minutos)}`)
    if (detalle?.tarifa) texto(`Tarifa: ${detalle.tarifa}`)
  }
  linea()

  // 4. Total en números y letras
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(esTermica ? 10 : 13)
  texto(`TOTAL PAGADO: ${pesos(comprobante.valor)}`)
  doc.setFont('helvetica', 'normal')
  doc.setFontSize(esTermica ? 7 : 8.5)
  texto(`Son: ${numeroALetrasCOP(comprobante.valor || 0)}`)
  texto(`Método de pago: ${detalle?.metodo_pago || '-'}`)
  texto(`Atendido por: ${detalle?.usuario || '-'}`)

  // 5. Pie configurable
  if (parqueadero?.texto_pie_comprobante) {
    y += 2
    doc.setFontSize(esTermica ? 6.5 : 7.5)
    doc.setTextColor(80, 80, 80)
    texto(parqueadero.texto_pie_comprobante, { align: 'center' })
    doc.setTextColor(0, 0, 0)
  }

  return doc
}
