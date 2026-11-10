<template>
  <div class="min-h-screen flex items-center justify-center p-4 bg-background">
    <div class="w-full max-w-sm bg-surface p-6 rounded-2xl border border-border shadow-md">
      <div class="text-center mb-6">
        <h2 class="text-xl font-bold">Recuperar Contraseña</h2>
        <p class="text-xs text-text-muted mt-1">Te enviaremos un correo con las instrucciones</p>
      </div>

      <div v-if="enviado" class="p-3 mb-4 rounded-lg bg-success-bg text-success text-xs font-medium border border-success/20">
        Revisa tu bandeja de entrada. Te hemos enviado un enlace para restablecer tu contraseña.
      </div>

      <div v-if="errorMensaje" class="p-3 mb-4 rounded-lg bg-danger-bg text-danger text-xs font-medium border border-danger/20">
        {{ errorMensaje }}
      </div>

      <form v-if="!enviado" @submit.prevent="handleRecuperar" class="space-y-4">
        <div>
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Correo electrónico</label>
          <input 
            v-model="email"
            type="email" 
            required
            class="w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary"
            placeholder="usuario@parqueadero.com"
          />
        </div>

        <button 
          type="submit" 
          :disabled="cargando"
          class="w-full py-2.5 px-4 bg-primary text-white font-semibold rounded-lg text-sm hover:opacity-90 transition-opacity disabled:opacity-50"
        >
          <span v-if="cargando">Enviando enlace...</span>
          <span v-else>Enviar Enlace de Recuperación</span>
        </button>
      </form>

      <div class="mt-4 text-center">
        <router-link to="/login" class="text-xs text-primary hover:underline font-medium">
          ← Volver a iniciar sesión
        </router-link>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'
import { authService } from '@/modules/auth/services/authService'

const email = ref('')
const cargando = ref(false)
const enviado = ref(false)
const errorMensaje = ref('')

async function handleRecuperar() {
  if (!email.value) return
  errorMensaje.value = ''
  cargando.value = true

  try {
    await authService.recuperarPassword(email.value)
    enviado.value = true
  } catch (err) {
    errorMensaje.value = err.message || 'No se pudo enviar el correo de recuperación'
  } finally {
    cargando.value = false
  }
}
</script>
