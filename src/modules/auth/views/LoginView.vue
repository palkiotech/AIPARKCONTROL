<template>
  <MarcoAcceso titulo="Iniciar sesión" subtitulo="Ingresa con el correo con el que te invitaron.">
    <div class="space-y-3 mb-5" v-if="(authStore.motivoSalida && !errorMensaje) || errorMensaje || !conexion.isOnline">
      <!-- Motivo de salida: sesión expirada, usuario desactivado o parqueadero suspendido -->
      <div v-if="authStore.motivoSalida && !errorMensaje" class="alerta-aviso">
        {{ authStore.motivoSalida }}
      </div>

      <div v-if="errorMensaje" class="alerta-error" role="alert">
        <svg class="w-4 h-4 flex-shrink-0 mt-px" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
        <span>{{ errorMensaje }}</span>
      </div>

      <div v-if="!conexion.isOnline" class="alerta-aviso">
        Sin conexión: para iniciar sesión por primera vez en este dispositivo necesitas internet.
      </div>
    </div>

    <form @submit.prevent="handleLogin" class="space-y-4">
      <div>
        <label for="login-email" class="etiqueta">Correo electrónico</label>
        <input
          id="login-email"
          v-model="email"
          type="email"
          required
          autocomplete="email"
          autocapitalize="off"
          spellcheck="false"
          class="campo py-2.5"
          placeholder="usuario@parqueadero.com"
        />
      </div>

      <div>
        <div class="flex items-center justify-between gap-2 mb-1.5">
          <label for="login-pass" class="text-xs font-medium text-text-secondary">Contraseña</label>
          <router-link to="/recuperar" class="inline-flex items-center min-h-10 -my-3 pl-2 text-xs font-medium text-primary hover:underline text-right">
            ¿Olvidaste tu contraseña?
          </router-link>
        </div>
        <input
          id="login-pass"
          v-model="password"
          type="password"
          required
          autocomplete="current-password"
          class="campo py-2.5"
          placeholder="••••••••"
        />
      </div>

      <button
        type="submit"
        :disabled="cargando || !conexion.isOnline"
        class="btn-craft-primary w-full py-2.5 rounded-lg text-sm"
      >
        <span v-if="cargando" class="w-4 h-4 rounded-full border-2 border-white/40 border-t-white animate-spin"></span>
        <span>{{ cargando ? 'Iniciando sesión…' : 'Iniciar sesión' }}</span>
      </button>
    </form>

    <p class="mt-8 pt-5 border-t border-border text-xs text-text-muted">
      El acceso es por invitación del administrador de tu parqueadero.
    </p>
  </MarcoAcceso>
</template>

<script setup>
import { ref } from 'vue'
import MarcoAcceso from '@/components/MarcoAcceso.vue'
import { useRouter, useRoute } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { rutaInicioPorRol } from '@/router'
import { mensajeDeError } from '@/lib/sesionCaches'

const router = useRouter()
const route = useRoute()
const authStore = useAuthStore()
const conexion = useConexionStore()

const email = ref('')
const password = ref('')
const cargando = ref(false)
const errorMensaje = ref('')

function redirigir() {
  const destino = route.query.redirect
  // Solo rutas internas (evita redirecciones abiertas)
  if (typeof destino === 'string' && destino.startsWith('/') && !destino.startsWith('//')) {
    router.push(destino)
  } else {
    router.push(rutaInicioPorRol(authStore))
  }
}

async function handleLogin() {
  if (!email.value || !password.value) return
  errorMensaje.value = ''
  cargando.value = true
  try {
    await authStore.login(email.value, password.value)
    redirigir()
  } catch (err) {
    errorMensaje.value = mensajeDeError(err, 'Error al iniciar sesión')
  } finally {
    cargando.value = false
  }
}
</script>
