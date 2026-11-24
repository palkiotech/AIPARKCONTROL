import { supabase } from '@/lib/supabase'
import { mensualidadesService } from '@/modules/mensualidades/services/mensualidadesService'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { ajustesService } from '@/modules/ajustes/services/ajustesService'
import { registrarLimpieza, estaEnLinea } from '@/lib/sesionCaches'
import { hoyEnZona, sumarDias, rangoDiaUtc, fechaEnZona, partesEnZona } from '@/utils/fecha'

let cacheDashboard = null
registrarLimpieza(() => { cacheDashboard = null })

// El patio lo mantiene al día Realtime; solo se vuelve a pedir si la copia es vieja
const EDAD_MAXIMA_PATIO = 10 * 60 * 1000

// Ocupación por tipo (la capacidad informa, no bloquea)
function calcularOcupacionPorTipo(tipos, dentro) {
  return tipos.filter(t => t.activo !== false).map(t => {
    const delTipo = dentro.filter(v => v.tipo_vehiculo_id === t.id)
    return {
      id: t.id,
      nombre: t.nombre,
      capacidad: t.capacidad,
      ocupados: delTipo.length,
      mensualesDentro: delTipo.filter(v => v.es_mensual).length,
      sobrecupo: delTipo.length > t.capacidad
    }
  })
}

/**
 * Dashboard (HU-23): semáforo, clientes para avisar, ocupación por tipo y,
 * solo para el admin, ingresos del día y gráficas.
 */
export const dashboardService = {
  obtenerDashboardCache() {
    return cacheDashboard
  },

  async obtenerDatosDashboard(parqueaderoId, { diasAviso = 5, zonaHoraria = 'America/Bogota', esAdmin = false } = {}) {
    const [mensualidades, dentro, tipos] = await Promise.all([
      mensualidadesService.listarMensualidades(parqueaderoId, { diasAviso, zonaHoraria }),
      ocupacionService.obtenerVehiculosDentro(parqueaderoId, { edadMaxima: EDAD_MAXIMA_PATIO }),
      ajustesService.listarTiposVehiculo(parqueaderoId).catch(() => [])
    ])

    // 1. Semáforo
    const semaforo = {
      rojo: { count: 0, valor: 0, mensualidades: [] },
      amarillo: { count: 0, valor: 0, vencenHoy: 0, mensualidades: [] },
      verde: { count: 0, valor: 0, mensualidades: [] }
    }
    for (const m of mensualidades) {
      const color = m.clasificacion.color
      const grupo = semaforo[color]
      grupo.count++
      grupo.valor += m.planes_mensuales?.valor || 0
      grupo.mensualidades.push(m)
      if (color === 'amarillo' && m.clasificacion.esHoy) grupo.vencenHoy++
    }

    // 2. Clientes para avisar: vencidas y por vencer, la más urgente primero
    const clientesAvisar = [...semaforo.rojo.mensualidades, ...semaforo.amarillo.mensualidades]
      .sort((a, b) => a.fecha_fin.localeCompare(b.fecha_fin))

    // 3. Ocupación por tipo
    const ocupacionPorTipo = calcularOcupacionPorTipo(tipos, dentro)

    // 4. Total por cobrar en los próximos 7 días: lo pendiente (vencidas) más lo
    //    que vence desde hoy hasta hoy + 7
    const limite7 = sumarDias(hoyEnZona(zonaHoraria), 7)
    const porCobrar7Dias = mensualidades
      .filter(m => m.fecha_fin <= limite7)
      .reduce((s, m) => s + (m.planes_mensuales?.valor || 0), 0)

    const resultado = {
      semaforo,
      clientesAvisar,
      ocupacionCount: dentro.length,
      ocupacionPorTipo,
      porCobrar7Dias,
      admin: null
    }

    if (esAdmin && estaEnLinea()) {
      resultado.admin = await this.obtenerCifrasAdmin(parqueaderoId, zonaHoraria).catch(e => {
        console.warn('No se pudieron cargar las cifras del admin:', e)
        return null
      })
    }

    cacheDashboard = resultado
    return resultado
  },

  /**
   * Recalcula solo la ocupación con la copia local del patio (sin consultar el
   * servidor). Se usa con cada entrada o salida que llega por Realtime.
   */
  async actualizarOcupacion(parqueaderoId, datos) {
    if (!datos) return datos
    const dentro = ocupacionService.obtenerVehiculosDentroCache() || []
    const tipos = await ajustesService.listarTiposVehiculo(parqueaderoId).catch(() => [])
    cacheDashboard = { ...datos, ocupacionCount: dentro.length, ocupacionPorTipo: calcularOcupacionPorTipo(tipos, dentro) }
    return cacheDashboard
  },

  /** Vuelve a pedir solo las cifras del admin (ingresos y entradas por hora). */
  async actualizarCifrasAdmin(parqueaderoId, zonaHoraria, datos) {
    if (!datos || !estaEnLinea()) return datos
    const admin = await this.obtenerCifrasAdmin(parqueaderoId, zonaHoraria)
    cacheDashboard = { ...datos, admin }
    return cacheDashboard
  },

  /**
   * Cifras solo para el admin: ingresos de hoy por origen y método, ingresos de
   * los últimos 30 días y entradas por hora del día de hoy.
   */
  async obtenerCifrasAdmin(parqueaderoId, zonaHoraria) {
    const hoy = hoyEnZona(zonaHoraria)
    const desde30 = sumarDias(hoy, -29)

    const [{ data: reporteHoy, error: e1 }, { data: reporte30, error: e2 }] = await Promise.all([
      supabase.rpc('obtener_reporte_ingresos', { p_fecha_desde: hoy, p_fecha_hasta: hoy }),
      supabase.rpc('obtener_reporte_ingresos', { p_fecha_desde: desde30, p_fecha_hasta: hoy })
    ])
    if (e1) throw e1
    if (e2) throw e2

    // Serie de 30 días completa (días sin ingresos en 0)
    const porDia = new Map((reporte30?.por_dia || []).map(d => [d.fecha, d.total]))
    const ingresos30Dias = Array.from({ length: 30 }, (_, i) => {
      const fecha = sumarDias(desde30, i)
      return { fecha, total: porDia.get(fecha) || 0 }
    })

    // Entradas por hora de hoy
    const { desde, hasta } = rangoDiaUtc(hoy, zonaHoraria)
    const { data: entradas, error: e3 } = await supabase
      .from('registros')
      .select('entrada_at')
      .eq('parqueadero_id', parqueaderoId)
      .neq('estado', 'anulado')
      .gte('entrada_at', desde)
      .lt('entrada_at', hasta)
    if (e3) throw e3
    const entradasPorHora = Array.from({ length: 24 }, (_, h) => ({ hora: h, cantidad: 0 }))
    for (const r of entradas || []) {
      if (fechaEnZona(r.entrada_at, zonaHoraria) === hoy) {
        entradasPorHora[partesEnZona(r.entrada_at, zonaHoraria).hora].cantidad++
      }
    }

    return {
      hoy: {
        total: reporteHoy?.gran_total || 0,
        porHora: reporteHoy?.total_hora || 0,
        mensualidades: reporteHoy?.total_mensualidades || 0,
        porMetodo: reporteHoy?.por_metodo || []
      },
      ingresos30Dias,
      entradasPorHora
    }
  }
}
