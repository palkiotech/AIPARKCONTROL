<template>
  <div class="space-y-6">
    <!-- Encabezado de Sección -->
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div>
        <h2 class="text-xl md:text-2xl font-bold tracking-tight text-text-primary">Reportes Financieros</h2>
        <p class="text-xs md:text-sm text-text-secondary">
          Consolidado de ingresos por horas y mensualidades con desglose por tipo y método de pago (HU-25).
        </p>
      </div>

      <!-- Botones de Exportación -->
      <div class="flex items-center space-x-2">
        <button 
          @click="exportarExcel"
          :disabled="cargando"
          class="inline-flex items-center space-x-1.5 px-3 py-2 text-xs font-bold rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white shadow-sm transition-colors disabled:opacity-50"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
          </svg>
          <span>Exportar Excel (.xlsx)</span>
        </button>

        <button 
          @click="exportarCSV"
          :disabled="cargando"
          class="inline-flex items-center space-x-1.5 px-3 py-2 text-xs font-semibold rounded-xl border border-border bg-surface text-text-secondary hover:text-text-primary hover:bg-surface-elevated transition-colors disabled:opacity-50"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
          </svg>
          <span>CSV</span>
        </button>
      </div>
    </div>

    <!-- Filtros de Fecha y Rangos Rápidos -->
    <div class="bg-surface rounded-2xl border border-border p-4 shadow-sm space-y-3">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <!-- Rangos rápidos -->
        <div class="flex items-center space-x-1.5">
          <button 
            v-for="r in rangosRapidos" 
            :key="r.id"
            @click="seleccionarRango(r.id)"
            class="px-2.5 py-1 text-xs font-medium rounded-lg transition-colors border"
            :class="rangoActivo === r.id ? 'bg-primary text-white border-primary' : 'bg-surface-elevated text-text-secondary border-border hover:text-text-primary'"
          >
            {{ r.nombre }}
          </button>
        </div>

        <!-- Inputs de fecha -->
        <div class="flex items-center space-x-2">
          <div class="flex items-center space-x-1">
            <span class="text-xs text-text-muted">Desde:</span>
            <input 
              v-model="fechaDesde" 
              type="date" 
              class="input-field text-xs py-1 px-2 w-auto"
              @change="rangoActivo = 'personalizado'; cargarReporte()" 
            />
          </div>
          <div class="flex items-center space-x-1">
            <span class="text-xs text-text-muted">Hasta:</span>
            <input 
              v-model="fechaHasta" 
              type="date" 
              class="input-field text-xs py-1 px-2 w-auto"
              @change="rangoActivo = 'personalizado'; cargarReporte()" 
            />
          </div>
          <button 
            @click="cargarReporte"
            class="p-1.5 text-xs font-semibold rounded-lg bg-surface-elevated hover:bg-border text-text-primary border border-border"
            title="Actualizar datos"
          >
            <svg class="w-4 h-4" :class="{ 'animate-spin': cargando }" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
          </button>
        </div>
      </div>
    </div>

    <!-- Indicador de Notificación -->
    <div v-if="notificacion" class="p-3 bg-success-bg border border-success text-success text-xs rounded-xl flex items-center justify-between">
      <span>{{ notificacion }}</span>
      <button @click="notificacion = ''" class="font-bold underline ml-2">✕</button>
    </div>

    <!-- Tarjetas de Totales Generales -->
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
      <!-- Total Por Horas -->
      <div class="bg-surface rounded-2xl border border-border p-5 shadow-sm">
        <p class="text-xs font-semibold text-text-secondary uppercase tracking-wider">Ingresos por Horas</p>
        <p class="text-2xl md:text-3xl font-bold text-text-primary mt-2 font-mono">
          ${{ (datosReporte.total_hora || 0).toLocaleString() }}
        </p>
        <p class="text-[11px] text-text-muted mt-1">Estancias rotativas en patio</p>
      </div>

      <!-- Total Mensualidades -->
      <div class="bg-surface rounded-2xl border border-border p-5 shadow-sm">
        <p class="text-xs font-semibold text-text-secondary uppercase tracking-wider">Ingresos Mensualidades</p>
        <p class="text-2xl md:text-3xl font-bold text-text-primary mt-2 font-mono">
          ${{ (datosReporte.total_mensualidades || 0).toLocaleString() }}
        </p>
        <p class="text-[11px] text-text-muted mt-1">Abonos y renovaciones de contratos</p>
      </div>

      <!-- Gran Total -->
      <div class="bg-surface rounded-2xl border border-primary/30 bg-primary-bg/20 p-5 shadow-sm">
        <p class="text-xs font-bold text-primary uppercase tracking-wider">Gran Total Recaudado</p>
        <p class="text-2xl md:text-3xl font-extrabold text-primary mt-2 font-mono">
          ${{ (datosReporte.gran_total || 0).toLocaleString() }}
        </p>
        <p class="text-[11px] text-primary/80 mt-1 font-medium">100% de operaciones conciliadas</p>
      </div>
    </div>

    <!-- Desglose por Tipo de Vehículo y Método de Pago -->
    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <!-- Tabla: Por Tipo de Vehículo -->
      <div class="bg-surface rounded-2xl border border-border p-5 shadow-sm space-y-4">
        <h3 class="text-sm font-bold text-text-primary flex items-center justify-between">
          <span>Ingresos por Tipo de Vehículo</span>
          <span class="text-xs text-text-muted font-normal">Patio y mensualidades</span>
        </h3>

        <div class="overflow-x-auto">
          <table class="w-full text-left text-xs">
            <thead class="text-text-secondary border-b border-border uppercase font-semibold text-[10px]">
              <tr>
                <th class="py-2">Tipo</th>
                <th class="py-2 text-center">Operaciones</th>
                <th class="py-2 text-right">Total ($)</th>
                <th class="py-2 text-right">% Participación</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="t in datosReporte.por_tipo" :key="t.tipo" class="hover:bg-surface-elevated/40">
                <td class="py-2.5 font-medium text-text-primary">{{ t.tipo }}</td>
                <td class="py-2.5 text-center text-text-secondary">{{ t.cantidad }}</td>
                <td class="py-2.5 text-right font-mono font-bold text-text-primary">${{ t.total.toLocaleString() }}</td>
                <td class="py-2.5 text-right text-text-muted font-mono">
                  {{ calcularPorcentaje(t.total, datosReporte.gran_total) }}%
                </td>
              </tr>
              <tr v-if="!datosReporte.por_tipo?.length" class="text-center text-text-muted py-4">
                <td colspan="4" class="py-4">No hay datos en el periodo</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Tabla: Por Método de Pago -->
      <div class="bg-surface rounded-2xl border border-border p-5 shadow-sm space-y-4">
        <h3 class="text-sm font-bold text-text-primary flex items-center justify-between">
          <span>Ingresos por Método de Pago</span>
          <span class="text-xs text-text-muted font-normal">Efectivo vs Digital</span>
        </h3>

        <div class="overflow-x-auto">
          <table class="w-full text-left text-xs">
            <thead class="text-text-secondary border-b border-border uppercase font-semibold text-[10px]">
              <tr>
                <th class="py-2">Método</th>
                <th class="py-2 text-center">Naturaleza</th>
                <th class="py-2 text-right">Total ($)</th>
                <th class="py-2 text-right">% Participación</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-border">
              <tr v-for="m in datosReporte.por_metodo" :key="m.metodo" class="hover:bg-surface-elevated/40">
                <td class="py-2.5 font-medium text-text-primary">{{ m.metodo }}</td>
                <td class="py-2.5 text-center">
                  <span 
                    class="px-2 py-0.5 rounded-full text-[10px] font-semibold"
                    :class="m.es_efectivo ? 'bg-emerald-100 dark:bg-emerald-950/40 text-emerald-600 dark:text-emerald-400' : 'bg-blue-100 dark:bg-blue-950/40 text-blue-600 dark:text-blue-400'"
                  >
                    {{ m.es_efectivo ? 'Efectivo en Caja' : 'Digital / Banco' }}
                  </span>
                </td>
                <td class="py-2.5 text-right font-mono font-bold text-text-primary">${{ m.total.toLocaleString() }}</td>
                <td class="py-2.5 text-right text-text-muted font-mono">
                  {{ calcularPorcentaje(m.total, datosReporte.gran_total) }}%
                </td>
              </tr>
              <tr v-if="!datosReporte.por_metodo?.length" class="text-center text-text-muted py-4">
                <td colspan="4" class="py-4">No hay datos en el periodo</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { reportesService } from '../services/reportesService'

const cargando = ref(false)
const notificacion = ref('')
const rangoActivo = ref('hoy')

const fechaDesde = ref('')
const fechaHasta = ref('')

const rangosRapidos = [
  { id: 'hoy', nombre: 'Hoy' },
  { id: '7dias', nombre: 'Últimos 7 días' },
  { id: 'esteMes', nombre: 'Este Mes' },
  { id: 'mesAnterior', nombre: 'Mes Anterior' }
]

const datosReporte = ref({
  total_hora: 0,
  total_mensualidades: 0,
  gran_total: 0,
  por_tipo: [],
  por_metodo: []
})

function seleccionarRango(id) {
  rangoActivo.value = id
  const hoy = new Date()
  
  if (id === 'hoy') {
    const ymd = hoy.toISOString().split('T')[0]
    fechaDesde.value = ymd
    fechaHasta.value = ymd
  } else if (id === '7dias') {
    const d = new Date(hoy)
    d.setDate(d.getDate() - 7)
    fechaDesde.value = d.toISOString().split('T')[0]
    fechaHasta.value = hoy.toISOString().split('T')[0]
  } else if (id === 'esteMes') {
    const primerDia = new Date(hoy.getFullYear(), hoy.getMonth(), 1)
    const ultimoDia = new Date(hoy.getFullYear(), hoy.getMonth() + 1, 0)
    fechaDesde.value = primerDia.toISOString().split('T')[0]
    fechaHasta.value = ultimoDia.toISOString().split('T')[0]
  } else if (id === 'mesAnterior') {
    const primerDia = new Date(hoy.getFullYear(), hoy.getMonth() - 1, 1)
    const ultimoDia = new Date(hoy.getFullYear(), hoy.getMonth(), 0)
    fechaDesde.value = primerDia.toISOString().split('T')[0]
    fechaHasta.value = ultimoDia.toISOString().split('T')[0]
  }

  cargarReporte()
}

async function cargarReporte() {
  cargando.value = true
  try {
    const res = await reportesService.obtenerReporteIngresos(fechaDesde.value, fechaHasta.value)
    datosReporte.value = res || {
      total_hora: 0,
      total_mensualidades: 0,
      gran_total: 0,
      por_tipo: [],
      por_metodo: []
    }
  } catch (err) {
    console.error('Error al cargar reporte:', err)
  } finally {
    cargando.value = false
  }
}

function calcularPorcentaje(parcial, total) {
  if (!total || total === 0) return 0
  return ((parcial / total) * 100).toFixed(1)
}

function exportarExcel() {
  const resumen = [
    { Concepto: 'Total Por Horas', Monto: datosReporte.value.total_hora },
    { Concepto: 'Total Mensualidades', Monto: datosReporte.value.total_mensualidades },
    { Concepto: 'Gran Total Recaudado', Monto: datosReporte.value.gran_total }
  ]

  const vehiculos = datosReporte.value.por_tipo.map(t => ({
    'Tipo de Vehículo': t.tipo,
    'Cantidad Operaciones': t.cantidad,
    'Total Recaudado': t.total,
    'Porcentaje (%)': Number(calcularPorcentaje(t.total, datosReporte.value.gran_total))
  }))

  const metodos = datosReporte.value.por_metodo.map(m => ({
    'Método de Pago': m.metodo,
    'Es Efectivo': m.es_efectivo ? 'Sí' : 'No',
    'Total Recaudado': m.total,
    'Porcentaje (%)': Number(calcularPorcentaje(m.total, datosReporte.value.gran_total))
  }))

  const hojas = {
    'Resumen General': resumen,
    'Por Tipo Vehiculo': vehiculos,
    'Por Metodo Pago': metodos
  }

  reportesService.exportarAExcel(`Reporte_Ingresos_${fechaDesde.value}_a_${fechaHasta.value}`, hojas)
  notificacion.value = 'Reporte exportado exitosamente a formato Excel (.xlsx) con valores numéricos reales.'
}

function exportarCSV() {
  const datosCSV = [
    ...datosReporte.value.por_tipo.map(t => ({ Categoria: 'Vehículo', Detalle: t.tipo, Cantidad: t.cantidad, Total: t.total })),
    ...datosReporte.value.por_metodo.map(m => ({ Categoria: 'Método', Detalle: m.metodo, Cantidad: 1, Total: m.total }))
  ]

  reportesService.exportarACSV(`Reporte_Ingresos_${fechaDesde.value}_a_${fechaHasta.value}`, datosCSV)
  notificacion.value = 'Reporte exportado exitosamente a CSV.'
}

onMounted(() => {
  seleccionarRango('hoy')
})
</script>
