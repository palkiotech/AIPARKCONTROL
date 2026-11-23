<template>
  <MarcoAcceso
    :titulo="modo === 'definir' ? (esInvitacion ? 'Bienvenido a ParkControl' : 'Define tu contraseña') : 'Recuperar contraseña'"
    :subtitulo="modo === 'definir' ? 'Crea una contraseña de al menos 8 caracteres.' : 'Te enviaremos un correo con un enlace para definir una nueva contraseña.'"
  >
    <!-- Modo B: llegó desde el enlace de invitación o recuperación -->
    <template v-if="modo === 'definir'">
      <div v-if="errorMensaje" class="alerta-error mb-5" role="alert">
        {{ errorMensaje }}
      </div>

      <form @submit.prevent="handleDefinir" class="space-y-4">
        <div>
          <label for="pass1" class="etiqueta">Nueva contraseña</label>
          <input
            id="pass1"
            v-model="password"
            type="password"
            required
            minlength="8"
            autocomplete="new-password"
            class="campo py-2.5"
          />
        </div>
        <div>
          <label for="pass2" class="etiqueta">Confirmar contraseña</label>
          <input
            id="pass2"
            v-model="confirmacion"
            type="password"
            required
            minlength="8"
            autocomplete="new-password"
            class="campo py-2.5"
          />
        </div>
        <button
          type="submit"
          :disabled="cargando"
          class="btn-craft-primary w-full py-2.5 rounded-lg text-sm"
        >
          {{ cargando ? 'Guardando…' : 'Guardar contraseña y entrar' }}
        </button>
      </form>
    </template>

    <!-- Modo A: solicitar correo de recuperación -->
    <template v-else>
      <div v-if="enviado" class="alerta-exito mb-5">
        Si el correo está registrado, recibirás un enlace para definir una nueva contraseña. Revisa también la carpeta de spam.
      </div>

      <div v-if="errorMensaje" class="alerta-error mb-5" role="alert">
        {{ errorMensaje }}
      </div>

      <form v-if="!enviado" @submit.prevent="handleRecuperar" class="space-y-4">
        <div>
          <label for="rec-email" class="etiqueta">Correo electrónico</label>
          <input
            id="rec-email"
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
        <button
          type="submit"
          :disabled="cargando"
          class="btn-craft-primary w-full py-2.5 rounded-lg text-sm"
        >
          {{ cargando ? 'Enviando enlace…' : 'Enviar enlace de recuperación' }}
        </button>
      </form>
    </template>

    <div class="mt-8 pt-5 border-t border-border">
      <router-link to="/login" class="inline-flex items-center gap-1.5 min-h-10 -my-2 text-sm text-primary hover:underline font-medium">
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" /></svg>
        Volver a iniciar sesión
      </router-link>
    </div>
  </MarcoAcceso>
</template>

<script setup>
import { ref, onMounted, onBeforeUnmount } from 'vue'
import MarcoAcceso from '@/components/MarcoAcceso.vue'
import { authService } from '@/modules/auth/services/authService'
import { mensajeDeError } from '@/lib/sesionCaches'

// Leer el hash antes de que Supabase lo procese y lo limpie de la URL
const hashInicial = typeof window !== 'undefined' ? window.location.hash : ''
const tipoEnlace = new URLSearchParams(hashInicial.replace(/^#/, '')).get('type')

const modo = ref(tipoEnlace === 'invite' || tipoEnlace === 'recovery' ? 'definir' : 'solicitar')
const esInvitacion = ref(tipoEnlace === 'invite')
const email = ref('')
const password = ref('')
const confirmacion = ref('')
const cargando = ref(false)
const enviado = ref(false)
const errorMensaje = ref('')
let cancelarEscucha = null

onMounted(async () => {
  cancelarEscucha = authService.onCambioSesion((evento) => {
    if (evento === 'PASSWORD_RECOVERY') modo.value = 'definir'
  })
  if (modo.value === 'solicitar') {
    try {
      const sesion = await authService.obtenerSesion()
      if (sesion && hashInicial.includes('access_token')) modo.value = 'definir'
    } catch (e) {}
  }
})

onBeforeUnmount(() => {
  if (cancelarEscucha) cancelarEscucha()
})

async function handleRecuperar() {
  if (!email.value) return
  errorMensaje.value = ''
  cargando.value = true
  try {
    await authService.recuperarPassword(email.value)
    enviado.value = true
  } catch (err) {
    errorMensaje.value = mensajeDeError(err, 'No se pudo enviar el correo de recuperación')
  } finally {
    cargando.value = false
  }
}

async function handleDefinir() {
  errorMensaje.value = ''
  if (password.value.length < 8) {
    errorMensaje.value = 'La contraseña debe tener al menos 8 caracteres'
    return
  }
  if (password.value !== confirmacion.value) {
    errorMensaje.value = 'Las contraseñas no coinciden'
    return
  }
  cargando.value = true
  try {
    const sesion = await authService.obtenerSesion()
    if (!sesion) throw new Error('El enlace expiró o ya fue usado. Solicita uno nuevo.')
    await authService.definirPassword(password.value)
    // Recarga completa para inicializar la sesión y el perfil desde cero
    window.location.assign('/')
  } catch (err) {
    errorMensaje.value = mensajeDeError(err, 'No se pudo guardar la contraseña')
  } finally {
    cargando.value = false
  }
}
</script>
