<template>
  <div class="min-h-screen flex flex-col bg-background text-text-primary transition-colors duration-200">
    <!-- Banner de Alerta de Desfase Horario (Recomendación #1) -->
    <div 
      v-if="conexionStore.hasClockDriftWarning" 
      class="bg-warning-bg border-b border-warning text-warning px-4 py-2 text-xs md:text-sm font-medium flex items-center justify-between"
    >
      <div class="flex items-center space-x-2">
        <svg class="w-4 h-4 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
        </svg>
        <span>
          <strong>Advertencia de reloj:</strong> La hora de tu dispositivo difiere más de 5 minutos del servidor. Las operaciones locales se ajustarán automáticamente.
        </span>
      </div>
      <button 
        @click="conexionStore.hasClockDriftWarning = false"
        class="text-xs font-bold underline ml-2"
      >
        Entendido
      </button>
    </div>

    <!-- Header Superior -->
    <header class="bg-surface border-b border-border sticky top-0 z-30 px-4 py-2.5 flex items-center justify-between shadow-sm">
      <div class="flex items-center space-x-3">
        <div class="w-9 h-9 rounded-xl bg-gradient-to-br from-primary to-blue-700 text-white flex items-center justify-center font-black text-base shadow-sm ring-1 ring-white/20">
          P
        </div>
        <div>
          <div class="flex items-center space-x-2">
            <h1 class="text-sm md:text-base font-black tracking-tight text-text-primary leading-tight">
              {{ authStore.isSuperadmin ? 'ParkControl · Superadmin' : (authStore.parqueadero?.nombre || 'ParkControl') }}
            </h1>
            <span v-if="!authStore.isSuperadmin" class="hidden sm:inline-flex text-[10px] font-bold px-1.5 py-0.5 rounded bg-surface-elevated text-text-muted border border-border uppercase">
              Operativo
            </span>
          </div>
          <p class="text-xs text-text-muted flex items-center space-x-1.5 mt-0.5">
            <span v-if="!authStore.isSuperadmin" class="flex items-center">
              <span class="relative flex h-2 w-2 mr-1.5">
                <span v-if="tieneTurnoAbierto" class="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400 opacity-75"></span>
                <span class="relative inline-flex rounded-full h-2 w-2" :class="tieneTurnoAbierto ? 'bg-emerald-500' : 'bg-amber-500'"></span>
              </span>
              <span class="font-medium text-[11px]" :class="tieneTurnoAbierto ? 'text-emerald-600 dark:text-emerald-400 font-semibold' : 'text-amber-600 dark:text-amber-400'">
                {{ tieneTurnoAbierto ? 'Turno Abierto' : 'Caja sin Turno' }}
              </span>
            </span>
            <span v-else class="text-[11px]">Plataforma Global Multi-Tenant</span>
          </p>
        </div>
      </div>

      <div class="flex items-center space-x-2">
        <!-- Indicador de Conexión Offline / Online y Botón Sincronizar (HU-26) -->
        <div class="flex items-center space-x-1.5">
          <div 
            class="flex items-center text-xs px-2.5 py-1 rounded-lg font-medium border"
            :class="conexionStore.isOnline ? 'bg-emerald-500/10 text-emerald-600 dark:text-emerald-400 border-emerald-500/20' : 'bg-amber-500/10 text-amber-600 dark:text-amber-400 border-amber-500/20'"
          >
            <span class="w-1.5 h-1.5 rounded-full mr-1.5" :class="conexionStore.isOnline ? 'bg-emerald-500' : 'bg-amber-500 animate-pulse'"></span>
            <span class="font-semibold text-[11px]">
              {{ conexionStore.isOnline ? (conexionStore.pendingOperationsCount > 0 ? `${conexionStore.pendingOperationsCount} pendientes` : 'En línea') : `Sin red (${conexionStore.pendingOperationsCount})` }}
            </span>
          </div>

          <!-- Botón Sincronizar ahora -->
          <button 
            v-if="conexionStore.pendingOperationsCount > 0 && conexionStore.isOnline"
            @click="ejecutarSincronizacion"
            :disabled="sincronizandoManual"
            class="text-[11px] font-bold px-2 py-1 rounded-lg bg-primary text-white hover:opacity-90 disabled:opacity-50 shadow-sm"
          >
            {{ sincronizandoManual ? 'Sincronizando...' : 'Sincronizar' }}
          </button>
        </div>

        <!-- Selector de Tema (HU-10) -->
        <button 
          @click="toggleTheme" 
          class="p-1.5 rounded-lg border border-border bg-surface hover:bg-surface-elevated text-text-secondary hover:text-text-primary transition-colors"
          title="Cambiar tema claro / oscuro"
        >
          <svg v-if="temaStore.isDark" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 3v1m0 16v1m9-9h-1M4 12H3m15.364 6.364l-.707-.707M6.343 6.343l-.707-.707m12.728 0l-.707.707M6.343 17.657l-.707.707M16 12a4 4 0 11-8 0 4 4 0 018 0z" />
          </svg>
          <svg v-else class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M20.354 15.354A9 9 0 018.646 3.646 9.003 9.003 0 0012 21a9.003 9.003 0 008.354-5.646z" />
          </svg>
        </button>

        <!-- Botón Salir (HU-02) -->
        <button 
          @click="handleLogout"
          class="p-1.5 rounded-lg border border-border bg-surface text-danger hover:bg-danger-bg transition-colors"
          title="Cerrar sesión"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
          </svg>
        </button>
      </div>
    </header>

    <!-- Contenedor Principal (Escritorio: Sidebar + Contenido) -->
    <div class="flex-1 flex overflow-hidden">
      <!-- Navegación lateral en escritorio (md+) -->
      <aside class="hidden md:flex flex-col w-64 bg-surface border-r border-border p-3.5 space-y-1 justify-between">
        <div class="space-y-1">
          <!-- Opciones para Superadmin -->
          <template v-if="authStore.isSuperadmin">
            <router-link 
              to="/superadmin" 
              class="flex items-center space-x-2.5 px-3 py-2 text-xs font-semibold rounded-xl transition-all"
              :class="$route.name === 'superadmin' ? 'bg-primary text-white shadow-sm' : 'text-text-secondary hover:bg-surface-elevated hover:text-text-primary'"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4" /></svg>
              <span>Parqueaderos</span>
            </router-link>
          </template>

          <!-- Opciones para Admin y Operador -->
          <template v-else>
            <router-link 
              v-if="authStore.isAdmin"
              to="/" 
              class="flex items-center space-x-2.5 px-3 py-2 text-xs font-semibold rounded-xl transition-all"
              :class="$route.name === 'dashboard' ? 'bg-primary text-white shadow-sm' : 'text-text-secondary hover:bg-surface-elevated hover:text-text-primary'"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6" /></svg>
              <span>Dashboard</span>
            </router-link>
            <router-link 
              to="/ocupacion" 
              class="flex items-center space-x-2.5 px-3 py-2 text-xs font-semibold rounded-xl transition-all"
              :class="$route.name === 'ocupacion' ? 'bg-primary text-white shadow-sm' : 'text-text-secondary hover:bg-surface-elevated hover:text-text-primary'"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4" /></svg>
              <span>Patio de Parqueo</span>
            </router-link>
            <router-link 
              to="/mensualidades" 
              class="flex items-center space-x-2.5 px-3 py-2 text-xs font-semibold rounded-xl transition-all"
              :class="$route.name === 'mensualidades' ? 'bg-primary text-white shadow-sm' : 'text-text-secondary hover:bg-surface-elevated hover:text-text-primary'"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" /></svg>
              <span>Mensualidades</span>
            </router-link>
            <router-link 
              to="/caja" 
              class="flex items-center space-x-2.5 px-3 py-2 text-xs font-semibold rounded-xl transition-all"
              :class="$route.name === 'caja' ? 'bg-primary text-white shadow-sm' : 'text-text-secondary hover:bg-surface-elevated hover:text-text-primary'"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" /></svg>
              <span>Caja y Turno</span>
            </router-link>
            <router-link 
              v-if="authStore.isAdmin"
              to="/comprobantes" 
              class="flex items-center space-x-2.5 px-3 py-2 text-xs font-semibold rounded-xl transition-all"
              :class="$route.name === 'comprobantes' ? 'bg-primary text-white shadow-sm' : 'text-text-secondary hover:bg-surface-elevated hover:text-text-primary'"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" /></svg>
              <span>Comprobantes</span>
            </router-link>
            <router-link 
              v-if="authStore.isAdmin"
              to="/reportes" 
              class="flex items-center space-x-2.5 px-3 py-2 text-xs font-semibold rounded-xl transition-all"
              :class="$route.name === 'reportes' ? 'bg-primary text-white shadow-sm' : 'text-text-secondary hover:bg-surface-elevated hover:text-text-primary'"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" /></svg>
              <span>Reportes</span>
            </router-link>
            <router-link 
              v-if="authStore.isAdmin"
              to="/ajustes" 
              class="flex items-center space-x-2.5 px-3 py-2 text-xs font-semibold rounded-xl transition-all"
              :class="!conexionStore.isOnline ? 'opacity-40 pointer-events-none' : ($route.name === 'ajustes' ? 'bg-primary text-white shadow-sm' : 'text-text-secondary hover:bg-surface-elevated hover:text-text-primary')"
              :title="!conexionStore.isOnline ? 'Ajustes requiere conexión a internet' : ''"
            >
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
              <span>Ajustes</span>
            </router-link>
          </template>
        </div>

        <!-- Perfil del usuario activo -->
        <div class="pt-3 border-t border-border flex items-center justify-between text-xs">
          <div class="truncate pr-2">
            <p class="font-bold text-text-primary truncate">{{ authStore.userProfile?.nombre_completo || 'Administrador' }}</p>
            <span class="text-[10px] text-text-muted capitalize">{{ authStore.userRole || 'Admin' }}</span>
          </div>
          <span class="w-2 h-2 rounded-full bg-emerald-500"></span>
        </div>
      </aside>

      <!-- Área de contenido con scroll con KeepAlive para navegación ultra rápida (0ms) -->
      <main class="flex-1 overflow-y-auto p-4 md:p-6 pb-20 md:pb-6">
        <router-view v-slot="{ Component }">
          <keep-alive>
            <component :is="Component" :key="$route.name" />
          </keep-alive>
        </router-view>
      </main>
    </div>

    <!-- Barra de Navegación Inferior en Móvil (< md) -->
    <nav class="md:hidden fixed bottom-0 left-0 right-0 bg-surface border-t border-border px-2 py-1.5 flex items-center overflow-x-auto no-scrollbar space-x-2 z-30 shadow-lg">
      <template v-if="authStore.isSuperadmin">
        <router-link 
          to="/superadmin" 
          class="flex flex-col items-center py-1 px-3 text-xs whitespace-nowrap flex-shrink-0"
          :class="$route.name === 'superadmin' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Parqueaderos</span>
        </router-link>
      </template>

      <template v-else>
        <router-link 
          v-if="authStore.isAdmin"
          to="/" 
          class="flex flex-col items-center py-1 px-2 text-xs whitespace-nowrap flex-shrink-0"
          :class="$route.name === 'dashboard' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Inicio</span>
        </router-link>
        <router-link 
          to="/ocupacion" 
          class="flex flex-col items-center py-1 px-2 text-xs whitespace-nowrap flex-shrink-0"
          :class="$route.name === 'ocupacion' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Ocupación</span>
        </router-link>
        <router-link 
          to="/mensualidades" 
          class="flex flex-col items-center py-1 px-2 text-xs whitespace-nowrap flex-shrink-0"
          :class="$route.name === 'mensualidades' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Mensuales</span>
        </router-link>
        <router-link 
          to="/caja" 
          class="flex flex-col items-center py-1 px-2 text-xs whitespace-nowrap flex-shrink-0"
          :class="$route.name === 'caja' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Caja</span>
        </router-link>
        <router-link 
          v-if="authStore.isAdmin"
          to="/comprobantes" 
          class="flex flex-col items-center py-1 px-2 text-xs whitespace-nowrap flex-shrink-0"
          :class="$route.name === 'comprobantes' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Comprobantes</span>
        </router-link>
        <router-link 
          v-if="authStore.isAdmin"
          to="/reportes" 
          class="flex flex-col items-center py-1 px-2 text-xs whitespace-nowrap flex-shrink-0"
          :class="$route.name === 'reportes' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Reportes</span>
        </router-link>
        <router-link 
          v-if="authStore.isAdmin"
          to="/ajustes" 
          class="flex flex-col items-center py-1 px-2 text-xs whitespace-nowrap flex-shrink-0"
          :class="!conexionStore.isOnline ? 'opacity-40 pointer-events-none' : ($route.name === 'ajustes' ? 'text-primary font-bold' : 'text-text-muted')"
        >
          <span>Ajustes</span>
        </router-link>
      </template>
    </nav>
  </div>
</template>

<script setup>
import { ref, onMounted, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useTemaStore } from '@/stores/tema'
import { useConexionStore } from '@/stores/conexion'
import { useAuthStore } from '@/stores/auth'
import { cajaService } from '@/modules/caja/services/cajaService'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { mensualidadesService } from '@/modules/mensualidades/services/mensualidadesService'
import { ajustesService } from '@/modules/ajustes/services/ajustesService'
import { dashboardService } from '@/modules/dashboard/services/dashboardService'
import { sincronizarAhora } from '@/offline/sync'

const router = useRouter()
const route = useRoute()
const temaStore = useTemaStore()
const conexionStore = useConexionStore()
const authStore = useAuthStore()

const sincronizandoManual = ref(false)
const tieneTurnoAbierto = ref(false)

async function precalentarDatos(pqId) {
  if (!pqId || authStore.isSuperadmin) return
  // Precarga paralela en segundo plano: las vistas ya estarán en memoria antes de que el usuario haga clic
  Promise.allSettled([
    ajustesService.listarTiposVehiculo(pqId),
    ajustesService.listarMetodosPago(pqId),
    ajustesService.listarTarifas(pqId),
    ajustesService.listarPlanesMensuales(pqId),
    ocupacionService.obtenerVehiculosDentro(pqId),
    cajaService.obtenerTurnoActual(pqId),
    mensualidadesService.listarMensualidades(pqId),
    dashboardService.obtenerDatosDashboard(pqId)
  ])
}

async function verificarTurno() {
  if (authStore.parqueaderoId && !authStore.isSuperadmin) {
    const turno = await cajaService.obtenerTurnoActual(authStore.parqueaderoId)
    tieneTurnoAbierto.value = !!turno
  }
}

watch(() => authStore.parqueaderoId, (newId) => {
  if (newId) {
    verificarTurno()
    precalentarDatos(newId)
  }
})

watch(() => route.path, () => {
  verificarTurno()
})

onMounted(() => {
  verificarTurno()
  if (authStore.parqueaderoId) {
    precalentarDatos(authStore.parqueaderoId)
  }
})

function toggleTheme() {
  const next = temaStore.isDark ? 'light' : 'dark'
  temaStore.setTheme(next)
}

async function ejecutarSincronizacion() {
  sincronizandoManual.value = true
  try {
    await sincronizarAhora(conexionStore)
  } finally {
    sincronizandoManual.value = false
  }
}

async function handleLogout() {
  await authStore.logout()
  router.push('/login')
}
</script>
