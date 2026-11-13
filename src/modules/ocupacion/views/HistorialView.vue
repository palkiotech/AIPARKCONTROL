<template>
  <div class="space-y-6">
    <div>
      <h2 class="titulo-pagina">Historial de registros</h2>
      <p class="subtitulo-pagina">Consulta entradas y salidas por placa y fechas para resolver reclamos.</p>
    </div>

    <div v-if="!conexionStore.isOnline" class="alerta-aviso">
      El historial requiere conexión a internet. Vuelve a intentarlo cuando haya red.
    </div>

    <!-- Filtros -->
    <form @submit.prevent="buscar(0)" class="card-craft p-4 sm:p-5 grid grid-cols-1 sm:grid-cols-4 gap-3 items-end">
      <div>
        <label class="etiqueta">Placa</label>
        <input
          v-model="filtros.placa"
          type="text"
          placeholder="ABC123"
          class="campo uppercase font-mono tracking-wider"
        />
      </div>
      <div>
        <label class="etiqueta">Desde</label>
        <input v-model="filtros.desde" type="date" class="campo" />
      </div>
      <div>
        <label class="etiqueta">Hasta</label>
        <input v-model="filtros.hasta" type="date" class="campo" />
      </div>
      <button type="submit" :disabled="!conexionStore.isOnline || cargando" class="btn-craft-primary text-sm px-4 py-2 rounded-lg">
        {{ cargando ? 'Buscando...' : 'Buscar' }}
      </button>
    </form>

    <div v-if="error" class="alerta-error" role="alert">{{ error }}</div>
    <div v-if="exito" class="alerta-exito">{{ exito }}</div>

    <!-- Resultados -->
    <div class="card-craft overflow-hidden">
      <div class="flex items-center justify-between gap-2 px-4 sm:px-5 py-3.5 border-b border-border">
        <h3 class="titulo-seccion">Resultados</h3>
        <span class="text-xs text-text-muted num-tabular">{{ total }} registro(s)</span>
      </div>

      <div v-if="cargando" class="vacio">
        <div class="spinner"></div>
        <span>Consultando...</span>
      </div>
      <div v-else-if="filas.length === 0" class="vacio">
        {{ buscado ? 'No hay registros con esos filtros.' : 'Usa los filtros para consultar el historial.' }}
      </div>

      <div v-else class="divide-y divide-border-subtle">
        <div
          v-for="r in filas"
          :key="r.id"
          class="p-4 sm:px-5 space-y-2.5"
          :class="r.estado === 'anulado' ? 'bg-danger-bg/40' : ''"
        >
          <div class="flex flex-wrap items-center justify-between gap-2">
            <div class="flex flex-wrap items-center gap-1.5">
              <span class="plate-colombia text-xs" :class="[clasePlaca(r.tipos_vehiculo?.nombre), r.estado === 'anulado' ? 'opacity-60' : '']">{{ r.placa }}</span>
              <span class="text-2xs px-2 py-0.5 rounded-full" :class="claseEstado(r.estado)">{{ textoEstado(r.estado) }}</span>
              <span v-if="r.es_mensual" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-mint">Mensual</span>
              <span v-if="r.requiere_revision" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-amber" :title="`Cobrado ${pesos(r.valor)} · servidor ${pesos(r.valor_servidor)}`">Requiere revisión</span>
            </div>
            <span class="font-semibold text-sm text-text-primary num-tabular" :class="r.estado === 'anulado' ? 'line-through text-text-muted' : ''">{{ r.estado === 'abierto' ? '—' : pesos(r.valor) }}</span>
          </div>

          <dl class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-x-4 gap-y-1 text-xs text-text-secondary">
            <div><dt class="inline text-text-muted">Tipo:</dt> <dd class="inline">{{ r.tipos_vehiculo?.nombre || '—' }}</dd></div>
            <div><dt class="inline text-text-muted">Entrada:</dt> <dd class="inline num-tabular">{{ formatearFechaHora(r.entrada_at, zona, { year: 'numeric' }) }}</dd></div>
            <div><dt class="inline text-text-muted">Salida:</dt> <dd class="inline num-tabular">{{ r.salida_at ? formatearFechaHora(r.salida_at, zona, { year: 'numeric' }) : 'Dentro' }}</dd></div>
            <div><dt class="inline text-text-muted">Tiempo:</dt> <dd class="inline num-tabular">{{ r.minutos != null ? formatearDuracion(r.minutos) : '—' }}</dd></div>
            <div><dt class="inline text-text-muted">Tarifa:</dt> <dd class="inline">{{ r.tarifas?.nombre || '—' }}</dd></div>
            <div><dt class="inline text-text-muted">Método:</dt> <dd class="inline">{{ r.metodos_pago?.nombre || '—' }}</dd></div>
            <div><dt class="inline text-text-muted">Registró entrada:</dt> <dd class="inline">{{ r.entrada?.nombre || '—' }}</dd></div>
            <div><dt class="inline text-text-muted">Registró salida:</dt> <dd class="inline">{{ r.salida?.nombre || '—' }}</dd></div>
          </dl>

          <p v-if="r.estado === 'anulado'" class="text-xs text-danger font-medium">
            Anulado{{ r.anulado_at ? ` el ${formatearFechaHora(r.anulado_at, zona)}` : '' }}: {{ r.motivo_anulacion }}
          </p>

          <div v-if="r.estado !== 'anulado'" class="flex flex-wrap gap-2">
            <button
              v-if="r.estado === 'cerrado' && r.valor > 0"
              @click="comprobante(r)"
              :disabled="!conexionStore.isOnline || generandoId === r.id"
              class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg"
            >
              {{ generandoId === r.id ? 'Generando...' : 'Comprobante' }}
            </button>
            <button
              v-if="authStore.isAdmin"
              @click="abrirAnular(r)"
              :disabled="!conexionStore.isOnline"
              class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg text-danger"
            >
              Anular
            </button>
          </div>
        </div>
      </div>

      <!-- Paginación de 20 en 20 -->
      <div v-if="total > TAMANO" class="flex items-center justify-between gap-2 px-4 sm:px-5 py-3 border-t border-border">
        <button @click="buscar(pagina - 1)" :disabled="pagina === 0 || cargando" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg">Anterior</button>
        <span class="text-xs text-text-muted num-tabular">Página {{ pagina + 1 }} de {{ totalPaginas }}</span>
        <button @click="buscar(pagina + 1)" :disabled="pagina + 1 >= totalPaginas || cargando" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg">Siguiente</button>
      </div>
    </div>

    <!-- Modal anular (HU-15) -->
    <div v-if="anular.abierto" class="modal-fondo">
      <form @submit.prevent="confirmarAnular" class="modal-panel max-w-sm space-y-3">
        <div class="modal-encabezado">
          <h3 class="modal-titulo">Anular registro {{ anular.registro?.placa }}</h3>
          <button type="button" @click="anular.abierto = false" class="btn-icono" aria-label="Cerrar">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <p class="text-sm text-text-secondary">El registro no se borra: queda anulado con el motivo y tu usuario, y deja de sumar en caja y reportes.</p>
        <div>
          <label class="etiqueta">Motivo</label>
          <textarea
            v-model="anular.motivo"
            rows="3"
            placeholder="Motivo (mínimo 10 caracteres)"
            class="campo"
          ></textarea>
          <p class="text-xs text-text-muted mt-1 num-tabular">{{ anular.motivo.trim().length }}/10 caracteres mínimos</p>
        </div>
        <p v-if="anular.error" class="alerta-error" role="alert">{{ anular.error }}</p>
        <div class="flex gap-2">
          <button type="button" @click="anular.abierto = false" class="flex-1 btn-craft-subtle text-sm px-4 py-2 rounded-lg">Cancelar</button>
          <button type="submit" :disabled="anular.motivo.trim().length < 10 || anular.guardando" class="flex-1 btn-craft-danger text-sm px-4 py-2 rounded-lg">
            {{ anular.guardando ? 'Anulando...' : 'Anular' }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, onActivated, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { comprobanteService } from '@/modules/comprobantes/services/comprobanteService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { formatearFechaHora, rangoDiaUtc, hoyEnZona, sumarDias } from '@/utils/fecha'

const TAMANO = 20

const authStore = useAuthStore()
const conexionStore = useConexionStore()
const zona = computed(() => authStore.zonaHoraria)

const hoy = hoyEnZona(authStore.zonaHoraria)
const filtros = reactive({ placa: '', desde: sumarDias(hoy, -7), hasta: hoy })
const filas = ref([])
const total = ref(0)
const pagina = ref(0)
const cargando = ref(false)
const buscado = ref(false)
const error = ref('')
const exito = ref('')
const generandoId = ref(null)

const totalPaginas = computed(() => Math.max(1, Math.ceil(total.value / TAMANO)))

function pesos(v) {
  return `$${Number(v || 0).toLocaleString('es-CO')}`
}
function formatearDuracion(min) {
  const m = Math.max(0, Math.round(min || 0))
  if (m < 60) return `${m} min`
  const h = Math.floor(m / 60)
  const r = m % 60
  return r === 0 ? `${h}h` : `${h}h ${r}m`
}
function clasePlaca(n) {
  const t = (n || '').toLowerCase()
  return t.includes('moto') ? 'plate-moto' : (t.includes('bici') ? 'plate-bici' : 'plate-carro')
}
function claseEstado(e) {
  return { abierto: 'badge-pastel-blue', cerrado: 'badge-pastel-mint', anulado: 'badge-pastel-rose' }[e] || 'badge-pastel-blue'
}
function textoEstado(e) {
  return { abierto: 'Dentro', cerrado: 'Cerrado', anulado: 'Anulado' }[e] || e
}

async function buscar(nuevaPagina = 0) {
  if (!conexionStore.isOnline) {
    error.value = 'El historial requiere conexión'
    return
  }
  if (filtros.desde && filtros.hasta && filtros.desde > filtros.hasta) {
    error.value = 'La fecha "desde" no puede ser posterior a "hasta"'
    return
  }
  cargando.value = true
  error.value = ''
  try {
    const desde = filtros.desde ? rangoDiaUtc(filtros.desde, zona.value).desde : null
    const hasta = filtros.hasta ? rangoDiaUtc(filtros.hasta, zona.value).hasta : null
    const res = await ocupacionService.buscarHistorial({
      parqueaderoId: authStore.parqueaderoId,
      placa: filtros.placa,
      desde,
      hasta,
      pagina: nuevaPagina,
      tamano: TAMANO
    })
    filas.value = res.filas
    total.value = res.total
    pagina.value = nuevaPagina
    buscado.value = true
  } catch (err) {
    error.value = mensajeDeError(err, 'No se pudo consultar el historial')
  } finally {
    cargando.value = false
  }
}

async function comprobante(r) {
  generandoId.value = r.id
  error.value = ''
  try {
    const res = await comprobanteService.emitir({ origen: 'registro', origenId: r.id })
    await comprobanteService.descargarPDF({
      parqueadero: res.parqueadero,
      comprobante: res.comprobante,
      detalle: res.detalle,
      esCopia: res.existente
    })
  } catch (err) {
    error.value = mensajeDeError(err, 'No se pudo generar el comprobante')
  } finally {
    generandoId.value = null
  }
}

const anular = reactive({ abierto: false, registro: null, motivo: '', guardando: false, error: '' })
function abrirAnular(r) {
  Object.assign(anular, { abierto: true, registro: r, motivo: '', guardando: false, error: '' })
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
    anular.abierto = false
    exito.value = `Registro ${anular.registro.placa} anulado`
    setTimeout(() => { exito.value = '' }, 4000)
    await buscar(pagina.value)
  } catch (err) {
    anular.error = mensajeDeError(err, 'No se pudo anular el registro')
  } finally {
    anular.guardando = false
  }
}

onMounted(() => {
  if (conexionStore.isOnline) buscar(0)
})
onActivated(() => {
  if (buscado.value && conexionStore.isOnline) buscar(pagina.value)
})
</script>
