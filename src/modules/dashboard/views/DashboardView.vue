<template>
  <div class="space-y-6 max-w-5xl">
    <div>
      <h2 class="text-xl md:text-2xl font-bold">Dashboard Operativo</h2>
      <p class="text-xs md:text-sm text-text-secondary">Semáforo de cobros, clientes para avisar y resumen del día.</p>
    </div>

    <!-- 1. SEMÁFORO DE VENCIMIENTOS (HU-23) -->
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
      <!-- Tarjeta Roja: Vencidas -->
      <div 
        @click="filtroColor = (filtroColor === 'rojo' ? null : 'rojo')"
        class="bg-surface p-4 rounded-2xl border cursor-pointer transition-all hover:shadow-md"
        :class="filtroColor === 'rojo' ? 'ring-2 ring-danger border-danger shadow-md' : 'border-border'"
      >
        <div class="flex items-center space-x-2">
          <span class="w-3 h-3 rounded-full bg-danger animate-pulse"></span>
          <span class="text-xs font-bold uppercase tracking-wider text-danger">ROJO · Vencidas</span>
        </div>
        <p class="text-3xl font-black text-danger mt-2">
          {{ datos.semaforo.rojo.count }} <span class="text-sm font-semibold text-text-muted">clientes</span>
        </p>
        <p class="text-xs font-bold text-text-primary mt-1">
          ${{ datos.semaforo.rojo.valor.toLocaleString() }} por cobrar
        </p>
      </div>

      <!-- Tarjeta Amarilla: Por Vencer -->
      <div 
        @click="filtroColor = (filtroColor === 'amarillo' ? null : 'amarillo')"
        class="bg-surface p-4 rounded-2xl border cursor-pointer transition-all hover:shadow-md"
        :class="filtroColor === 'amarillo' ? 'ring-2 ring-warning border-warning shadow-md' : 'border-border'"
      >
        <div class="flex items-center space-x-2">
          <span class="w-3 h-3 rounded-full bg-warning"></span>
          <span class="text-xs font-bold uppercase tracking-wider text-warning">AMARILLO · Por vencer</span>
        </div>
        <p class="text-3xl font-black text-warning mt-2">
          {{ datos.semaforo.amarillo.count }} <span class="text-sm font-semibold text-text-muted">clientes</span>
        </p>
        <p class="text-xs text-text-secondary mt-1">
          <strong class="text-danger">{{ datos.semaforo.amarillo.vencenHoy }} vencen hoy</strong> · ${{ datos.semaforo.amarillo.valor.toLocaleString() }}
        </p>
      </div>

      <!-- Tarjeta Verde: Al Día -->
      <div 
        @click="filtroColor = (filtroColor === 'verde' ? null : 'verde')"
        class="bg-surface p-4 rounded-2xl border cursor-pointer transition-all hover:shadow-md"
        :class="filtroColor === 'verde' ? 'ring-2 ring-success border-success shadow-md' : 'border-border'"
      >
        <div class="flex items-center space-x-2">
          <span class="w-3 h-3 rounded-full bg-success"></span>
          <span class="text-xs font-bold uppercase tracking-wider text-success">VERDE · Al día</span>
        </div>
        <p class="text-3xl font-black text-success mt-2">
          {{ datos.semaforo.verde.count }} <span class="text-sm font-semibold text-text-muted">clientes</span>
        </p>
        <p class="text-xs text-text-muted mt-1">
          Sin acción pendiente
        </p>
      </div>
    </div>

    <!-- 2. CLIENTES PARA AVISAR (HU-19, HU-23) -->
    <div class="bg-surface rounded-2xl border border-border p-5 space-y-4 shadow-sm">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-border pb-3">
        <div>
          <h3 class="font-bold text-sm text-text-primary">
            Clientes para Avisar y Cobrar ({{ clientesFiltrados.length }})
          </h3>
          <p class="text-[11px] text-text-secondary">Priorizados por fecha de vencimiento. Pulsa el teléfono para llamar desde el móvil.</p>
        </div>

        <label class="flex items-center space-x-2 text-xs font-semibold cursor-pointer">
          <input v-model="soloSinAvisar" type="checkbox" class="rounded text-primary focus:ring-0" />
          <span>Solo sin avisar</span>
        </label>
      </div>

      <div v-if="clientesFiltrados.length === 0" class="text-center py-6 text-xs text-text-muted">
        No hay clientes pendientes en este filtro. ¡Todo al día!
      </div>

      <div v-else class="space-y-2">
        <div 
          v-for="c in clientesFiltrados" 
          :key="c.id"
          class="p-3.5 rounded-xl bg-surface-elevated/60 border border-border flex flex-col sm:flex-row sm:items-center justify-between gap-3 hover:border-primary/40 transition-colors"
        >
          <div class="flex items-start space-x-3">
            <span 
              class="w-3 h-3 rounded-full mt-1 flex-shrink-0"
              :class="c.clasificacion.color === 'rojo' ? 'bg-danger' : 'bg-warning'"
            ></span>
            <div>
              <div class="flex items-center space-x-2">
                <span class="font-bold text-sm text-text-primary">{{ c.clientes?.nombre }}</span>
                <span class="font-mono font-bold text-xs px-2 py-0.5 rounded bg-surface border border-border text-primary">
                  {{ c.vehiculos?.placa }}
                </span>
              </div>
              <div class="text-xs text-text-secondary mt-0.5 flex flex-wrap gap-x-3 gap-y-1">
                <span>Vence: <strong :class="c.clasificacion.color === 'rojo' ? 'text-danger' : 'text-warning'">{{ formatVenceRelativo(c) }}</strong></span>
                <a :href="`tel:${c.clientes?.telefono}`" class="text-primary font-bold hover:underline">
                  📞 {{ c.clientes?.telefono || 'Sin teléfono' }}
                </a>
                <span>Valor: <strong>${{ (c.planes_mensuales?.valor || 0).toLocaleString() }}</strong></span>
              </div>
              <p class="text-[11px] text-text-muted mt-0.5">
                Estado aviso: <strong class="text-text-primary">{{ c.ultimoAviso ? `${c.ultimoAviso.medio} (${c.ultimoAviso.nota || 'Sin nota'})` : 'Sin avisar' }}</strong>
              </p>
            </div>
          </div>

          <div class="flex items-center space-x-2 self-end sm:self-center">
            <router-link to="/mensualidades" class="btn-secondary text-xs">
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
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { dashboardService } from '@/modules/dashboard/services/dashboardService'

const authStore = useAuthStore()

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
  try {
    datos.value = await dashboardService.obtenerDatosDashboard(pqId)
  } catch (err) {
    console.warn(err)
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
