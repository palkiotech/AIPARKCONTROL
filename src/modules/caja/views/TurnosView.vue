<template>
  <div class="space-y-6 max-w-5xl">
    <div class="flex flex-col lg:flex-row lg:items-end lg:justify-between gap-4">
      <div>
        <router-link to="/caja" class="inline-flex items-center gap-1 text-xs text-primary font-medium hover:underline">
          <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" /></svg>
          Caja
        </router-link>
        <h2 class="titulo-pagina mt-1">Historial de turnos</h2>
        <p class="subtitulo-pagina">Quién entregó y recibió, diferencias y movimientos de cada turno.</p>
      </div>
      <div class="flex flex-wrap gap-2 items-end">
        <label class="w-36"><span class="etiqueta">Desde</span><input v-model="desde" type="date" class="campo campo-sm" /></label>
        <label class="w-36"><span class="etiqueta">Hasta</span><input v-model="hasta" type="date" class="campo campo-sm" /></label>
        <button class="btn-craft-primary text-sm px-4 py-2 rounded-lg" :disabled="cargando || !conexion.isOnline" @click="cargar">Buscar</button>
        <button class="btn-craft-subtle text-sm px-4 py-2 rounded-lg" :disabled="!turnos.length" @click="exportar">Exportar Excel</button>
      </div>
    </div>

    <div v-if="!conexion.isOnline" class="alerta-aviso">El historial de turnos requiere conexión.</div>
    <div v-if="errorMensaje" class="alerta-error" role="alert">{{ errorMensaje }}</div>

    <div v-if="cargando" class="vacio py-16">
      <div class="spinner"></div>
      <span class="text-xs">Cargando turnos…</span>
    </div>
    <div v-else-if="!turnos.length" class="card-craft vacio">
      <p class="font-medium text-text-primary">Sin turnos</p>
      <p class="text-xs">No hay turnos en el rango seleccionado.</p>
    </div>

    <div v-else class="space-y-3">
      <div
        v-for="t in turnos"
        :key="t.id"
        class="card-craft card-interactiva p-4 sm:p-5"
        :class="seleccionado?.id === t.id ? 'ring-2 ring-primary/60 border-primary/50' : ''"
        @click="verDetalle(t)"
      >
        <div class="flex flex-wrap justify-between gap-2 text-xs">
          <div class="space-y-0.5">
            <p class="font-semibold text-sm text-text-primary">{{ fh(t.abierto_at) }} → {{ t.cerrado_at ? fh(t.cerrado_at) : 'en curso' }}</p>
            <p class="text-text-secondary">Entregó: <strong class="font-semibold text-text-primary">{{ t.entrego?.nombre || '—' }}</strong> · Recibió: <strong class="font-semibold text-text-primary">{{ t.recibio?.nombre || (t.cerrado_sin_relevo ? 'sin relevo' : '—') }}</strong></p>
            <p class="text-text-muted">Duración: {{ duracion(t) }}</p>
          </div>
          <div class="flex flex-wrap gap-1 items-start">
            <span class="px-2 py-0.5 rounded-full text-2xs" :class="t.estado === 'cerrado' ? 'badge-neutro' : 'badge-pastel-amber'">{{ t.estado }}</span>
            <span v-if="t.cerrado_sin_relevo" class="badge-pastel-rose px-2 py-0.5 rounded-full text-2xs">sin relevo</span>
          </div>
        </div>
        <div class="grid grid-cols-2 sm:grid-cols-6 gap-2 mt-3 text-xs">
          <Dato titulo="Base" :valor="pesos(t.base_inicial)" />
          <Dato titulo="Esperado" :valor="pesos(t.efectivo_esperado)" />
          <Dato titulo="Contado" :valor="t.efectivo_contado == null ? '—' : pesos(t.efectivo_contado)" />
          <Dato titulo="Recibido" :valor="t.efectivo_recibido == null ? '—' : pesos(t.efectivo_recibido)" />
          <Dato titulo="Dif. entrega" :valor="t.diferencia == null ? '—' : pesos(t.diferencia)" :clase="claseDif(t.diferencia)" />
          <Dato titulo="Dif. recepción" :valor="t.diferencia_recepcion == null ? '—' : pesos(t.diferencia_recepcion)" :clase="claseDif(t.diferencia_recepcion)" />
        </div>
        <p v-if="t.observacion" class="text-xs text-text-secondary mt-3">Observación: {{ t.observacion }}</p>
        <p v-if="t.nota_correccion" class="text-xs text-warning mt-1 whitespace-pre-line">Notas de corrección: {{ t.nota_correccion }}</p>

        <!-- Detalle -->
        <div v-if="seleccionado?.id === t.id" class="mt-4 pt-4 border-t border-border space-y-4 text-xs cursor-default" @click.stop>
          <div v-if="cargandoDetalle" class="flex items-center gap-2 text-text-muted"><div class="spinner w-4 h-4"></div>Cargando detalle…</div>
          <template v-else-if="detalle">
            <p class="text-text-secondary">Vehículos ingresados: <strong class="font-semibold text-text-primary num-tabular">{{ detalle.entradas }}</strong> · Salidas cobradas: <strong class="font-semibold text-text-primary num-tabular">{{ detalle.salidas }}</strong></p>
            <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div class="space-y-1">
                <p class="rotulo mb-1">Cobros por hora</p>
                <p v-for="c in detalle.cobros_hora" :key="'h' + c.metodo" class="flex justify-between"><span class="text-text-secondary">{{ c.metodo }} ({{ c.cantidad }})</span><span class="font-semibold num-tabular">{{ pesos(c.total) }}</span></p>
                <p v-if="!detalle.cobros_hora.length" class="text-text-muted">Ninguno</p>
              </div>
              <div class="space-y-1">
                <p class="rotulo mb-1">Pagos de mensualidad</p>
                <p v-for="c in detalle.pagos_mensualidad" :key="'m' + c.metodo" class="flex justify-between"><span class="text-text-secondary">{{ c.metodo }} ({{ c.cantidad }})</span><span class="font-semibold num-tabular">{{ pesos(c.total) }}</span></p>
                <p v-if="!detalle.pagos_mensualidad.length" class="text-text-muted">Ninguno</p>
              </div>
            </div>
            <div class="space-y-1">
              <p class="rotulo mb-1">Retiros e ingresos manuales</p>
              <p v-for="m in detalle.movimientos" :key="m.id" class="flex justify-between gap-2">
                <span class="text-text-secondary">{{ m.tipo === 'retiro' ? 'Retiro' : 'Ingreso' }} · {{ m.motivo }} · {{ m.usuario }}</span>
                <span class="font-semibold num-tabular" :class="m.tipo === 'retiro' ? 'text-danger' : 'text-success'">{{ m.tipo === 'retiro' ? '−' : '+' }}{{ pesos(m.valor) }}</span>
              </p>
              <p v-if="!detalle.movimientos.length" class="text-text-muted">Ninguno</p>
            </div>
          </template>
          <div v-if="t.estado === 'cerrado'" class="flex flex-col sm:flex-row gap-2">
            <input v-model="nota" type="text" placeholder="Nota de corrección (los turnos cerrados no se editan)" class="campo" aria-label="Nota de corrección" />
            <button class="btn-craft-subtle text-sm px-4 py-2 rounded-lg shrink-0" :disabled="!nota.trim() || guardandoNota" @click="agregarNota(t)">Agregar nota</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, h } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { cajaService } from '@/modules/caja/services/cajaService'
import { reportesService } from '@/modules/reportes/services/reportesService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { hoyEnZona, sumarDias, rangoDiaUtc, formatearFechaHora } from '@/utils/fecha'

const authStore = useAuthStore()
const conexion = useConexionStore()
const claseInput = 'campo'

const Dato = (props) => h('div', { class: 'rounded-lg bg-surface-elevated border border-border-subtle px-2.5 py-2' }, [
  h('p', { class: 'rotulo' }, props.titulo),
  h('p', { class: `font-semibold text-sm text-text-primary num-tabular mt-0.5 ${props.clase || ''}` }, props.valor)
])
Dato.props = ['titulo', 'valor', 'clase']

const hoy = hoyEnZona(authStore.zonaHoraria)
const desde = ref(sumarDias(hoy, -30))
const hasta = ref(hoy)
const turnos = ref([])
const cargando = ref(false)
const errorMensaje = ref('')
const seleccionado = ref(null)
const detalle = ref(null)
const cargandoDetalle = ref(false)
const nota = ref('')
const guardandoNota = ref(false)

function pesos(v) { return `$${Number(v || 0).toLocaleString('es-CO')}` }
function fh(v) { return v ? formatearFechaHora(v, authStore.zonaHoraria) : '—' }
function claseDif(d) { return d == null || d === 0 ? '' : d > 0 ? 'text-warning' : 'text-danger' }
function minutosTurno(t) {
  const fin = t.recibido_at || t.cerrado_at
  return fin ? Math.round((new Date(fin) - new Date(t.abierto_at)) / 60000) : null
}
function duracion(t) {
  const m = minutosTurno(t)
  if (m === null) return 'en curso'
  return `${Math.floor(m / 60)} h ${m % 60} min`
}

async function cargar() {
  errorMensaje.value = ''
  cargando.value = true
  seleccionado.value = null
  try {
    turnos.value = await cajaService.listarTurnos({
      parqueaderoId: authStore.parqueaderoId,
      desde: rangoDiaUtc(desde.value, authStore.zonaHoraria).desde,
      hasta: rangoDiaUtc(hasta.value, authStore.zonaHoraria).hasta
    })
  } catch (e) {
    errorMensaje.value = mensajeDeError(e, 'No se pudo cargar el historial')
  } finally {
    cargando.value = false
  }
}

async function verDetalle(t) {
  if (seleccionado.value?.id === t.id) {
    seleccionado.value = null
    return
  }
  seleccionado.value = t
  detalle.value = null
  nota.value = ''
  cargandoDetalle.value = true
  try {
    detalle.value = await cajaService.obtenerResumen(t.id)
  } catch (e) {
    errorMensaje.value = mensajeDeError(e)
  } finally {
    cargandoDetalle.value = false
  }
}

async function agregarNota(t) {
  guardandoNota.value = true
  try {
    await cajaService.agregarNota(t.id, nota.value)
    nota.value = ''
    await cargar()
  } catch (e) {
    errorMensaje.value = mensajeDeError(e)
  } finally {
    guardandoNota.value = false
  }
}

function exportar() {
  const filas = turnos.value.map(t => ({
    Apertura: fh(t.abierto_at),
    Cierre: t.cerrado_at ? fh(t.cerrado_at) : '',
    'Duración (min)': minutosTurno(t),
    Entregó: t.entrego?.nombre || '',
    Recibió: t.recibio?.nombre || '',
    'Sin relevo': t.cerrado_sin_relevo ? 'Sí' : 'No',
    Estado: t.estado,
    Base: t.base_inicial ?? 0,
    Esperado: t.efectivo_esperado ?? 0,
    Contado: t.efectivo_contado,
    Recibido: t.efectivo_recibido,
    'Diferencia entrega': t.diferencia,
    'Diferencia recepción': t.diferencia_recepcion,
    Observación: t.observacion || '',
    'Notas de corrección': t.nota_correccion || ''
  }))
  reportesService.exportarAExcel(`turnos-${desde.value}-a-${hasta.value}`, { Turnos: filas })
}

onMounted(cargar)
</script>
