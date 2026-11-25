/**
 * Ticket de entrada imprimible (HU-27), en dos formatos:
 *
 * - 'termica': rollo de 58 u 80 mm.
 * - 'hoja': impresora normal (láser o tinta) en carta o A4. El ticket sale en un
 *   recuadro punteado para recortar.
 *
 * Una página web no puede hablar directo con una impresora láser. Se imprime con
 * el diálogo del sistema: en Android (Mopria), iPhone/iPad (AirPrint), Windows o
 * macOS aparecen las impresoras WiFi, Bluetooth o USB que el equipo ya tenga
 * agregadas. El QR lleva el id del registro: Registro y cobro lo escanea para
 * cobrar la salida.
 */

function escapar(s) {
  return String(s ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]))
}

const MODALIDADES = {
  por_minuto: () => 'por minuto',
  por_hora: () => 'por hora',
  por_fraccion: (t) => `por fracción de ${t.minutos_fraccion || 15} min`,
  plena: () => 'tarifa plena (24 h)'
}

/** "Carro por hora · $3.000 por hora" */
export function textoTarifa(tarifa) {
  if (!tarifa) return ''
  const valor = `$${Number(tarifa.valor || 0).toLocaleString('es-CO')}`
  const modo = (MODALIDADES[tarifa.modalidad] || (() => ''))(tarifa)
  return [tarifa.nombre, [valor, modo].filter(Boolean).join(' ')].filter(Boolean).join(' · ')
}

/** Referencia corta y legible del registro (para buscarlo si el QR se daña). */
export function referenciaTicket(registroId) {
  return String(registroId || '').replace(/-/g, '').slice(0, 8).toUpperCase()
}

/**
 * HTML del ticket. Función pura: todo llega ya formateado.
 * @param {object} d
 * @param {{nombre, nit?, direccion?, telefono?, texto_pie_comprobante?, logo_url?}} d.parqueadero
 * @param {string} d.placa
 * @param {string} d.tipoNombre
 * @param {string} d.entradaTexto - fecha y hora de entrada ya formateadas en la zona del parqueadero
 * @param {string} [d.tarifaTexto]
 * @param {string} [d.referencia]
 * @param {string} [d.qr] - data URL del QR
 * @param {boolean} [d.prueba]
 * @param {{formato?: 'hoja'|'termica', ancho?: 58|80}} opciones
 */
export function construirHtmlTicket(d, { formato = 'hoja', ancho = 80 } = {}) {
  const p = d.parqueadero || {}
  const termica = formato === 'termica'
  const datosNegocio = [p.nit && `NIT ${p.nit}`, p.direccion, p.telefono && `Tel. ${p.telefono}`].filter(Boolean)
  const filas = [
    ['Tipo', d.tipoNombre],
    ['Entrada', d.entradaTexto],
    ['Tarifa', d.tarifaTexto],
    ['Ticket', d.referencia]
  ].filter(([, v]) => v)

  const estilo = termica ? ` style="width:${(ancho === 58 ? 58 : 80) - 4}mm"` : ''
  return `<div class="pc-ticket pc-ticket--${termica ? 'termica' : 'hoja'}"${estilo}>
  ${!termica && p.logo_url ? `<img class="pc-ticket__logo" src="${escapar(p.logo_url)}" alt="">` : ''}
  <p class="pc-ticket__negocio">${escapar(p.nombre || 'Parqueadero')}</p>
  ${datosNegocio.map(l => `<p class="pc-ticket__centro">${escapar(l)}</p>`).join('\n  ')}
  <p class="pc-ticket__titulo">TICKET DE ENTRADA</p>
  <p class="pc-ticket__placa">${escapar(d.placa)}</p>
  <table class="pc-ticket__datos">${filas.map(([k, v]) => `<tr><th>${k}</th><td>${escapar(v)}</td></tr>`).join('')}</table>
  ${d.qr ? `<img class="pc-ticket__qr" src="${escapar(d.qr)}" alt="Código QR del ticket">` : ''}
  <p class="pc-ticket__nota">Presente este ticket a la salida.</p>
  ${p.texto_pie_comprobante ? `<p class="pc-ticket__pie">${escapar(p.texto_pie_comprobante)}</p>` : ''}
  ${d.prueba ? '<p class="pc-ticket__titulo">*** TICKET DE PRUEBA ***</p>' : ''}
</div>${termica ? '' : '\n<p class="pc-ticket__recorte">Recorte por la línea punteada</p>'}`
}

/** CSS del ticket (pantalla de vista previa e impresión). */
export const CSS_TICKET = `
.pc-ticket { color: #000; background: #fff; box-sizing: border-box; }
.pc-ticket p { margin: 0 0 1.2mm; overflow-wrap: anywhere; }
.pc-ticket__centro, .pc-ticket__negocio, .pc-ticket__titulo, .pc-ticket__placa, .pc-ticket__nota, .pc-ticket__pie { text-align: center; }
.pc-ticket__negocio { font-weight: 700; }
.pc-ticket__titulo { font-weight: 700; letter-spacing: 1px; margin-top: 2mm !important; }
.pc-ticket__placa { font-weight: 800; letter-spacing: 3px; }
.pc-ticket__datos { width: 100%; border-collapse: collapse; margin: 1mm 0 2mm; }
.pc-ticket__datos th { text-align: left; font-weight: 600; padding: 0.6mm 2mm 0.6mm 0; white-space: nowrap; vertical-align: top; }
.pc-ticket__datos td { padding: 0.6mm 0; overflow-wrap: anywhere; }
.pc-ticket__qr { display: block; margin: 2mm auto; image-rendering: pixelated; }
.pc-ticket__logo { display: block; margin: 0 auto 2mm; max-height: 16mm; max-width: 50mm; object-fit: contain; }
.pc-ticket--termica { font-family: 'Courier New', monospace; font-size: 10pt; line-height: 1.25; padding: 2mm; }
.pc-ticket--termica .pc-ticket__placa { font-size: 16pt; }
.pc-ticket--termica .pc-ticket__qr { width: 70%; }
.pc-ticket--termica .pc-ticket__pie { font-size: 8pt; }
.pc-ticket--hoja { width: 95mm; font-family: Arial, Helvetica, sans-serif; font-size: 10.5pt; line-height: 1.3; padding: 6mm 7mm; border: 1.2px dashed #000; }
.pc-ticket--hoja .pc-ticket__negocio { font-size: 13pt; }
.pc-ticket--hoja .pc-ticket__placa { font-size: 26pt; margin: 1mm 0 2mm !important; }
.pc-ticket--hoja .pc-ticket__qr { width: 48mm; height: 48mm; }
.pc-ticket--hoja .pc-ticket__nota { font-weight: 600; }
.pc-ticket--hoja .pc-ticket__pie { font-size: 8.5pt; }
.pc-ticket__recorte { width: 95mm; margin: 1.5mm 0 0; text-align: center; font: 7.5pt Arial, Helvetica, sans-serif; color: #555; }
`

/** Reglas de página para imprimir. La hoja usa el papel que se elija en el diálogo. */
export function cssPagina({ formato = 'hoja', ancho = 80 } = {}) {
  return formato === 'termica'
    ? `@page { size: ${ancho === 58 ? 58 : 80}mm auto; margin: 0; }`
    : '@page { margin: 10mm; }'
}

function esperarImagenes(contenedor, tiempoMax = 2500) {
  const pendientes = [...contenedor.querySelectorAll('img')].filter(img => !img.complete)
  if (!pendientes.length) return Promise.resolve()
  return Promise.race([
    Promise.all(pendientes.map(img => new Promise(r => { img.onload = r; img.onerror = r }))),
    new Promise(r => setTimeout(r, tiempoMax))
  ])
}

/**
 * Imprime el ticket con el diálogo de impresión del sistema. El contenido se
 * deja oculto en la página (no se borra con un temporizador: en celulares
 * window.print() no bloquea y el sistema captura la página después).
 */
/** Instala el CSS del ticket (vista previa en pantalla y reglas de impresión). */
export function instalarEstiloTicket(opciones = {}) {
  let estilo = document.getElementById('pc-ticket-estilo')
  if (!estilo) {
    estilo = document.createElement('style')
    estilo.id = 'pc-ticket-estilo'
    document.head.appendChild(estilo)
  }
  estilo.textContent = `${CSS_TICKET}
#pc-ticket-impresion { display: none; }
@media print {
  ${cssPagina(opciones)}
  body.pc-imprimiendo-ticket > *:not(#pc-ticket-impresion) { display: none !important; }
  body.pc-imprimiendo-ticket #pc-ticket-impresion { display: block !important; }
  body.pc-imprimiendo-ticket { background: #fff !important; margin: 0 !important; }
}`
}

export async function imprimirTicket(datos, opciones = {}) {
  let contenedor = document.getElementById('pc-ticket-impresion')
  if (!contenedor) {
    contenedor = document.createElement('div')
    contenedor.id = 'pc-ticket-impresion'
    document.body.appendChild(contenedor)
  }
  instalarEstiloTicket(opciones)
  contenedor.innerHTML = construirHtmlTicket(datos, opciones)
  await esperarImagenes(contenedor)

  document.body.classList.add('pc-imprimiendo-ticket')
  const limpiar = () => {
    document.body.classList.remove('pc-imprimiendo-ticket')
    window.removeEventListener('afterprint', limpiar)
  }
  window.addEventListener('afterprint', limpiar)
  window.print()
}
