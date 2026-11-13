<template>
  <div class="space-y-6 max-w-3xl">
    <div class="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
      <div>
        <h2 class="titulo-pagina">Caja y turnos</h2>
        <p class="subtitulo-pagina">Base, cobros del turno, retiros y entrega de caja.</p>
      </div>
      <router-link v-if="authStore.isAdmin" to="/caja/turnos" class="btn-craft-subtle text-sm px-4 py-2 rounded-lg">
        Historial de turnos
      </router-link>
    </div>

    <div v-if="mensajeExito" class="alerta-exito">{{ mensajeExito }}</div>
    <div v-if="errorMensaje" class="alerta-error" role="alert">{{ errorMensaje }}</div>
    <div v-if="!conexion.isOnline" class="alerta-aviso">
      Sin conexión: abrir, entregar, recibir y registrar movimientos de caja requieren internet. Se muestra la última copia guardada.
    </div>

    <div v-if="cargando" class="vacio py-20">
      <div class="spinner"></div>
      <span class="text-xs">Consultando estado de caja…</span>
    </div>

    <template v-else>
      <!-- SIN TURNO: ABRIR CON BASE -->
      <div v-if="!turno" class="card-craft p-6 sm:p-8 text-center space-y-4">
        <div class="w-12 h-12 bg-warning-bg text-warning border border-warning-border rounded-full mx-auto flex items-center justify-center">
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="1.8" aria-hidden="true">
            <path stroke-linecap="round" stroke-linejoin="round" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" />
          </svg>
        </div>
        <div class="space-y-1">
          <h3 class="text-lg font-semibold text-text-primary">No hay un turno de caja abierto</h3>
          <p class="text-sm text-text-secondary max-w-md mx-auto">
            Sin turno abierto no se pueden cobrar salidas ni pagos de mensualidad. Indica el efectivo con el que inicias (si no hay base, déjalo vacío).
          </p>
        </div>
        <form class="max-w-xs mx-auto space-y-3 pt-2 text-left" @submit.prevent="abrirTurno">
          <div>
            <label class="etiqueta" for="caja-base">Base inicial en efectivo ($)</label>
            <input id="caja-base" v-model="formAbrir.base" type="number" min="0" step="1" inputmode="numeric" placeholder="0" class="campo text-center font-semibold text-lg num-tabular" />
          </div>
          <button type="submit" class="btn-craft-primary w-full text-sm px-4 py-2.5 rounded-lg" :disabled="procesando || !conexion.isOnline">
            Abrir turno
          </button>
          <p v-if="!conexion.isOnline" class="text-2xs text-text-muted text-center">Requiere conexión.</p>
        </form>
      </div>

      <!-- TURNO ABIERTO -->
      <div v-else-if="turno.estado === 'abierto'" class="space-y-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div class="card-craft pastel-card-mint p-5 space-y-1">
            <span class="rotulo">Efectivo esperado en caja</span>
            <p class="text-3xl sm:text-4xl font-semibold tracking-tight text-success num-tabular">{{ pesos(turno.efectivo_esperado) }}</p>
            <p class="text-xs text-text-secondary">Base inicial: <strong class="font-semibold text-text-primary num-tabular">{{ pesos(turno.base_inicial) }}</strong></p>
            <p class="text-2xs text-text-muted">Base + cobros y pagos en efectivo + ingresos manuales − retiros</p>
          </div>
          <div class="card-craft p-5 space-y-2.5 text-sm text-text-secondary">
            <div class="flex justify-between gap-2"><span>Responsable</span><strong class="font-semibold text-text-primary truncate">{{ nombreResponsable }}</strong></div>
            <div class="flex justify-between gap-2"><span>Abierto</span><strong class="font-semibold text-text-primary">{{ fh(turno.abierto_at) }}</strong></div>
            <div class="flex justify-between gap-2"><span>Entradas del turno</span><strong class="font-semibold text-text-primary num-tabular">{{ resumen?.entradas ?? '—' }}</strong></div>
            <div class="flex justify-between gap-2"><span>Salidas cobradas</span><strong class="font-semibold text-text-primary num-tabular">{{ resumen?.salidas ?? '—' }}</strong></div>
            <div class="flex justify-between gap-2"><span>Vehículos dentro</span><strong class="font-semibold text-text-primary num-tabular">{{ totalDentro }}</strong></div>
          </div>
        </div>

        <!-- Cobros por método -->
        <div v-if="resumen" class="card-craft p-5 space-y-4">
          <h3 class="titulo-seccion">Cobros del turno por método de pago</h3>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-5 text-sm">
            <div>
              <p class="rotulo mb-2">Parqueo por hora</p>
              <ul class="space-y-1.5">
                <li v-for="c in resumen.cobros_hora" :key="'h' + c.metodo" class="flex justify-between gap-2">
                  <span class="text-text-secondary">{{ c.metodo }} <span class="text-text-muted">({{ c.cantidad }})</span> <span v-if="c.es_efectivo" class="badge-pastel-mint px-1.5 py-px rounded-full text-2xs">efectivo</span></span>
                  <strong class="font-semibold num-tabular">{{ pesos(c.total) }}</strong>
                </li>
                <li v-if="!resumen.cobros_hora.length" class="text-text-muted text-xs">Sin cobros todavía.</li>
              </ul>
            </div>
            <div>
              <p class="rotulo mb-2">Mensualidades</p>
              <ul class="space-y-1.5">
                <li v-for="c in resumen.pagos_mensualidad" :key="'m' + c.metodo" class="flex justify-between gap-2">
                  <span class="text-text-secondary">{{ c.metodo }} <span class="text-text-muted">({{ c.cantidad }})</span> <span v-if="c.es_efectivo" class="badge-pastel-mint px-1.5 py-px rounded-full text-2xs">efectivo</span></span>
                  <strong class="font-semibold num-tabular">{{ pesos(c.total) }}</strong>
                </li>
                <li v-if="!resumen.pagos_mensualidad.length" class="text-text-muted text-xs">Sin pagos todavía.</li>
              </ul>
            </div>
          </div>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-x-5 gap-y-2 text-sm border-t border-border pt-3">
            <div class="flex justify-between"><span class="text-text-secondary">Total en efectivo</span><strong class="font-semibold num-tabular">{{ pesos(totalesMetodo.efectivo) }}</strong></div>
            <div class="flex justify-between"><span class="text-text-secondary">Otros métodos</span><strong class="font-semibold num-tabular">{{ pesos(totalesMetodo.otros) }}</strong></div>
          </div>
        </div>

        <!-- Movimientos -->
        <div class="card-craft p-5 space-y-3">
          <h3 class="titulo-seccion">Retiros e ingresos manuales</h3>
          <ul v-if="resumen?.movimientos?.length" class="divide-y divide-border-subtle text-sm">
            <li v-for="m in resumen.movimientos" :key="m.id" class="flex justify-between gap-2 py-2">
              <span class="truncate">
                <span :class="m.tipo === 'retiro' ? 'badge-pastel-rose' : 'badge-pastel-mint'" class="px-1.5 py-px rounded-full text-2xs mr-1">{{ m.tipo === 'retiro' ? 'Retiro' : 'Ingreso' }}</span>
                {{ m.motivo }} <span class="text-text-muted text-xs">· {{ m.usuario }} · {{ fh(m.created_at) }}</span>
              </span>
              <strong class="font-semibold num-tabular shrink-0" :class="m.tipo === 'retiro' ? 'text-danger' : 'text-success'">{{ m.tipo === 'retiro' ? '−' : '+' }}{{ pesos(m.valor) }}</strong>
            </li>
          </ul>
          <p v-else class="text-xs text-text-muted">Sin movimientos en este turno.</p>

          <form class="grid grid-cols-1 sm:grid-cols-4 gap-2 pt-3 border-t border-border" @submit.prevent="registrarMovimiento">
            <select v-model="formMov.tipo" class="campo" aria-label="Tipo de movimiento">
              <option value="retiro">Retiro</option>
              <option value="ingreso_manual">Ingreso manual</option>
            </select>
            <input v-model="formMov.valor" type="number" min="1" step="1" inputmode="numeric" placeholder="Valor" class="campo num-tabular" aria-label="Valor" />
            <input v-model="formMov.motivo" type="text" placeholder="Motivo (obligatorio)" class="campo" aria-label="Motivo" />
            <button type="submit" class="btn-craft-subtle text-sm px-4 py-2 rounded-lg" :disabled="procesando || !conexion.isOnline || !formMov.motivo.trim() || !(parseInt(formMov.valor) > 0)">
              Registrar
            </button>
          </form>
        </div>

        <!-- Entregar turno -->
        <div class="card-craft p-5 space-y-3">
          <div>
            <h3 class="titulo-seccion">Entregar turno</h3>
            <p class="text-xs text-text-muted mt-0.5">Cuenta el efectivo físico. Quien te releva lo recibirá en este dispositivo.</p>
          </div>
          <VehiculosDentro :lista="resumen?.vehiculos_dentro" />
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <input v-model="formEntrega.contado" type="number" min="0" step="1" inputmode="numeric" placeholder="Efectivo contado" class="campo num-tabular" aria-label="Efectivo contado" />
            <input v-model="formEntrega.observacion" type="text" placeholder="Observación (opcional)" class="campo" aria-label="Observación" />
          </div>
          <p v-if="formEntrega.contado !== ''" class="text-sm font-semibold" :class="claseDiferencia(diferenciaEntrega)">
            {{ textoDiferencia(diferenciaEntrega) }} (esperado {{ pesos(turno.efectivo_esperado) }})
          </p>
          <div class="flex flex-col sm:flex-row gap-2 pt-1">
            <button class="btn-craft-primary text-sm px-4 py-2 rounded-lg" :disabled="procesando || !conexion.isOnline || formEntrega.contado === ''" @click="entregarTurno">
              Confirmar entrega
            </button>
            <button class="btn-craft-subtle text-sm px-4 py-2 rounded-lg" :disabled="procesando || !conexion.isOnline || formEntrega.contado === ''" @click="pedirCierreSinRelevo">
              Cerrar sin relevo
            </button>
          </div>
        </div>
      </div>

      <!-- TURNO POR RECIBIR -->
      <div v-else-if="turno.estado === 'por_recibir'" class="space-y-4">
        <div class="card-craft pastel-card-amber p-5 space-y-2.5 text-sm">
          <h3 class="titulo-seccion">Turno pendiente por recibir</h3>
          <div class="flex justify-between gap-2"><span class="text-text-secondary">Entregado por</span><strong class="font-semibold">{{ nombreResponsable }}</strong></div>
          <div class="flex justify-between gap-2"><span class="text-text-secondary">Entregado</span><strong class="font-semibold">{{ fh(turno.cerrado_at) }}</strong></div>
          <div class="flex justify-between gap-2"><span class="text-text-secondary">Efectivo esperado</span><strong class="font-semibold num-tabular">{{ pesos(turno.efectivo_esperado) }}</strong></div>
          <div class="flex justify-between gap-2"><span class="text-text-secondary">Efectivo contado por quien entrega</span><strong class="font-semibold num-tabular">{{ pesos(turno.efectivo_contado) }}</strong></div>
          <div class="flex justify-between gap-2"><span class="text-text-secondary">Diferencia al entregar</span><strong class="font-semibold" :class="claseDiferencia(turno.diferencia)">{{ textoDiferencia(turno.diferencia) }}</strong></div>
          <p v-if="turno.observacion" class="text-text-secondary text-xs pt-1">Observación: {{ turno.observacion }}</p>
        </div>

        <div class="card-craft p-5 space-y-3">
          <div>
            <h3 class="titulo-seccion">Recibir turno</h3>
            <p class="text-xs text-text-muted mt-0.5">Cuenta el efectivo y confirma los vehículos que recibes. Se abrirá tu turno con el efectivo recibido como base.</p>
          </div>
          <VehiculosDentro :lista="resumen?.vehiculos_dentro" />
          <input v-model="formRecibir.recibido" type="number" min="0" step="1" inputmode="numeric" placeholder="Efectivo recibido" class="campo num-tabular" aria-label="Efectivo recibido" />
          <p v-if="formRecibir.recibido !== ''" class="text-sm font-semibold" :class="claseDiferencia(diferenciaRecepcion)">
            Frente a lo contado al entregar: {{ textoDiferencia(diferenciaRecepcion) }}
          </p>
          <label class="flex items-center gap-2 text-sm text-text-secondary cursor-pointer select-none">
            <input v-model="formRecibir.vehiculosOk" type="checkbox" class="rounded" />
            Confirmo que recibo {{ totalDentro }} vehículo(s) dentro
          </label>
          <div class="flex flex-col sm:flex-row gap-2 pt-1">
            <button class="btn-craft-primary text-sm px-4 py-2 rounded-lg" :disabled="procesando || !conexion.isOnline || formRecibir.recibido === '' || !formRecibir.vehiculosOk" @click="recibirTurno">
              Recibir y abrir mi turno
            </button>
            <button class="btn-craft-subtle text-sm px-4 py-2 rounded-lg" :disabled="procesando || !conexion.isOnline" @click="pedirCierreSinRelevo">
              Cerrar sin relevo
            </button>
          </div>
          <p v-if="ultimaRecepcion !== null" class="text-sm font-semibold" :class="claseDiferencia(ultimaRecepcion)">
            Diferencia registrada en la recepción: {{ textoDiferencia(ultimaRecepcion) }}
          </p>
        </div>
      </div>
    </template>

    <!-- Confirmación de cierre sin relevo -->
    <div v-if="confirmarCierre" class="modal-fondo" @click.self="confirmarCierre = false">
      <div class="modal-panel max-w-md" role="dialog" aria-modal="true">
        <div class="modal-encabezado">
          <h3 class="modal-titulo">¿Cerrar el turno sin relevo?</h3>
          <button type="button" class="btn-icono" aria-label="Cerrar" @click="confirmarCierre = false">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <p class="text-sm text-text-secondary">El turno quedará cerrado y el siguiente deberá abrirse indicando una base. Úsalo cuando el parqueadero cierra o nadie recibe la caja.</p>
        <input v-if="turno?.estado === 'por_recibir'" v-model="formCierre.contado" type="number" min="0" step="1" placeholder="Efectivo contado (opcional, se usa el de la entrega)" class="campo num-tabular" aria-label="Efectivo contado" />
        <input v-model="formCierre.observacion" type="text" placeholder="Observación" class="campo" aria-label="Observación" />
        <div class="flex gap-2 justify-end pt-1">
          <button class="btn-craft-subtle text-sm px-4 py-2 rounded-lg" @click="confirmarCierre = false">Cancelar</button>
          <button class="btn-craft-primary text-sm px-4 py-2 rounded-lg" :disabled="procesando" @click="cerrarSinRelevo">Cerrar turno</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onActivated, onBeforeUnmount, h } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { cajaService } from '@/modules/caja/services/cajaService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { formatearFechaHora } from '@/utils/fecha'

const authStore = useAuthStore()
const conexion = useConexionStore()

const claseInput = 'campo'

const VehiculosDentro = (props) => {
  const lista = props.lista || []
  if (!lista.length) return h('p', { class: 'text-xs text-text-muted' }, 'No quedan vehículos dentro.')
  return h('div', { class: 'flex flex-wrap gap-2' }, lista.map(v =>
    h('span', { class: 'badge-pastel-blue px-2 py-0.5 rounded-full text-2xs font-semibold' }, `${v.tipo}: ${v.cantidad}`)))
}
VehiculosDentro.props = ['lista']

const cargando = ref(true)
const procesando = ref(false)
const turno = ref(null)
const resumen = ref(null)
const errorMensaje = ref('')
const mensajeExito = ref('')
const confirmarCierre = ref(false)
const ultimaRecepcion = ref(null)

const formAbrir = ref({ base: '' })
const formMov = ref({ tipo: 'retiro', valor: '', motivo: '' })
const formEntrega = ref({ contado: '', observacion: '' })
const formRecibir = ref({ recibido: '', vehiculosOk: false })
const formCierre = ref({ contado: '', observacion: '' })

let cancelarSuscripcion = null

function pesos(v) {
  return `$${Number(v || 0).toLocaleString('es-CO')}`
}
function fh(v) {
  return v ? formatearFechaHora(v, authStore.zonaHoraria) : '—'
}
function textoDiferencia(d) {
  const n = Number(d || 0)
  if (n === 0) return 'Cuadra exacto'
  return n > 0 ? `Sobrante ${pesos(n)}` : `Faltante ${pesos(-n)}`
}
function claseDiferencia(d) {
  const n = Number(d || 0)
  return n === 0 ? 'text-success' : n > 0 ? 'text-warning' : 'text-danger'
}

const nombreResponsable = computed(() => turno.value?.profiles?.nombre || resumen.value?.turno?.usuario_nombre || '—')
const totalDentro = computed(() => (resumen.value?.vehiculos_dentro || []).reduce((s, v) => s + v.cantidad, 0))
const diferenciaEntrega = computed(() => parseInt(formEntrega.value.contado || 0, 10) - (turno.value?.efectivo_esperado || 0))
const diferenciaRecepcion = computed(() => parseInt(formRecibir.value.recibido || 0, 10) - (turno.value?.efectivo_contado || 0))
const totalesMetodo = computed(() => {
  const todos = [...(resumen.value?.cobros_hora || []), ...(resumen.value?.pagos_mensualidad || [])]
  return {
    efectivo: todos.filter(c => c.es_efectivo).reduce((s, c) => s + Number(c.total), 0),
    otros: todos.filter(c => !c.es_efectivo).reduce((s, c) => s + Number(c.total), 0)
  }
})

function avisar(texto) {
  mensajeExito.value = texto
  errorMensaje.value = ''
  setTimeout(() => { if (mensajeExito.value === texto) mensajeExito.value = '' }, 4000)
}

async function cargar({ silencioso = false } = {}) {
  const pq = authStore.parqueaderoId
  if (!pq) return
  const cache = cajaService.obtenerTurnoCache()
  if (cache !== undefined) {
    turno.value = cache
    cargando.value = false
  } else if (!silencioso) {
    cargando.value = true
  }
  try {
    turno.value = await cajaService.obtenerTurnoActual(pq)
    resumen.value = turno.value && conexion.isOnline ? await cajaService.obtenerResumen(turno.value.id) : null
    if (resumen.value?.turno) turno.value = { ...turno.value, ...resumen.value.turno, profiles: turno.value.profiles }
  } catch (e) {
    errorMensaje.value = mensajeDeError(e, 'No se pudo consultar la caja')
  } finally {
    cargando.value = false
  }
}

async function ejecutar(fn, exito) {
  procesando.value = true
  errorMensaje.value = ''
  try {
    const r = await fn()
    avisar(exito)
    await cargar({ silencioso: true })
    return r
  } catch (e) {
    errorMensaje.value = mensajeDeError(e)
    return null
  } finally {
    procesando.value = false
  }
}

async function abrirTurno() {
  const base = formAbrir.value.base === '' ? 0 : parseInt(formAbrir.value.base, 10)
  if (Number.isNaN(base) || base < 0) {
    errorMensaje.value = 'La base debe ser 0 o mayor'
    return
  }
  const r = await ejecutar(() => cajaService.abrirTurno(base), 'Turno abierto')
  if (r) formAbrir.value.base = ''
}

async function registrarMovimiento() {
  const r = await ejecutar(
    () => cajaService.registrarMovimiento(turno.value.id, formMov.value.tipo, formMov.value.valor, formMov.value.motivo),
    formMov.value.tipo === 'retiro' ? 'Retiro registrado' : 'Ingreso registrado'
  )
  if (r) formMov.value = { tipo: formMov.value.tipo, valor: '', motivo: '' }
}

async function entregarTurno() {
  const r = await ejecutar(
    () => cajaService.entregarTurno(turno.value.id, formEntrega.value.contado, formEntrega.value.observacion),
    'Turno entregado. Quien te releva debe recibirlo.'
  )
  if (r) formEntrega.value = { contado: '', observacion: '' }
}

async function recibirTurno() {
  const r = await ejecutar(
    () => cajaService.recibirTurno(turno.value.id, formRecibir.value.recibido),
    'Turno recibido. Tu turno quedó abierto.'
  )
  if (r) {
    ultimaRecepcion.value = r.diferencia_recepcion ?? null
    formRecibir.value = { recibido: '', vehiculosOk: false }
  }
}

function pedirCierreSinRelevo() {
  formCierre.value = { contado: turno.value?.estado === 'abierto' ? formEntrega.value.contado : '', observacion: formEntrega.value.observacion || '' }
  confirmarCierre.value = true
}

async function cerrarSinRelevo() {
  const contado = formCierre.value.contado === '' ? null : formCierre.value.contado
  const r = await ejecutar(
    () => cajaService.cerrarSinRelevo(turno.value.id, contado, formCierre.value.observacion),
    'Turno cerrado sin relevo'
  )
  if (r) {
    confirmarCierre.value = false
    formEntrega.value = { contado: '', observacion: '' }
  }
}

onMounted(() => {
  cargar()
  cancelarSuscripcion = cajaService.suscribirCambios(authStore.parqueaderoId, () => cargar({ silencioso: true }))
})
// Con <keep-alive> onActivated también corre tras el primer montaje: se omite esa vez
let primeraActivacion = true
onActivated(() => {
  if (primeraActivacion) { primeraActivacion = false; return }
  cargar({ silencioso: true })
})
onBeforeUnmount(() => cancelarSuscripcion?.())
</script>
