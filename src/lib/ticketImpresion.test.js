import { describe, it, expect } from 'vitest'
import { construirHtmlTicket, textoTarifa, referenciaTicket, cssPagina } from '@/lib/ticketImpresion'

const base = {
  parqueadero: { nombre: 'Parqueadero Demo', nit: '900123456-7', direccion: 'Calle 10 # 20-30', telefono: '3001234567', texto_pie_comprobante: 'Gracias por su visita' },
  placa: 'ABC123',
  tipoNombre: 'Carro',
  entradaTexto: '24 de nov de 2026, 05:01 p. m.',
  tarifaTexto: 'Carro por hora · $3.000 por hora',
  referencia: 'A1B2C3D4',
  qr: 'data:image/png;base64,AAAA'
}

describe('construirHtmlTicket', () => {
  it('formato hoja: recuadro para recortar con placa, datos, QR y pie', () => {
    const html = construirHtmlTicket(base, { formato: 'hoja' })
    expect(html).toContain('pc-ticket--hoja')
    expect(html).toContain('ABC123')
    expect(html).toContain('NIT 900123456-7')
    expect(html).toContain('Tel. 3001234567')
    expect(html).toContain('A1B2C3D4')
    expect(html).toContain('pc-ticket__qr')
    expect(html).toContain('Gracias por su visita')
    expect(html).toContain('Recorte por la línea punteada')
  })

  it('formato térmico: ancho del rollo y sin línea de recorte', () => {
    const html = construirHtmlTicket(base, { formato: 'termica', ancho: 58 })
    expect(html).toContain('pc-ticket--termica')
    expect(html).toContain('width:54mm')
    expect(html).not.toContain('Recorte')
  })

  it('escapa lo que escribe el usuario (nombre, pie, placa)', () => {
    const html = construirHtmlTicket({ ...base, placa: '<b>X</b>', parqueadero: { nombre: 'A & B <script>' } })
    expect(html).not.toContain('<script>')
    expect(html).toContain('A &amp; B &lt;script&gt;')
    expect(html).toContain('&lt;b&gt;X&lt;/b&gt;')
  })

  it('omite filas y datos vacíos', () => {
    const html = construirHtmlTicket({ placa: 'XYZ98F', parqueadero: { nombre: 'P' } })
    expect(html).not.toContain('Tarifa')
    expect(html).not.toContain('NIT')
    expect(html).not.toContain('pc-ticket__qr')
  })
})

describe('utilidades del ticket', () => {
  it('textoTarifa describe la modalidad', () => {
    expect(textoTarifa({ nombre: 'Carro por hora', valor: 3000, modalidad: 'por_hora' })).toBe('Carro por hora · $3.000 por hora')
    expect(textoTarifa({ nombre: 'Moto', valor: 500, modalidad: 'por_fraccion', minutos_fraccion: 15 })).toBe('Moto · $500 por fracción de 15 min')
    expect(textoTarifa(null)).toBe('')
  })

  it('referenciaTicket toma 8 caracteres del id en mayúsculas', () => {
    expect(referenciaTicket('a1b2c3d4-e5f6-4a1b-8c2d-123456789abc')).toBe('A1B2C3D4')
  })

  it('cssPagina: rollo con ancho fijo, hoja con el papel del diálogo', () => {
    expect(cssPagina({ formato: 'termica', ancho: 80 })).toContain('size: 80mm auto')
    expect(cssPagina({ formato: 'hoja' })).not.toContain('size')
  })
})
