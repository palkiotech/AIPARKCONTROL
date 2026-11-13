<template>
  <div class="space-y-6">
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div>
        <h2 class="titulo-pagina">Parqueaderos</h2>
        <p class="subtitulo-pagina">Alta, estado y soporte de los parqueaderos de la plataforma.</p>
      </div>
      <button
        @click="abrirNuevo"
        :disabled="!conexion.isOnline"
        class="w-full sm:w-auto btn-craft-primary text-sm px-4 py-2 rounded-lg"
      >
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
        Nuevo parqueadero
      </button>
    </div>

    <div v-if="!conexion.isOnline" class="alerta-aviso">El panel de superadmin requiere conexión a internet.</div>
    <div v-if="mensajeExito" class="alerta-exito">{{ mensajeExito }}</div>
    <div v-if="errorMensaje" class="alerta-error" role="alert">{{ errorMensaje }}</div>

    <div class="card-craft overflow-hidden">
      <div v-if="cargando" class="vacio">
        <div class="spinner"></div>
        <span class="text-xs">Cargando parqueaderos…</span>
      </div>
      <div v-else-if="parqueaderos.length === 0" class="vacio">
        <p class="font-medium text-text-primary">Aún no hay parqueaderos</p>
        <p class="text-xs">Pulsa "Nuevo parqueadero" para crear el primero.</p>
      </div>

      <template v-else>
        <!-- Tabla (escritorio) -->
        <div class="hidden md:block overflow-x-auto">
          <table class="tabla">
            <thead>
              <tr>
                <th>Parqueadero</th>
                <th>Alta</th>
                <th>Administrador</th>
                <th class="text-right">Usuarios</th>
                <th class="text-right">Registros 30 d</th>
                <th>Última actividad</th>
                <th>Estado</th>
                <th class="text-right">Acciones</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="pq in parqueaderos" :key="pq.id">
                <td>
                  <p class="font-semibold text-text-primary">{{ pq.nombre }}</p>
                  <p class="text-xs text-text-muted">NIT {{ pq.nit }} · {{ pq.telefono || 'sin teléfono' }}</p>
                </td>
                <td class="text-text-secondary text-xs whitespace-nowrap">{{ fecha(pq.created_at) }}</td>
                <td class="text-xs">
                  <template v-if="pq.admin_email">
                    <p class="text-text-primary">{{ pq.admin_email }}</p>
                    <span v-if="pq.admin_invitacion_pendiente" class="badge-pastel-amber text-2xs px-2 py-0.5 rounded-full inline-block mt-0.5">Invitación pendiente</span>
                  </template>
                  <span v-else class="badge-pastel-rose text-2xs px-2 py-0.5 rounded-full">Sin administrador</span>
                </td>
                <td class="text-right num-tabular">{{ pq.total_usuarios }}</td>
                <td class="text-right num-tabular">{{ pq.registros_ultimo_mes }}</td>
                <td class="text-xs text-text-secondary whitespace-nowrap">{{ pq.ultima_actividad ? fechaHora(pq.ultima_actividad) : '—' }}</td>
                <td>
                  <span class="px-2 py-0.5 rounded-full text-xs" :class="pq.estado === 'activo' ? 'badge-pastel-mint' : 'badge-pastel-rose'">
                    {{ pq.estado === 'activo' ? 'Activo' : 'Suspendido' }}
                  </span>
                </td>
                <td class="text-right whitespace-nowrap space-x-1">
                  <button v-if="pq.admin_email" @click="reenviar(pq)" :disabled="ocupado" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg">Reenviar acceso</button>
                  <button v-else @click="abrirInvitar(pq)" :disabled="ocupado" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg">Invitar admin</button>
                  <button @click="pedirCambioEstado(pq)" :disabled="ocupado" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg" :class="pq.estado === 'activo' ? '!text-danger' : '!text-success'">
                    {{ pq.estado === 'activo' ? 'Suspender' : 'Activar' }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Tarjetas (celular) -->
        <div class="md:hidden divide-y divide-border">
          <div v-for="pq in parqueaderos" :key="pq.id" class="p-4 space-y-2 text-xs">
            <div class="flex items-start justify-between gap-2">
              <div>
                <p class="font-semibold text-sm text-text-primary">{{ pq.nombre }}</p>
                <p class="text-text-muted">NIT {{ pq.nit }} · alta {{ fecha(pq.created_at) }}</p>
              </div>
              <span class="px-2 py-0.5 rounded-full shrink-0" :class="pq.estado === 'activo' ? 'badge-pastel-mint' : 'badge-pastel-rose'">
                {{ pq.estado === 'activo' ? 'Activo' : 'Suspendido' }}
              </span>
            </div>
            <p class="text-text-secondary">
              Admin: {{ pq.admin_email || 'sin administrador' }}
              <span v-if="pq.admin_invitacion_pendiente" class="text-warning font-semibold">(pendiente)</span>
            </p>
            <p class="text-text-secondary">{{ pq.total_usuarios }} usuarios · {{ pq.registros_ultimo_mes }} registros en 30 días · última actividad {{ pq.ultima_actividad ? fechaHora(pq.ultima_actividad) : '—' }}</p>
            <div class="flex gap-2 pt-1">
              <button v-if="pq.admin_email" @click="reenviar(pq)" :disabled="ocupado" class="btn-craft-subtle text-xs px-3 py-2 rounded-lg flex-1">Reenviar acceso</button>
              <button v-else @click="abrirInvitar(pq)" :disabled="ocupado" class="btn-craft-subtle text-xs px-3 py-2 rounded-lg flex-1">Invitar admin</button>
              <button @click="pedirCambioEstado(pq)" :disabled="ocupado" class="btn-craft-subtle text-xs px-3 py-2 rounded-lg flex-1" :class="pq.estado === 'activo' ? '!text-danger' : '!text-success'">
                {{ pq.estado === 'activo' ? 'Suspender' : 'Activar' }}
              </button>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- Modal: nuevo parqueadero (HU-01) -->
    <div v-if="modal === 'nuevo'" class="modal-fondo" @click.self="cerrarModal">
      <div class="modal-panel max-w-md" role="dialog" aria-modal="true">
        <div class="modal-encabezado">
          <h3 class="modal-titulo">Nuevo parqueadero</h3>
          <button type="button" class="btn-icono" aria-label="Cerrar" @click="cerrarModal">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <p class="text-xs text-text-muted">Se crea con Carro, Moto, una tarifa por hora de ejemplo y el método "Efectivo". El administrador recibe un correo para definir su contraseña.</p>
        <form @submit.prevent="guardarNuevo" class="space-y-3">
          <div>
            <label class="etiqueta">Nombre del parqueadero *</label>
            <input v-model.trim="form.nombre" required class="campo" placeholder="Parqueadero Central" />
          </div>
          <div class="grid grid-cols-2 gap-3">
            <div>
              <label class="etiqueta">NIT *</label>
              <input v-model.trim="form.nit" required class="campo" placeholder="900.123.456-7" />
            </div>
            <div>
              <label class="etiqueta">Teléfono</label>
              <input v-model.trim="form.telefono" class="campo" placeholder="310 555 0100" />
            </div>
          </div>
          <div>
            <label class="etiqueta">Dirección</label>
            <input v-model.trim="form.direccion" class="campo" placeholder="Calle 10 # 5-20" />
          </div>
          <div class="pt-3 border-t border-border">
            <p class="rotulo mb-2">Administrador</p>
            <div class="space-y-3">
              <div>
                <label class="etiqueta">Nombre *</label>
                <input v-model.trim="form.adminNombre" required class="campo" placeholder="Nombre completo" />
              </div>
              <div>
                <label class="etiqueta">Correo *</label>
                <input v-model.trim="form.adminEmail" type="email" required class="campo" placeholder="admin@parqueadero.com" />
              </div>
            </div>
          </div>
          <p v-if="errorModal" class="alerta-error" role="alert">{{ errorModal }}</p>
          <div class="flex justify-end gap-2 pt-2">
            <button type="button" @click="cerrarModal" class="btn-craft-subtle text-sm px-4 py-2 rounded-lg">Cancelar</button>
            <button type="submit" :disabled="ocupado" class="btn-craft-primary text-sm px-4 py-2 rounded-lg">
              {{ ocupado ? 'Creando…' : 'Crear e invitar' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- Modal: invitar administrador a un parqueadero existente -->
    <div v-if="modal === 'invitar'" class="modal-fondo" @click.self="cerrarModal">
      <div class="modal-panel max-w-md" role="dialog" aria-modal="true">
        <div class="modal-encabezado">
          <div>
            <h3 class="modal-titulo">Invitar administrador</h3>
            <p class="text-xs text-text-muted">{{ seleccionado?.nombre }}</p>
          </div>
          <button type="button" class="btn-icono" aria-label="Cerrar" @click="cerrarModal">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <form @submit.prevent="guardarInvitacion" class="space-y-3">
          <div>
            <label class="etiqueta">Nombre *</label>
            <input v-model.trim="form.adminNombre" required class="campo" />
          </div>
          <div>
            <label class="etiqueta">Correo *</label>
            <input v-model.trim="form.adminEmail" type="email" required class="campo" />
          </div>
          <p v-if="errorModal" class="alerta-error" role="alert">{{ errorModal }}</p>
          <div class="flex justify-end gap-2 pt-2">
            <button type="button" @click="cerrarModal" class="btn-craft-subtle text-sm px-4 py-2 rounded-lg">Cancelar</button>
            <button type="submit" :disabled="ocupado" class="btn-craft-primary text-sm px-4 py-2 rounded-lg">
              {{ ocupado ? 'Enviando…' : 'Enviar invitación' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- Modal: confirmar cambio de estado (HU-05) -->
    <div v-if="modal === 'estado'" class="modal-fondo" @click.self="cerrarModal">
      <div class="modal-panel max-w-md" role="dialog" aria-modal="true">
        <div class="modal-encabezado">
          <h3 class="modal-titulo">{{ seleccionado?.estado === 'activo' ? 'Suspender' : 'Activar' }} parqueadero</h3>
          <button type="button" class="btn-icono" aria-label="Cerrar" @click="cerrarModal">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <p class="text-sm text-text-secondary">
          <template v-if="seleccionado?.estado === 'activo'">
            Los usuarios de <strong class="font-semibold text-text-primary">{{ seleccionado?.nombre }}</strong> no podrán iniciar sesión ni operar mientras esté suspendido.
          </template>
          <template v-else>
            Los usuarios de <strong class="font-semibold text-text-primary">{{ seleccionado?.nombre }}</strong> podrán volver a iniciar sesión.
          </template>
        </p>
        <p v-if="errorModal" class="alerta-error" role="alert">{{ errorModal }}</p>
        <div class="flex justify-end gap-2">
          <button @click="cerrarModal" class="btn-craft-subtle text-sm px-4 py-2 rounded-lg">Cancelar</button>
          <button @click="confirmarCambioEstado" :disabled="ocupado" class="text-sm px-4 py-2 rounded-lg" :class="seleccionado?.estado === 'activo' ? 'btn-craft-danger' : 'btn-craft-success'">
            {{ ocupado ? 'Guardando…' : 'Confirmar' }}
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onActivated } from 'vue'
import { superadminService } from '@/modules/superadmin/services/superadminService'
import { useConexionStore } from '@/stores/conexion'
import { mensajeDeError } from '@/lib/sesionCaches'
import { formatearFechaHora } from '@/utils/fecha'

const conexion = useConexionStore()

const parqueaderos = ref([])
const cargando = ref(false)
const ocupado = ref(false)
const modal = ref(null)
const seleccionado = ref(null)
const mensajeExito = ref('')
const errorMensaje = ref('')
const errorModal = ref('')

const formVacio = () => ({ nombre: '', nit: '', direccion: '', telefono: '', adminNombre: '', adminEmail: '' })
const form = ref(formVacio())

function fecha(iso) {
  return formatearFechaHora(iso, 'America/Bogota', { hour: undefined, minute: undefined, year: 'numeric' })
}
function fechaHora(iso) {
  return formatearFechaHora(iso, 'America/Bogota')
}

async function cargar() {
  if (!conexion.isOnline) return
  cargando.value = parqueaderos.value.length === 0
  errorMensaje.value = ''
  try {
    parqueaderos.value = await superadminService.listarParqueaderos()
  } catch (err) {
    errorMensaje.value = mensajeDeError(err, 'Error al cargar parqueaderos')
  } finally {
    cargando.value = false
  }
}

function abrirNuevo() {
  form.value = formVacio()
  errorModal.value = ''
  modal.value = 'nuevo'
}

function abrirInvitar(pq) {
  seleccionado.value = pq
  form.value = formVacio()
  errorModal.value = ''
  modal.value = 'invitar'
}

function pedirCambioEstado(pq) {
  seleccionado.value = pq
  errorModal.value = ''
  modal.value = 'estado'
}

function cerrarModal() {
  if (ocupado.value) return
  modal.value = null
  seleccionado.value = null
}

async function guardarNuevo() {
  ocupado.value = true
  errorModal.value = ''
  mensajeExito.value = ''
  errorMensaje.value = ''
  try {
    const res = await superadminService.crearParqueadero(form.value)
    modal.value = null
    if (res.errorInvitacion) {
      errorMensaje.value = `Parqueadero creado, pero la invitación al administrador falló: ${res.errorInvitacion}. Usa "Invitar admin" para reintentar con otro correo.`
    } else {
      mensajeExito.value = `Parqueadero creado. Se envió la invitación a ${form.value.adminEmail}.`
    }
    await cargar()
  } catch (err) {
    errorModal.value = mensajeDeError(err, 'No se pudo crear el parqueadero')
  } finally {
    ocupado.value = false
  }
}

async function guardarInvitacion() {
  ocupado.value = true
  errorModal.value = ''
  try {
    await superadminService.invitarAdmin(seleccionado.value.id, { nombre: form.value.adminNombre, email: form.value.adminEmail })
    mensajeExito.value = `Invitación enviada a ${form.value.adminEmail}.`
    modal.value = null
    await cargar()
  } catch (err) {
    errorModal.value = mensajeDeError(err, 'No se pudo enviar la invitación')
  } finally {
    ocupado.value = false
  }
}

async function reenviar(pq) {
  ocupado.value = true
  mensajeExito.value = ''
  errorMensaje.value = ''
  try {
    await superadminService.reenviarAcceso(pq.admin_email)
    mensajeExito.value = `Se envió a ${pq.admin_email} un correo para definir su contraseña.`
  } catch (err) {
    errorMensaje.value = mensajeDeError(err, 'No se pudo reenviar el acceso')
  } finally {
    ocupado.value = false
  }
}

async function confirmarCambioEstado() {
  const pq = seleccionado.value
  const nuevo = pq.estado === 'activo' ? 'suspendido' : 'activo'
  ocupado.value = true
  errorModal.value = ''
  try {
    await superadminService.cambiarEstado(pq.id, nuevo)
    pq.estado = nuevo
    mensajeExito.value = `${pq.nombre} quedó ${nuevo === 'activo' ? 'activo' : 'suspendido'}.`
    modal.value = null
  } catch (err) {
    errorModal.value = mensajeDeError(err, 'Error al cambiar el estado')
  } finally {
    ocupado.value = false
  }
}

onMounted(cargar)
onActivated(cargar)
</script>

