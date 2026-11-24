<template>
  <div class="space-y-6 max-w-5xl">
    <div class="flex items-start justify-between gap-3">
      <div class="min-w-0">
        <h2 class="titulo-pagina">Inicio</h2>
        <p class="subtitulo-pagina">Semáforo de cobros, clientes para avisar y ocupación del momento.</p>
      </div>
      <button class="btn-craft-subtle text-sm px-3 sm:px-4 py-2.5 sm:py-2 rounded-lg shrink-0" :disabled="cargando" @click="cargar(true)">
        <svg class="w-4 h-4" :class="cargando ? 'animate-spin' : ''" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
        <span>{{ cargando ? 'Actualizando…' : 'Actualizar' }}</span>
      </button>
    </div>

    <div v-if="error" class="alerta-error" role="alert">
      {{ error }}
    </div>
    <div v-if="aviso.info" class="alerta-aviso">
      {{ aviso.info }}
    </div>

    <div v-if="!datos && cargando" class="vacio py-24">
      <div class="spinner w-8 h-8"></div>
      <span class="text-xs font-medium">Cargando el día…</span>
    </div>

    <template v-if="datos">
      <!-- 1. SEMÁFORO -->
      <div class="grid grid-cols-3 gap-2 md:gap-4">
        <button
          v-for="card in tarjetas"
          :key="card.color"
          type="button"
          class="card-craft card-interactiva p-3 md:p-5 text-left min-w-0"
          :class="[card.clase, filtroColor === card.color ? 'ring-2 ring-offset-2 ring-offset-background ' + card.ring : '']"
          :aria-pressed="filtroColor === card.color"
          @click="filtroColor = filtroColor === card.color ? null : card.color"
        >
          <div class="flex items-center gap-1.5">
            <span class="w-2 h-2 rounded-full shrink-0" :class="card.punto"></span>
            <span class="text-2xs font-semibold uppercase tracking-wider truncate" :class="card.texto">{{ card.titulo }}</span>
          </div>
          <div class="mt-2 flex items-baseline gap-1">
            <span class="text-2xl lg:text-4xl font-semibold tracking-tight num-tabular text-text-primary">{{ card.count }}</span>
            <span class="hidden sm:inline text-xs font-medium text-text-muted">clientes</span>
          </div>
          <p class="text-2xs md:text-xs font-semibold mt-1 num-tabular break-words" :class="card.texto">{{ pesos(card.valor) }}</p>
          <p class="text-2xs md:text-xs text-text-muted mt-0.5">{{ card.detalle }}</p>
        </button>
      </div>

      <!-- 2. CLIENTES PARA AVISAR -->
      <div class="card-craft p-4 md:p-5 space-y-4">
        <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-border pb-3">
          <div>
            <h3 class="titulo-seccion flex items-center gap-2">
              <span>{{ filtroColor === 'verde' ? 'Mensualidades al día' : 'Clientes para avisar' }}</span>
              <span class="badge-neutro text-2xs px-2 py-0.5 rounded-full num-tabular">{{ listaFiltrada.length }}</span>
            </h3>
            <p class="text-xs text-text-muted mt-0.5">Ordenados por fecha de cobro: la más urgente primero.</p>
          </div>
          <label v-if="filtroColor !== 'verde'" class="flex items-center gap-2 py-2 sm:py-0 text-xs font-medium text-text-secondary cursor-pointer select-none">
            <input v-model="soloSinAvisar" type="checkbox" class="rounded w-4 h-4" />
            <span>Solo sin avisar</span>
          </label>
        </div>

        <div v-if="listaFiltrada.length === 0" class="vacio">
          <p class="font-medium text-text-primary">No hay mensualidades en este filtro</p>
          <p v-if="soloSinAvisar && filtroColor !== 'verde'" class="text-xs">Quita "Solo sin avisar" para ver también las ya avisadas.</p>
        </div>

        <ul v-else class="divide-y divide-border-subtle">
          <li v-for="m in listaFiltrada" :key="m.id" class="py-3 flex flex-col md:flex-row md:items-center gap-2 md:gap-4">
            <div class="flex items-start gap-2.5 flex-1 min-w-0">
              <span class="w-2 h-2 rounded-full mt-2 shrink-0" :class="puntoColor(m.clasificacion.color)" :title="textoEstado(m)"></span>
              <div class="min-w-0">
                <p class="text-sm font-semibold text-text-primary truncate">
                  {{ m.clientes?.nombre }} · <span class="font-mono tracking-wide">{{ m.vehiculos?.placa }}</span>
                </p>
                <p class="text-xs text-text-secondary flex flex-wrap gap-x-3">
                  <a v-if="m.clientes?.telefono" :href="`tel:${m.clientes.telefono}`" class="inline-block py-1 text-primary font-medium hover:underline">{{ m.clientes.telefono }}</a>
                  <span class="py-1">{{ textoEstado(m) }} · vence {{ fechaRelativa(m.fecha_fin) }}</span>
                  <span class="py-1 font-semibold num-tabular">{{ pesos(m.planes_mensuales?.valor) }}</span>
                </p>
                <p class="text-2xs break-words" :class="m.ultimoAviso ? 'text-success' : 'text-text-muted'">{{ textoAviso(m) }}</p>
              </div>
            </div>
            <div class="flex gap-2 shrink-0 pl-[1.125rem] md:pl-0">
              <button class="flex-1 md:flex-none btn-craft-subtle text-xs px-3 py-2.5 md:py-1.5 rounded-lg" @click="abrirAviso(m)">Marcar avisado</button>
              <button class="flex-1 md:flex-none btn-craft-primary text-xs px-3 py-2.5 md:py-1.5 rounded-lg" @click="irAPagar(m)">Registrar pago</button>
            </div>
          </li>
        </ul>
      </div>

      <!-- 3. OCUPACIÓN AHORA -->
      <div class="card-craft p-4 md:p-5 space-y-4">
        <div class="flex flex-wrap items-center justify-between gap-2">
          <h3 class="titulo-seccion">Ocupación ahora · <span class="num-tabular">{{ datos.ocupacionCount }}</span> dentro</h3>
          <div class="flex gap-2">
            <router-link to="/registro" class="btn-craft-primary text-xs px-3 py-2.5 sm:py-1.5 rounded-lg">Entrada</router-link>
            <router-link to="/registro" class="btn-craft-subtle text-xs px-3 py-2.5 sm:py-1.5 rounded-lg">Salida</router-link>
          </div>
        </div>
        <div v-if="datos.ocupacionPorTipo.length" class="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 gap-2">
          <div
            v-for="t in datos.ocupacionPorTipo"
            :key="t.id"
            class="rounded-lg border p-3 min-w-0"
            :class="t.sobrecupo || t.ocupados >= t.capacidad ? 'border-warning-border bg-warning-bg' : 'border-border bg-surface-elevated'"
          >
            <p class="rotulo truncate">{{ t.nombre }}</p>
            <p class="mt-1 text-xl font-semibold tracking-tight num-tabular" :class="t.sobrecupo ? 'text-warning' : 'text-text-primary'">
              {{ t.ocupados }}<span class="text-sm font-medium text-text-muted">/{{ t.capacidad }}</span>
            </p>
            <p class="text-2xs text-text-muted">
              {{ t.sobrecupo ? `Sobrecupo +${t.ocupados - t.capacidad}` : `${Math.max(t.capacidad - t.ocupados, 0)} libres` }}
              <span v-if="t.mensualesDentro"> · {{ t.mensualesDentro }} mensuales</span>
            </p>
          </div>
        </div>
        <p v-else class="text-xs text-text-muted">No hay tipos de vehículo configurados.</p>
      </div>

      <!-- 4. SOLO ADMIN -->
      <template v-if="authStore.isAdmin">
        <div v-if="!datos.admin" class="alerta-info">
          Las cifras de ingresos requieren conexión.
        </div>
        <template v-else>
          <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <div class="card-craft p-4 md:p-5 space-y-2">
              <p class="rotulo">Ingresos de hoy</p>
              <p class="text-2xl font-semibold tracking-tight num-tabular break-words">{{ pesos(datos.admin.hoy.total) }}</p>
              <div class="text-xs space-y-1 pt-1">
                <div class="flex justify-between gap-2"><span class="text-text-secondary">Parqueo por hora</span><span class="font-semibold num-tabular">{{ pesos(datos.admin.hoy.porHora) }}</span></div>
                <div class="flex justify-between gap-2"><span class="text-text-secondary">Mensualidades</span><span class="font-semibold num-tabular">{{ pesos(datos.admin.hoy.mensualidades) }}</span></div>
              </div>
            </div>
            <div class="card-craft p-4 md:p-5 space-y-2">
              <p class="rotulo">Hoy por método de pago</p>
              <div v-if="datos.admin.hoy.porMetodo.length" class="text-xs space-y-1">
                <div v-for="mp in datos.admin.hoy.porMetodo" :key="mp.metodo" class="flex justify-between gap-2">
                  <span class="text-text-secondary min-w-0 truncate">{{ mp.metodo }}<span v-if="mp.es_efectivo" class="text-text-muted"> (efectivo)</span></span>
                  <span class="font-semibold num-tabular shrink-0">{{ pesos(mp.total) }}</span>
                </div>
              </div>
              <p v-else class="text-xs text-text-muted">Sin cobros hoy.</p>
            </div>
            <div class="card-craft p-4 md:p-5 space-y-2 sm:col-span-2 lg:col-span-1">
              <p class="rotulo">Por cobrar en 7 días</p>
              <p class="text-2xl font-semibold tracking-tight num-tabular break-words">{{ pesos(datos.porCobrar7Dias) }}</p>
              <p class="text-xs text-text-muted">Vencidas más las que vencen en los próximos 7 días.</p>
            </div>
          </div>

          <div class="card-craft p-4 md:p-5 space-y-3">
            <h3 class="titulo-seccion">Ingresos de los últimos 30 días</h3>
            <div class="flex items-end gap-[2px] h-32 border-b border-border" role="img" :aria-label="`Ingresos de 30 días, máximo ${pesos(max30)}`">
              <div
                v-for="d in datos.admin.ingresos30Dias"
                :key="d.fecha"
                class="flex-1 bg-primary/70 hover:bg-primary transition-colors rounded-t-sm min-h-[2px]"
                :style="{ height: `${max30 ? Math.max(2, (d.total / max30) * 100) : 2}%` }"
                :title="`${formatearFechaCorta(d.fecha)}: ${pesos(d.total)}`"
              ></div>
            </div>
            <div class="flex justify-between gap-2 text-2xs text-text-muted num-tabular">
              <span>{{ formatearFechaCorta(datos.admin.ingresos30Dias[0]?.fecha) }}</span>
              <span>Máx. {{ pesos(max30) }}</span>
              <span>Hoy</span>
            </div>
          </div>

          <div class="card-craft p-4 md:p-5 space-y-3">
            <h3 class="titulo-seccion">Entradas por hora (hoy)</h3>
            <div class="flex items-end gap-[2px] h-24 border-b border-border" role="img" aria-label="Entradas por hora del día">
              <div
                v-for="h in datos.admin.entradasPorHora"
                :key="h.hora"
                class="flex-1 bg-success/70 hover:bg-success transition-colors rounded-t-sm min-h-[2px]"
                :style="{ height: `${maxHora ? Math.max(2, (h.cantidad / maxHora) * 100) : 2}%` }"
                :title="`${String(h.hora).padStart(2, '0')}:00 · ${h.cantidad} entradas`"
              ></div>
            </div>
            <div class="flex justify-between text-2xs text-text-muted num-tabular">
              <span>00 h</span><span>06 h</span><span>12 h</span><span>18 h</span><span>23 h</span>
            </div>
          </div>
        </template>
      </template>
    </template>

    <!-- MODAL MARCAR AVISADO -->
    <div v-if="aviso.abierto" class="modal-fondo" @click.self="aviso.abierto = false">
      <form class="modal-panel max-w-sm" @submit.prevent="guardarAviso">
        <div class="modal-encabezado">
          <div class="min-w-0">
            <h3 class="modal-titulo">Marcar avisado</h3>
            <p class="text-xs text-text-secondary truncate">{{ aviso.m?.clientes?.nombre }} · {{ aviso.m?.vehiculos?.placa }}</p>
          </div>
          <button type="button" class="btn-icono shrink-0" aria-label="Cerrar" @click="aviso.abierto = false">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <div>
          <span class="etiqueta">Medio</span>
          <div class="grid grid-cols-3 gap-2">
            <button
              v-for="op in medios"
              :key="op.valor"
              type="button"
              class="text-xs px-2 py-2.5 rounded-lg border font-medium transition-colors"
              :class="aviso.medio === op.valor ? 'border-primary bg-primary/10 text-primary' : 'border-border text-text-secondary hover:bg-surface-elevated'"
              @click="aviso.medio = op.valor"
            >{{ op.texto }}</button>
          </div>
        </div>
        <div>
          <label for="aviso-nota" class="etiqueta">Nota (opcional)</label>
          <textarea id="aviso-nota" v-model="aviso.nota" rows="2" class="campo"></textarea>
        </div>
        <div v-if="aviso.error" class="alerta-error" role="alert">{{ aviso.error }}</div>
        <div class="flex flex-col-reverse sm:flex-row gap-2 sm:justify-end pt-1">
          <button type="button" class="w-full sm:w-auto btn-craft-subtle text-sm px-4 py-2.5 sm:py-2 rounded-lg" @click="aviso.abierto = false">Cancelar</button>
          <button type="submit" class="w-full sm:w-auto btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg" :disabled="aviso.guardando">
            {{ aviso.guardando ? 'Guardando…' : 'Guardar aviso' }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onActivated, onDeactivated, onBeforeUnmount } from 'vue'
import { useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { dashboardService } from '@/modules/dashboard/services/dashboardService'
import { mensualidadesService } from '@/modules/mensualidades/services/mensualidadesService'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { hoyEnZona, diferenciaDias, formatearFechaHora, formatearFechaCorta } from '@/utils/fecha'

const authStore = useAuthStore()
const router = useRouter()

const datos = ref(dashboardService.obtenerDashboardCache())
const cargando = ref(false)
const error = ref('')
const filtroColor = ref(null)
const soloSinAvisar = ref(true)

const medios = [
  { valor: 'llamada', texto: 'Llamada' },
  { valor: 'en_persona', texto: 'En persona' },
  { valor: 'mensaje', texto: 'Mensaje' }
]
const aviso = ref({ abierto: false, m: null, medio: 'llamada', nota: '', guardando: false, error: '', info: '' })
let temporizadorInfo = null

function pesos(v) {
  return `$${Number(v || 0).toLocaleString('es-CO')}`
}

const tarjetas = computed(() => {
  const s = datos.value?.semaforo
  if (!s) return []
  return [
    {
      color: 'rojo', titulo: 'Vencidas', count: s.rojo.count, valor: s.rojo.valor,
      detalle: 'por cobrar', clase: 'pastel-card-rose', ring: 'ring-danger',
      punto: 'bg-danger', texto: 'text-danger'
    },
    {
      color: 'amarillo', titulo: 'Por vencer', count: s.amarillo.count, valor: s.amarillo.valor,
      detalle: s.amarillo.vencenHoy ? `${s.amarillo.vencenHoy} vencen hoy` : `próximos ${authStore.diasAviso} días`,
      clase: 'pastel-card-amber', ring: 'ring-warning',
      punto: 'bg-warning', texto: 'text-warning'
    },
    {
      color: 'verde', titulo: 'Al día', count: s.verde.count, valor: s.verde.valor,
      detalle: 'sin acción pendiente', clase: 'pastel-card-mint', ring: 'ring-success',
      punto: 'bg-success', texto: 'text-success'
    }
  ]
})

const listaFiltrada = computed(() => {
  if (!datos.value) return []
  if (filtroColor.value === 'verde') return datos.value.semaforo.verde.mensualidades
  let lista = datos.value.clientesAvisar
  if (filtroColor.value) lista = lista.filter(m => m.clasificacion.color === filtroColor.value)
  if (soloSinAvisar.value) lista = lista.filter(m => !m.ultimoAviso)
  return lista
})

const max30 = computed(() => Math.max(0, ...(datos.value?.admin?.ingresos30Dias || []).map(d => d.total)))
const maxHora = computed(() => Math.max(0, ...(datos.value?.admin?.entradasPorHora || []).map(h => h.cantidad)))

function puntoColor(color) {
  return { rojo: 'bg-danger', amarillo: 'bg-warning', verde: 'bg-success' }[color] || 'bg-text-muted'
}

function textoEstado(m) {
  const c = m.clasificacion
  if (c.estado === 'vencida') return `Vencida (${c.diasMora} ${c.diasMora === 1 ? 'día' : 'días'} de mora)`
  if (c.estado === 'por_vencer') return c.esHoy ? 'Vence hoy' : 'Por vencer'
  return 'Al día'
}

function fechaRelativa(fecha) {
  const d = diferenciaDias(fecha, hoyEnZona(authStore.zonaHoraria))
  if (d === 0) return 'hoy'
  if (d === 1) return 'mañana'
  if (d === -1) return 'ayer'
  return d > 0 ? `en ${d} días` : `hace ${-d} días`
}

function textoAviso(m) {
  const a = m.ultimoAviso
  if (!a) return 'Sin avisar'
  const medio = medios.find(x => x.valor === a.medio)?.texto.toLowerCase() || a.medio
  const fecha = formatearFechaHora(a.created_at, authStore.zonaHoraria, { hour: undefined, minute: undefined })
  return `Avisado ${fecha} · ${medio}${a.profiles?.nombre ? ' · ' + a.profiles.nombre : ''}`
}

// Las recargas forzadas (Realtime, botón, tras guardar) pueden solaparse:
// solo la consulta más reciente actualiza la pantalla.
let consultaVigente = 0

async function cargar(forzar = false) {
  const pq = authStore.parqueaderoId
  if (!pq || (cargando.value && !forzar)) return
  const consulta = ++consultaVigente
  cargando.value = true
  error.value = ''
  try {
    const resultado = await dashboardService.obtenerDatosDashboard(pq, {
      diasAviso: authStore.diasAviso,
      zonaHoraria: authStore.zonaHoraria,
      esAdmin: authStore.isAdmin
    })
    if (consulta === consultaVigente) datos.value = resultado
  } catch (e) {
    if (consulta === consultaVigente) error.value = mensajeDeError(e, 'No se pudo cargar el dashboard')
  } finally {
    if (consulta === consultaVigente) cargando.value = false
  }
}

function abrirAviso(m) {
  aviso.value = { abierto: true, m, medio: 'llamada', nota: '', guardando: false, error: '', info: '' }
}

async function guardarAviso() {
  aviso.value.guardando = true
  aviso.value.error = ''
  try {
    const res = await mensualidadesService.registrarAviso({
      mensualidadId: aviso.value.m.id,
      medio: aviso.value.medio,
      nota: aviso.value.nota,
      periodoHasta: aviso.value.m.fecha_fin
    })
    aviso.value.abierto = false
    if (res.offline) {
      aviso.value.info = 'Aviso guardado sin conexión; se sincronizará al volver la red.'
      clearTimeout(temporizadorInfo)
      temporizadorInfo = setTimeout(() => { aviso.value.info = '' }, 6000)
    }
    await cargar(true)
  } catch (e) {
    aviso.value.error = mensajeDeError(e, 'No se pudo registrar el aviso')
  } finally {
    aviso.value.guardando = false
  }
}

function irAPagar(m) {
  router.push({ path: '/mensualidades', query: { pagar: m.id } })
}

// Actualización: Realtime + cada 60 s mientras la vista está activa
let cancelarMens = null
let cancelarPatio = null
let intervalo = null
let debounce = null

function programarRecarga() {
  clearTimeout(debounce)
  debounce = setTimeout(() => cargar(true), 800)
}

function activar() {
  const pq = authStore.parqueaderoId
  if (!pq) return
  if (!cancelarMens) cancelarMens = mensualidadesService.suscribirCambios(pq, programarRecarga)
  if (!cancelarPatio) cancelarPatio = ocupacionService.suscribirCambios(pq, programarRecarga)
  if (!intervalo) intervalo = setInterval(() => cargar(), 60000)
}

function desactivar() {
  if (cancelarMens) { cancelarMens(); cancelarMens = null }
  if (cancelarPatio) { cancelarPatio(); cancelarPatio = null }
  if (intervalo) { clearInterval(intervalo); intervalo = null }
  clearTimeout(debounce)
}

// Con <keep-alive>, onActivated también se dispara justo después del primer montaje
let primeraActivacion = true
onMounted(() => {
  cargar(true)
  activar()
})
onActivated(() => {
  if (primeraActivacion) {
    primeraActivacion = false
    return
  }
  cargar(true)
  activar()
})
onDeactivated(desactivar)
onBeforeUnmount(desactivar)
</script>
