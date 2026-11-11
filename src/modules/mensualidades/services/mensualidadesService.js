import { supabase } from '@/lib/supabase'
import { clasificarEstadoMensualidad } from '@/domain/estadoMensualidad'

// Mock local en caso de correr offline o sin base remota conectada
const mensualidadesLocales = [
  {
    id: 'mens-demo-1',
    fecha_inicio: '2026-10-20',
    fecha_fin: '2026-11-06',
    dia_corte: 20,
    activa: true,
    clientes: { nombre: 'Ana Gómez', documento: '10203040', telefono: '3105550101', email: 'ana@gmail.com' },
    vehiculos: { placa: 'ABC123', marca: 'Mazda', color: 'Rojo' },
    planes_mensuales: { nombre: 'Mensual Carro', valor: 150000, tipo_periodo: 'mensual' },
    avisos: []
  },
  {
    id: 'mens-demo-2',
    fecha_inicio: '2026-10-10',
    fecha_fin: new Date().toISOString().slice(0, 10),
    dia_corte: 10,
    activa: true,
    clientes: { nombre: 'Marta Ruiz', documento: '20304050', telefono: '3125550103', email: 'marta@gmail.com' },
    vehiculos: { placa: 'DEF456', marca: 'Renault', color: 'Gris' },
    planes_mensuales: { nombre: 'Mensual Carro', valor: 150000, tipo_periodo: 'mensual' },
    avisos: []
  },
  {
    id: 'mens-demo-3',
    fecha_inicio: '2026-11-01',
    fecha_fin: new Date(Date.now() + 2 * 24 * 3600000).toISOString().slice(0, 10),
    dia_corte: 1,
    activa: true,
    clientes: { nombre: 'Pedro Díaz', documento: '30405060', telefono: '3135550104', email: 'pedro@gmail.com' },
    vehiculos: { placa: 'GHI789', marca: 'Chevrolet', color: 'Blanco' },
    planes_mensuales: { nombre: 'Mensual Carro', valor: 150000, tipo_periodo: 'mensual' },
    avisos: []
  },
  {
    id: 'mens-demo-4',
    fecha_inicio: '2026-11-05',
    fecha_fin: '2026-12-05',
    dia_corte: 5,
    activa: true,
    clientes: { nombre: 'Carlos Duque', documento: '40506070', telefono: '3145550105', email: 'carlos@gmail.com' },
    vehiculos: { placa: 'JKL012', marca: 'Toyota', color: 'Negro' },
    planes_mensuales: { nombre: 'Mensual Camioneta', valor: 180000, tipo_periodo: 'mensual' },
    avisos: []
  }
]

export const mensualidadesService = {
  /**
   * Lista todas las mensualidades y clasifica su estado según el semáforo (HU-17)
   */
  async listarMensualidades(parqueaderoId) {
    if (!parqueaderoId) return []

    if (typeof navigator !== 'undefined' && navigator.onLine) {
      try {
        const { data, error } = await supabase
          .from('mensualidades')
          .select('*, clientes(nombre, documento, telefono, email), vehiculos(placa, marca, color), planes_mensuales(nombre, valor, tipo_periodo), avisos_mensualidad(medio, nota, created_at)')
          .eq('parqueadero_id', parqueaderoId)
          .eq('activa', true)
          .order('fecha_fin', { ascending: true })

        if (!error && data) {
          return data.map(m => {
            const clasificacion = clasificarEstadoMensualidad({
              fechaFin: m.fecha_fin,
              diasAviso: 5,
              diasGracia: 0
            })
            const ultimoAviso = m.avisos_mensualidad?.[0] || null

            return {
              ...m,
              clasificacion,
              ultimoAviso
            }
          })
        }
      } catch (e) {
        console.warn('Error cargando mensualidades desde Supabase:', e)
      }
    }

    return []
  },

  /**
   * Crea una nueva mensualidad con cliente y vehículo (HU-16)
   */
  async crearMensualidad(datos) {
    try {
      const { data, error } = await supabase.rpc('crear_mensualidad', {
        p_cliente_nombre: datos.nombre.trim(),
        p_cliente_documento: datos.documento.trim(),
        p_cliente_telefono: datos.telefono?.trim() || '',
        p_cliente_email: datos.email?.trim() || '',
        p_placa: datos.placa.trim(),
        p_tipo_vehiculo_id: datos.tipoVehiculoId,
        p_plan_id: datos.planId,
        p_fecha_inicio: datos.fechaInicio,
        p_metodo_pago_id: datos.metodoPagoId,
        p_registrar_primer_pago: !!datos.registrarPrimerPago
      })
      if (error) throw error
      return data
    } catch (err) {
      // Mock local
      const nuevo = {
        id: crypto.randomUUID(),
        fecha_inicio: datos.fechaInicio,
        fecha_fin: datos.fechaInicio, // se extiende
        dia_corte: parseInt(datos.fechaInicio.split('-')[2], 10),
        activa: true,
        clientes: { nombre: datos.nombre, documento: datos.documento, telefono: datos.telefono, email: datos.email },
        vehiculos: { placa: datos.placa },
        planes_mensuales: { nombre: 'Plan', valor: 150000 },
        avisos: []
      }
      mensualidadesLocales.push(nuevo)
      return { success: true, mensualidad_id: nuevo.id }
    }
  },

  /**
   * Registra el pago y extiende la vigencia (HU-18)
   */
  async registrarPago({ mensualidadId, metodoPagoId, valor }) {
    try {
      const { data, error } = await supabase.rpc('registrar_pago_mensualidad', {
        p_mensualidad_id: mensualidadId,
        p_metodo_pago_id: metodoPagoId,
        p_valor: valor
      })
      if (error) throw error
      return data
    } catch (err) {
      const item = mensualidadesLocales.find(m => m.id === mensualidadId)
      if (item) {
        // Extender 30 días en local
        const d = new Date(item.fecha_fin)
        d.setDate(d.getDate() + 30)
        item.fecha_fin = d.toISOString().slice(0, 10)
      }
      return { success: true }
    }
  },

  /**
   * Registra un aviso de cobro (HU-19)
   */
  async registrarAviso({ mensualidadId, medio, nota = '' }) {
    try {
      const { data, error } = await supabase.rpc('registrar_aviso_mensualidad', {
        p_mensualidad_id: mensualidadId,
        p_medio: medio,
        p_nota: nota
      })
      if (error) throw error
      return data
    } catch (err) {
      const item = mensualidadesLocales.find(m => m.id === mensualidadId)
      if (item) {
        item.avisos = [{ medio, nota, created_at: new Date().toISOString() }]
      }
      return { success: true }
    }
  }
}
