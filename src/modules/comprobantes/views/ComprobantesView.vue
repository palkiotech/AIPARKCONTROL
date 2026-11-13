<template>
  <div class="space-y-6 max-w-5xl">
    <div>
      <h2 class="titulo-pagina">Comprobantes</h2>
      <p class="subtitulo-pagina">Comprobantes emitidos por consecutivo. La re-descarga sale con el mismo número y la marca "Copia".</p>
    </div>

    <div v-if="!conexion.isOnline" class="alerta-aviso">La consulta de comprobantes requiere conexión.</div>
    <div v-if="errorMensaje" class="alerta-error" role="alert">{{ errorMensaje }}</div>

    <div class="card-craft p-4 sm:p-5 space-y-4">
      <form class="grid grid-cols-1 sm:grid-cols-5 gap-3 items-end" @submit.prevent="cargar">
        <label><span class="etiqueta">Desde</span><input v-model="desde" type="date" class="campo" /></label>
        <label><span class="etiqueta">Hasta</span><input v-model="hasta" type="date" class="campo" /></label>
        <label class="sm:col-span-2"><span class="etiqueta">Buscar (consecutivo o placa)</span><input v-model="busqueda" type="text" placeholder="Ej. 125 o ABC123" class="campo" /></label>
        <button type="submit" class="btn-craft-primary text-sm px-4 py-2 rounded-lg" :disabled="cargando || !conexion.isOnline">Buscar</button>
      </form>

      <div class="flex flex-wrap items-center gap-x-4 gap-y-2 text-sm pt-3 border-t border-border-subtle">
        <span class="text-text-secondary text-xs font-medium">Formato del PDF</span>
        <label class="flex items-center gap-1.5 cursor-pointer"><input v-model="formato" type="radio" value="carta" /> Carta</label>
        <label class="flex items-center gap-1.5 cursor-pointer"><input v-model="formato" type="radio" value="termica" /> Térmica {{ authStore.parqueadero?.ancho_ticket_mm || 80 }} mm</label>
      </div>
    </div>

    <div v-if="cargando" class="vacio py-16">
      <div class="spinner"></div>
      <span class="text-xs">Cargando comprobantes…</span>
    </div>
    <div v-else-if="!comprobantes.length" class="card-craft vacio">
      <p class="font-medium text-text-primary">Sin resultados</p>
      <p class="text-xs">No hay comprobantes con esos filtros.</p>
    </div>

    <template v-else>
      <!-- Tabla en escritorio -->
      <div class="hidden sm:block card-craft overflow-hidden">
        <div class="overflow-x-auto">
          <table class="tabla">
            <thead>
              <tr>
                <th>N°</th>
                <th>Fecha</th>
                <th>Cliente</th>
                <th>Placa</th>
                <th>Origen</th>
                <th class="text-right">Valor</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="c in comprobantes" :key="c.id">
                <td class="font-semibold num-tabular">{{ numero(c.consecutivo) }}</td>
                <td class="text-text-secondary whitespace-nowrap">{{ fh(c.created_at) }}</td>
                <td>{{ c.cliente_nombre }}<span v-if="c.cliente_documento" class="text-text-muted"> · {{ c.cliente_documento }}</span></td>
                <td class="font-mono text-xs font-semibold tracking-wider">{{ c.placa || '—' }}</td>
                <td class="text-text-secondary">
                  {{ c.origen === 'registro' ? 'Parqueo' : 'Mensualidad' }}
                  <span v-if="c.anulado" class="badge-pastel-rose px-2 py-0.5 rounded-full text-2xs ml-1">Anulado</span>
                </td>
                <td class="text-right font-semibold num-tabular">{{ pesos(c.valor) }}</td>
                <td class="text-right">
                  <button class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg" :disabled="descargando === c.id" @click="descargar(c)">
                    {{ descargando === c.id ? 'Generando…' : 'Descargar copia' }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Tarjetas en celular -->
      <div class="sm:hidden space-y-2">
        <div v-for="c in comprobantes" :key="'m' + c.id" class="card-craft p-4 text-sm space-y-1">
          <div class="flex justify-between">
            <strong class="font-semibold num-tabular">N° {{ numero(c.consecutivo) }}</strong>
            <strong class="font-semibold num-tabular">{{ pesos(c.valor) }}</strong>
          </div>
          <p class="text-xs text-text-secondary">{{ fh(c.created_at) }} · {{ c.origen === 'registro' ? 'Parqueo' : 'Mensualidad' }} · {{ c.placa || '—' }}</p>
          <p class="text-text-primary">{{ c.cliente_nombre }}</p>
          <div class="flex justify-between items-center pt-2">
            <span v-if="c.anulado" class="badge-pastel-rose px-2 py-0.5 rounded-full text-2xs">Anulado</span>
            <span v-else></span>
            <button class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg" :disabled="descargando === c.id" @click="descargar(c)">Descargar copia</button>
          </div>
        </div>
      </div>
    </template>
  </div>
</template>

<script setup>
import { ref, onMounted, onActivated } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { comprobanteService } from '@/modules/comprobantes/services/comprobanteService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { hoyEnZona, sumarDias, formatearFechaHora } from '@/utils/fecha'

const authStore = useAuthStore()
const conexion = useConexionStore()
const claseInput = 'campo'

const hoy = hoyEnZona(authStore.zonaHoraria)
const desde = ref(sumarDias(hoy, -30))
const hasta = ref(hoy)
const busqueda = ref('')
const formato = ref(authStore.parqueadero?.modo_ticket === 'termica' ? 'termica' : 'carta')
const comprobantes = ref([])
const cargando = ref(false)
const descargando = ref(null)
const errorMensaje = ref('')

function pesos(v) { return `$${Number(v || 0).toLocaleString('es-CO')}` }
function fh(v) { return formatearFechaHora(v, authStore.zonaHoraria, { year: 'numeric' }) }
function numero(n) { return String(n).padStart(6, '0') }

async function cargar() {
  if (!conexion.isOnline) return
  errorMensaje.value = ''
  cargando.value = true
  try {
    comprobantes.value = await comprobanteService.listarComprobantes({
      desde: desde.value,
      hasta: hasta.value,
      busqueda: busqueda.value.trim()
    })
  } catch (e) {
    errorMensaje.value = mensajeDeError(e, 'No se pudieron cargar los comprobantes')
  } finally {
    cargando.value = false
  }
}

async function descargar(c) {
  descargando.value = c.id
  errorMensaje.value = ''
  try {
    const { comprobante, detalle, parqueadero } = await comprobanteService.obtenerDetalle(c.id)
    await comprobanteService.descargarPDF({
      parqueadero: { ...parqueadero, modo_ticket: authStore.parqueadero?.modo_ticket },
      comprobante,
      detalle,
      esCopia: true,
      formato: formato.value
    })
  } catch (e) {
    errorMensaje.value = mensajeDeError(e, 'No se pudo generar el comprobante')
  } finally {
    descargando.value = null
  }
}

// Con <keep-alive> onActivated también corre tras el primer montaje: se omite esa vez
let primeraActivacion = true
onMounted(cargar)
onActivated(() => {
  if (primeraActivacion) { primeraActivacion = false; return }
  cargar()
})
</script>
