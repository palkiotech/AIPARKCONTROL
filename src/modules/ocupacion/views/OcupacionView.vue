<template>
  <div class="space-y-6">
    <!-- Encabezado -->
    <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4">
      <div>
        <h2 class="titulo-pagina">Ocupación</h2>
        <p class="subtitulo-pagina">Estado actual del parqueadero: cupos, vehículos dentro y tiempo de permanencia.</p>
      </div>
      <router-link :to="{ name: 'registro' }" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg">
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" /></svg>
        <span>Registrar o cobrar</span>
      </router-link>
    </div>

    <!-- Feedback -->
    <div v-if="mensajeExito" class="alerta-exito">{{ mensajeExito }}</div>
    <div v-if="errorMensaje" class="alerta-error" role="alert">{{ errorMensaje }}</div>
    <div v-if="!conexionStore.isOnline" class="alerta-aviso">
      Sin conexión: se muestra la última información guardada en este dispositivo.
    </div>

    <!-- Resumen general -->
    <div class="grid grid-cols-2 lg:grid-cols-4 gap-2 sm:gap-4">
      <div class="card-craft px-3.5 py-3 sm:p-5">
        <p class="rotulo">Vehículos dentro</p>
        <p class="mt-1 text-2xl sm:text-3xl font-semibold tracking-tight num-tabular text-text-primary">{{ totales.ocupados }}</p>
      </div>
      <div class="card-craft px-3.5 py-3 sm:p-5">
        <p class="rotulo">Cupos libres</p>
        <p class="mt-1 text-2xl sm:text-3xl font-semibold tracking-tight num-tabular" :class="totales.libres > 0 ? 'text-success' : 'text-danger'">
          {{ totales.libres }}<span class="text-sm font-normal text-text-muted"> / {{ totales.capacidad }}</span>
        </p>
      </div>
      <div class="card-craft px-3.5 py-3 sm:p-5">
        <p class="rotulo">Mensuales dentro</p>
        <p class="mt-1 text-2xl sm:text-3xl font-semibold tracking-tight num-tabular text-text-primary">{{ totales.mensuales }}</p>
      </div>
      <div class="card-craft px-3.5 py-3 sm:p-5">
        <p class="rotulo">Por cobrar (estimado)</p>
        <p class="mt-1 text-2xl sm:text-3xl font-semibold tracking-tight num-tabular text-text-primary truncate">{{ pesos(totales.estimado) }}</p>
      </div>
    </div>

    <!-- Ocupación por tipo (HU-12) -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2 sm:gap-4">
      <div
        v-for="tipo in resumenOcupacion"
        :key="tipo.id"
        class="card-craft px-3.5 py-3 sm:p-5"
        :class="tipo.ocupados > tipo.capacidad ? 'pastel-card-amber' : ''"
      >
        <div class="flex justify-between items-center sm:items-start gap-2">
          <div class="flex items-center gap-2 min-w-0">
            <span class="w-8 h-8 rounded-lg bg-surface-elevated border border-border flex items-center justify-center text-text-secondary shrink-0">
              <IconoVehiculo :nombre="tipo.nombre" clase="w-4 h-4" />
            </span>
            <span class="text-sm font-semibold text-text-primary truncate">{{ tipo.nombre }}</span>
            <span class="sm:hidden text-sm num-tabular shrink-0" :class="tipo.ocupados > tipo.capacidad ? 'text-warning font-semibold' : 'text-text-secondary'">
              <span class="font-semibold text-text-primary" :class="tipo.ocupados > tipo.capacidad ? 'text-warning' : ''">{{ tipo.ocupados }}</span>/{{ tipo.capacidad }}
            </span>
          </div>
          <span
            class="text-2xs px-2 py-0.5 rounded-full shrink-0"
            :class="tipo.ocupados > tipo.capacidad ? 'badge-pastel-amber' : (tipo.ocupados === tipo.capacidad ? 'badge-pastel-rose' : 'badge-pastel-mint')"
          >
            {{ tipo.ocupados > tipo.capacidad ? `Sobrecupo +${tipo.ocupados - tipo.capacidad}` : (tipo.ocupados === tipo.capacidad ? 'Lleno' : `${tipo.capacidad - tipo.ocupados} libres`) }}
          </span>
        </div>

        <div class="mt-4 hidden sm:flex items-baseline gap-1.5">
          <span class="text-3xl font-semibold tracking-tight num-tabular" :class="tipo.ocupados > tipo.capacidad ? 'text-warning' : 'text-text-primary'">{{ tipo.ocupados }}</span>
          <span class="text-sm text-text-muted">/ {{ tipo.capacidad }} cupos</span>
        </div>
        <p class="mt-0.5 hidden sm:block text-xs text-text-secondary">
          {{ tipo.mensualesDentro }} mensual(es) dentro
          <span v-if="!tarifasGeneralesDe(tipo.id).length" class="text-warning font-medium"> · sin tarifa activa</span>
        </p>

        <div class="mt-2.5 sm:mt-3 w-full bg-border h-1.5 rounded-full overflow-hidden">
          <div
            class="h-full rounded-full transition-all duration-500"
            :class="tipo.ocupados > tipo.capacidad ? 'bg-warning' : (tipo.ocupados === tipo.capacidad ? 'bg-danger' : 'bg-success')"
            :style="{ width: Math.min(100, Math.round((tipo.ocupados / (tipo.capacidad || 1)) * 100)) + '%' }"
          ></div>
        </div>
      </div>
      <div v-if="!cargando && resumenOcupacion.length === 0" class="card-craft p-4 text-sm text-text-muted sm:col-span-2 lg:col-span-3">
        No hay tipos de vehículo activos. Un administrador debe configurarlos en Ajustes.
      </div>
    </div>

    <!-- Lista de vehículos dentro -->
    <div class="card-craft overflow-hidden">
      <div class="flex flex-col lg:flex-row lg:items-center justify-between gap-3 p-4 sm:px-5 border-b border-border">
        <div>
          <h3 class="titulo-seccion flex items-center gap-2">
            <span>Vehículos en patio</span>
            <span class="badge-neutro text-2xs px-2 py-0.5 rounded-full num-tabular">{{ vehiculosDentro.length }}</span>
          </h3>
          <p class="text-xs text-text-muted mt-0.5">El valor es una estimación; el cobro final lo calcula el servidor.</p>
        </div>
        <div class="flex flex-col sm:flex-row gap-2 w-full lg:w-auto">
          <div class="relative w-full sm:w-56">
            <svg class="w-4 h-4 absolute left-2.5 top-1/2 -translate-y-1/2 text-text-muted pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-4.35-4.35M17 11a6 6 0 11-12 0 6 6 0 0112 0z" />
            </svg>
            <input
              v-model="filtroPlaca"
              type="text"
              autocomplete="off"
              autocapitalize="characters"
              spellcheck="false"
              aria-label="Buscar por placa"
              placeholder="Buscar por placa..."
              class="campo pl-8 uppercase font-mono tracking-wider"
            />
          </div>
          <select v-model="filtroTipo" aria-label="Filtrar por tipo de vehículo" class="campo sm:w-44">
            <option value="">Todos los tipos</option>
            <option v-for="t in tiposActivos" :key="t.id" :value="t.id">{{ t.nombre }}</option>
          </select>
          <select v-model="orden" aria-label="Ordenar vehículos" class="campo sm:w-44">
            <option value="recientes">Más recientes</option>
            <option value="antiguos">Más tiempo dentro</option>
          </select>
        </div>
      </div>

      <div v-if="cargando" class="vacio">
        <div class="spinner"></div>
        <span>Consultando vehículos en patio...</span>
      </div>

      <div v-else-if="vehiculosFiltrados.length === 0" class="vacio py-12">
        <div class="w-11 h-11 rounded-full bg-surface-elevated border border-border flex items-center justify-center text-text-muted">
          <IconoVehiculo nombre="carro" clase="w-5 h-5" />
        </div>
        <p class="font-medium text-text-primary">{{ vehiculosDentro.length ? 'No hay vehículos dentro con ese criterio' : 'El patio está vacío' }}</p>
      </div>

      <template v-else>
        <!-- Tabla (escritorio) -->
        <div class="hidden sm:block overflow-x-auto">
          <table class="tabla">
            <thead>
              <tr>
                <th>Placa</th>
                <th>Tipo</th>
                <th>Entrada</th>
                <th>Tiempo</th>
                <th class="text-right">Est. cobro</th>
                <th class="text-right">Acción</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="v in vehiculosFiltrados" :key="v.id">
                <td>
                  <div class="flex items-center flex-wrap gap-1.5">
                    <span class="plate-colombia text-xs" :class="clasePlaca(nombreTipo(v))">{{ v.placa }}</span>
                    <span v-if="v.es_mensual" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-mint">Mensual</span>
                    <span v-if="v.pendiente_sync" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-amber">Pendiente de sincronizar</span>
                  </div>
                </td>
                <td class="text-text-secondary">
                  <span class="inline-flex items-center gap-1.5">
                    <IconoVehiculo :nombre="nombreTipo(v)" clase="w-4 h-4 text-text-muted" />
                    {{ nombreTipo(v) || 'Vehículo' }}
                  </span>
                </td>
                <td class="text-text-secondary num-tabular">{{ formatearHora(v.entrada_at) }}</td>
                <td class="text-text-secondary num-tabular">{{ formatearDuracion(minutosTranscurridos(v.entrada_at)) }}</td>
                <td class="text-right font-semibold text-text-primary num-tabular">{{ textoEstimado(v) }}</td>
                <td class="text-right whitespace-nowrap space-x-2">
                  <button
                    v-if="authStore.isAdmin && !v.pendiente_sync"
                    @click="abrirAnular(v)"
                    class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg text-danger"
                  >
                    Anular
                  </button>
                  <button @click="irACobrar(v)" class="btn-craft-primary text-xs px-3 py-1.5 rounded-lg">
                    {{ v.es_mensual ? 'Dar salida' : 'Cobrar' }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Tarjetas (celular) -->
        <div class="sm:hidden divide-y divide-border-subtle">
          <div v-for="v in vehiculosFiltrados" :key="v.id" class="p-4 space-y-2.5">
            <div class="flex items-center justify-between gap-2 min-w-0">
              <span class="plate-colombia text-sm shrink-0" :class="clasePlaca(nombreTipo(v))">{{ v.placa }}</span>
              <span class="font-semibold text-sm text-text-primary num-tabular truncate">{{ textoEstimado(v) }}</span>
            </div>
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-text-secondary">
              <span class="inline-flex items-center gap-1">
                <IconoVehiculo :nombre="nombreTipo(v)" clase="w-3.5 h-3.5 text-text-muted" />
                {{ nombreTipo(v) }}
              </span>
              <span class="num-tabular">· {{ formatearHora(v.entrada_at) }}</span>
              <span class="num-tabular">· {{ formatearDuracion(minutosTranscurridos(v.entrada_at)) }}</span>
              <span v-if="v.es_mensual" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-mint">Mensual</span>
              <span v-if="v.pendiente_sync" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-amber">Pendiente de sincronizar</span>
            </div>
            <div class="flex gap-2">
              <button @click="irACobrar(v)" class="flex-1 btn-craft-primary text-sm px-4 py-2.5 rounded-lg">
                {{ v.es_mensual ? 'Dar salida' : 'Cobrar' }}
              </button>
              <button
                v-if="authStore.isAdmin && !v.pendiente_sync"
                @click="abrirAnular(v)"
                class="btn-craft-subtle text-sm px-4 py-2.5 rounded-lg text-danger"
              >
                Anular
              </button>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- MODAL ANULAR (HU-15) -->
    <div v-if="anular.abierto" class="modal-fondo">
      <form @submit.prevent="confirmarAnular" class="modal-panel max-w-sm space-y-3">
        <div class="modal-encabezado">
          <h3 class="modal-titulo min-w-0 break-words">Anular registro {{ anular.registro?.placa }}</h3>
          <button type="button" @click="anular.abierto = false" class="btn-icono shrink-0" aria-label="Cerrar">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <p class="text-sm text-text-secondary">El registro no se borra: queda anulado con el motivo y tu usuario.</p>
        <div>
          <label for="anular-motivo" class="etiqueta">Motivo</label>
          <textarea id="anular-motivo" v-model="anular.motivo" rows="3" placeholder="Motivo (mínimo 10 caracteres)" class="campo"></textarea>
          <p class="text-xs text-text-muted mt-1 num-tabular">{{ anular.motivo.trim().length }}/10 caracteres mínimos</p>
        </div>
        <p v-if="anular.error" class="alerta-error" role="alert">{{ anular.error }}</p>
        <div class="flex flex-col-reverse sm:flex-row gap-2">
          <button type="button" @click="anular.abierto = false" class="flex-1 btn-craft-subtle text-sm px-4 py-2.5 sm:py-2 rounded-lg">Cancelar</button>
          <button type="submit" :disabled="anular.motivo.trim().length < 10 || anular.guardando" class="flex-1 btn-craft-danger text-sm px-4 py-2.5 sm:py-2 rounded-lg">
            {{ anular.guardando ? 'Anulando...' : 'Anular' }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed } from 'vue'
import { useRouter } from 'vue-router'
import { useConexionStore } from '@/stores/conexion'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { normalizarPlaca } from '@/utils/placa'
import { usePatio } from '@/modules/ocupacion/composables/usePatio'
import IconoVehiculo from '@/components/IconoVehiculo.vue'

const router = useRouter()
const conexionStore = useConexionStore()
const {
  authStore, vehiculosDentro, cargando, errorMensaje,
  pesos, formatearHora, formatearDuracion, minutosTranscurridos, nombreTipo, clasePlaca,
  tiposActivos, tarifasGeneralesDe, resumenOcupacion, estimaciones, textoEstimado, quitarDelPatio
} = usePatio()

const mensajeExito = ref('')
const filtroPlaca = ref('')
const filtroTipo = ref('')
const orden = ref('recientes')

function avisar(msg) {
  mensajeExito.value = msg
  setTimeout(() => { if (mensajeExito.value === msg) mensajeExito.value = '' }, 4000)
}

const totales = computed(() => {
  const capacidad = resumenOcupacion.value.reduce((s, t) => s + t.capacidad, 0)
  const ocupados = vehiculosDentro.value.length
  const estimado = Object.values(estimaciones.value).reduce((s, e) => s + (e || 0), 0)
  return {
    capacidad,
    ocupados,
    libres: Math.max(0, capacidad - ocupados),
    mensuales: vehiculosDentro.value.filter(v => v.es_mensual).length,
    estimado
  }
})

const vehiculosFiltrados = computed(() => {
  const placa = normalizarPlaca(filtroPlaca.value)
  const lista = vehiculosDentro.value.filter(v =>
    (!placa || v.placa.includes(placa)) && (!filtroTipo.value || v.tipo_vehiculo_id === filtroTipo.value)
  )
  const t = (v) => new Date(v.entrada_at).getTime()
  return [...lista].sort((a, b) => orden.value === 'antiguos' ? t(a) - t(b) : t(b) - t(a))
})

// El cobro se hace en Registro y cobro, que abre la salida de este vehículo
function irACobrar(v) {
  router.push({ name: 'registro', query: { salida: v.id } })
}

// ---------- Anular (HU-15) ----------
const anular = reactive({ abierto: false, registro: null, motivo: '', guardando: false, error: '' })
function abrirAnular(v) {
  Object.assign(anular, { abierto: true, registro: v, motivo: '', guardando: false, error: '' })
}
async function confirmarAnular() {
  if (anular.motivo.trim().length < 10) {
    anular.error = 'El motivo debe tener al menos 10 caracteres'
    return
  }
  anular.guardando = true
  anular.error = ''
  try {
    await ocupacionService.anularRegistro(anular.registro.id, anular.motivo)
    quitarDelPatio(anular.registro.id)
    anular.abierto = false
    avisar(`Registro ${anular.registro.placa} anulado`)
  } catch (err) {
    anular.error = mensajeDeError(err, 'No se pudo anular el registro')
  } finally {
    anular.guardando = false
  }
}
</script>
