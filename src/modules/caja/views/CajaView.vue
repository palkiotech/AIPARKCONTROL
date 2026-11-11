<template>
  <div class="space-y-6 max-w-3xl">
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
      <div>
        <h2 class="text-xl md:text-2xl font-bold">Caja y Turnos</h2>
        <p class="text-xs md:text-sm text-text-secondary">Control del efectivo, retiros y flujo de entrega de turno.</p>
      </div>

      <div v-if="mensajeExito" class="px-3 py-1.5 rounded-lg bg-success-bg text-success text-xs font-semibold border border-success/20">
        {{ mensajeExito }}
      </div>
      <div v-if="errorMensaje" class="px-3 py-1.5 rounded-lg bg-danger-bg text-danger text-xs font-semibold border border-danger/20">
        {{ errorMensaje }}
      </div>
    </div>

    <!-- Indicador de Carga / Spinner -->
    <div v-if="cargando" class="flex flex-col items-center justify-center py-20 text-text-muted space-y-3">
      <div class="w-8 h-8 border-3 border-primary/20 border-t-primary rounded-full animate-spin"></div>
      <span class="text-xs font-semibold">Consultando estado de caja...</span>
    </div>

    <template v-else>
      <!-- ESTADO 1: SIN TURNO ABIERTO (PIDE ABRIR TURNO CON BASE) -->
      <div v-if="!turnoActual || turnoActual.estado === 'cerrado'" class="bg-surface rounded-2xl border border-border p-6 text-center space-y-4">
      <div class="w-12 h-12 bg-warning-bg text-warning rounded-full mx-auto flex items-center justify-center font-bold text-xl">
        !
      </div>
      <h3 class="font-bold text-lg">No hay un turno de caja abierto</h3>
      <p class="text-xs text-text-muted max-w-md mx-auto">
        Para poder cobrar salidas y registrar pagos en efectivo es obligatorio abrir un turno e indicar la base inicial de caja.
      </p>

      <div class="max-w-xs mx-auto space-y-3 pt-2">
        <div>
          <label class="block text-xs font-semibold text-text-secondary mb-1">Base Inicial en Efectivo ($)</label>
          <input 
            v-model.number="formAbrir.base"
            type="number" 
            placeholder="0"
            class="input-field text-center font-bold text-lg"
          />
        </div>
        <button @click="abrirNuevoTurno" class="btn-primary w-full text-sm py-2.5">
          Abrir Turno con Base
        </button>
      </div>
    </div>

    <!-- ESTADO 2: TURNO ABIERTO EN CURSO (RESUMEN EN VIVO) -->
    <div v-else-if="turnoActual.estado === 'abierto'" class="space-y-4">
      <!-- Tarjetas de Caja -->
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div class="bg-surface p-5 rounded-2xl border border-primary/30 shadow-sm space-y-1">
          <span class="text-xs font-semibold uppercase tracking-wider text-text-muted">Efectivo Esperado en Caja</span>
          <p class="text-3xl font-black text-primary">
            ${{ (turnoActual.efectivo_esperado || 0).toLocaleString() }}
          </p>
          <p class="text-xs text-text-secondary pt-1">
            Base inicial: ${{ (turnoActual.base_inicial || 0).toLocaleString() }}
          </p>
        </div>

        <div class="bg-surface p-5 rounded-2xl border border-border space-y-2">
          <div class="flex justify-between items-center text-xs">
            <span class="text-text-muted">Estado del Turno:</span>
            <span class="px-2 py-0.5 rounded-full font-bold bg-success-bg text-success uppercase text-[10px]">
              Abierto en Vivo
            </span>
          </div>
          <div class="text-xs space-y-1 text-text-secondary">
            <p>Abierto a las: <strong>{{ formatearHora(turnoActual.abierto_at) }}</strong></p>
            <p>Responsable: <strong>{{ turnoActual.profiles?.nombre || 'Operador actual' }}</strong></p>
          </div>
        </div>
      </div>

      <!-- Acciones de Caja -->
      <div class="flex flex-wrap gap-3">
        <button @click="mostrarModalRetiro = true" class="btn-secondary text-xs py-2 px-4 flex items-center space-x-1.5">
          <span>💸 Registrar Retiro / Ingreso</span>
        </button>
        <button @click="mostrarModalEntrega = true" class="btn-primary text-xs py-2 px-4 flex items-center space-x-1.5">
          <span>🤝 Entregar Turno al Relevo</span>
        </button>
      </div>
    </div>

    <!-- ESTADO 3: TURNO POR RECIBIR (ENTREGA EN PROCESO) -->
    <div v-else-if="turnoActual.estado === 'por_recibir'" class="bg-surface rounded-2xl border border-warning/40 p-6 space-y-4">
      <div class="flex items-center space-x-2 text-warning font-bold text-sm">
        <span>🤝 Relevo de Turno en Proceso</span>
      </div>
      <p class="text-xs text-text-secondary">
        El operador saliente contó <strong>${{ (turnoActual.efectivo_contado || 0).toLocaleString() }}</strong> en efectivo (Diferencia: ${{ (turnoActual.diferencia || 0).toLocaleString() }}).
      </p>

      <div class="bg-surface-elevated p-4 rounded-xl border border-border space-y-3">
        <h4 class="font-bold text-xs text-text-primary uppercase tracking-wider">Confirmación del Operador Entrante</h4>
        <div>
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Efectivo Físico Recibido ($)</label>
          <input 
            v-model.number="formRecibir.efectivo"
            type="number" 
            placeholder="0"
            class="input-field text-sm font-bold"
          />
        </div>
        <button @click="confirmarRecepcionTurno" class="btn-primary w-full text-xs py-2.5">
          Confirmar Recepción e Iniciar Mi Turno
        </button>
      </div>
    </div>

    <!-- MODAL RETIRO / INGRESO MANUAL (HU-24) -->
    <div v-if="mostrarModalRetiro" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-sm w-full shadow-2xl space-y-4">
        <h3 class="text-base font-bold text-text-primary">Movimiento de Caja</h3>
        <div class="space-y-3">
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Tipo de Movimiento</label>
            <select v-model="formMovimiento.tipo" class="input-field text-xs">
              <option value="retiro">Retiro (El dueño retira efectivo)</option>
              <option value="ingreso_manual">Ingreso Manual (Aporte a la caja)</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Valor ($)</label>
            <input v-model.number="formMovimiento.valor" type="number" class="input-field text-sm font-bold" placeholder="0" />
          </div>
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Motivo Justificado *</label>
            <input v-model="formMovimiento.motivo" type="text" placeholder="Ej. Retiro del dueño..." class="input-field text-xs" />
          </div>
        </div>

        <div class="flex space-x-2 pt-2">
          <button @click="mostrarModalRetiro = false" class="btn-secondary w-1/3 text-xs">Cancelar</button>
          <button @click="guardarMovimiento" class="btn-primary w-2/3 text-xs">Registrar Movimiento</button>
        </div>
      </div>
    </div>

    <!-- MODAL ENTREGAR TURNO (HU-24) -->
    <div v-if="mostrarModalEntrega" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-sm w-full shadow-2xl space-y-4">
        <h3 class="text-base font-bold text-text-primary">Entregar Turno</h3>
        <p class="text-xs text-text-secondary">
          Efectivo esperado en el sistema: <strong class="text-primary">${{ (turnoActual.efectivo_esperado || 0).toLocaleString() }}</strong>
        </p>

        <div class="space-y-3">
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Efectivo Físico Contado ($) *</label>
            <input v-model.number="formEntrega.efectivo" type="number" class="input-field text-sm font-bold" placeholder="0" />
          </div>
          <div v-if="formEntrega.efectivo !== null && formEntrega.efectivo !== undefined">
            <p class="text-xs font-semibold" :class="diferenciaCalculada >= 0 ? 'text-success' : 'text-danger'">
              {{ diferenciaCalculada >= 0 ? `Sobrante: +$${diferenciaCalculada.toLocaleString()}` : `Faltante: -$${Math.abs(diferenciaCalculada).toLocaleString()}` }}
            </p>
          </div>
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Observación</label>
            <textarea v-model="formEntrega.observacion" rows="2" class="input-field text-xs" placeholder="Novedades en el turno..."></textarea>
          </div>
        </div>

        <div class="flex space-x-2 pt-2">
          <button @click="mostrarModalEntrega = false" class="btn-secondary w-1/3 text-xs">Cancelar</button>
          <button @click="confirmarEntregaTurno" class="btn-primary w-2/3 text-xs">Entregar Turno</button>
        </div>
      </div>
    </div>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { cajaService } from '@/modules/caja/services/cajaService'

const authStore = useAuthStore()

const cargando = ref(true)
const turnoActual = ref(null)
const mensajeExito = ref('')
const errorMensaje = ref('')

const mostrarModalRetiro = ref(false)
const mostrarModalEntrega = ref(false)

const formAbrir = ref({ base: 50000 })
const formMovimiento = ref({ tipo: 'retiro', valor: 0, motivo: '' })
const formEntrega = ref({ efectivo: 0, observacion: '' })
const formRecibir = ref({ efectivo: 0 })

const diferenciaCalculada = computed(() => {
  return (formEntrega.value.efectivo || 0) - (turnoActual.value?.efectivo_esperado || 0)
})

function formatearHora(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

async function cargarTurno() {
  const pqId = authStore.parqueaderoId
  cargando.value = true
  try {
    turnoActual.value = await cajaService.obtenerTurnoActual(pqId)
    if (turnoActual.value) {
      formRecibir.value.efectivo = turnoActual.value.efectivo_contado || turnoActual.value.efectivo_esperado || 0
      formEntrega.value.efectivo = turnoActual.value.efectivo_esperado || 0
    }
  } catch (err) {
    console.warn(err)
  } finally {
    cargando.value = false
  }
}

async function abrirNuevoTurno() {
  errorMensaje.value = ''
  try {
    await cajaService.abrirTurno(formAbrir.value.base)
    mensajeExito.value = 'Turno de caja abierto correctamente'
    await cargarTurno()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al abrir turno'
  }
}

async function guardarMovimiento() {
  if (!formMovimiento.value.valor || !formMovimiento.value.motivo) {
    return alert('Indica el valor y el motivo')
  }
  try {
    await cajaService.registrarMovimiento(
      turnoActual.value.id,
      formMovimiento.value.tipo,
      formMovimiento.value.valor,
      formMovimiento.value.motivo
    )
    mostrarModalRetiro.value = false
    formMovimiento.value = { tipo: 'retiro', valor: 0, motivo: '' }
    mensajeExito.value = 'Movimiento registrado correctamente'
    await cargarTurno()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al registrar movimiento'
  }
}

async function confirmarEntregaTurno() {
  try {
    await cajaService.entregarTurno(
      turnoActual.value.id,
      formEntrega.value.efectivo,
      formEntrega.value.observacion
    )
    mostrarModalEntrega.value = false
    mensajeExito.value = 'Turno entregado, listo para recepción del relevo'
    await cargarTurno()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al entregar turno'
  }
}

async function confirmarRecepcionTurno() {
  try {
    await cajaService.recibirTurno(turnoActual.value.id, formRecibir.value.efectivo)
    mensajeExito.value = 'Turno recibido con éxito. Nuevo turno iniciado.'
    await cargarTurno()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al recibir turno'
  }
}

onMounted(() => {
  cargarTurno()
})
</script>

<style scoped>
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
