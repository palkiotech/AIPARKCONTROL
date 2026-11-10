<template>
  <div class="space-y-6">
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div>
        <h2 class="text-xl md:text-2xl font-bold">Gestión de Parqueaderos</h2>
        <p class="text-sm text-text-secondary">Panel global de administración de la plataforma (Superadmin).</p>
      </div>
      <div>
        <button 
          @click="mostrarModal = true"
          class="w-full sm:w-auto bg-primary text-white font-semibold px-4 py-2 rounded-lg text-sm shadow-sm hover:opacity-90 transition-opacity"
        >
          + Nuevo Parqueadero
        </button>
      </div>
    </div>

    <!-- Feedback / Alertas -->
    <div v-if="mensajeExito" class="p-3 rounded-lg bg-success-bg text-success text-xs font-semibold border border-success/20">
      {{ mensajeExito }}
    </div>
    <div v-if="errorMensaje" class="p-3 rounded-lg bg-danger-bg text-danger text-xs font-semibold border border-danger/20">
      {{ errorMensaje }}
    </div>

    <!-- Lista de Parqueaderos -->
    <div class="bg-surface rounded-xl border border-border shadow-sm overflow-hidden">
      <div v-if="cargando" class="p-8 text-center text-text-muted text-sm">
        Cargando parqueaderos...
      </div>

      <div v-else-if="parqueaderos.length === 0" class="p-8 text-center text-text-muted text-sm">
        No hay parqueaderos registrados aún. Pulsa "+ Nuevo Parqueadero" para crear el primero.
      </div>

      <div v-else class="overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="bg-surface-elevated text-xs text-text-secondary uppercase border-b border-border">
            <tr>
              <th class="px-4 py-3">Parqueadero</th>
              <th class="px-4 py-3">NIT</th>
              <th class="px-4 py-3">Teléfono</th>
              <th class="px-4 py-3">Usuarios</th>
              <th class="px-4 py-3">Estado</th>
              <th class="px-4 py-3 text-right">Acciones</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <tr v-for="pq in parqueaderos" :key="pq.id" class="hover:bg-surface-elevated/50 transition-colors">
              <td class="px-4 py-3 font-semibold text-text-primary">
                {{ pq.nombre }}
                <div class="text-xs font-normal text-text-muted">{{ pq.direccion || 'Sin dirección' }}</div>
              </td>
              <td class="px-4 py-3 text-text-secondary">{{ pq.nit }}</td>
              <td class="px-4 py-3 text-text-secondary">{{ pq.telefono || '—' }}</td>
              <td class="px-4 py-3 text-text-secondary">{{ pq.total_usuarios }}</td>
              <td class="px-4 py-3">
                <span 
                  class="px-2 py-0.5 rounded-full text-xs font-medium"
                  :class="pq.estado === 'activo' ? 'bg-success-bg text-success' : 'bg-danger-bg text-danger'"
                >
                  {{ pq.estado === 'activo' ? 'Activo' : 'Suspendido' }}
                </span>
              </td>
              <td class="px-4 py-3 text-right">
                <button 
                  @click="toggleEstado(pq)"
                  class="text-xs font-semibold px-2.5 py-1 rounded border border-border hover:bg-surface-elevated transition-colors"
                >
                  {{ pq.estado === 'activo' ? 'Suspender' : 'Activar' }}
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- Modal Crear Parqueadero (HU-01) -->
    <div v-if="mostrarModal" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/50 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-6 max-w-md w-full shadow-xl">
        <h3 class="text-lg font-bold mb-1">Nuevo Parqueadero</h3>
        <p class="text-xs text-text-muted mb-4">Ingresa los datos para dar de alta el parqueadero.</p>

        <form @submit.prevent="guardarNuevoParqueadero" class="space-y-3">
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Nombre del parqueadero *</label>
            <input 
              v-model="formulario.nombre"
              type="text" 
              required
              placeholder="Ej. Parqueadero Central"
              class="w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary"
            />
          </div>

          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">NIT / Identificación *</label>
            <input 
              v-model="formulario.nit"
              type="text" 
              required
              placeholder="Ej. 900.123.456-7"
              class="w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary"
            />
          </div>

          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Dirección</label>
            <input 
              v-model="formulario.direccion"
              type="text" 
              placeholder="Ej. Calle 10 # 4-20"
              class="w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary"
            />
          </div>

          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Teléfono</label>
            <input 
              v-model="formulario.telefono"
              type="text" 
              placeholder="Ej. 310 555 0100"
              class="w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary"
            />
          </div>

          <div class="flex items-center justify-end space-x-2 pt-4">
            <button 
              type="button" 
              @click="mostrarModal = false"
              class="px-4 py-2 text-xs font-semibold rounded-lg border border-border hover:bg-surface-elevated transition-colors"
            >
              Cancelar
            </button>
            <button 
              type="submit" 
              :disabled="guardando"
              class="px-4 py-2 text-xs font-semibold rounded-lg bg-primary text-white hover:opacity-90 transition-opacity disabled:opacity-50"
            >
              {{ guardando ? 'Guardando...' : 'Crear Parqueadero' }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { superadminService } from '@/modules/superadmin/services/superadminService'

const parqueaderos = ref([])
const cargando = ref(false)
const guardando = ref(false)
const mostrarModal = ref(false)
const mensajeExito = ref('')
const errorMensaje = ref('')

const formulario = ref({
  nombre: '',
  nit: '',
  direccion: '',
  telefono: ''
})

async function cargarParqueaderos() {
  cargando.value = true
  errorMensaje.value = ''
  try {
    parqueaderos.value = await superadminService.listarParqueaderos()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al cargar parqueaderos'
  } finally {
    cargando.value = false
  }
}

async function guardarNuevoParqueadero() {
  guardando.value = true
  errorMensaje.value = ''
  mensajeExito.value = ''

  try {
    const res = await superadminService.crearParqueadero(formulario.value)
    mensajeExito.value = res.mensaje || 'Parqueadero creado correctamente'
    mostrarModal.value = false
    formulario.value = { nombre: '', nit: '', direccion: '', telefono: '' }
    await cargarParqueaderos()
  } catch (err) {
    errorMensaje.value = err.message || 'No se pudo crear el parqueadero'
  } finally {
    guardando.value = false
  }
}

async function toggleEstado(pq) {
  const nuevo = pq.estado === 'activo' ? 'suspendido' : 'activo'
  try {
    await superadminService.cambiarEstado(pq.id, nuevo)
    pq.estado = nuevo
  } catch (err) {
    alert(err.message || 'Error al cambiar estado')
  }
}

onMounted(() => {
  cargarParqueaderos()
})
</script>
