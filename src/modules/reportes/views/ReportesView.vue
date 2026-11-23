<template>
  <div class="space-y-6 max-w-5xl">
    <div>
      <h2 class="titulo-pagina">Reportes de ingresos</h2>
      <p class="subtitulo-pagina">Fechas en la zona horaria del parqueadero ({{ authStore.zonaHoraria }}).</p>
    </div>

    <div v-if="!conexion.isOnline" class="alerta-aviso">Los reportes requieren conexión.</div>
    <div v-if="errorMensaje" class="alerta-error" role="alert">{{ errorMensaje }}</div>

    <div class="card-craft p-4 sm:p-5 space-y-4">
      <div class="flex flex-wrap gap-2">
        <button v-for="r in rangosRapidos" :key="r.id" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0" @click="aplicarRango(r.id)">{{ r.nombre }}</button>
      </div>
      <form class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 items-end" @submit.prevent="cargar">
        <label class="min-w-0"><span class="etiqueta">Desde</span><input v-model="desde" type="date" class="campo" /></label>
        <label class="min-w-0"><span class="etiqueta">Hasta</span><input v-model="hasta" type="date" class="campo" /></label>
        <button type="submit" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg" :disabled="cargando || !conexion.isOnline">Consultar</button>
        <div class="flex gap-2">
          <button type="button" class="btn-craft-subtle text-sm px-3 py-2.5 sm:py-2 rounded-lg flex-1" :disabled="!reporte || exportando" @click="exportarExcel">Excel</button>
          <button type="button" class="btn-craft-subtle text-sm px-3 py-2.5 sm:py-2 rounded-lg flex-1" :disabled="!reporte || exportando" @click="exportarCSV">CSV</button>
        </div>
      </form>
    </div>

    <div v-if="cargando" class="vacio py-16">
      <div class="spinner"></div>
      <span class="text-xs">Calculando reporte…</span>
    </div>

    <template v-else-if="reporte">
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <div class="card-craft p-5 border-l-4 border-l-primary min-w-0">
          <p class="rotulo">Total del rango</p>
          <p class="text-2xl lg:text-3xl font-semibold tracking-tight num-tabular mt-1 break-words">{{ pesos(reporte.gran_total) }}</p>
        </div>
        <div class="card-craft p-5 min-w-0">
          <p class="rotulo">Parqueo por hora</p>
          <p class="text-2xl font-semibold tracking-tight num-tabular mt-1 break-words">{{ pesos(reporte.total_hora) }}</p>
        </div>
        <div class="card-craft p-5 min-w-0">
          <p class="rotulo">Mensualidades</p>
          <p class="text-2xl font-semibold tracking-tight num-tabular mt-1 break-words">{{ pesos(reporte.total_mensualidades) }}</p>
        </div>
      </div>

      <div v-if="reporte.requieren_revision || reporte.conflictos_sync" class="alerta-aviso flex-col gap-1">
        <p v-if="reporte.requieren_revision">{{ reporte.requieren_revision }} cobro(s) hechos sin conexión difieren del cálculo del servidor y requieren revisión (ver hoja "Registros").</p>
        <p v-if="reporte.conflictos_sync">{{ reporte.conflictos_sync }} operación(es) de sincronización con conflicto o error (ver abajo).</p>
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <div class="card-craft overflow-hidden min-w-0">
          <h3 class="titulo-seccion px-5 pt-5 pb-3">Por día</h3>
          <div class="overflow-x-auto">
            <table class="tabla min-w-[24rem]">
              <thead><tr><th>Fecha</th><th class="text-right">Hora</th><th class="text-right">Mensual.</th><th class="text-right">Total</th></tr></thead>
              <tbody>
                <tr v-for="d in reporte.por_dia" :key="d.fecha">
                  <td class="text-text-secondary whitespace-nowrap">{{ formatearFechaCorta(d.fecha) }}</td>
                  <td class="text-right num-tabular whitespace-nowrap">{{ pesos(d.hora) }}</td>
                  <td class="text-right num-tabular whitespace-nowrap">{{ pesos(d.mensualidades) }}</td>
                  <td class="text-right num-tabular font-semibold whitespace-nowrap">{{ pesos(d.total) }}</td>
                </tr>
                <tr v-if="!reporte.por_dia.length"><td colspan="4" class="text-text-muted text-xs">Sin ingresos en el rango.</td></tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="card-craft overflow-hidden min-w-0">
          <h3 class="titulo-seccion px-5 pt-5 pb-3">Por método de pago</h3>
          <div class="overflow-x-auto">
            <table class="tabla min-w-[24rem]">
              <thead><tr><th>Método</th><th class="text-right">Hora</th><th class="text-right">Mensual.</th><th class="text-right">Total</th></tr></thead>
              <tbody>
                <tr v-for="m in reporte.por_metodo" :key="m.metodo">
                  <td>{{ m.metodo }} <span v-if="m.es_efectivo" class="badge-pastel-mint px-1.5 py-px rounded-full text-2xs">efectivo</span></td>
                  <td class="text-right num-tabular whitespace-nowrap">{{ pesos(m.hora) }}</td>
                  <td class="text-right num-tabular whitespace-nowrap">{{ pesos(m.mensualidades) }}</td>
                  <td class="text-right num-tabular font-semibold whitespace-nowrap">{{ pesos(m.total) }}</td>
                </tr>
                <tr v-if="!reporte.por_metodo.length"><td colspan="4" class="text-text-muted text-xs">Sin cobros.</td></tr>
              </tbody>
            </table>
          </div>
        </div>

        <div class="card-craft p-5 text-sm min-w-0">
          <h3 class="titulo-seccion mb-2">Por tipo de vehículo (parqueo por hora)</h3>
          <p v-for="t in reporte.por_tipo" :key="t.tipo" class="flex justify-between gap-3 border-t border-border-subtle py-2">
            <span class="text-text-secondary min-w-0 break-words">{{ t.tipo }} <span class="text-text-muted">({{ t.cantidad }})</span></span>
            <span class="num-tabular font-semibold whitespace-nowrap">{{ pesos(t.total) }}</span>
          </p>
          <p v-if="!reporte.por_tipo.length" class="text-text-muted text-xs">Sin salidas cobradas.</p>
        </div>

        <div class="card-craft p-5 text-sm min-w-0">
          <h3 class="titulo-seccion mb-2">Por origen</h3>
          <p v-for="o in reporte.por_origen" :key="o.origen" class="flex justify-between gap-3 border-t border-border-subtle py-2">
            <span class="text-text-secondary min-w-0 break-words">{{ o.origen }}</span><span class="num-tabular font-semibold whitespace-nowrap">{{ pesos(o.total) }}</span>
          </p>
        </div>
      </div>

      <div class="card-craft p-5 text-sm">
        <h3 class="titulo-seccion">Anulados</h3>
        <p class="text-xs text-text-muted mt-0.5 mb-2">No suman en los totales.</p>
        <div v-for="(a, i) in reporte.anulados" :key="i" class="flex flex-wrap justify-between gap-2 border-t border-border-subtle py-2">
          <span class="text-text-secondary min-w-0 break-words">{{ a.origen === 'registro' ? 'Parqueo' : 'Mensualidad' }}<span v-if="a.placa" class="font-mono"> · {{ a.placa }}</span> · {{ a.fecha ? fh(a.fecha) : '—' }} · {{ a.motivo }}</span>
          <span class="num-tabular line-through text-text-muted whitespace-nowrap">{{ pesos(a.valor) }}</span>
        </div>
        <p v-if="!reporte.anulados.length" class="text-xs text-text-muted">No hay anulaciones en el rango.</p>
      </div>
    </template>

    <!-- Conflictos de sincronización (HU-26) -->
    <div class="card-craft p-5 text-sm">
      <div class="flex flex-wrap justify-between items-center gap-3">
        <h3 class="titulo-seccion">Conflictos de sincronización</h3>
        <button class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0" :disabled="!conexion.isOnline" @click="cargarConflictos">Actualizar</button>
      </div>
      <p class="text-xs text-text-muted mt-1 mb-2">Operaciones hechas sin conexión que el servidor no pudo aplicar tal cual. Se aplicó la primera operación; revisa estas y corrige manualmente si hace falta.</p>
      <div v-for="c in conflictos" :key="c.id" class="border-t border-border-subtle py-2.5 space-y-0.5">
        <div class="flex flex-wrap justify-between gap-2">
          <strong class="font-semibold min-w-0 break-words">{{ tipoOperacion(c.tipo) }}<span v-if="c.payload?.placa" class="font-mono"> · {{ c.payload.placa }}</span></strong>
          <span class="px-2 py-0.5 rounded-full text-2xs" :class="c.resultado === 'error' ? 'badge-pastel-rose' : 'badge-pastel-amber'">{{ c.resultado }}</span>
        </div>
        <p class="text-xs text-text-secondary break-words">{{ fh(c.creada_en_dispositivo_at) }} (dispositivo) · {{ c.profiles?.nombre || '—' }}</p>
        <p class="text-xs text-danger break-words">{{ c.detalle }}</p>
      </div>
      <p v-if="!conflictos.length" class="text-xs text-text-muted">Sin conflictos.</p>
    </div>
  </div>
</template>

<script setup>
import { ref, onActivated } from 'vue'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { reportesService } from '@/modules/reportes/services/reportesService'
import { mensualidadesService } from '@/modules/mensualidades/services/mensualidadesService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { hoyEnZona, sumarDias, formatearFechaHora, formatearFechaCorta } from '@/utils/fecha'

const authStore = useAuthStore()
const conexion = useConexionStore()

const hoy = hoyEnZona(authStore.zonaHoraria)
const desde = ref(hoy)
const hasta = ref(hoy)
const reporte = ref(null)
const conflictos = ref([])
const cargando = ref(false)
const exportando = ref(false)
const errorMensaje = ref('')

const rangosRapidos = [
  { id: 'hoy', nombre: 'Hoy' },
  { id: '7', nombre: 'Últimos 7 días' },
  { id: 'mes', nombre: 'Este mes' }
]

function pesos(v) { return `$${Number(v || 0).toLocaleString('es-CO')}` }
function fh(v) { return formatearFechaHora(v, authStore.zonaHoraria, { year: 'numeric' }) }
function tipoOperacion(t) {
  return { entrada: 'Entrada', salida: 'Salida', pago_mensualidad: 'Pago de mensualidad', aviso: 'Aviso' }[t] || t
}

function aplicarRango(id) {
  const h = hoyEnZona(authStore.zonaHoraria)
  hasta.value = h
  desde.value = id === 'hoy' ? h : id === '7' ? sumarDias(h, -6) : `${h.slice(0, 8)}01`
  cargar()
}

async function cargar() {
  if (!conexion.isOnline) return
  if (desde.value > hasta.value) {
    errorMensaje.value = 'La fecha inicial no puede ser posterior a la final'
    return
  }
  errorMensaje.value = ''
  cargando.value = true
  try {
    reporte.value = await reportesService.obtenerReporteIngresos(desde.value, hasta.value)
  } catch (e) {
    reporte.value = null
    errorMensaje.value = mensajeDeError(e, 'No se pudo generar el reporte')
  } finally {
    cargando.value = false
  }
}

async function cargarConflictos() {
  if (!conexion.isOnline) return
  try {
    conflictos.value = await reportesService.listarConflictosSync(authStore.parqueaderoId)
  } catch (e) {
    errorMensaje.value = mensajeDeError(e, 'No se pudieron cargar los conflictos')
  }
}

async function obtenerRegistros() {
  return reportesService.obtenerDetalleRegistros({
    parqueaderoId: authStore.parqueaderoId,
    fechaDesde: desde.value,
    fechaHasta: hasta.value,
    zonaHoraria: authStore.zonaHoraria
  })
}

const nombreArchivo = () => `ingresos-${desde.value}-a-${hasta.value}`

async function exportarExcel() {
  exportando.value = true
  errorMensaje.value = ''
  try {
    const r = reporte.value
    const [registros, mensualidades] = await Promise.all([
      obtenerRegistros(),
      mensualidadesService.listarMensualidades(authStore.parqueaderoId, {
        diasAviso: authStore.diasAviso,
        zonaHoraria: authStore.zonaHoraria,
        incluirInactivas: true
      })
    ])
    reportesService.exportarAExcel(nombreArchivo(), {
      Resumen: [
        { Concepto: 'Desde', Valor: desde.value },
        { Concepto: 'Hasta', Valor: hasta.value },
        { Concepto: 'Parqueo por hora', Valor: Number(r.total_hora) },
        { Concepto: 'Mensualidades', Valor: Number(r.total_mensualidades) },
        { Concepto: 'Total', Valor: Number(r.gran_total) },
        { Concepto: 'Cobros que requieren revisión', Valor: Number(r.requieren_revision || 0) },
        { Concepto: 'Conflictos de sincronización', Valor: Number(r.conflictos_sync || 0) }
      ],
      'Por día': r.por_dia.map(d => ({ Fecha: d.fecha, 'Parqueo por hora': Number(d.hora), Mensualidades: Number(d.mensualidades), Total: Number(d.total) })),
      'Por tipo': r.por_tipo.map(t => ({ Tipo: t.tipo, Cantidad: Number(t.cantidad), Total: Number(t.total) })),
      'Por método': r.por_metodo.map(m => ({ Método: m.metodo, Efectivo: m.es_efectivo ? 'Sí' : 'No', 'Parqueo por hora': Number(m.hora), Mensualidades: Number(m.mensualidades), Total: Number(m.total) })),
      Registros: registros,
      Mensualidades: mensualidades.map(m => ({
        Cliente: m.clientes?.nombre || '',
        Documento: m.clientes?.documento || '',
        Teléfono: m.clientes?.telefono || '',
        Placa: m.vehiculos?.placa || '',
        Plan: m.planes_mensuales?.nombre || '',
        Valor: Number(m.planes_mensuales?.valor || 0),
        'Fecha inicio': m.fecha_inicio,
        'Vence': m.fecha_fin,
        Activa: m.activa ? 'Sí' : 'No',
        Estado: m.activa ? ({ al_dia: 'Al día', por_vencer: 'Por vencer', vencida: 'Vencida' }[m.clasificacion?.estado] || '') : 'Desactivada'
      })),
      Anulados: r.anulados.map(a => ({
        Origen: a.origen === 'registro' ? 'Parqueo' : 'Mensualidad',
        Fecha: a.fecha ? fh(a.fecha) : '',
        Placa: a.placa || '',
        Valor: Number(a.valor || 0),
        Motivo: a.motivo || ''
      }))
    })
  } catch (e) {
    errorMensaje.value = mensajeDeError(e, 'No se pudo exportar')
  } finally {
    exportando.value = false
  }
}

async function exportarCSV() {
  exportando.value = true
  errorMensaje.value = ''
  try {
    reportesService.exportarACSV(`registros-${desde.value}-a-${hasta.value}`, await obtenerRegistros())
  } catch (e) {
    errorMensaje.value = mensajeDeError(e, 'No se pudo exportar')
  } finally {
    exportando.value = false
  }
}

// Vista en <keep-alive>: onActivated corre en el primer montaje y al volver,
// así el reporte y los conflictos no quedan desactualizados.
onActivated(() => {
  cargar()
  cargarConflictos()
})
</script>
