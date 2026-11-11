<template>
  <div class="space-y-6 max-w-5xl">
    <div>
      <h2 class="text-xl md:text-2xl font-bold">Dashboard Operativo</h2>
      <p class="text-xs md:text-sm text-text-secondary">Semáforo de cobros, clientes para avisar y resumen del día.</p>
    </div>

    <!-- Spinner de carga -->
    <div v-if="cargando" class="flex flex-col items-center justify-center py-24 text-text-muted space-y-3">
      <div class="w-8 h-8 border-3 border-primary/20 border-t-primary rounded-full animate-spin"></div>
      <span class="text-xs font-semibold">Cargando métricas del día...</span>
    </div>

    <template v-else>
      <!-- 1. SEMÁFORO DE VENCIMIENTOS (BENTO GRID ASIMÉTRICO) -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <!-- Tarjeta Roja: Hero Alert (Vencidas) -->
        <div 
          @click="filtroColor = (filtroColor === 'rojo' ? null : 'rojo')"
          class="card-craft p-5 cursor-pointer relative overflow-hidden"
          :class="filtroColor === 'rojo' ? 'ring-2 ring-danger border-danger shadow-md' : 'border-danger/30 hover:border-danger/60'"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-2">
              <span class="relative flex h-2.5 w-2.5">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-danger opacity-75"></span>
                <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-danger"></span>
              </span>
              <span class="text-[11px] font-black uppercase tracking-wider text-danger">ROJO · Vencidas</span>
            </div>
            <span class="text-[10px] font-bold px-2 py-0.5 rounded-full bg-danger/10 text-danger border border-danger/20">
              Prioritario
            </span>
          </div>

          <div class="mt-3 flex items-baseline space-x-2">
            <span class="text-4xl font-black text-danger num-tabular">{{ datos.semaforo.rojo.count }}</span>
            <span class="text-xs font-bold text-text-muted">clientes en mora</span>
          </div>

          <p class="text-xs font-black text-text-primary mt-2 font-mono num-tabular">
            ${{ datos.semaforo.rojo.valor.toLocaleString() }} <span class="font-sans font-normal text-text-muted">por cobrar</span>
          </p>
        </div>

        <!-- Tarjeta Amarilla: Por Vencer -->
        <div 
          @click="filtroColor = (filtroColor === 'amarillo' ? null : 'amarillo')"
          class="card-craft p-5 cursor-pointer relative overflow-hidden"
          :class="filtroColor === 'amarillo' ? 'ring-2 ring-warning border-warning shadow-md' : 'border-warning/30 hover:border-warning/60'"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-2">
              <span class="w-2.5 h-2.5 rounded-full bg-warning"></span>
              <span class="text-[11px] font-black uppercase tracking-wider text-warning">AMARILLO · Por vencer</span>
            </div>
            <span v-if="datos.semaforo.amarillo.vencenHoy > 0" class="text-[10px] font-black px-2 py-0.5 rounded-full bg-warning/15 text-warning border border-warning/30">
              ¡{{ datos.semaforo.amarillo.vencenHoy }} hoy!
            </span>
          </div>

          <div class="mt-3 flex items-baseline space-x-2">
            <span class="text-4xl font-black text-warning num-tabular">{{ datos.semaforo.amarillo.count }}</span>
            <span class="text-xs font-bold text-text-muted">próximos</span>
          </div>

          <p class="text-xs font-semibold text-text-secondary mt-2 font-mono num-tabular">
            ${{ datos.semaforo.amarillo.valor.toLocaleString() }} <span class="font-sans font-normal text-text-muted">en alerta</span>
          </p>
        </div>

        <!-- Tarjeta Verde: Al Día -->
        <div 
          @click="filtroColor = (filtroColor === 'verde' ? null : 'verde')"
          class="card-craft p-5 cursor-pointer relative overflow-hidden"
          :class="filtroColor === 'verde' ? 'ring-2 ring-success border-success shadow-md' : 'border-success/30 hover:border-success/60'"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-2">
              <span class="w-2.5 h-2.5 rounded-full bg-success"></span>
              <span class="text-[11px] font-black uppercase tracking-wider text-success">VERDE · Al día</span>
            </div>
            <span class="text-[10px] font-semibold text-text-muted">Vigente</span>
          </div>

          <div class="mt-3 flex items-baseline space-x-2">
            <span class="text-4xl font-black text-success num-tabular">{{ datos.semaforo.verde.count }}</span>
            <span class="text-xs font-bold text-text-muted">al día</span>
          </div>

          <p class="text-xs text-text-muted mt-2">
            Sin acciones pendientes
          </p>
        </div>
      </div>

    <!-- 2. CLIENTES PARA AVISAR (HU-19, HU-23) -->
    <div class="card-craft p-5 space-y-4">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-border pb-3">
        <div>
          <h3 class="font-black text-sm tracking-tight text-text-primary">
            Clientes para Avisar y Cobrar ({{ clientesFiltrados.length }})
          </h3>
          <p class="text-[11px] text-text-muted">Priorizados por urgencia de mora. Pulsa el teléfono o WhatsApp para contactar de inmediato.</p>
        </div>

        <label class="flex items-center space-x-2 text-xs font-semibold cursor-pointer">
          <input v-model="soloSinAvisar" type="checkbox" class="rounded text-primary focus:ring-0" />
          <span>Solo sin avisar</span>
        </label>
      </div>

      <div v-if="clientesFiltrados.length === 0" class="text-center py-6 text-xs text-text-muted">
        No hay clientes pendientes en este filtro. ¡Todo al día!
      </div>

      <div v-else class="space-y-2.5">
        <div 
          v-for="c in clientesFiltrados" 
          :key="c.id"
          class="p-3.5 rounded-xl bg-surface-elevated/70 border border-border flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:border-primary/50 transition-all"
        >
          <div class="flex items-start space-x-3">
            <span 
              class="w-2.5 h-2.5 rounded-full mt-1.5 flex-shrink-0"
              :class="c.clasificacion.color === 'rojo' ? 'bg-danger animate-pulse' : 'bg-warning'"
            ></span>
            <div class="space-y-1">
              <div class="flex items-center space-x-2.5">
                <span class="font-black text-sm text-text-primary">{{ c.clientes?.nombre }}</span>
                <span class="plate-colombia plate-carro text-[10px]">
                  {{ c.vehiculos?.placa }}
                </span>
              </div>
              <div class="text-xs text-text-secondary flex flex-wrap gap-x-3 gap-y-1 items-center">
                <span>Vence: <strong :class="c.clasificacion.color === 'rojo' ? 'text-danger font-black' : 'text-warning font-black'">{{ formatVenceRelativo(c) }}</strong></span>
                <a :href="`tel:${c.clientes?.telefono}`" class="text-primary font-bold hover:underline inline-flex items-center space-x-1">
                  <span>📞</span>
                  <span>{{ c.clientes?.telefono || 'Sin teléfono' }}</span>
                </a>
                <span class="font-mono font-bold text-text-primary num-tabular">${{ (c.planes_mensuales?.valor || 0).toLocaleString() }}</span>
              </div>
              <p class="text-[11px] text-text-muted">
                Último aviso: <strong class="text-text-primary">{{ c.ultimoAviso ? `${c.ultimoAviso.medio} (${c.ultimoAviso.nota || 'Sin nota'})` : 'Sin avisar todavía' }}</strong>
              </p>
            </div>
          </div>

          <div class="flex items-center space-x-2 self-end sm:self-center">
            <router-link to="/mensualidades" class="btn-secondary text-xs py-1.5 px-3">
              Ver en Agenda
            </router-link>
          </div>
        </div>
      </div>
    </div>

    <!-- 3. OCUPACIÓN Y ACCESOS RÁPIDOS DE PATIO -->
    <div class="bg-surface rounded-2xl border border-border p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-sm">
      <div class="flex items-center space-x-3">
        <div class="w-10 h-10 rounded-xl bg-primary/10 text-primary flex items-center justify-center font-bold text-lg">
          🚗
        </div>
        <div>
          <h4 class="font-bold text-sm text-text-primary">Ocupación Actual de Patio</h4>
          <p class="text-xs text-text-secondary">{{ datos.ocupacionCount }} vehículos presentes en este momento.</p>
        </div>
      </div>

      <div class="flex space-x-2">
        <router-link to="/ocupacion" class="btn-primary text-xs py-2 px-3">
          Ir al Patio
        </router-link>
      </div>
    </div>

    <!-- 4. MÉTRICAS PARA EL ADMINISTRADOR (HU-23) -->
    <div v-if="authStore.isAdmin" class="bg-surface rounded-2xl border border-border p-5 space-y-3 shadow-sm">
      <h3 class="font-bold text-xs uppercase tracking-wider text-text-muted">Cifras Administrativas de Hoy</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="p-3.5 rounded-xl bg-surface-elevated border border-border space-y-1">
          <span class="text-xs text-text-secondary">Efectivo Esperado en Caja:</span>
          <p class="text-2xl font-black text-primary">${{ datos.ingresos.efectivoCaja.toLocaleString() }}</p>
          <p class="text-[11px] text-text-muted">Base de turno: ${{ datos.ingresos.baseInicial.toLocaleString() }}</p>
        </div>

        <div class="p-3.5 rounded-xl bg-surface-elevated border border-border space-y-1">
          <span class="text-xs text-text-secondary">Total a Cobrar Próximos 7 Días:</span>
          <p class="text-2xl font-black text-warning">${{ datos.ingresos.porCobrarProximos7Dias.toLocaleString() }}</p>
          <p class="text-[11px] text-text-muted">Mensualidades en cobro inminente</p>
        </div>
      </div>
    </div>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { dashboardService } from '@/modules/dashboard/services/dashboardService'

const authStore = useAuthStore()

const cargando = ref(true)
const filtroColor = ref(null)
const soloSinAvisar = ref(true)

const datos = ref({
  semaforo: {
    rojo: { count: 0, valor: 0, mensualidades: [] },
    amarillo: { count: 0, valor: 0, vencenHoy: 0, mensualidades: [] },
    verde: { count: 0, valor: 0, mensualidades: [] }
  },
  clientesAvisar: [],
  ocupacionCount: 0,
  ingresos: { efectivoCaja: 0, baseInicial: 0, porCobrarProximos7Dias: 0 }
})

const clientesFiltrados = computed(() => {
  let lista = datos.value.clientesAvisar

  if (filtroColor.value) {
    lista = lista.filter(c => c.clasificacion.color === filtroColor.value)
  }

  if (soloSinAvisar.value) {
    lista = lista.filter(c => !c.ultimoAviso)
  }

  return lista
})

function formatVenceRelativo(c) {
  if (c.clasificacion.esHoy) return '¡Hoy!'
  if (c.clasificacion.diasRestantes > 0) return `en ${c.clasificacion.diasRestantes} días`
  return `hace ${c.clasificacion.diasMora} días`
}

async function cargarDashboard() {
  const pqId = authStore.parqueaderoId
  const cached = dashboardService.obtenerDashboardCache()
  
  if (cached) {
    datos.value = cached
    cargando.value = false
  } else {
    cargando.value = true
  }

  try {
    datos.value = await dashboardService.obtenerDatosDashboard(pqId)
  } catch (err) {
    console.warn(err)
  } finally {
    cargando.value = false
  }
}

onMounted(() => {
  cargarDashboard()
})
</script>

<style scoped>
.btn-primary {
  @apply px-4 py-2 rounded-lg bg-primary text-white font-semibold hover:opacity-90 transition-opacity disabled:opacity-50 shadow-sm;
}
.btn-secondary {
  @apply px-3 py-1.5 rounded-lg border border-border bg-surface text-text-primary hover:bg-surface-elevated transition-colors font-medium;
}
</style>
