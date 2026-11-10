<template>
  <div class="space-y-6">
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-2">
      <div>
        <h2 class="text-xl md:text-2xl font-bold">Ajustes del Parqueadero</h2>
        <p class="text-sm text-text-secondary">Configuración de datos, tipos de vehículo, tarifas y cobros.</p>
      </div>

      <div v-if="mensajeExito" class="px-3 py-1.5 rounded-lg bg-success-bg text-success text-xs font-semibold border border-success/20">
        {{ mensajeExito }}
      </div>
      <div v-if="errorMensaje" class="px-3 py-1.5 rounded-lg bg-danger-bg text-danger text-xs font-semibold border border-danger/20">
        {{ errorMensaje }}
      </div>
    </div>

    <!-- Pestañas de Ajustes -->
    <div class="flex border-b border-border overflow-x-auto space-x-2 pb-px text-sm">
      <button 
        v-for="tab in tabs" 
        :key="tab.id"
        @click="tabActiva = tab.id"
        class="px-4 py-2 font-medium border-b-2 whitespace-nowrap transition-colors"
        :class="tabActiva === tab.id ? 'border-primary text-primary font-bold' : 'border-transparent text-text-secondary hover:text-text-primary'"
      >
        {{ tab.label }}
      </button>
    </div>

    <!-- 1. PESTAÑA NEGOCIO & TICKET (HU-06, HU-27) -->
    <div v-if="tabActiva === 'negocio'" class="bg-surface rounded-xl border border-border p-5 space-y-4 max-w-2xl">
      <h3 class="font-bold text-base">Datos Generales</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Nombre del Parqueadero *</label>
          <input v-model="negocioForm.nombre" type="text" class="input-field" />
        </div>
        <div>
          <label class="block text-xs font-semibold mb-1 text-text-secondary">NIT *</label>
          <input v-model="negocioForm.nit" type="text" class="input-field" />
        </div>
        <div>
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Dirección</label>
          <input v-model="negocioForm.direccion" type="text" class="input-field" />
        </div>
        <div>
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Teléfono</label>
          <input v-model="negocioForm.telefono" type="text" class="input-field" />
        </div>
      </div>

      <h3 class="font-bold text-base pt-2 border-t border-border">Ticket y Operación</h3>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
        <div>
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Modo de Ticket (HU-27)</label>
          <select v-model="negocioForm.modo_ticket" class="input-field">
            <option value="qr">QR en Pantalla (Recomendado sin impresora)</option>
            <option value="termica">Impresora Térmica</option>
            <option value="ninguno">Sin Ticket</option>
          </select>
        </div>
        <div v-if="negocioForm.modo_ticket === 'termica'">
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Ancho de papel</label>
          <select v-model="negocioForm.ancho_ticket_mm" class="input-field">
            <option :value="80">80 mm</option>
            <option :value="58">58 mm</option>
          </select>
        </div>
        <div class="sm:col-span-2">
          <label class="block text-xs font-semibold mb-1 text-text-secondary">Pie de comprobante / ticket</label>
          <textarea v-model="negocioForm.texto_pie_comprobante" rows="2" class="input-field" placeholder="Gracias por su visita. No nos hacemos responsables por objetos de valor..."></textarea>
        </div>
      </div>

      <div class="pt-2">
        <button @click="guardarNegocio" :disabled="guardando" class="btn-primary">
          {{ guardando ? 'Guardando...' : 'Guardar Datos del Negocio' }}
        </button>
      </div>
    </div>

    <!-- 2. PESTAÑA TIPOS DE VEHÍCULO (HU-07) -->
    <div v-if="tabActiva === 'vehiculos'" class="space-y-4">
      <div class="flex justify-between items-center">
        <h3 class="font-bold text-base">Tipos de Vehículo y Capacidad</h3>
        <button @click="abrirModalTipo(null)" class="btn-primary text-xs">+ Agregar Tipo</button>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        <div v-for="tipo in tiposVehiculo" :key="tipo.id" class="bg-surface p-4 rounded-xl border border-border space-y-2">
          <div class="flex justify-between items-start">
            <span class="font-bold text-lg text-text-primary">{{ tipo.nombre }}</span>
            <span class="text-xs px-2 py-0.5 rounded-full" :class="tipo.activo ? 'bg-success-bg text-success' : 'bg-surface-elevated text-text-muted'">
              {{ tipo.activo ? 'Activo' : 'Inactivo' }}
            </span>
          </div>
          <p class="text-xs text-text-secondary">Capacidad: <strong class="text-text-primary">{{ tipo.capacidad }} cupos</strong></p>
          <div class="pt-2 flex justify-end space-x-2">
            <button @click="abrirModalTipo(tipo)" class="btn-secondary text-xs">Editar</button>
          </div>
        </div>
      </div>
    </div>

    <!-- 3. PESTAÑA TARIFAS Y SIMULADOR (HU-08) -->
    <div v-if="tabActiva === 'tarifas'" class="space-y-6">
      <div class="flex justify-between items-center">
        <div>
          <h3 class="font-bold text-base">Tarifas por Tipo de Vehículo</h3>
          <p class="text-xs text-text-muted">Configura tarifas por hora, minuto, fracción, plena y franja nocturna.</p>
        </div>
        <button @click="abrirModalTarifa(null)" class="btn-primary text-xs">+ Nueva Tarifa</button>
      </div>

      <!-- Tabla de tarifas -->
      <div class="bg-surface rounded-xl border border-border overflow-x-auto">
        <table class="w-full text-left text-sm">
          <thead class="bg-surface-elevated text-xs text-text-secondary uppercase border-b border-border">
            <tr>
              <th class="px-4 py-3">Tipo</th>
              <th class="px-4 py-3">Nombre</th>
              <th class="px-4 py-3">Modalidad</th>
              <th class="px-4 py-3">Valor</th>
              <th class="px-4 py-3">Franja Nocturna</th>
              <th class="px-4 py-3">Predeterminada</th>
              <th class="px-4 py-3 text-right">Acción</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border">
            <tr v-for="t in tarifas" :key="t.id" class="hover:bg-surface-elevated/40">
              <td class="px-4 py-3 font-semibold">{{ t.tipos_vehiculo?.nombre || '—' }}</td>
              <td class="px-4 py-3">{{ t.nombre }}</td>
              <td class="px-4 py-3 text-xs uppercase">{{ t.modalidad.replace('_', ' ') }}</td>
              <td class="px-4 py-3 font-bold">${{ t.valor.toLocaleString() }}</td>
              <td class="px-4 py-3 text-xs">
                <span v-if="t.franja_inicio && t.franja_fin" class="text-warning font-semibold">
                  {{ t.franja_inicio }} a {{ t.franja_fin }}
                </span>
                <span v-else class="text-text-muted">No</span>
              </td>
              <td class="px-4 py-3 text-xs">
                <span v-if="t.es_predeterminada" class="px-2 py-0.5 bg-primary/10 text-primary font-bold rounded-full">Sí</span>
                <span v-else class="text-text-muted">No</span>
              </td>
              <td class="px-4 py-3 text-right">
                <button @click="abrirModalTarifa(t)" class="btn-secondary text-xs">Editar</button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- SIMULADOR EN VIVO DE COBRO (HU-08) -->
      <div class="bg-surface rounded-xl border border-primary/30 p-5 space-y-4">
        <div class="flex items-center space-x-2">
          <span class="w-2.5 h-2.5 rounded-full bg-primary"></span>
          <h4 class="font-bold text-sm text-primary uppercase tracking-wider">Simulador de Cobro en Vivo</h4>
        </div>
        <p class="text-xs text-text-secondary">Prueba cómo se calcula una estancia con las tarifas actuales antes de aplicarla.</p>

        <div class="grid grid-cols-1 sm:grid-cols-4 gap-3">
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Fecha/Hora Entrada</label>
            <input v-model="simuladorTarifa.entrada" type="datetime-local" class="input-field text-xs" />
          </div>
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Fecha/Hora Salida</label>
            <input v-model="simuladorTarifa.salida" type="datetime-local" class="input-field text-xs" />
          </div>
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Tarifa General</label>
            <select v-model="simuladorTarifa.tarifaGeneralId" class="input-field text-xs">
              <option v-for="t in tarifas" :key="t.id" :value="t.id">{{ t.tipos_vehiculo?.nombre }} - {{ t.nombre }} (${{ t.valor }})</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Tarifa Nocturna (Opcional)</label>
            <select v-model="simuladorTarifa.tarifaNocturnaId" class="input-field text-xs">
              <option :value="null">Ninguna</option>
              <option v-for="t in tarifas.filter(x => x.franja_inicio)" :key="t.id" :value="t.id">{{ t.nombre }} ({{ t.franja_inicio }}-{{ t.franja_fin }})</option>
            </select>
          </div>
        </div>

        <button @click="ejecutarSimulacionCobro" class="btn-primary text-xs">Calcular Simulación</button>

        <!-- Resultado del simulador -->
        <div v-if="resultadoSimulacionCobro" class="p-4 rounded-lg bg-surface-elevated border border-border text-xs space-y-2">
          <div class="flex justify-between items-center text-sm font-bold">
            <span>Total Cobro Calculado:</span>
            <span class="text-primary text-base">${{ resultadoSimulacionCobro.valorTotal.toLocaleString() }} ({{ resultadoSimulacionCobro.minutosTotal }} min)</span>
          </div>
          <div v-if="resultadoSimulacionCobro.desglose?.length" class="space-y-1 pt-2 border-t border-border">
            <span class="font-semibold text-text-muted uppercase text-[10px]">Desglose de tramos:</span>
            <div v-for="(tr, idx) in resultadoSimulacionCobro.desglose" :key="idx" class="flex justify-between text-text-secondary">
              <span>Tramo {{ idx + 1 }} ({{ tr.tipo === 'nocturna' ? 'Nocturno' : 'General' }}): {{ tr.minutos }} min</span>
              <span class="font-bold text-text-primary">${{ tr.valor.toLocaleString() }}</span>
            </div>
          </div>
        </div>
      </div>
    </div>

    <!-- 4. PESTAÑA PLANES MENSUALES Y SIMULADOR (HU-09) -->
    <div v-if="tabActiva === 'planes'" class="space-y-6">
      <div class="flex justify-between items-center">
        <div>
          <h3 class="font-bold text-base">Planes de Mensualidad</h3>
          <p class="text-xs text-text-muted">Planes mensuales con fecha de corte dinámica o días fijos (quincenas, semanas).</p>
        </div>
        <button @click="abrirModalPlan(null)" class="btn-primary text-xs">+ Nuevo Plan</button>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div v-for="plan in planesMensuales" :key="plan.id" class="bg-surface p-4 rounded-xl border border-border space-y-2">
          <div class="flex justify-between items-start">
            <div>
              <span class="text-xs font-semibold text-text-muted uppercase">{{ plan.tipos_vehiculo?.nombre }}</span>
              <h4 class="font-bold text-base text-text-primary">{{ plan.nombre }}</h4>
            </div>
            <span class="font-bold text-primary text-lg">${{ plan.valor.toLocaleString() }}</span>
          </div>
          <p class="text-xs text-text-secondary">
            Tipo: <strong>{{ plan.tipo_periodo === 'mensual' ? 'Mensual (Día a día)' : `${plan.duracion_dias} días fijos` }}</strong>
          </p>
          <p class="text-xs text-text-secondary">Gracia de pago: {{ plan.dias_gracia_pago }} días</p>
          <div class="pt-2 flex justify-end">
            <button @click="abrirModalPlan(plan)" class="btn-secondary text-xs">Editar</button>
          </div>
        </div>
      </div>

      <!-- SIMULADOR EN VIVO DE PERIODOS (HU-09) -->
      <div class="bg-surface rounded-xl border border-primary/30 p-5 space-y-4">
        <div class="flex items-center space-x-2">
          <span class="w-2.5 h-2.5 rounded-full bg-primary"></span>
          <h4 class="font-bold text-sm text-primary uppercase tracking-wider">Simulador de Periodos y Vencimientos</h4>
        </div>
        <p class="text-xs text-text-secondary">Verifica cómo se calculan los próximos 3 periodos para un cliente que ingrese en una fecha dada.</p>

        <div class="grid grid-cols-1 sm:grid-cols-3 gap-3">
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Plan Seleccionado</label>
            <select v-model="simuladorPeriodo.planId" class="input-field text-xs">
              <option v-for="p in planesMensuales" :key="p.id" :value="p.id">{{ p.nombre }} ({{ p.tipo_periodo }})</option>
            </select>
          </div>
          <div>
            <label class="block text-xs font-semibold mb-1 text-text-secondary">Fecha de Inicio del Cliente</label>
            <input v-model="simuladorPeriodo.fechaInicio" type="date" class="input-field text-xs" />
          </div>
          <div class="flex items-end">
            <button @click="ejecutarSimulacionPeriodos" class="btn-primary text-xs w-full">Calcular Próximos Periodos</button>
          </div>
        </div>

        <div v-if="resultadoSimulacionPeriodos?.length" class="grid grid-cols-1 sm:grid-cols-3 gap-3 pt-2">
          <div v-for="(p, i) in resultadoSimulacionPeriodos" :key="i" class="p-3 bg-surface-elevated border border-border rounded-lg text-xs space-y-1">
            <span class="font-bold text-primary">Periodo {{ i + 1 }}</span>
            <p class="text-text-primary font-semibold">{{ p.desde }} al {{ p.hasta }}</p>
          </div>
        </div>
      </div>
    </div>

    <!-- 5. PESTAÑA MÉTODOS DE PAGO (HU-06) -->
    <div v-if="tabActiva === 'pagos'" class="space-y-4 max-w-2xl">
      <div class="flex justify-between items-center">
        <div>
          <h3 class="font-bold text-base">Métodos de Pago Aceptados</h3>
          <p class="text-xs text-text-muted">Define qué métodos suman al efectivo esperado del turno en caja.</p>
        </div>
        <button @click="abrirModalPago(null)" class="btn-primary text-xs">+ Nuevo Método</button>
      </div>

      <div class="bg-surface rounded-xl border border-border divide-y divide-border overflow-hidden">
        <div v-for="m in metodosPago" :key="m.id" class="p-3.5 flex items-center justify-between text-sm">
          <div>
            <span class="font-bold text-text-primary">{{ m.nombre }}</span>
            <span v-if="m.es_efectivo" class="ml-2 text-[10px] font-bold px-2 py-0.5 rounded-full bg-success-bg text-success uppercase">
              Efectivo
            </span>
          </div>
          <div class="flex items-center space-x-2">
            <span class="text-xs text-text-muted">Orden: {{ m.orden }}</span>
            <button @click="abrirModalPago(m)" class="btn-secondary text-xs">Editar</button>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { ajustesService } from '@/modules/ajustes/services/ajustesService'

const authStore = useAuthStore()

const tabs = [
  { id: 'negocio', label: 'Negocio y Ticket' },
  { id: 'vehiculos', label: 'Tipos de Vehículo' },
  { id: 'tarifas', label: 'Tarifas y Simulador' },
  { id: 'planes', label: 'Planes Mensuales' },
  { id: 'pagos', label: 'Métodos de Pago' }
]

const tabActiva = ref('negocio')
const guardando = ref(false)
const mensajeExito = ref('')
const errorMensaje = ref('')

const negocioForm = ref({
  nombre: '',
  nit: '',
  direccion: '',
  telefono: '',
  modo_ticket: 'qr',
  ancho_ticket_mm: 80,
  texto_pie_comprobante: ''
})

const tiposVehiculo = ref([])
const tarifas = ref([])
const planesMensuales = ref([])
const metodosPago = ref([])

// Simuladores
const simuladorTarifa = ref({
  entrada: new Date().toISOString().slice(0, 16),
  salida: new Date(Date.now() + 2 * 3600000).toISOString().slice(0, 16),
  tarifaGeneralId: null,
  tarifaNocturnaId: null
})
const resultadoSimulacionCobro = ref(null)

const simuladorPeriodo = ref({
  planId: null,
  fechaInicio: new Date().toISOString().slice(0, 10)
})
const resultadoSimulacionPeriodos = ref(null)

async function cargarTodo() {
  const pqId = authStore.parqueaderoId
  if (!pqId) return

  try {
    const [negocio, tipos, tar, planes, pagos] = await Promise.all([
      ajustesService.obtenerDatosNegocio(pqId),
      ajustesService.listarTiposVehiculo(pqId),
      ajustesService.listarTarifas(pqId),
      ajustesService.listarPlanesMensuales(pqId),
      ajustesService.listarMetodosPago(pqId)
    ])

    if (negocio) Object.assign(negocioForm.value, negocio)
    tiposVehiculo.value = tipos
    tarifas.value = tar
    planesMensuales.value = planes
    metodosPago.value = pagos

    if (tar.length) simuladorTarifa.value.tarifaGeneralId = tar[0].id
    if (planes.length) simuladorPeriodo.value.planId = planes[0].id
  } catch (err) {
    errorMensaje.value = err.message || 'Error al cargar ajustes'
  }
}

async function guardarNegocio() {
  guardando.value = true
  errorMensaje.value = ''
  mensajeExito.value = ''
  try {
    await ajustesService.guardarDatosNegocio(authStore.parqueaderoId, negocioForm.value)
    mensajeExito.value = 'Datos del negocio actualizados correctamente'
  } catch (err) {
    errorMensaje.value = err.message || 'No se pudo guardar la información'
  } finally {
    guardando.value = false
  }
}

function ejecutarSimulacionCobro() {
  const general = tarifas.value.find(t => t.id === simuladorTarifa.value.tarifaGeneralId)
  if (!general) return alert('Selecciona una tarifa general')

  const nocturna = tarifas.value.find(t => t.id === simuladorTarifa.value.tarifaNocturnaId)

  resultadoSimulacionCobro.value = ajustesService.simularCobroTarifa({
    entradaAt: simuladorTarifa.value.entrada,
    salidaAt: simuladorTarifa.value.salida,
    tarifaGeneral: {
      modalidad: general.modalidad,
      valor: general.valor,
      minutosGracia: general.minutos_gracia || 0,
      minutosFraccion: general.minutos_fraccion || 15,
      tope24h: general.tope_por_24h
    },
    tarifaNocturna: nocturna ? {
      modalidad: nocturna.modalidad,
      valor: nocturna.valor,
      franjaInicio: nocturna.franja_inicio,
      franjaFin: nocturna.franja_fin
    } : null
  })
}

function ejecutarSimulacionPeriodos() {
  const plan = planesMensuales.value.find(p => p.id === simuladorPeriodo.value.planId)
  if (!plan) return alert('Selecciona un plan')

  resultadoSimulacionPeriodos.value = ajustesService.simularPeriodosPlan({
    tipoPeriodo: plan.tipo_periodo,
    duracionDias: plan.duracion_dias || 30,
    fechaInicio: simuladorPeriodo.value.fechaInicio,
    cantidad: 3
  })
}

function abrirModalTipo(tipo) {
  // En Sprint 2 podemos interactuar mediante prompts o modales simples
  const nombre = prompt('Nombre del Tipo de Vehículo:', tipo ? tipo.nombre : '')
  if (!nombre) return
  const capacidad = prompt('Capacidad de cupos:', tipo ? tipo.capacidad : '20')
  ajustesService.guardarTipoVehiculo(authStore.parqueaderoId, {
    id: tipo?.id,
    nombre,
    capacidad: parseInt(capacidad, 10) || 0
  }).then(cargarTodo)
}

function abrirModalTarifa(tarifa) {
  const nombre = prompt('Nombre de la Tarifa:', tarifa ? tarifa.nombre : 'Por Hora')
  if (!nombre) return
  const valor = prompt('Valor ($):', tarifa ? tarifa.valor : '3000')
  const modalidad = prompt('Modalidad (por_hora | por_minuto | por_fraccion | plena):', tarifa ? tarifa.modalidad : 'por_hora')
  
  if (!tiposVehiculo.value.length) return alert('Crea primero un tipo de vehículo')

  ajustesService.guardarTarifa(authStore.parqueaderoId, {
    id: tarifa?.id,
    tipo_vehiculo_id: tarifa?.tipo_vehiculo_id || tiposVehiculo.value[0].id,
    nombre,
    modalidad,
    valor: parseInt(valor, 10),
    es_predeterminada: true
  }).then(cargarTodo)
}

function abrirModalPlan(plan) {
  const nombre = prompt('Nombre del Plan:', plan ? plan.nombre : 'Mensual Carro')
  if (!nombre) return
  const valor = prompt('Valor ($):', plan ? plan.valor : '150000')
  const tipoPeriodo = prompt('Tipo periodo (mensual | dias_fijos):', plan ? plan.tipo_periodo : 'mensual')

  if (!tiposVehiculo.value.length) return alert('Crea primero un tipo de vehículo')

  ajustesService.guardarPlanMensual(authStore.parqueaderoId, {
    id: plan?.id,
    tipo_vehiculo_id: plan?.tipo_vehiculo_id || tiposVehiculo.value[0].id,
    nombre,
    valor: parseInt(valor, 10),
    tipo_periodo: tipoPeriodo
  }).then(cargarTodo)
}

function abrirModalPago(metodo) {
  const nombre = prompt('Nombre del Método de Pago:', metodo ? metodo.nombre : 'Efectivo')
  if (!nombre) return
  const esEfectivo = confirm('¿Es dinero en efectivo (suma al conteo de caja)?')

  ajustesService.guardarMetodoPago(authStore.parqueaderoId, {
    id: metodo?.id,
    nombre,
    es_efectivo: esEfectivo
  }).then(cargarTodo)
}

onMounted(() => {
  cargarTodo()
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
