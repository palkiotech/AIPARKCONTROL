import { ref, computed, onMounted, onUnmounted, onActivated, onDeactivated } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { ajustesService, invalidarCacheCatalogos } from '@/modules/ajustes/services/ajustesService'
import { cajaService } from '@/modules/caja/services/cajaService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { calcularCobroConFranja, resolverTarifas } from '@/domain/cobro'
import { formatearFechaHora } from '@/utils/fecha'

/**
 * Estado del patio compartido por Ocupación y Registro y cobro: catálogos,
 * vehículos dentro, turno, refresco periódico y Realtime. Cada vista tiene su
 * propia instancia; los servicios mantienen la caché común.
 */
// Respaldo por si Realtime pierde eventos; lo normal es que llegue cada cambio al instante
export const INTERVALO_REFRESCO = 10 * 60 * 1000

export function usePatio() {
  const authStore = useAuthStore()
  const zona = computed(() => authStore.zonaHoraria)

  const tipos = ref([])
  const tarifas = ref([])
  const metodos = ref([])
  const vehiculosDentro = ref(ocupacionService.obtenerVehiculosDentroCache() || [])
  const turno = ref(null)
  const cargando = ref(!ocupacionService.obtenerVehiculosDentroCache())
  const errorMensaje = ref('')
  const ahora = ref(Date.now())

  // ---------- Presentación ----------
  function pesos(v) {
    return `$${Number(v || 0).toLocaleString('es-CO')}`
  }
  function formatearHora(iso) {
    return formatearFechaHora(iso, zona.value, { day: undefined, month: undefined })
  }
  function formatearDuracion(min) {
    const m = Math.max(0, Math.round(min || 0))
    if (m < 60) return `${m} min`
    const h = Math.floor(m / 60)
    const r = m % 60
    return r === 0 ? `${h}h` : `${h}h ${r}m`
  }
  function minutosTranscurridos(iso) {
    return Math.max(0, Math.floor((ahora.value - new Date(iso).getTime()) / 60000))
  }
  function nombreTipo(v) {
    return v?.tipos_vehiculo?.nombre || tipos.value.find(t => t.id === v?.tipo_vehiculo_id)?.nombre || ''
  }
  function clasePlaca(n) {
    const nombre = (n || '').toLowerCase()
    if (nombre.includes('moto')) return 'plate-moto'
    if (nombre.includes('bici')) return 'plate-bici'
    return 'plate-carro'
  }
  function nombreModalidad(m) {
    return { por_minuto: 'por minuto', por_hora: 'por hora', por_fraccion: 'por fracción', plena: 'plena' }[m] || m
  }

  // ---------- Derivados ----------
  const tiposActivos = computed(() => tipos.value.filter(t => t.activo !== false))
  const metodosActivos = computed(() => metodos.value.filter(m => m.activo !== false).sort((a, b) => (a.orden || 0) - (b.orden || 0)))
  const turnoAbierto = computed(() => turno.value?.estado === 'abierto')

  function tarifasGeneralesDe(tipoId) {
    return tarifas.value.filter(t => t.tipo_vehiculo_id === tipoId && t.activa !== false && !t.franja_inicio)
  }
  // Solo se registran entradas de tipos con al menos una tarifa general activa
  const tiposConTarifa = computed(() => tiposActivos.value.filter(t => tarifasGeneralesDe(t.id).length > 0))

  function ocupadosTipo(tipoId) {
    return vehiculosDentro.value.filter(v => v.tipo_vehiculo_id === tipoId).length
  }

  const resumenOcupacion = computed(() => tiposActivos.value.map(t => {
    const delTipo = vehiculosDentro.value.filter(v => v.tipo_vehiculo_id === t.id)
    return {
      id: t.id,
      nombre: t.nombre,
      capacidad: t.capacidad || 0,
      ocupados: delTipo.length,
      mensualesDentro: delTipo.filter(v => v.es_mensual).length
    }
  }))

  // Estimación local (el valor definitivo lo calcula el servidor al salir)
  const estimaciones = computed(() => {
    const mapa = {}
    for (const v of vehiculosDentro.value) {
      if (v.es_mensual) { mapa[v.id] = 0; continue }
      try {
        const delTipo = tarifas.value.filter(t => t.tipo_vehiculo_id === v.tipo_vehiculo_id)
        const { general, nocturna } = resolverTarifas(delTipo.length ? delTipo : [v.tarifas].filter(Boolean), v.tarifa_id)
        if (!general) { mapa[v.id] = null; continue }
        const entrada = new Date(v.entrada_at).getTime()
        mapa[v.id] = calcularCobroConFranja({
          entradaAt: v.entrada_at,
          salidaAt: new Date(Math.max(ahora.value, entrada)),
          tarifaGeneral: general,
          tarifaNocturna: nocturna,
          zonaHoraria: zona.value
        }).valorTotal
      } catch (e) {
        mapa[v.id] = null
      }
    }
    return mapa
  })

  function textoEstimado(v) {
    if (v.es_mensual) return 'Mensual · $0'
    const e = estimaciones.value[v.id]
    return e === null || e === undefined ? '—' : pesos(e)
  }

  // ---------- Carga ----------
  // Realtime mantiene el patio y el turno al día; la consulta completa solo se
  // repite cada 10 min como respaldo, al reconectar o al volver a una vista
  // que quedó con cambios pendientes.
  let cargaEnCurso = null
  let ultimaCargaCompleta = 0
  async function cargarDatos({ catalogosFrescos = false } = {}) {
    const pqId = authStore.parqueaderoId
    if (!pqId) return
    if (cargaEnCurso) return cargaEnCurso
    if (catalogosFrescos) invalidarCacheCatalogos(pqId)
    cargaEnCurso = (async () => {
      try {
        const [t, ta, m, dentro, tu] = await Promise.all([
          ajustesService.listarTiposVehiculo(pqId),
          ajustesService.listarTarifas(pqId),
          ajustesService.listarMetodosPago(pqId),
          ocupacionService.obtenerVehiculosDentro(pqId),
          cajaService.obtenerTurnoActual(pqId)
        ])
        tipos.value = t
        tarifas.value = ta
        metodos.value = m
        vehiculosDentro.value = dentro
        turno.value = tu
        errorMensaje.value = ''
        ultimaCargaCompleta = Date.now()
        pendiente = false
      } catch (err) {
        errorMensaje.value = mensajeDeError(err, 'No se pudo cargar el patio')
      } finally {
        cargando.value = false
        ahora.value = Date.now()
        cargaEnCurso = null
      }
    })()
    return cargaEnCurso
  }

  async function refrescarTurno() {
    try {
      turno.value = await cajaService.obtenerTurnoActual(authStore.parqueaderoId)
    } catch (e) {
      // Se conserva el último estado conocido
    }
    return turno.value
  }

  function quitarDelPatio(registroId) {
    vehiculosDentro.value = vehiculosDentro.value.filter(v => v.id !== registroId)
  }
  function tomarPatioDeCache() {
    vehiculosDentro.value = ocupacionService.obtenerVehiculosDentroCache() || vehiculosDentro.value
  }

  // ---------- Realtime y refresco ----------
  let activa = false
  let pendiente = false
  let temporizadorTurno = null

  function alCambiarPatio(payload) {
    if (payload.reconectado) {
      // Pudo perder eventos mientras estuvo desconectado
      if (activa) cargarDatos()
      else pendiente = true
      return
    }
    // El servicio ya aplicó el cambio a la caché: no se consulta el servidor
    tomarPatioDeCache()
  }

  function alCambiarTurno() {
    if (!activa) { pendiente = true; return }
    clearTimeout(temporizadorTurno)
    temporizadorTurno = setTimeout(refrescarTurno, 400)
  }

  let intervalo = null
  let intervaloReloj = null
  function iniciarRefresco() {
    detenerRefresco()
    intervalo = setInterval(cargarDatos, INTERVALO_REFRESCO)
    intervaloReloj = setInterval(() => { ahora.value = Date.now() }, 30000)
  }
  function detenerRefresco() {
    clearInterval(intervalo)
    clearInterval(intervaloReloj)
    intervalo = null
    intervaloReloj = null
  }

  const cancelaciones = []
  onMounted(() => {
    activa = true
    cargarDatos()
    iniciarRefresco()
    cancelaciones.push(ocupacionService.suscribirCambios(authStore.parqueaderoId, alCambiarPatio))
    cancelaciones.push(cajaService.suscribirCambios(authStore.parqueaderoId, alCambiarTurno))
  })
  // keep-alive: onActivated también corre tras el primer montaje
  onActivated(() => {
    activa = true
    tomarPatioDeCache()
    ahora.value = Date.now()
    if (pendiente || Date.now() - ultimaCargaCompleta > INTERVALO_REFRESCO) cargarDatos()
    iniciarRefresco()
  })
  onDeactivated(() => {
    activa = false
    detenerRefresco()
  })
  onUnmounted(() => {
    activa = false
    detenerRefresco()
    clearTimeout(temporizadorTurno)
    for (const cancelar of cancelaciones) cancelar()
  })

  return {
    authStore,
    zona,
    tipos,
    tarifas,
    metodos,
    vehiculosDentro,
    turno,
    cargando,
    errorMensaje,
    ahora,
    pesos,
    formatearHora,
    formatearDuracion,
    minutosTranscurridos,
    nombreTipo,
    clasePlaca,
    nombreModalidad,
    tiposActivos,
    tiposConTarifa,
    metodosActivos,
    turnoAbierto,
    tarifasGeneralesDe,
    ocupadosTipo,
    resumenOcupacion,
    estimaciones,
    textoEstimado,
    cargarDatos,
    refrescarTurno,
    quitarDelPatio,
    tomarPatioDeCache
  }
}
