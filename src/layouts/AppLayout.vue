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
        <div class="w-8 h-8 rounded-lg bg-primary text-white flex items-center justify-center font-bold text-lg shadow-sm">
          P
        </div>
        <div>
          <h1 class="text-sm md:text-base font-bold leading-tight">
            {{ authStore.isSuperadmin ? 'ParkControl · Superadmin' : (authStore.parqueadero?.nombre || 'ParkControl') }}
          </h1>
          <p class="text-xs text-text-muted flex items-center space-x-1">
            <span v-if="!authStore.isSuperadmin">Turno: Activo</span>
            <span v-else>Plataforma SaaS</span>
          </p>
        </div>
      </div>

      <div class="flex items-center space-x-3">
        <!-- Indicador de Conexión Offline / Online (HU-26) -->
        <div class="flex items-center text-xs px-2.5 py-1 rounded-full font-medium"
             :class="conexionStore.isOnline ? 'bg-success-bg text-success' : 'bg-warning-bg text-warning'">
          <span class="w-2 h-2 rounded-full mr-1.5" :class="conexionStore.isOnline ? 'bg-success' : 'bg-warning animate-pulse'"></span>
          <span>
            {{ conexionStore.isOnline ? 'En línea' : `Sin conexión · ${conexionStore.pendingOperationsCount} pend.` }}
          </span>
        </div>

        <!-- Selector de Tema (HU-10) -->
        <button 
          @click="toggleTheme" 
          class="p-1.5 rounded-lg border border-border bg-surface text-text-secondary hover:text-text-primary transition-colors"
          title="Cambiar tema"
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
      <aside class="hidden md:flex flex-col w-60 bg-surface border-r border-border p-4 space-y-1">
        <!-- Opciones para Superadmin -->
        <template v-if="authStore.isSuperadmin">
          <router-link 
            to="/superadmin" 
            class="flex items-center px-3 py-2 text-sm rounded-lg font-medium transition-colors"
            :class="$route.name === 'superadmin' ? 'bg-primary text-white' : 'text-text-secondary hover:bg-surface-elevated'"
          >
            Parqueaderos
          </router-link>
        </template>

        <!-- Opciones para Admin y Operador -->
        <template v-else>
          <router-link 
            v-if="authStore.isAdmin"
            to="/" 
            class="flex items-center px-3 py-2 text-sm rounded-lg font-medium transition-colors"
            :class="$route.name === 'dashboard' ? 'bg-primary text-white' : 'text-text-secondary hover:bg-surface-elevated'"
          >
            Inicio / Dashboard
          </router-link>
          <router-link 
            to="/ocupacion" 
            class="flex items-center px-3 py-2 text-sm rounded-lg font-medium transition-colors"
            :class="$route.name === 'ocupacion' ? 'bg-primary text-white' : 'text-text-secondary hover:bg-surface-elevated'"
          >
            Ocupación
          </router-link>
          <router-link 
            to="/mensualidades" 
            class="flex items-center px-3 py-2 text-sm rounded-lg font-medium transition-colors"
            :class="$route.name === 'mensualidades' ? 'bg-primary text-white' : 'text-text-secondary hover:bg-surface-elevated'"
          >
            Mensualidades
          </router-link>
          <router-link 
            to="/caja" 
            class="flex items-center px-3 py-2 text-sm rounded-lg font-medium transition-colors"
            :class="$route.name === 'caja' ? 'bg-primary text-white' : 'text-text-secondary hover:bg-surface-elevated'"
          >
            Caja y Turno
          </router-link>
          <router-link 
            v-if="authStore.isAdmin"
            to="/ajustes" 
            class="flex items-center px-3 py-2 text-sm rounded-lg font-medium transition-colors"
            :class="$route.name === 'ajustes' ? 'bg-primary text-white' : 'text-text-secondary hover:bg-surface-elevated'"
          >
            Ajustes
          </router-link>
        </template>
      </aside>

      <!-- Área de contenido con scroll -->
      <main class="flex-1 overflow-y-auto p-4 md:p-6 pb-20 md:pb-6">
        <router-view />
      </main>
    </div>

    <!-- Barra de Navegación Inferior en Móvil (< md) -->
    <nav class="md:hidden fixed bottom-0 left-0 right-0 bg-surface border-t border-border px-2 py-1.5 flex justify-around items-center z-30 shadow-lg">
      <template v-if="authStore.isSuperadmin">
        <router-link 
          to="/superadmin" 
          class="flex flex-col items-center py-1 px-2 text-xs"
          :class="$route.name === 'superadmin' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Parqueaderos</span>
        </router-link>
      </template>

      <template v-else>
        <router-link 
          v-if="authStore.isAdmin"
          to="/" 
          class="flex flex-col items-center py-1 px-2 text-xs"
          :class="$route.name === 'dashboard' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Inicio</span>
        </router-link>
        <router-link 
          to="/ocupacion" 
          class="flex flex-col items-center py-1 px-2 text-xs"
          :class="$route.name === 'ocupacion' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Ocupación</span>
        </router-link>
        <router-link 
          to="/mensualidades" 
          class="flex flex-col items-center py-1 px-2 text-xs"
          :class="$route.name === 'mensualidades' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Mensuales</span>
        </router-link>
        <router-link 
          to="/caja" 
          class="flex flex-col items-center py-1 px-2 text-xs"
          :class="$route.name === 'caja' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Caja</span>
        </router-link>
        <router-link 
          v-if="authStore.isAdmin"
          to="/ajustes" 
          class="flex flex-col items-center py-1 px-2 text-xs"
          :class="$route.name === 'ajustes' ? 'text-primary font-bold' : 'text-text-muted'"
        >
          <span>Ajustes</span>
        </router-link>
      </template>
    </nav>
  </div>
</template>

<script setup>
import { useRouter } from 'vue-router'
import { useTemaStore } from '@/stores/tema'
import { useConexionStore } from '@/stores/conexion'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const temaStore = useTemaStore()
const conexionStore = useConexionStore()
const authStore = useAuthStore()

function toggleTheme() {
  const next = temaStore.isDark ? 'light' : 'dark'
  temaStore.setTheme(next)
}

async function handleLogout() {
  await authStore.logout()
  router.push('/login')
}
</script>
