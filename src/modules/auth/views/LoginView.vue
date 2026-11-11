<template>
  <div class="min-h-screen flex items-center justify-center p-4 bg-background">
    <div class="w-full max-w-sm bg-surface p-6 rounded-2xl border border-border shadow-md space-y-6">
      <div class="text-center">
        <div class="w-12 h-12 bg-primary text-white rounded-xl mx-auto flex items-center justify-center font-bold text-2xl mb-2 shadow-sm">
          P
        </div>
        <h2 class="text-xl font-bold">ParkControl</h2>
        <p class="text-xs text-text-muted mt-0.5">Ingresa a tu cuenta de parqueadero</p>
      </div>

      <!-- Alerta de error -->
      <div v-if="errorMensaje" class="p-3 rounded-lg bg-danger-bg text-danger text-xs font-medium border border-danger/20 flex items-start space-x-2">
        <svg class="w-4 h-4 flex-shrink-0 mt-0.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <span>{{ errorMensaje }}</span>
      </div>

      <!-- Formulario para credenciales reales de Supabase -->
      <form @submit.prevent="handleLogin" class="space-y-4">
        <div>
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Correo electrónico</label>
          <input 
            v-model="email"
            type="email" 
            required
            autocomplete="email"
            class="w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary transition-colors text-text-primary"
            placeholder="usuario@parqueadero.com"
          />
        </div>

        <div>
          <div class="flex items-center justify-between mb-1">
            <label class="block text-xs font-semibold text-text-secondary">Contraseña</label>
            <router-link to="/recuperar" class="text-xs text-primary hover:underline">
              ¿Olvidaste tu contraseña?
            </router-link>
          </div>
          <input 
            v-model="password"
            type="password" 
            required
            autocomplete="current-password"
            class="w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary transition-colors text-text-primary"
            placeholder="••••••••"
          />
        </div>

        <button 
          type="submit" 
          :disabled="cargando"
          class="w-full py-2.5 px-4 bg-primary text-white font-semibold rounded-lg text-sm hover:opacity-90 transition-opacity disabled:opacity-50 flex items-center justify-center space-x-2 shadow-sm"
        >
          <span v-if="cargando">Iniciando sesión...</span>
          <span v-else>Iniciar Sesión</span>
        </button>
      </form>

      <!-- SECCIÓN ACCESOS RÁPIDOS DEMO PARA EXPLORAR -->
      <div class="pt-4 border-t border-border space-y-2">
        <p class="text-[11px] font-bold text-text-muted uppercase tracking-wider text-center">
          Acceso Rápido de Prueba (Demo)
        </p>
        <p class="text-[11px] text-text-secondary text-center">
          Explora la app con un clic según el rol que quieras probar:
        </p>
        <div class="grid grid-cols-1 gap-2 pt-1">
          <button 
            type="button"
            @click="entrarComo('admin')"
            class="w-full py-2 px-3 text-xs font-semibold rounded-lg bg-surface-elevated border border-border hover:border-primary hover:text-primary transition-colors flex items-center justify-between"
          >
            <span>👑 Como <strong>Administrador (Dueño)</strong></span>
            <span class="text-text-muted text-[10px]">Dashboard, Ajustes</span>
          </button>

          <button 
            type="button"
            @click="entrarComo('operador')"
            class="w-full py-2 px-3 text-xs font-semibold rounded-lg bg-surface-elevated border border-border hover:border-primary hover:text-primary transition-colors flex items-center justify-between"
          >
            <span>🚗 Como <strong>Operador (Portero)</strong></span>
            <span class="text-text-muted text-[10px]">Patio, Ocupación</span>
          </button>

          <button 
            type="button"
            @click="entrarComo('superadmin')"
            class="w-full py-2 px-3 text-xs font-semibold rounded-lg bg-surface-elevated border border-border hover:border-primary hover:text-primary transition-colors flex items-center justify-between"
          >
            <span>⚡ Como <strong>Superadmin (Plataforma)</strong></span>
            <span class="text-text-muted text-[10px]">Parqueaderos</span>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()

const email = ref('')
const password = ref('')
const cargando = ref(false)
const errorMensaje = ref('')

function redirigirSegunRol() {
  const redirectPath = route.query.redirect
  if (redirectPath) {
    router.push(redirectPath)
  } else if (authStore.isSuperadmin) {
    router.push('/superadmin')
  } else if (authStore.isAdmin) {
    router.push('/')
  } else {
    router.push('/ocupacion')
  }
}

async function handleLogin() {
  if (!email.value || !password.value) return
  errorMensaje.value = ''
  cargando.value = true

  try {
    await authStore.login(email.value, password.value)
    redirigirSegunRol()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al iniciar sesión'
  } finally {
    cargando.value = false
  }
}

function entrarComo(rol) {
  authStore.entrarComoDemo(rol)
  redirigirSegunRol()
}
</script>
