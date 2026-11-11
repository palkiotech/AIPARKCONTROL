<template>
  <div class="space-y-6">
    <!-- Encabezado Operativo y Resumen de Ocupación -->
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
      <div>
        <h2 class="text-xl md:text-2xl font-bold">Patio de Parqueo</h2>
        <p class="text-xs md:text-sm text-text-secondary">Control de entradas, salidas y capacidad en tiempo real.</p>
      </div>

      <div class="flex gap-2">
        <button 
          @click="mostrarModalEntrada = true"
          class="flex-1 sm:flex-none px-4 py-2.5 bg-primary text-white font-bold rounded-xl text-sm shadow-md hover:opacity-90 transition-opacity flex items-center justify-center space-x-1.5"
        >
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg>
          <span>Nueva Entrada</span>
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

    <!-- TARJETAS DE OCUPACIÓN Y CAPACIDAD CON SOBRECUPO (HU-12) -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <div 
        v-for="tipo in resumenOcupacion" 
        :key="tipo.id"
        class="bg-surface p-3.5 rounded-xl border transition-all"
        :class="tipo.ocupados >= tipo.capacidad ? 'border-warning shadow-sm' : 'border-border'"
      >
        <div class="flex justify-between items-start">
          <span class="text-xs font-bold uppercase text-text-secondary">{{ tipo.nombre }}</span>
          <span v-if="tipo.ocupados >= tipo.capacidad" class="text-[10px] font-bold px-1.5 py-0.5 rounded bg-warning-bg text-warning">
            Lleno
          </span>
        </div>
        <div class="mt-1 flex items-baseline space-x-1">
          <span class="text-2xl font-black text-text-primary">{{ tipo.ocupados }}</span>
          <span class="text-xs text-text-muted">/ {{ tipo.capacidad }}</span>
        </div>
        <p class="text-[10px] text-text-secondary mt-1">
          {{ tipo.ocupados >= tipo.capacidad ? `Sobrecupo (${tipo.ocupados - tipo.capacidad})` : `${tipo.capacidad - tipo.ocupados} libres` }}
        </p>
      </div>
    </div>

    <!-- FILTRO Y LISTA DE VEHÍCULOS DENTRO -->
    <div class="bg-surface rounded-xl border border-border overflow-hidden space-y-3 p-4">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
        <h3 class="font-bold text-sm text-text-primary">
          Vehículos en Patio ({{ vehiculosDentro.length }})
        </h3>
        <div class="relative w-full sm:w-64">
          <input 
            v-model="filtroPlaca"
            type="text" 
            placeholder="Buscar por placa..."
            class="w-full px-3 py-1.5 text-xs rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary uppercase"
          />
        </div>
      </div>

      <div v-if="cargando" class="text-center py-8 text-xs text-text-muted">
        Cargando vehículos en patio...
      </div>

      <div v-else-if="vehiculosFiltrados.length === 0" class="text-center py-8 text-xs text-text-muted">
        No hay vehículos dentro con ese criterio.
      </div>

      <!-- Tarjetas en Móvil / Tabla en Desktop -->
      <div v-else class="overflow-x-auto">
        <table class="w-full text-left text-xs">
          <thead class="bg-surface-elevated text-text-secondary uppercase border-b border-border text-[10px]">
            <tr>
              <th class="px-3 py-2.5">Placa</th>
              <th class="px-3 py-2.5">Tipo</th>
              <th class="px-3 py-2.5">Entrada</th>
              <th class="px-3 py-2.5">Tiempo</th>
              <th class="px-3 py-2.5">Est. Cobro</th>
              <th class="px-3 py-2.5 text-right">Acción</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <tr v-for="v in vehiculosFiltrados" :key="v.id" class="hover:bg-surface-elevated/40">
              <td class="px-3 py-3 font-mono font-bold text-sm text-primary">
                {{ v.placa }}
                <span v-if="v.hora_origen === 'dispositivo'" class="text-[9px] px-1 rounded bg-surface-elevated text-text-muted ml-1 font-sans">
                  Offline
                </span>
              </td>
              <td class="px-3 py-3">{{ v.tipos_vehiculo?.nombre || 'Vehículo' }}</td>
              <td class="px-3 py-3 text-text-secondary">{{ formatearHora(v.entrada_at) }}</td>
              <td class="px-3 py-3 font-semibold">{{ calcularMinutos(v.entrada_at) }} min</td>
              <td class="px-3 py-3 font-bold text-text-primary">${{ estimarCobro(v).toLocaleString() }}</td>
              <td class="px-3 py-3 text-right space-x-1">
                <button 
                  @click="abrirModalCobro(v)"
                  class="px-3 py-1.5 rounded-lg bg-primary text-white font-bold text-xs hover:opacity-90"
                >
                  Cobrar
                </button>
                <button 
                  v-if="authStore.isAdmin"
                  @click="abrirModalAnular(v)"
                  class="px-2 py-1.5 rounded-lg border border-border text-danger hover:bg-danger-bg text-[11px]"
                  title="Anular registro"
                >
                  Anular
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- MODAL REGISTRO RÁPIDO DE ENTRADA (< 10 segs, HU-11) -->
    <div v-if="mostrarModalEntrada" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-sm w-full shadow-2xl space-y-4">
        <div class="flex justify-between items-center">
          <h3 class="text-base font-bold text-text-primary">Registrar Entrada</h3>
          <button @click="mostrarModalEntrada = false" class="text-text-muted hover:text-text-primary text-sm font-bold">✕</button>
        </div>

        <form @submit.prevent="confirmarEntrada" class="space-y-4">
          <!-- Campo Placa enfocado y gigante -->
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Placa del Vehículo *</label>
            <input 
              v-model="entradaForm.placa"
              type="text" 
              required
              autofocus
              maxlength="10"
              placeholder="ABC123"
              class="w-full text-center text-2xl font-mono font-bold tracking-widest px-3 py-2.5 rounded-xl bg-surface-elevated border-2 border-primary focus:outline-none uppercase text-text-primary"
            />
          </div>

          <!-- Botones grandes para selección de Tipo de Vehículo -->
          <div>
            <label class="block text-xs font-semibold mb-1.5 text-text-secondary">Tipo de Vehículo</label>
            <div class="grid grid-cols-2 gap-2">
              <button 
                v-for="t in tiposDisponibles" 
                :key="t.id"
                type="button"
                @click="entradaForm.tipoVehiculoId = t.id"
                class="py-2.5 px-3 rounded-xl border text-xs font-bold transition-all text-center"
                :class="entradaForm.tipoVehiculoId === t.id ? 'bg-primary text-white border-primary shadow-sm' : 'bg-surface-elevated border-border text-text-secondary hover:text-text-primary'"
              >
                {{ t.nombre }}
              </button>
            </div>
          </div>

          <!-- Advertencia de sobrecupo (Informativa, no bloqueante, HU-11) -->
          <div v-if="verificarSobrecupo(entradaForm.tipoVehiculoId)" class="p-2.5 rounded-lg bg-warning-bg text-warning text-xs border border-warning/20">
            ⚠️ <strong>Capacidad alcanzada:</strong> Este tipo ya está lleno según la capacidad, pero puedes registrarlo de todas formas.
          </div>

          <div class="flex space-x-2 pt-2">
            <button 
              type="button" 
              @click="mostrarModalEntrada = false" 
              class="w-1/3 py-2.5 text-xs font-semibold rounded-xl border border-border text-text-secondary hover:bg-surface-elevated"
            >
              Cancelar
            </button>
            <button 
              type="submit" 
              :disabled="guardandoEntrada"
              class="w-2/3 py-2.5 text-xs font-bold rounded-xl bg-primary text-white hover:opacity-90 shadow-md disabled:opacity-50"
            >
              {{ guardandoEntrada ? 'Guardando...' : 'Confirmar Entrada' }}
            </button>
          </div>
        </form>
      </div>
    </div>

    <!-- MODAL DE TICKET / QR GENERADO (HU-27) -->
    <div v-if="ticketGenerado" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-6 max-w-xs w-full shadow-2xl text-center space-y-4">
        <h4 class="font-bold text-sm text-text-primary">Ticket de Entrada</h4>
        
        <div class="p-3 bg-white rounded-xl inline-block border shadow-inner">
          <div class="w-40 h-40 flex items-center justify-center font-mono font-bold text-slate-800 text-lg border-2 border-dashed border-slate-300 rounded-lg">
            [ QR: {{ ticketGenerado.placa }} ]
          </div>
        </div>

        <div class="text-xs space-y-0.5 font-mono text-text-secondary">
          <p class="font-bold text-base text-text-primary">{{ ticketGenerado.placa }}</p>
          <p>Entrada: {{ formatearHora(ticketGenerado.entrada_at) }}</p>
          <p class="text-[10px] text-text-muted">Presenta este QR o placa a la salida</p>
        </div>

        <button 
          @click="ticketGenerado = null"
          class="w-full py-2 bg-primary text-white font-bold rounded-xl text-xs"
        >
          Aceptar
        </button>
      </div>
    </div>

    <!-- MODAL DE COBRO Y SALIDA (HU-13) -->
    <div v-if="modalCobro" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-sm w-full shadow-2xl space-y-4">
        <div class="flex justify-between items-center">
          <h3 class="text-base font-bold text-text-primary">Cobrar y Registrar Salida</h3>
          <button @click="modalCobro = null" class="text-text-muted hover:text-text-primary text-sm font-bold">✕</button>
        </div>

        <div class="bg-surface-elevated p-3 rounded-xl border border-border text-xs space-y-1.5">
          <div class="flex justify-between text-sm">
            <span class="font-mono font-bold text-primary">{{ modalCobro.registro.placa }}</span>
            <span>{{ modalCobro.registro.tipos_vehiculo?.nombre }}</span>
          </div>
          <div class="flex justify-between text-text-secondary">
            <span>Tiempo estancia:</span>
            <span class="font-semibold text-text-primary">{{ modalCobro.minutos }} minutos</span>
          </div>
          <div class="flex justify-between text-base font-bold pt-1 border-t border-border">
            <span>Total a Cobrar:</span>
            <span class="text-primary">${{ modalCobro.valorTotal.toLocaleString() }}</span>
          </div>
        </div>

        <!-- Método de Pago -->
        <div>
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Método de Pago</label>
          <select v-model="modalCobro.metodoPagoId" class="input-field text-xs">
            <option v-for="m in metodosPagoDisponibles" :key="m.id" :value="m.id">
              {{ m.nombre }} {{ m.es_efectivo ? '(Efectivo)' : '' }}
            </option>
          </select>
        </div>

        <!-- Si es efectivo, cálculo de vuelto -->
        <div v-if="esMetodoEfectivo" class="space-y-1">
          <label class="block text-xs font-semibold text-text-secondary">Paga con ($)</label>
          <input 
            v-model.number="modalCobro.pagaCon" 
            type="number" 
            class="input-field text-sm font-bold"
            placeholder="0"
          />
          <p v-if="modalCobro.pagaCon >= modalCobro.valorTotal" class="text-xs font-bold text-success">
            Vuelto: ${{ (modalCobro.pagaCon - modalCobro.valorTotal).toLocaleString() }}
          </p>
        </div>

        <div class="flex space-x-2 pt-2">
          <button 
            type="button" 
            @click="modalCobro = null" 
            class="w-1/3 py-2 text-xs font-semibold rounded-xl border border-border text-text-secondary hover:bg-surface-elevated"
          >
            Cancelar
          </button>
          <button 
            @click="confirmarSalida"
            :disabled="guardandoSalida"
            class="w-2/3 py-2 text-xs font-bold rounded-xl bg-primary text-white hover:opacity-90 shadow-md disabled:opacity-50"
          >
            {{ guardandoSalida ? 'Cobrando...' : 'Confirmar Cobro' }}
          </button>
        </div>
      </div>
    </div>

    <!-- MODAL DE COBRO EXITOSO Y COMPROBANTE (HU-20, HU-21) -->
    <div v-if="modalExitoCobro" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-sm w-full shadow-2xl text-center space-y-4">
        <div class="w-12 h-12 mx-auto rounded-full bg-success-bg text-success flex items-center justify-center">
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
          </svg>
        </div>

        <div>
          <h3 class="text-base font-bold text-text-primary">¡Cobro Registrado!</h3>
          <p class="text-xs text-text-secondary mt-1">
            Placa: <strong class="text-text-primary font-mono text-sm">{{ modalExitoCobro.placa }}</strong>
          </p>
        </div>

        <div class="bg-surface-elevated p-3 rounded-xl border border-border text-xs space-y-1">
          <div class="flex justify-between">
            <span class="text-text-secondary">Total Pagado:</span>
            <span class="font-bold text-primary font-mono">${{ modalExitoCobro.valorTotal.toLocaleString() }}</span>
          </div>
          <div v-if="modalExitoCobro.vuelto > 0" class="flex justify-between text-success font-semibold">
            <span>Cambio / Vuelto:</span>
            <span class="font-mono">${{ modalExitoCobro.vuelto.toLocaleString() }}</span>
          </div>
          <div class="flex justify-between text-[11px] text-text-muted">
            <span>Comprobante:</span>
            <span class="font-mono font-bold">{{ modalExitoCobro.consecutivo ? '#' + modalExitoCobro.consecutivo : 'Provisional' }}</span>
          </div>
        </div>

        <div class="space-y-2 pt-1">
          <button 
            @click="descargarComprobanteSalida"
            class="w-full py-2.5 text-xs font-bold rounded-xl bg-primary text-white hover:opacity-90 shadow-md flex items-center justify-center space-x-1.5"
          >
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 10v6m0 0l-3-3m3 3l3-3m2 8H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
            </svg>
            <span>Descargar Comprobante PDF</span>
          </button>
          <button 
            @click="modalExitoCobro = null"
            class="w-full py-2 text-xs font-semibold rounded-xl border border-border text-text-secondary hover:bg-surface-elevated"
          >
            Finalizar y Cerrar
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { ajustesService } from '@/modules/ajustes/services/ajustesService'
import { comprobanteService } from '@/modules/comprobantes/services/comprobanteService'
import { normalizarPlaca } from '@/utils/placa'
import { calcularCobroBase } from '@/domain/cobro'

const authStore = useAuthStore()

const cargando = ref(false)
const guardandoEntrada = ref(false)
const guardandoSalida = ref(false)
const mostrarModalEntrada = ref(false)
const ticketGenerado = ref(null)
const modalCobro = ref(null)
const modalExitoCobro = ref(null)
const mensajeExito = ref('')
const errorMensaje = ref('')
const filtroPlaca = ref('')

const vehiculosDentro = ref([])
const tiposDisponibles = ref([])
const metodosPagoDisponibles = ref([])

const entradaForm = ref({
  placa: '',
  tipoVehiculoId: null
})

const vehiculosFiltrados = computed(() => {
  if (!filtroPlaca.value) return vehiculosDentro.value
  const q = normalizarPlaca(filtroPlaca.value)
  return vehiculosDentro.value.filter(v => v.placa.includes(q))
})

const resumenOcupacion = computed(() => {
  return tiposDisponibles.value.map(tipo => {
    const ocupados = vehiculosDentro.value.filter(v => v.tipo_vehiculo_id === tipo.id).length
    return {
      id: tipo.id,
      nombre: tipo.nombre,
      capacidad: tipo.capacidad || 20,
      ocupados
    }
  })
})

const esMetodoEfectivo = computed(() => {
  const met = metodosPagoDisponibles.value.find(m => m.id === modalCobro.value?.metodoPagoId)
  return met?.es_efectivo ?? true
})

function formatearHora(iso) {
  if (!iso) return '—'
  return new Date(iso).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

function calcularMinutos(entradaIso) {
  const ms = Date.now() - new Date(entradaIso).getTime()
  return Math.max(1, Math.round(ms / 60000))
}

function estimarCobro(v) {
  const min = calcularMinutos(v.entrada_at)
  const tar = v.tarifas || { modalidad: 'por_hora', valor: 3500, minutos_gracia: 0 }
  return calcularCobroBase({
    minutos: min,
    modalidad: tar.modalidad || 'por_hora',
    valor: tar.valor || 3500,
    minutosGracia: 0 // Sin tiempo de gracia: desde el minuto 1 inicia el cobro
  })
}

function verificarSobrecupo(tipoId) {
  const tipo = resumenOcupacion.value.find(t => t.id === tipoId)
  return tipo && tipo.ocupados >= tipo.capacidad
}

async function cargarDatos() {
  const pqId = authStore.parqueaderoId
  const cachedVehiculos = ocupacionService.obtenerVehiculosDentroCache()
  
  // Renderizado instantáneo (0ms) si ya hay datos en memoria
  if (cachedVehiculos) {
    vehiculosDentro.value = cachedVehiculos
    cargando.value = false
  } else {
    cargando.value = true
  }

  try {
    const [dentro, tipos, metodos] = await Promise.all([
      ocupacionService.obtenerVehiculosDentro(pqId),
      ajustesService.listarTiposVehiculo(pqId),
      ajustesService.listarMetodosPago(pqId)
    ])

    vehiculosDentro.value = dentro
    tiposDisponibles.value = tipos.length ? tipos : [
      { id: 'tipo-carro', nombre: 'Carro', capacidad: 40 },
      { id: 'tipo-moto', nombre: 'Moto', capacidad: 25 }
    ]
    metodosPagoDisponibles.value = metodos.length ? metodos : [
      { id: 'met-efectivo', nombre: 'Efectivo', es_efectivo: true },
      { id: 'met-nequi', nombre: 'Nequi', es_efectivo: false }
    ]

    if (tiposDisponibles.value.length && !entradaForm.value.tipoVehiculoId) {
      entradaForm.value.tipoVehiculoId = tiposDisponibles.value[0].id
    }
  } catch (err) {
    console.warn(err)
  } finally {
    cargando.value = false
  }
}

async function confirmarEntrada() {
  guardandoEntrada.value = true
  errorMensaje.value = ''
  mensajeExito.value = ''

  try {
    const res = await ocupacionService.registrarEntrada({
      placa: entradaForm.value.placa,
      tipoVehiculoId: entradaForm.value.tipoVehiculoId
    })

    ticketGenerado.value = {
      placa: normalizarPlaca(entradaForm.value.placa),
      entrada_at: new Date().toISOString()
    }
    mostrarModalEntrada.value = false
    entradaForm.value.placa = ''
    mensajeExito.value = `Entrada registrada con éxito: ${ticketGenerado.value.placa}`
    await cargarDatos()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al registrar entrada'
  } finally {
    guardandoEntrada.value = false
  }
}

function abrirModalCobro(registro) {
  const min = calcularMinutos(registro.entrada_at)
  const val = estimarCobro(registro)

  modalCobro.value = {
    registro,
    minutos: min,
    valorTotal: val,
    metodoPagoId: metodosPagoDisponibles.value[0]?.id,
    pagaCon: val
  }
}

async function confirmarSalida() {
  if (!modalCobro.value) return
  guardandoSalida.value = true
  const infoCobro = { ...modalCobro.value }

  try {
    const resSalida = await ocupacionService.registrarSalida({
      registroId: infoCobro.registro.id,
      metodoPagoId: infoCobro.metodoPagoId,
      valorCobrado: infoCobro.valorTotal
    })

    // Generar consecutivo de comprobante (HU-20)
    let consecutivo = null
    try {
      const resComp = await comprobanteService.crearComprobante({
        origen: 'registro',
        origenId: infoCobro.registro.id,
        clienteNombre: 'Consumidor final'
      })
      if (resComp?.comprobante) {
        consecutivo = resComp.comprobante.consecutivo
      }
    } catch (e) {
      console.warn('Comprobante provisional:', e)
    }

    const metodoSel = metodosPagoDisponibles.value.find(m => m.id === infoCobro.metodoPagoId)

    modalExitoCobro.value = {
      placa: infoCobro.registro.placa,
      tipoVehiculo: infoCobro.registro.tipos_vehiculo?.nombre || 'Vehículo',
      entrada: infoCobro.registro.entrada_at,
      salida: new Date().toISOString(),
      minutos: infoCobro.minutos,
      valorTotal: infoCobro.valorTotal,
      vuelto: (infoCobro.pagaCon || 0) > infoCobro.valorTotal ? (infoCobro.pagaCon - infoCobro.valorTotal) : 0,
      metodoPago: metodoSel?.nombre || 'Efectivo',
      consecutivo
    }

    mensajeExito.value = `Salida cobrada exitosamente: ${infoCobro.registro.placa} ($${infoCobro.valorTotal.toLocaleString()})`
    modalCobro.value = null
    await cargarDatos()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al cobrar salida'
  } finally {
    guardandoSalida.value = false
  }
}

function descargarComprobanteSalida() {
  if (!modalExitoCobro.value) return
  const info = modalExitoCobro.value

  const detalle = {
    tipo: 'hora',
    placa: info.placa,
    tipoVehiculo: info.tipoVehiculo,
    entrada: formatearHora(info.entrada),
    salida: formatearHora(info.salida),
    minutos: info.minutos,
    metodoPago: info.metodoPago,
    cajero: authStore.userProfile?.nombre_completo || 'Cajero'
  }

  comprobanteService.descargarPDF({
    parqueadero: authStore.parqueadero,
    comprobante: {
      consecutivo: info.consecutivo,
      cliente_nombre: 'Consumidor final',
      valor: info.valorTotal
    },
    detalle,
    esCopia: false
  })
}

async function abrirModalAnular(v) {
  const motivo = prompt(`Anular registro de placa ${v.placa}.\nEscribe el motivo (mínimo 10 caracteres):`)
  if (!motivo) return
  if (motivo.trim().length < 10) return alert('El motivo debe tener al menos 10 caracteres')

  try {
    await ocupacionService.anularRegistro(v.id, motivo)
    mensajeExito.value = `Registro de ${v.placa} anulado correctamente`
    await cargarDatos()
  } catch (err) {
    errorMensaje.value = err.message || 'Error al anular registro'
  }
}

onMounted(() => {
  cargarDatos()
})
</script>

<style scoped>
.input-field {
  @apply w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary transition-colors;
}
</style>
