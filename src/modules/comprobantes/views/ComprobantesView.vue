<template>
  <div class="space-y-6">
    <!-- Encabezado de Sección -->
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div>
        <h2 class="text-xl md:text-2xl font-bold tracking-tight text-text-primary">Comprobantes de Pago</h2>
        <p class="text-xs md:text-sm text-text-secondary">
          Historial de comprobantes emitidos, consecutivos oficiales y reimpresión con copia (HU-20 a HU-22).
        </p>
      </div>

      <button 
        @click="cargarComprobantes" 
        :disabled="cargando"
        class="inline-flex items-center justify-center space-x-1.5 px-3 py-2 text-xs font-semibold rounded-xl border border-border bg-surface text-text-secondary hover:text-text-primary hover:bg-surface-elevated transition-colors"
      >
        <svg class="w-4 h-4" :class="{ 'animate-spin': cargando }" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
        <span>Refrescar</span>
      </button>
    </div>

    <!-- Filtros de Búsqueda -->
    <div class="bg-surface rounded-2xl border border-border p-4 shadow-sm space-y-3">
      <div class="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3">
        <!-- Búsqueda texto -->
        <div class="space-y-1">
          <label class="block text-xs font-medium text-text-secondary">Buscar</label>
          <input 
            v-model="filtroTexto" 
            type="text" 
            placeholder="Consecutivo, placa o cliente..." 
            class="input-field text-xs"
          />
        </div>

        <!-- Tipo de Origen -->
        <div class="space-y-1">
          <label class="block text-xs font-medium text-text-secondary">Tipo de Servicio</label>
          <select v-model="filtroOrigen" class="input-field text-xs">
            <option value="todos">Todos los servicios</option>
            <option value="registro">Por horas (Patio)</option>
            <option value="pago_mensualidad">Mensualidades</option>
          </select>
        </div>

        <!-- Fecha Desde -->
        <div class="space-y-1">
          <label class="block text-xs font-medium text-text-secondary">Fecha Desde</label>
          <input v-model="filtroFechaDesde" type="date" class="input-field text-xs" />
        </div>

        <!-- Fecha Hasta -->
        <div class="space-y-1">
          <label class="block text-xs font-medium text-text-secondary">Fecha Hasta</label>
          <input v-model="filtroFechaHasta" type="date" class="input-field text-xs" />
        </div>
      </div>
    </div>

    <!-- Mensaje Informativo de Éxito / Alerta -->
    <div v-if="mensajeAlerta" class="p-3 bg-success-bg border border-success text-success text-xs rounded-xl flex items-center justify-between">
      <span>{{ mensajeAlerta }}</span>
      <button @click="mensajeAlerta = ''" class="font-bold underline ml-2">Cerrar</button>
    </div>

    <!-- Tabla de Comprobantes -->
    <div class="bg-surface rounded-2xl border border-border shadow-sm overflow-hidden">
      <div class="overflow-x-auto">
        <table class="w-full text-left text-xs">
          <thead class="bg-surface-elevated text-text-secondary border-b border-border uppercase font-semibold text-[11px]">
            <tr>
              <th class="px-4 py-3">Consecutivo</th>
              <th class="px-4 py-3">Origen</th>
              <th class="px-4 py-3">Fecha y Hora</th>
              <th class="px-4 py-3">Cliente</th>
              <th class="px-4 py-3">Documento</th>
              <th class="px-4 py-3 text-right">Valor</th>
              <th class="px-4 py-3 text-center">Acciones</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <tr v-if="cargando" class="text-center text-text-muted">
              <td colspan="7" class="py-8">Cargando comprobantes...</td>
            </tr>
            <tr v-else-if="comprobantesFiltrados.length === 0" class="text-center text-text-muted">
              <td colspan="7" class="py-8">No se encontraron comprobantes con los filtros seleccionados.</td>
            </tr>
            <tr 
              v-for="c in comprobantesFiltrados" 
              :key="c.id" 
              class="hover:bg-surface-elevated/50 transition-colors"
            >
              <!-- Consecutivo -->
              <td class="px-4 py-3 font-mono font-bold">
                <span v-if="c.consecutivo" class="text-primary">
                  #{{ String(c.consecutivo).padStart(6, '0') }}
                </span>
                <span v-else class="text-warning bg-warning-bg px-2 py-0.5 rounded-full text-[10px]">
                  Provisional
                </span>
              </td>

              <!-- Origen -->
              <td class="px-4 py-3">
                <span 
                  class="px-2 py-0.5 rounded-full text-[10px] font-semibold"
                  :class="c.origen === 'registro' ? 'bg-primary-bg text-primary' : 'bg-purple-100 dark:bg-purple-950/40 text-purple-600 dark:text-purple-400'"
                >
                  {{ c.origen === 'registro' ? 'Por Horas' : 'Mensualidad' }}
                </span>
              </td>

              <!-- Fecha -->
              <td class="px-4 py-3 text-text-secondary">
                {{ formatearFecha(c.created_at) }}
              </td>

              <!-- Cliente -->
              <td class="px-4 py-3 font-medium text-text-primary">
                {{ c.cliente_nombre || 'Consumidor final' }}
              </td>

              <!-- Documento -->
              <td class="px-4 py-3 text-text-secondary font-mono">
                {{ c.cliente_documento || '—' }}
              </td>

              <!-- Valor -->
              <td class="px-4 py-3 text-right font-bold text-text-primary font-mono">
                ${{ (c.valor || 0).toLocaleString() }}
              </td>

              <!-- Acciones de Descarga y Reimpresión (HU-22) -->
              <td class="px-4 py-3">
                <div class="flex items-center justify-center space-x-1.5">
                  <button 
                    @click="descargar(c, false)" 
                    class="px-2 py-1 bg-surface-elevated hover:bg-primary hover:text-white border border-border text-text-secondary rounded-lg font-medium text-[11px] transition-colors"
                    title="Descargar PDF Original"
                  >
                    Original
                  </button>
                  <button 
                    @click="descargar(c, true)" 
                    class="px-2 py-1 bg-surface-elevated hover:bg-warning hover:text-white border border-border text-text-secondary rounded-lg font-medium text-[11px] transition-colors"
                    title="Reimprimir copia con marca de agua (HU-22)"
                  >
                    Copia
                  </button>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { comprobanteService } from '../services/comprobanteService'

const authStore = useAuthStore()

const cargando = ref(false)
const comprobantes = ref([])
const mensajeAlerta = ref('')

const filtroTexto = ref('')
const filtroOrigen = ref('todos')
const filtroFechaDesde = ref('')
const filtroFechaHasta = ref('')

const comprobantesFiltrados = computed(() => {
  return comprobantes.value.filter(c => {
    // Filtro texto
    if (filtroTexto.value.trim()) {
      const q = filtroTexto.value.toLowerCase()
      const matchConsecutivo = c.consecutivo ? String(c.consecutivo).includes(q) : false
      const matchCliente = c.cliente_nombre ? c.cliente_nombre.toLowerCase().includes(q) : false
      const matchDoc = c.cliente_documento ? c.cliente_documento.toLowerCase().includes(q) : false
      if (!matchConsecutivo && !matchCliente && !matchDoc) return false
    }

    // Filtro origen
    if (filtroOrigen.value !== 'todos' && c.origen !== filtroOrigen.value) {
      return false
    }

    // Filtro fechas
    if (filtroFechaDesde.value) {
      const desde = new Date(filtroFechaDesde.value).setHours(0, 0, 0, 0)
      const fechaC = new Date(c.created_at).getTime()
      if (fechaC < desde) return false
    }

    if (filtroFechaHasta.value) {
      const hasta = new Date(filtroFechaHasta.value).setHours(23, 59, 59, 999)
      const fechaC = new Date(c.created_at).getTime()
      if (fechaC > hasta) return false
    }

    return true
  })
})

async function cargarComprobantes() {
  cargando.value = true
  try {
    const data = await comprobanteService.listarComprobantes(authStore.parqueadero?.id)
    comprobantes.value = data || []
  } catch (err) {
    console.error('Error al cargar comprobantes:', err)
  } finally {
    cargando.value = false
  }
}

function formatearFecha(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleString('es-CO', {
    dateStyle: 'short',
    timeStyle: 'short'
  })
}

function descargar(c, esCopia) {
  const detalle = {
    tipo: c.origen === 'pago_mensualidad' ? 'mensualidad' : 'hora',
    placa: c.placa || 'VEH-000',
    tipoVehiculo: 'Vehículo',
    entrada: formatearFecha(c.created_at),
    salida: formatearFecha(c.created_at),
    minutos: 60,
    metodoPago: 'Efectivo',
    cajero: 'Cajero en turno',
    periodoDesde: '2026-11-01',
    periodoHasta: '2026-11-30'
  }

  comprobanteService.descargarPDF({
    parqueadero: authStore.parqueadero || {
      nombre: 'PARKCONTROL PARKING',
      nit: '900.123.456-7',
      direccion: 'Carrera 15 # 85-20',
      telefono: '3001234567',
      modo_ticket: 'termica',
      ancho_ticket_mm: 80,
      texto_pie_comprobante: 'Régimen simplificado. Conserve este comprobante para cualquier reclamo.'
    },
    comprobante: c,
    detalle,
    esCopia
  })

  mensajeAlerta.value = esCopia 
    ? `Comprobante #${c.consecutivo || 'prov'} descargado con marca de agua COPIA.`
    : `Comprobante #${c.consecutivo || 'prov'} descargado correctamente.`
}

onMounted(() => {
  cargarComprobantes()
})
</script>
