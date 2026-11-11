<template>
  <div class="space-y-6">
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div>
        <h2 class="text-xl md:text-2xl font-bold">Mensualidades</h2>
        <p class="text-xs md:text-sm text-text-secondary">Control de clientes mensuales, agenda de cobro y vencimientos.</p>
      </div>

      <div>
        <button 
          @click="mostrarModalNueva = true"
          class="px-4 py-2.5 bg-primary text-white font-bold rounded-xl text-xs sm:text-sm shadow-md hover:opacity-90 flex items-center space-x-1.5"
        >
          <span>+ Nueva Mensualidad</span>
        </button>
      </div>
    </div>

    <!-- Feedback -->
    <div v-if="mensajeExito" class="p-3 rounded-lg bg-success-bg text-success text-xs font-semibold border border-success/20">
      {{ mensajeExito }}
    </div>
    <div v-if="errorMensaje" class="p-3 rounded-lg bg-danger-bg text-danger text-xs font-semibold border border-danger/20">
      {{ errorMensaje }}
    </div>

    <!-- Pestañas Agenda vs Todas -->
    <div class="flex border-b border-border space-x-4 text-xs font-bold">
      <button 
        @click="pestañaActiva = 'agenda'"
        class="pb-2 border-b-2 transition-colors uppercase tracking-wider"
        :class="pestañaActiva === 'agenda' ? 'border-primary text-primary' : 'border-transparent text-text-muted hover:text-text-primary'"
      >
        📅 Agenda de Vencimientos
      </button>
      <button 
        @click="pestañaActiva = 'todas'"
        class="pb-2 border-b-2 transition-colors uppercase tracking-wider"
        :class="pestañaActiva === 'todas' ? 'border-primary text-primary' : 'border-transparent text-text-muted hover:text-text-primary'"
      >
        Todas las Mensualidades ({{ mensualidades.length }})
      </button>
    </div>

    <!-- VISTA 1: AGENDA DE VENCIMIENTOS (HU-17) -->
    <div v-if="pestañaActiva === 'agenda'" class="space-y-6">
      <!-- Sección: Vencidas (Rojo) -->
      <div v-if="gruposAgenda.vencidas.length" class="space-y-2">
        <h3 class="text-xs font-bold uppercase tracking-wider text-danger flex items-center space-x-1.5">
          <span class="w-2.5 h-2.5 rounded-full bg-danger"></span>
          <span>Vencidas ({{ gruposAgenda.vencidas.length }})</span>
        </h3>
        <div class="grid grid-cols-1 gap-2.5">
          <div v-for="m in gruposAgenda.vencidas" :key="m.id" class="card-mensualidad border-l-4 border-l-danger">
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
              <div>
                <div class="flex items-center space-x-2">
                  <span class="font-bold text-sm text-text-primary">{{ m.clientes?.nombre }}</span>
                  <span class="font-mono font-bold text-xs px-2 py-0.5 rounded bg-surface-elevated text-primary">
                    {{ m.vehiculos?.placa }}
                  </span>
                </div>
                <p class="text-xs text-text-secondary mt-0.5">
                  Venció el {{ m.fecha_fin }} <strong class="text-danger">({{ m.clasificacion.diasMora }} días de mora)</strong> · 
                  <a :href="`tel:${m.clientes?.telefono}`" class="text-primary hover:underline font-semibold">📞 {{ m.clientes?.telefono || 'Sin teléfono' }}</a>
                </p>
                <p class="text-[11px] text-text-muted mt-1">
                  Aviso: <strong>{{ m.ultimoAviso ? `${m.ultimoAviso.medio} (${m.ultimoAviso.nota || 'Sin nota'})` : 'Sin avisar' }}</strong>
                </p>
              </div>

              <div class="flex items-center space-x-2 self-end sm:self-center">
                <span class="font-bold text-text-primary text-sm mr-2">${{ (m.planes_mensuales?.valor || 0).toLocaleString() }}</span>
                <button @click="abrirAviso(m)" class="btn-secondary text-xs">Avisar</button>
                <button @click="abrirPago(m)" class="btn-primary text-xs">Pagar</button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Sección: Vencen Hoy / Mañana (Amarillo) -->
      <div v-if="gruposAgenda.urgentes.length" class="space-y-2">
        <h3 class="text-xs font-bold uppercase tracking-wider text-warning flex items-center space-x-1.5">
          <span class="w-2.5 h-2.5 rounded-full bg-warning"></span>
          <span>Vencen Hoy o Próximamente ({{ gruposAgenda.urgentes.length }})</span>
        </h3>
        <div class="grid grid-cols-1 gap-2.5">
          <div v-for="m in gruposAgenda.urgentes" :key="m.id" class="card-mensualidad border-l-4 border-l-warning">
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
              <div>
                <div class="flex items-center space-x-2">
                  <span class="font-bold text-sm text-text-primary">{{ m.clientes?.nombre }}</span>
                  <span class="font-mono font-bold text-xs px-2 py-0.5 rounded bg-surface-elevated text-primary">
                    {{ m.vehiculos?.placa }}
                  </span>
                </div>
                <p class="text-xs text-text-secondary mt-0.5">
                  Vence: <strong :class="m.clasificacion.esHoy ? 'text-danger' : 'text-warning'">{{ m.clasificacion.esHoy ? '¡HOY!' : `en ${m.clasificacion.diasRestantes} días (${m.fecha_fin})` }}</strong> · 
                  <a :href="`tel:${m.clientes?.telefono}`" class="text-primary hover:underline font-semibold">📞 {{ m.clientes?.telefono }}</a>
                </p>
                <p class="text-[11px] text-text-muted mt-1">
                  Aviso: <strong>{{ m.ultimoAviso ? `${m.ultimoAviso.medio} · ${formatearHora(m.ultimoAviso.created_at)}` : 'Sin avisar' }}</strong>
                </p>
              </div>

              <div class="flex items-center space-x-2 self-end sm:self-center">
                <span class="font-bold text-text-primary text-sm mr-2">${{ (m.planes_mensuales?.valor || 0).toLocaleString() }}</span>
                <button @click="abrirAviso(m)" class="btn-secondary text-xs">Avisar</button>
                <button @click="abrirPago(m)" class="btn-primary text-xs">Pagar</button>
              </div>
            </div>
          </div>
        </div>
      </div>

      <!-- Sección: Al Día (Verde) -->
      <div v-if="gruposAgenda.alDia.length" class="space-y-2">
        <h3 class="text-xs font-bold uppercase tracking-wider text-success flex items-center space-x-1.5">
          <span class="w-2.5 h-2.5 rounded-full bg-success"></span>
          <span>Al Día ({{ gruposAgenda.alDia.length }})</span>
        </h3>
        <div class="grid grid-cols-1 gap-2.5">
          <div v-for="m in gruposAgenda.alDia" :key="m.id" class="card-mensualidad border-l-4 border-l-success">
            <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-2">
              <div>
                <span class="font-bold text-sm text-text-primary">{{ m.clientes?.nombre }}</span>
                <span class="font-mono font-bold text-xs px-2 py-0.5 rounded bg-surface-elevated text-primary ml-2">
                  {{ m.vehiculos?.placa }}
                </span>
                <p class="text-xs text-text-secondary mt-0.5">Vigente hasta: {{ m.fecha_fin }} (en {{ m.clasificacion.diasRestantes }} días)</p>
              </div>
              <span class="font-bold text-text-primary text-sm">${{ (m.planes_mensuales?.valor || 0).toLocaleString() }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- VISTA 2: TODAS LAS MENSUALIDADES -->
    <div v-if="pestañaActiva === 'todas'" class="bg-surface rounded-xl border border-border overflow-x-auto">
      <table class="w-full text-left text-xs">
        <thead class="bg-surface-elevated text-text-secondary uppercase border-b border-border text-[10px]">
          <tr>
            <th class="px-3 py-2.5">Cliente</th>
            <th class="px-3 py-2.5">Placa</th>
            <th class="px-3 py-2.5">Plan</th>
            <th class="px-3 py-2.5">Día Corte</th>
            <th class="px-3 py-2.5">Vence</th>
            <th class="px-3 py-2.5">Estado</th>
            <th class="px-3 py-2.5 text-right">Acción</th>
          </tr>
        </thead>
        <tbody class="divide-y divide-border">
          <tr v-for="m in mensualidades" :key="m.id" class="hover:bg-surface-elevated/40">
            <td class="px-3 py-3 font-bold text-text-primary">{{ m.clientes?.nombre }}</td>
            <td class="px-3 py-3 font-mono font-bold text-primary">{{ m.vehiculos?.placa }}</td>
            <td class="px-3 py-3">{{ m.planes_mensuales?.nombre }}</td>
            <td class="px-3 py-3">Día {{ m.dia_corte }}</td>
            <td class="px-3 py-3 font-semibold">{{ m.fecha_fin }}</td>
            <td class="px-3 py-3">
              <span 
                class="px-2 py-0.5 rounded-full text-[10px] font-bold uppercase"
                :class="{
                  'bg-danger-bg text-danger': m.clasificacion.color === 'rojo',
                  'bg-warning-bg text-warning': m.clasificacion.color === 'amarillo',
                  'bg-success-bg text-success': m.clasificacion.color === 'verde'
                }"
              >
                {{ m.clasificacion.estado.replace('_', ' ') }}
              </span>
            </td>
            <td class="px-3 py-3 text-right space-x-1">
              <button @click="abrirPago(m)" class="btn-primary text-[10px] py-1 px-2">Pagar</button>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- MODAL NUEVA MENSUALIDAD (HU-16) -->
    <div v-if="mostrarModalNueva" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-md w-full shadow-2xl space-y-4 max-h-[90vh] overflow-y-auto">
        <h3 class="text-base font-bold text-text-primary">Nueva Mensualidad</h3>

        <form @submit.prevent="guardarMensualidad" class="space-y-3">
          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="block text-xs font-semibold mb-1 text-text-secondary">Nombre Cliente *</label>
              <input v-model="formNueva.nombre" type="text" required placeholder="Ana Gómez" class="input-field text-xs" />
            </div>
            <div>
              <label class="block text-xs font-semibold mb-1 text-text-secondary">Documento / Cédula *</label>
              <input v-model="formNueva.documento" type="text" required placeholder="10203040" class="input-field text-xs" />
            </div>
          </div>

          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="block text-xs font-semibold mb-1 text-text-secondary">Teléfono (Llamadas / WhatsApp)</label>
              <input v-model="formNueva.telefono" type="tel" placeholder="310 555 0101" class="input-field text-xs" />
            </div>
            <div>
              <label class="block text-xs font-semibold mb-1 text-text-secondary">Correo (Opcional)</label>
              <input v-model="formNueva.email" type="email" placeholder="cliente@correo.com" class="input-field text-xs" />
            </div>
          </div>

          <div class="grid grid-cols-2 gap-2">
            <div>
              <label class="block text-xs font-semibold mb-1 text-text-secondary">Placa Vehículo *</label>
              <input v-model="formNueva.placa" type="text" required placeholder="ABC123" class="input-field text-xs font-mono uppercase" />
            </div>
            <div>
              <label class="block text-xs font-semibold mb-1 text-text-secondary">Plan Mensual *</label>
              <select v-model="formNueva.planId" class="input-field text-xs">
                <option v-for="p in planesDisponibles" :key="p.id" :value="p.id">
                  {{ p.nombre }} (${{ p.valor.toLocaleString() }})
                </option>
              </select>
            </div>
          </div>

          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Fecha de Inicio *</label>
            <input v-model="formNueva.fechaInicio" type="date" required class="input-field text-xs" />
          </div>

          <div class="p-3 bg-surface-elevated rounded-xl border border-border space-y-2">
            <label class="flex items-center space-x-2 text-xs font-semibold cursor-pointer">
              <input v-model="formNueva.registrarPrimerPago" type="checkbox" class="rounded text-primary focus:ring-0" />
              <span>Registrar primer pago de una vez</span>
            </label>
            <div v-if="formNueva.registrarPrimerPago">
              <label class="block text-[11px] font-semibold text-text-secondary mb-1">Método de Pago</label>
              <select v-model="formNueva.metodoPagoId" class="input-field text-xs">
                <option v-for="m in metodosDisponibles" :key="m.id" :value="m.id">{{ m.nombre }}</option>
              </select>
            </div>
          </div>

          <div class="flex space-x-2 pt-2">
            <button type="button" @click="mostrarModalNueva = false" class="btn-secondary w-1/3 text-xs">Cancelar</button>
            <button type="submit" class="btn-primary w-2/3 text-xs">Crear Mensualidad</button>
          </div>
        </form>
      </div>
    </div>

    <!-- MODAL REGISTRAR PAGO (HU-18) -->
    <div v-if="modalPago" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-sm w-full shadow-2xl space-y-4">
        <h3 class="text-base font-bold text-text-primary">Registrar Pago y Renovar</h3>
        <p class="text-xs text-text-secondary">
          Cliente: <strong class="text-text-primary">{{ modalPago.mensualidad.clientes?.nombre }}</strong> ({{ modalPago.mensualidad.vehiculos?.placa }})
        </p>

        <div class="space-y-3">
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Valor a Pagar ($)</label>
            <input v-model.number="modalPago.valor" type="number" class="input-field text-sm font-bold" />
          </div>
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Método de Pago</label>
            <select v-model="modalPago.metodoPagoId" class="input-field text-xs">
              <option v-for="m in metodosDisponibles" :key="m.id" :value="m.id">{{ m.nombre }}</option>
            </select>
          </div>
        </div>

        <div class="flex space-x-2 pt-2">
          <button @click="modalPago = null" class="btn-secondary w-1/3 text-xs">Cancelar</button>
          <button @click="confirmarPago" class="btn-primary w-2/3 text-xs">Confirmar Pago</button>
        </div>
      </div>
    </div>

    <!-- MODAL REGISTRAR AVISO (HU-19) -->
    <div v-if="modalAviso" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-sm w-full shadow-2xl space-y-4">
        <h3 class="text-base font-bold text-text-primary">Registrar Aviso de Cobro</h3>
        <p class="text-xs text-text-secondary">
          Avisar a <strong>{{ modalAviso.mensualidad.clientes?.nombre }}</strong> (Tel: {{ modalAviso.mensualidad.clientes?.telefono }})
        </p>

        <div class="space-y-3">
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Medio del Aviso *</label>
            <select v-model="modalAviso.medio" class="input-field text-xs">
              <option value="llamada">Llamada telefónica</option>
              <option value="mensaje">Mensaje (WhatsApp / SMS)</option>
              <option value="en_persona">En persona (en el patio)</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Nota del aviso</label>
            <input v-model="modalAviso.nota" type="text" placeholder="Ej. Dijo que pasa a pagar hoy en la tarde..." class="input-field text-xs" />
          </div>
        </div>

        <div class="flex space-x-2 pt-2">
          <button @click="modalAviso = null" class="btn-secondary w-1/3 text-xs">Cancelar</button>
          <button @click="confirmarAviso" class="btn-primary w-2/3 text-xs">Guardar Aviso</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { mensualidadesService } from '@/modules/mensualidades/services/mensualidadesService'
import { ajustesService } from '@/modules/ajustes/services/ajustesService'

const authStore = useAuthStore()

const pestañaActiva = ref('agenda')
const mensualidades = ref([])
const planesDisponibles = ref([])
const metodosDisponibles = ref([])

const mostrarModalNueva = ref(false)
const modalPago = ref(null)
const modalAviso = ref(null)
const mensajeExito = ref('')
const errorMensaje = ref('')

const formNueva = ref({
  nombre: '',
  documento: '',
  telefono: '',
  email: '',
  placa: '',
  planId: null,
  tipoVehiculoId: null,
  fechaInicio: new Date().toISOString().slice(0, 10),
  registrarPrimerPago: true,
  metodoPagoId: null
})

const gruposAgenda = computed(() => {
  const vencidas = []
  const urgentes = []
  const alDia = []

  mensualidades.value.forEach(m => {
    if (m.clasificacion.color === 'rojo') {
      vencidas.push(m)
    } else if (m.clasificacion.color === 'amarillo') {
      urgentes.push(m)
    } else {
      alDia.push(m)
    }
  })

  return { vencidas, urgentes, alDia }
})

function formatearHora(iso) {
  if (!iso) return ''
  return new Date(iso).toLocaleDateString([], { month: 'short', day: 'numeric' })
}

async function cargarTodo() {
  const pqId = authStore.parqueaderoId
  try {
    const [lista, planes, metodos, tipos] = await Promise.all([
      mensualidadesService.listarMensualidades(pqId),
      ajustesService.listarPlanesMensuales(pqId),
      ajustesService.listarMetodosPago(pqId),
      ajustesService.listarTiposVehiculo(pqId)
    ])

    mensualidades.value = lista
    planesDisponibles.value = planes.length ? planes : [{ id: 'p1', nombre: 'Mensual Carro', valor: 150000 }]
    metodosDisponibles.value = metodos.length ? metodos : [{ id: 'm1', nombre: 'Efectivo' }]

    if (planesDisponibles.value.length) formNueva.value.planId = planesDisponibles.value[0].id
    if (metodosDisponibles.value.length) formNueva.value.metodoPagoId = metodosDisponibles.value[0].id
    if (tipos.length) formNueva.value.tipoVehiculoId = tipos[0].id
  } catch (err) {
    console.warn(err)
  }
}

async function guardarMensualidad() {
  try {
    await mensualidadesService.crearMensualidad(formNueva.value)
    mensajeExito.value = 'Mensualidad creada correctamente'
    mostrarModalNueva.value = false
    await cargarTodo()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al crear mensualidad'
  }
}

function abrirPago(m) {
  modalPago.value = {
    mensualidad: m,
    valor: m.planes_mensuales?.valor || 150000,
    metodoPagoId: metodosDisponibles.value[0]?.id
  }
}

async function confirmarPago() {
  try {
    await mensualidadesService.registrarPago({
      mensualidadId: modalPago.value.mensualidad.id,
      metodoPagoId: modalPago.value.metodoPagoId,
      valor: modalPago.value.valor
    })
    mensajeExito.value = 'Pago registrado y mensualidad renovada exitosamente'
    modalPago.value = null
    await cargarTodo()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al registrar pago'
  }
}

function abrirAviso(m) {
  modalAviso.value = {
    mensualidad: m,
    medio: 'llamada',
    nota: ''
  }
}

async function confirmarAviso() {
  try {
    await mensualidadesService.registrarAviso({
      mensualidadId: modalAviso.value.mensualidad.id,
      medio: modalAviso.value.medio,
      nota: modalAviso.value.nota
    })
    mensajeExito.value = 'Aviso de cobro registrado'
    modalAviso.value = null
    await cargarTodo()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al guardar aviso'
  }
}

onMounted(() => {
  cargarTodo()
})
</script>

<style scoped>
.card-mensualidad {
  @apply bg-surface p-3.5 rounded-xl border border-border shadow-sm;
}
.input-field {
  @apply w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary transition-colors;
}
.btn-primary {
  @apply px-4 py-2 rounded-lg bg-primary text-white font-semibold hover:opacity-90 transition-opacity disabled:opacity-50 shadow-sm;
}
.btn-secondary {
  @apply px-3 py-1.5 rounded-lg border border-border bg-surface text-text-primary hover:bg-surface-elevated transition-colors font-medium;
}
</style>
