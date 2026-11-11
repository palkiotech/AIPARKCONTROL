import { mensualidadesService } from '@/modules/mensualidades/services/mensualidadesService'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { cajaService } from '@/modules/caja/services/cajaService'

export const dashboardService = {
  /**
   * Obtiene la información agregada para el Dashboard principal (HU-23)
   */
  async obtenerDatosDashboard(parqueaderoId) {
    const [mensualidades, dentro, turno] = await Promise.all([
      mensualidadesService.listarMensualidades(parqueaderoId),
      ocupacionService.obtenerVehiculosDentro(parqueaderoId),
      cajaService.obtenerTurnoActual(parqueaderoId)
    ])

    // 1. Semáforo de vencimientos
    const semaforo = {
      rojo: { count: 0, valor: 0, mensualidades: [] },
      amarillo: { count: 0, valor: 0, vencenHoy: 0, mensualidades: [] },
      verde: { count: 0, valor: 0, mensualidades: [] }
    }

    mensualidades.forEach(m => {
      const v = m.planes_mensuales?.valor || 0
      if (m.clasificacion.color === 'rojo') {
        semaforo.rojo.count++
        semaforo.rojo.valor += v
        semaforo.rojo.mensualidades.push(m)
      } else if (m.clasificacion.color === 'amarillo') {
        semaforo.amarillo.count++
        semaforo.amarillo.valor += v
        if (m.clasificacion.esHoy) semaforo.amarillo.vencenHoy++
        semaforo.amarillo.mensualidades.push(m)
      } else {
        semaforo.verde.count++
        semaforo.verde.valor += v
        semaforo.verde.mensualidades.push(m)
      }
    })

    // 2. Clientes para avisar (Rojo y Amarillo, más urgentes primero)
    const clientesAvisar = [...semaforo.rojo.mensualidades, ...semaforo.amarillo.mensualidades]

    // 3. Resumen de ingresos
    const ingresos = {
      efectivoCaja: turno?.efectivo_esperado || 0,
      baseInicial: turno?.base_inicial || 0,
      porCobrarProximos7Dias: semaforo.amarillo.valor + semaforo.rojo.valor
    }

    return {
      semaforo,
      clientesAvisar,
      ocupacionCount: dentro.length,
      ingresos
    }
  }
}
