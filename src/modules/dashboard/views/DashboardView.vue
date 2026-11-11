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
      <!-- 1. SEMÁFORO DE VENCIMIENTOS (BENTO GRID CON PALETA PASTEL DE ALERTA) -->
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <!-- Tarjeta Roja: Hero Alert (Vencidas) -->
        <div 
          @click="filtroColor = (filtroColor === 'rojo' ? null : 'rojo')"
          class="card-craft pastel-card-rose p-5 cursor-pointer relative overflow-hidden transition-all"
          :class="filtroColor === 'rojo' ? 'ring-2 ring-rose-500 shadow-md scale-[1.01]' : 'hover:border-rose-400'"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-2">
              <span class="relative flex h-2.5 w-2.5">
                <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-rose-400 opacity-75"></span>
                <span class="relative inline-flex rounded-full h-2.5 w-2.5 bg-rose-500"></span>
              </span>
              <span class="text-[11px] font-black uppercase tracking-wider text-rose-800 dark:text-rose-300">Vencidas</span>
            </div>
            <span class="badge-pastel-rose text-[10px] font-black px-2 py-0.5 rounded-full">
              Prioridad
            </span>
          </div>

          <div class="mt-3 flex items-baseline space-x-2">
            <span class="text-4xl font-black text-rose-700 dark:text-rose-400 num-tabular">{{ datos.semaforo.rojo.count }}</span>
            <span class="text-xs font-bold text-text-muted">clientes en mora</span>
          </div>

          <p class="text-xs font-black text-rose-800 dark:text-rose-300 mt-2 font-mono num-tabular">
            ${{ datos.semaforo.rojo.valor.toLocaleString() }} <span class="font-sans font-normal text-text-muted">por cobrar</span>
          </p>
        </div>

        <!-- Tarjeta Amarilla: Por Vencer -->
        <div 
          @click="filtroColor = (filtroColor === 'amarillo' ? null : 'amarillo')"
          class="card-craft pastel-card-amber p-5 cursor-pointer relative overflow-hidden transition-all"
          :class="filtroColor === 'amarillo' ? 'ring-2 ring-amber-500 shadow-md scale-[1.01]' : 'hover:border-amber-400'"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-2">
              <span class="w-2.5 h-2.5 rounded-full bg-amber-500"></span>
              <span class="text-[11px] font-black uppercase tracking-wider text-amber-800 dark:text-amber-300">Por Vencer</span>
            </div>
            <span v-if="datos.semaforo.amarillo.vencenHoy > 0" class="badge-pastel-rose text-[10px] font-black px-2 py-0.5 rounded-full animate-pulse">
              ¡{{ datos.semaforo.amarillo.vencenHoy }} hoy!
            </span>
            <span v-else class="badge-pastel-amber text-[10px] font-bold px-2 py-0.5 rounded-full">
              Próximos 7d
            </span>
          </div>

          <div class="mt-3 flex items-baseline space-x-2">
            <span class="text-4xl font-black text-amber-700 dark:text-amber-400 num-tabular">{{ datos.semaforo.amarillo.count }}</span>
            <span class="text-xs font-bold text-text-muted">próximos</span>
          </div>

          <p class="text-xs font-black text-amber-800 dark:text-amber-300 mt-2 font-mono num-tabular">
            ${{ datos.semaforo.amarillo.valor.toLocaleString() }} <span class="font-sans font-normal text-text-muted">en alerta</span>
          </p>
        </div>

        <!-- Tarjeta Verde: Al Día -->
        <div 
          @click="filtroColor = (filtroColor === 'verde' ? null : 'verde')"
          class="card-craft pastel-card-mint p-5 cursor-pointer relative overflow-hidden transition-all"
          :class="filtroColor === 'verde' ? 'ring-2 ring-emerald-500 shadow-md scale-[1.01]' : 'hover:border-emerald-400'"
        >
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-2">
              <span class="w-2.5 h-2.5 rounded-full bg-emerald-500"></span>
              <span class="text-[11px] font-black uppercase tracking-wider text-emerald-800 dark:text-emerald-300">Al Día</span>
            </div>
            <span class="badge-pastel-mint text-[10px] font-bold px-2 py-0.5 rounded-full">Vigentes</span>
          </div>

          <div class="mt-3 flex items-baseline space-x-2">
            <span class="text-4xl font-black text-emerald-700 dark:text-emerald-400 num-tabular">{{ datos.semaforo.verde.count }}</span>
            <span class="text-xs font-bold text-text-muted">al día</span>
          </div>

          <p class="text-xs text-emerald-800 dark:text-emerald-300 mt-2 font-medium">
            Sin acciones pendientes
          </p>
        </div>
      </div>

    <!-- 2. CLIENTES PARA AVISAR (HU-19, HU-23) -->
    <div class="card-craft p-5 space-y-4">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2 border-b border-border/60 pb-3">
        <div>
          <h3 class="font-black text-sm tracking-tight text-text-primary flex items-center space-x-2">
            <span>Clientes para Avisar y Cobrar</span>
            <span class="badge-pastel-blue text-[11px] font-black px-2 py-0.5 rounded-full">{{ clientesFiltrados.length }}</span>
          </h3>
          <p class="text-[11px] text-text-muted">Priorizados por urgencia de mora. Pulsa en WhatsApp para contactar en 1 clic.</p>
        </div>

        <label class="flex items-center space-x-2 text-xs font-semibold cursor-pointer select-none">
          <input v-model="soloSinAvisar" type="checkbox" class="rounded text-primary focus:ring-0" />
          <span>Solo sin avisar</span>
        </label>
      </div>

      <div v-if="clientesFiltrados.length === 0" class="text-center py-8 text-xs text-text-muted space-y-1">
        <p class="text-base">🎉</p>
        <p class="font-bold text-text-primary">No hay clientes pendientes en este filtro</p>
        <p>¡Toda la cartera de abonados está al día!</p>
      </div>

      <div v-else class="space-y-2.5">
        <div 
          v-for="c in clientesFiltrados" 
          :key="c.id"
          class="p-4 rounded-xl border flex flex-col sm:flex-row sm:items-center justify-between gap-3 transition-all"
          :class="c.clasificacion.color === 'rojo' ? 'pastel-card-rose' : 'pastel-card-amber'"
        >
          <div class="flex items-start space-x-3.5">
            <span 
              class="w-2.5 h-2.5 rounded-full mt-1.5 flex-shrink-0"
              :class="c.clasificacion.color === 'rojo' ? 'bg-rose-500 animate-pulse' : 'bg-amber-500'"
            ></span>
            <div class="space-y-1">
              <div class="flex items-center space-x-2.5 flex-wrap gap-y-1">
                <span class="font-black text-sm text-text-primary">{{ c.clientes?.nombre }}</span>
                <span class="plate-colombia plate-carro text-[10px]">
                  {{ c.vehiculos?.placa }}
                </span>
                <span 
                  class="text-[10px] font-black px-2 py-0.5 rounded-full"
                  :class="c.clasificacion.color === 'rojo' ? 'badge-pastel-rose' : 'badge-pastel-amber'"
                >
                  {{ formatVenceRelativo(c) }}
                </span>
              </div>
              <div class="text-xs text-text-secondary flex flex-wrap gap-x-3 gap-y-1 items-center">
                <!-- Enlace directo WhatsApp -->
                <a 
                  :href="generarLinkWhatsApp(c)" 
                  target="_blank"
                  rel="noopener noreferrer"
                  class="inline-flex items-center space-x-1 text-emerald-700 dark:text-emerald-400 font-bold hover:underline bg-emerald-50 dark:bg-emerald-950/40 px-2.5 py-0.5 rounded-full border border-emerald-200 dark:border-emerald-800/40 text-[11px]"
                  title="Abrir WhatsApp para recordarle el cobro"
                >
                  <span>💬 WhatsApp</span>
                  <span>{{ c.clientes?.telefono || 'Sin teléfono' }}</span>
                </a>
                <span class="font-mono font-black text-text-primary num-tabular">${{ (c.planes_mensuales?.valor || 0).toLocaleString() }}</span>
              </div>
              <p class="text-[11px] text-text-muted">
                Último aviso: <strong>{{ c.ultimoAviso ? `${c.ultimoAviso.medio} (${c.ultimoAviso.nota || 'Sin nota'})` : 'Sin avisar todavía' }}</strong>
              </p>
            </div>
          </div>

          <div class="flex items-center space-x-2 self-end sm:self-center">
            <router-link to="/mensualidades" class="px-3 py-1.5 rounded-xl border border-border bg-surface hover:bg-surface-elevated text-text-primary text-xs font-bold transition-all shadow-xs">
              Ver en Agenda
            </router-link>
          </div>
        </div>
      </div>
    </div>

    <!-- 3. OCUPACIÓN Y ACCESOS RÁPIDOS DE PATIO -->
    <div class="card-craft pastel-card-sky p-5 flex flex-col sm:flex-row sm:items-center justify-between gap-3 shadow-xs">
      <div class="flex items-center space-x-3.5">
        <div class="w-11 h-11 rounded-2xl bg-sky-100 dark:bg-sky-950/60 text-sky-800 dark:text-sky-200 flex items-center justify-center font-bold text-xl shadow-xs border border-sky-200 dark:border-sky-800/40">
          🚗
        </div>
        <div>
          <h4 class="font-black text-sm text-text-primary">Ocupación Actual de Patio</h4>
          <p class="text-xs text-text-secondary">{{ datos.ocupacionCount }} vehículos presentes en este momento en parqueadero.</p>
        </div>
      </div>

      <div class="flex space-x-2">
        <router-link to="/ocupacion" class="btn-craft-primary text-xs py-2 px-4 rounded-xl text-white font-bold shadow-xs">
          Ir al Patio de Parqueo →
        </router-link>
      </div>
    </div>

    <!-- 4. MÉTRICAS PARA EL ADMINISTRADOR (HU-23) -->
    <div v-if="authStore.isAdmin" class="card-craft p-5 space-y-3">
      <h3 class="font-black text-xs uppercase tracking-wider text-text-muted">Cifras Administrativas de Hoy</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="p-4 rounded-xl pastel-card-mint border space-y-1">
          <span class="text-xs font-bold text-emerald-800 dark:text-emerald-300">Efectivo Esperado en Caja:</span>
          <p class="text-3xl font-black text-emerald-700 dark:text-emerald-400 font-mono num-tabular">${{ datos.ingresos.efectivoCaja.toLocaleString() }}</p>
          <p class="text-[11px] text-text-muted">Base de turno: ${{ datos.ingresos.baseInicial.toLocaleString() }}</p>
        </div>

        <div class="p-4 rounded-xl pastel-card-amber border space-y-1">
          <span class="text-xs font-bold text-amber-800 dark:text-amber-300">Total a Cobrar Próximos 7 Días:</span>
          <p class="text-3xl font-black text-amber-700 dark:text-amber-400 font-mono num-tabular">${{ datos.ingresos.porCobrarProximos7Dias.toLocaleString() }}</p>
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

function generarLinkWhatsApp(c) {
  const tel = (c.clientes?.telefono || '').replace(/\D/g, '')
  if (!tel) return '#'
  const numeroCompleto = tel.startsWith('57') ? tel : `57${tel}`
  const nombreCliente = c.clientes?.nombre || 'Cliente'
  const placa = c.vehiculos?.placa || ''
  const pqNombre = authStore.parqueadero?.nombre || 'el parqueadero'
  const valor = (c.planes_mensuales?.valor || 0).toLocaleString()
  const diasMora = c.clasificacion?.diasMora || 0
  
  let texto = ''
  if (c.clasificacion?.esHoy) {
    texto = `Hola ${nombreCliente}, te saludamos de ${pqNombre}. Te informamos que tu mensualidad del vehículo ${placa} vence el día de HOY. El valor es de $${valor} COP.`
  } else if (diasMora > 0) {
    texto = `Hola ${nombreCliente}, cordial saludo de ${pqNombre}. Te recordamos que tu mensualidad del vehículo ${placa} presenta ${diasMora} días de mora. El valor a cancelar es $${valor} COP.`
  } else {
    texto = `Hola ${nombreCliente}, te recordamos de ${pqNombre} que la mensualidad del vehículo ${placa} vencerá próximamente.`
  }
  return `https://wa.me/${numeroCompleto}?text=${encodeURIComponent(texto)}`
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
