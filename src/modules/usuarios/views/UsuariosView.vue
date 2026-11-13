<template>
  <div class="space-y-6">
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div>
        <h2 class="titulo-pagina">Usuarios</h2>
        <p class="subtitulo-pagina">Invita operadores y administradores, cambia su rol o desactívalos.</p>
      </div>
      <button
        @click="abrirInvitar"
        :disabled="!conexion.isOnline"
        class="w-full sm:w-auto btn-craft-primary text-sm px-4 py-2 rounded-lg"
      >
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
        Invitar usuario
      </button>
    </div>

    <div v-if="!conexion.isOnline" class="alerta-aviso">
      La gestión de usuarios requiere conexión a internet.
    </div>
    <div v-if="mensajeExito" class="alerta-exito">{{ mensajeExito }}</div>
    <div v-if="errorMensaje" class="alerta-error" role="alert">{{ errorMensaje }}</div>

    <div class="card-craft overflow-hidden">
      <div v-if="cargando" class="vacio">
        <div class="spinner"></div>
        <span>Cargando usuarios...</span>
      </div>
      <div v-else-if="usuarios.length === 0" class="vacio">No hay usuarios.</div>
      <div v-else class="divide-y divide-border">
        <div v-for="u in usuarios" :key="u.id" class="p-4 flex flex-col md:flex-row md:items-center gap-3">
          <div class="flex items-start gap-3 flex-1 min-w-0">
            <span class="w-9 h-9 shrink-0 rounded-full bg-primary/10 text-primary font-semibold text-sm flex items-center justify-center">
              {{ (u.nombre || '?').charAt(0).toUpperCase() }}
            </span>
            <div class="min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <p class="font-semibold text-sm text-text-primary truncate">{{ u.nombre }}</p>
                <span v-if="u.es_yo" class="badge-pastel-blue text-2xs px-2 py-0.5 rounded-full">Tú</span>
                <span v-if="u.invitacion_pendiente" class="badge-pastel-amber text-2xs px-2 py-0.5 rounded-full">Invitación pendiente</span>
                <span class="text-2xs px-2 py-0.5 rounded-full" :class="u.activo ? 'badge-pastel-mint' : 'badge-pastel-rose'">
                  {{ u.activo ? 'Activo' : 'Desactivado' }}
                </span>
              </div>
              <p class="text-xs text-text-secondary truncate">{{ u.email }}</p>
              <p class="text-2xs text-text-muted">
                Último ingreso: {{ u.ultimo_ingreso ? formatearFechaHora(u.ultimo_ingreso, authStore.zonaHoraria, { year: 'numeric' }) : 'nunca' }}
              </p>
            </div>
          </div>

          <div class="flex items-center gap-2 flex-wrap md:pl-0 pl-12">
            <select
              :value="u.rol"
              @change="cambiarRol(u, $event.target.value)"
              :disabled="u.es_yo || ocupado === u.id || !conexion.isOnline"
              :title="u.es_yo ? 'No puedes cambiar tu propio rol' : 'Rol'"
              class="campo campo-sm w-auto"
            >
              <option value="operador">Operador</option>
              <option value="admin">Administrador</option>
            </select>
            <button
              @click="cambiarActivo(u)"
              :disabled="u.es_yo || ocupado === u.id || !conexion.isOnline"
              :title="u.es_yo ? 'No puedes desactivarte a ti mismo' : ''"
              class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg"
              :class="u.activo ? '!text-danger' : '!text-success'"
            >
              {{ u.activo ? 'Desactivar' : 'Reactivar' }}
            </button>
            <button
              @click="reenviar(u)"
              :disabled="ocupado === u.id || !conexion.isOnline"
              class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg"
            >
              Reenviar acceso
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Modal invitar -->
    <div v-if="mostrarInvitar" class="modal-fondo" @click.self="cerrarInvitar">
      <div class="modal-panel max-w-md">
        <div class="modal-encabezado">
          <div>
            <h3 class="modal-titulo">Invitar usuario</h3>
            <p class="text-xs text-text-muted mt-0.5">Recibirá un correo para definir su contraseña y entrar a este parqueadero.</p>
          </div>
          <button type="button" class="btn-icono shrink-0" aria-label="Cerrar" @click="cerrarInvitar">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <form @submit.prevent="invitar" class="space-y-4">
          <div>
            <label for="inv-nombre" class="etiqueta">Nombre *</label>
            <input id="inv-nombre" v-model.trim="form.nombre" required class="campo" />
          </div>
          <div>
            <label for="inv-email" class="etiqueta">Correo *</label>
            <input id="inv-email" v-model.trim="form.email" type="email" required class="campo" />
          </div>
          <div>
            <label class="etiqueta">Rol</label>
            <div class="grid grid-cols-2 gap-2">
              <button type="button" @click="form.rol = 'operador'" class="px-3 py-2.5 rounded-lg border text-sm font-medium text-left transition-colors" :class="form.rol === 'operador' ? 'border-primary text-primary bg-primary/10' : 'border-border text-text-secondary hover:border-primary/50'">
                Operador
                <span class="block text-2xs font-normal text-text-muted">Patio, caja, mensualidades</span>
              </button>
              <button type="button" @click="form.rol = 'admin'" class="px-3 py-2.5 rounded-lg border text-sm font-medium text-left transition-colors" :class="form.rol === 'admin' ? 'border-primary text-primary bg-primary/10' : 'border-border text-text-secondary hover:border-primary/50'">
                Administrador
                <span class="block text-2xs font-normal text-text-muted">Todo el parqueadero</span>
              </button>
            </div>
          </div>
          <p v-if="errorModal" class="alerta-error" role="alert">{{ errorModal }}</p>
          <div class="flex justify-end gap-2 pt-2">
            <button type="button" @click="cerrarInvitar" class="btn-craft-subtle px-4 py-2 text-sm rounded-lg">Cancelar</button>
            <button type="submit" :disabled="enviando" class="btn-craft-primary px-4 py-2 text-sm rounded-lg">
              {{ enviando ? 'Enviando...' : 'Enviar invitación' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onActivated } from 'vue'
import { usuariosService } from '@/modules/usuarios/services/usuariosService'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { mensajeDeError } from '@/lib/sesionCaches'
import { formatearFechaHora } from '@/utils/fecha'

const authStore = useAuthStore()
const conexion = useConexionStore()

const usuarios = ref([])
const cargando = ref(false)
const ocupado = ref(null)
const enviando = ref(false)
const mostrarInvitar = ref(false)
const mensajeExito = ref('')
const errorMensaje = ref('')
const errorModal = ref('')
const form = ref({ nombre: '', email: '', rol: 'operador' })

async function cargar() {
  if (!conexion.isOnline) return
  cargando.value = usuarios.value.length === 0
  errorMensaje.value = ''
  try {
    usuarios.value = await usuariosService.listar()
  } catch (err) {
    errorMensaje.value = mensajeDeError(err, 'No se pudieron cargar los usuarios')
  } finally {
    cargando.value = false
  }
}

function limpiarAvisos() {
  mensajeExito.value = ''
  errorMensaje.value = ''
}

function abrirInvitar() {
  form.value = { nombre: '', email: '', rol: 'operador' }
  errorModal.value = ''
  mostrarInvitar.value = true
}

function cerrarInvitar() {
  if (!enviando.value) mostrarInvitar.value = false
}

async function invitar() {
  enviando.value = true
  errorModal.value = ''
  limpiarAvisos()
  try {
    await usuariosService.invitar(form.value)
    mensajeExito.value = `Invitación enviada a ${form.value.email}.`
    mostrarInvitar.value = false
    await cargar()
  } catch (err) {
    errorModal.value = mensajeDeError(err, 'No se pudo enviar la invitación')
  } finally {
    enviando.value = false
  }
}

async function actualizar(u, cambios, exito) {
  ocupado.value = u.id
  limpiarAvisos()
  try {
    await usuariosService.actualizar(u.id, cambios)
    mensajeExito.value = exito
    await cargar()
  } catch (err) {
    errorMensaje.value = mensajeDeError(err, 'No se pudo actualizar el usuario')
    await cargar()
  } finally {
    ocupado.value = null
  }
}

function cambiarRol(u, rol) {
  if (rol === u.rol) return
  actualizar(u, { rol }, `${u.nombre} ahora es ${rol === 'admin' ? 'administrador' : 'operador'}.`)
}

function cambiarActivo(u) {
  actualizar(u, { activo: !u.activo }, `${u.nombre} quedó ${u.activo ? 'desactivado' : 'activo'}.`)
}

async function reenviar(u) {
  ocupado.value = u.id
  limpiarAvisos()
  try {
    await usuariosService.reenviarAcceso(u.email)
    mensajeExito.value = `Se envió a ${u.email} un correo para definir su contraseña.`
  } catch (err) {
    errorMensaje.value = mensajeDeError(err, 'No se pudo reenviar el acceso')
  } finally {
    ocupado.value = null
  }
}

onMounted(cargar)
onActivated(cargar)
</script>
