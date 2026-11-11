import jsPDF from 'jspdf'
import { numeroALetrasCOP } from '@/utils/numeroALetras'

export function generarPDFComprobante({
  parqueadero,
  comprobante,
  detalle,
  esCopia = false
}) {
  const formatoTermica = parqueadero?.ancho_ticket_mm === 58 ? [58, 150] : [80, 180]
  const esTermica = parqueadero?.modo_ticket === 'termica'

  const doc = esTermica 
    ? new jsPDF({ unit: 'mm', format: formatoTermica }) 
    : new jsPDF({ unit: 'mm', format: 'letter' })

  const pageWidth = doc.internal.pageSize.getWidth()
  let y = 10

  // 1. Encabezado del Parqueadero
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(esTermica ? 11 : 14)
  doc.text(parqueadero?.nombre || 'PARQUEADERO', pageWidth / 2, y, { align: 'center' })
  y += 5

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(esTermica ? 8 : 9)
  doc.text(`NIT: ${parqueadero?.nit || 'No especificado'}`, pageWidth / 2, y, { align: 'center' })
  y += 4
  if (parqueadero?.direccion) {
    doc.text(parqueadero.direccion, pageWidth / 2, y, { align: 'center' })
    y += 4
  }
  if (parqueadero?.telefono) {
    doc.text(`Tel: ${parqueadero.telefono}`, pageWidth / 2, y, { align: 'center' })
    y += 4
  }

  y += 2
  doc.line(8, y, pageWidth - 8, y)
  y += 5

  // 2. Título y Consecutivo
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(esTermica ? 10 : 11)
  const consecutivoTexto = comprobante.consecutivo 
    ? `COMPROBANTE DE PAGO N° ${String(comprobante.consecutivo).padStart(6, '0')}`
    : 'COMPROBANTE DE PAGO PROVISIONAL'
  doc.text(consecutivoTexto, pageWidth / 2, y, { align: 'center' })
  y += 4

  if (esCopia) {
    doc.setFontSize(8)
    doc.setTextColor(150, 0, 0)
    doc.text('*** COPIA ***', pageWidth / 2, y, { align: 'center' })
    doc.setTextColor(0, 0, 0)
    y += 4
  }

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(esTermica ? 7.5 : 9)
  doc.text(`Fecha de emisión: ${new Date().toLocaleString()}`, 8, y)
  y += 4

  // 3. Datos del Cliente
  doc.text(`Cliente: ${comprobante.cliente_nombre || 'Consumidor final'}`, 8, y)
  y += 4
  if (comprobante.cliente_documento) {
    doc.text(`Doc: ${comprobante.cliente_documento}`, 8, y)
    y += 4
  }

  y += 1
  doc.line(8, y, pageWidth - 8, y)
  y += 5

  // 4. Detalle de la Operación
  doc.setFont('helvetica', 'bold')
  doc.text('DETALLE DEL SERVICIO', 8, y)
  y += 4
  doc.setFont('helvetica', 'normal')

  if (detalle.tipo === 'hora') {
    doc.text(`Vehículo / Placa: ${detalle.placa} (${detalle.tipoVehiculo || 'Vehículo'})`, 8, y)
    y += 4
    doc.text(`Entrada: ${detalle.entrada}`, 8, y)
    y += 4
    doc.text(`Salida:  ${detalle.salida}`, 8, y)
    y += 4
    doc.text(`Tiempo liquidado: ${detalle.minutos} minutos`, 8, y)
    y += 4
  } else if (detalle.tipo === 'mensualidad') {
    doc.text(`Plan: ${detalle.planNombre || 'Mensualidad'}`, 8, y)
    y += 4
    doc.text(`Placa: ${detalle.placa}`, 8, y)
    y += 4
    doc.text(`Periodo cubierto: ${detalle.periodoDesde} al ${detalle.periodoHasta}`, 8, y)
    y += 4
  }

  y += 2
  doc.line(8, y, pageWidth - 8, y)
  y += 5

  // 5. Total en Números y Letras
  doc.setFont('helvetica', 'bold')
  doc.setFontSize(esTermica ? 10 : 12)
  doc.text(`TOTAL PAGADO: $${(comprobante.valor || 0).toLocaleString()}`, 8, y)
  y += 5

  doc.setFont('helvetica', 'normal')
  doc.setFontSize(esTermica ? 7 : 8)
  const letras = numeroALetrasCOP(comprobante.valor || 0)
  doc.text(`Son: ${letras}`, 8, y, { maxWidth: pageWidth - 16 })
  y += 6

  doc.text(`Método de pago: ${detalle.metodoPago || 'Efectivo'}`, 8, y)
  y += 4
  doc.text(`Atendido por: ${detalle.cajero || 'Caja'}`, 8, y)
  y += 6

  // 6. Pie del Comprobante
  if (parqueadero?.texto_pie_comprobante) {
    doc.setFontSize(6.5)
    doc.setTextColor(80, 80, 80)
    doc.text(parqueadero.texto_pie_comprobante, pageWidth / 2, y, { align: 'center', maxWidth: pageWidth - 16 })
  }

  return doc
}
