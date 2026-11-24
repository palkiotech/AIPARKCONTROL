<template>
  <div class="min-h-screen flex flex-col bg-background text-text-primary">
    <!-- Advertencia persistente de desfase horario (decisión #8, HU-26) -->
    <div
      v-if="conexionStore.hasClockDriftWarning"
      class="bg-warning-bg border-b border-warning-border text-warning px-4 py-2 text-xs font-medium flex items-center gap-2"
      role="alert"
    >
      <svg class="w-4 h-4 flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" />
      </svg>
      <span>
        <strong class="font-semibold">Reloj desajustado:</strong> la hora de este dispositivo difiere
        {{ Math.abs(conexionStore.desfaseMinutos) }} min del servidor
        ({{ conexionStore.desfaseMinutos > 0 ? 'atrasada' : 'adelantada' }}). Las operaciones se corrigen automáticamente; ajusta la hora del equipo.
      </span>
    </div>

    <!-- Encabezado -->
    <header class="bg-surface/95 backdrop-blur border-b border-border sticky top-0 z-30 h-14 px-3 md:px-5 flex items-center justify-between gap-3">
      <div class="flex items-center gap-3 min-w-0">
        <!-- Marca -->
        <div class="flex items-center gap-2.5 lg:w-[13.5rem] flex-shrink-0">
          <svg class="w-8 h-8 flex-shrink-0" viewBox="0 0 32 32" aria-hidden="true">
            <rect width="32" height="32" rx="8" class="fill-primary" />
            <path d="M11 24V8h6.25a4.75 4.75 0 0 1 0 9.5H14.5V24H11zm3.5-9.75h2.6a1.75 1.75 0 0 0 0-3.5h-2.6v3.5z" fill="#fff" />
          </svg>
          <span class="hidden lg:block text-[15px] font-semibold tracking-tight">ParkControl</span>
        </div>

        <div class="hidden md:block w-px h-6 bg-border"></div>

        <!-- Parqueadero y turno -->
        <div class="min-w-0">
          <h1 class="text-sm font-semibold text-text-primary leading-tight truncate">
            {{ authStore.isSuperadmin ? 'Administración de la plataforma' : (authStore.parqueadero?.nombre || 'ParkControl') }}
          </h1>
          <p class="text-2xs text-text-muted flex items-center gap-1.5 mt-0.5 min-w-0">
            <template v-if="!authStore.isSuperadmin">
              <span class="w-1.5 h-1.5 rounded-full flex-shrink-0" :class="turno?.estado === 'abierto' ? 'bg-success' : 'bg-warning'"></span>
              <span class="truncate" :class="turno?.estado === 'abierto' ? 'text-text-secondary' : 'text-warning font-medium'">
                {{ textoTurno }}
              </span>
            </template>
            <span v-else>Superadmin</span>
          </p>
        </div>
      </div>

      <div class="flex items-center gap-2 flex-shrink-0">
        <!-- Estado de conexión (HU-26) -->
        <div
          class="flex items-center gap-1.5 text-2xs px-2.5 py-1 rounded-full font-medium border"
          :class="conexionStore.isOnline && !conexionStore.pendingOperationsCount ? 'badge-neutro' : 'badge-pastel-amber'"
          :title="textoConexion"
        >
          <span class="w-1.5 h-1.5 rounded-full" :class="conexionStore.isOnline && !conexionStore.sincronizando ? 'bg-success' : 'bg-warning animate-pulse'"></span>
          <span class="whitespace-nowrap hidden sm:inline">{{ textoConexion }}</span>
          <span class="whitespace-nowrap sm:hidden">{{ conexionStore.isOnline ? (conexionStore.pendingOperationsCount || 'En línea') : 'Sin red' }}</span>
        </div>

        <button
          v-if="!authStore.isSuperadmin && conexionStore.isOnline && conexionStore.pendingOperationsCount > 0"
          @click="ejecutarSincronizacion"
          :disabled="conexionStore.sincronizando"
          class="btn-craft-primary text-2xs px-2.5 py-1 rounded-full"
        >
          {{ conexionStore.sincronizando ? 'Sincronizando…' : 'Sincronizar' }}
        </button>

        <!-- Menú de usuario -->
        <div class="relative">
          <button
            @click.stop="menuUsuario = !menuUsuario"
            class="flex items-center gap-2 p-1 lg:pr-2.5 rounded-lg hover:bg-surface-elevated transition-colors"
            aria-haspopup="true"
            :aria-expanded="menuUsuario"
          >
            <span class="w-8 h-8 rounded-full bg-primary/10 text-primary font-semibold flex items-center justify-center text-xs">
              {{ iniciales }}
            </span>
            <span class="hidden lg:block text-left leading-tight">
              <span class="block text-xs font-semibold text-text-primary max-w-[140px] truncate">{{ authStore.userName }}</span>
              <span class="block text-2xs text-text-muted">{{ authStore.rolLegible }}</span>
            </span>
            <svg class="hidden lg:block w-4 h-4 text-text-muted" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7" /></svg>
          </button>
          <div
            v-if="menuUsuario"
            class="absolute right-0 mt-2 w-64 bg-surface border border-border rounded-xl p-1.5 z-40 text-sm"
            style="box-shadow: var(--sombra-flotante)"
            @click.stop
          >
            <div class="px-3 py-2.5 border-b border-border mb-1.5">
              <p class="font-semibold text-text-primary truncate">{{ authStore.userName }}</p>
              <p class="text-xs text-text-muted">{{ authStore.rolLegible }}</p>
            </div>
            <div class="px-3 py-2">
              <p class="rotulo mb-2">Apariencia</p>
              <div class="grid grid-cols-3 gap-1 p-1 rounded-lg bg-surface-elevated border border-border">
                <button
                  v-for="op in opcionesTema"
                  :key="op.valor"
                  type="button"
                  @click="temaStore.setTheme(op.valor)"
                  class="text-xs font-medium py-1.5 rounded-md transition-colors"
                  :class="temaStore.currentTheme === op.valor ? 'bg-surface text-text-primary shadow-xs border border-border' : 'text-text-muted hover:text-text-primary border border-transparent'"
                >
                  {{ op.etiqueta }}
                </button>
              </div>
            </div>
            <div class="border-t border-border mt-1.5 pt-1.5">
              <button
                @click="handleLogout"
                class="w-full flex items-center gap-2 text-left px-3 py-2 rounded-lg text-danger font-medium hover:bg-danger-bg"
              >
                <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" /></svg>
                Cerrar sesión
              </button>
            </div>
          </div>
        </div>
      </div>
    </header>

    <div class="flex-1 flex min-h-0" @click="menuUsuario = false">
      <!-- Menú lateral (escritorio) -->
      <aside class="hidden md:flex flex-col w-[4.5rem] lg:w-60 flex-shrink-0 bg-surface border-r border-border px-2 lg:px-3 py-4 gap-5 select-none overflow-y-auto sticky top-14 h-[calc(100vh-3.5rem)]">
        <nav v-for="grupo in gruposMenu" :key="grupo.titulo" class="space-y-0.5">
          <p class="rotulo px-3 pb-1.5 hidden lg:block">{{ grupo.titulo }}</p>
          <router-link
            v-for="item in grupo.items"
            :key="item.to"
            :to="item.to"
            class="relative flex items-center justify-center lg:justify-start gap-3 px-3 py-2.5 lg:py-2 text-sm rounded-lg transition-colors"
            :class="claseItem(item)"
            :title="item.requiereRed && !conexionStore.isOnline ? 'Requiere conexión a internet' : item.label"
            :aria-label="item.label"
          >
            <span v-if="esActivo(item)" class="absolute left-0 top-1.5 bottom-1.5 w-[3px] rounded-r bg-primary"></span>
            <svg class="w-[18px] h-[18px] flex-shrink-0" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" :d="item.icono" /></svg>
            <span class="hidden lg:inline">{{ item.label }}</span>
          </router-link>
        </nav>
        <p v-if="!conexionStore.isOnline && !authStore.isSuperadmin" class="hidden lg:block mt-auto mx-1 text-2xs text-text-muted leading-relaxed">
          Sin conexión: las opciones atenuadas necesitan internet.
        </p>
      </aside>

      <main class="flex-1 min-w-0 px-4 py-5 md:px-8 md:py-7 pb-[calc(6rem+env(safe-area-inset-bottom))] md:pb-10">
        <div class="mx-auto w-full max-w-6xl">
          <router-view v-slot="{ Component }">
            <keep-alive>
              <component :is="Component" :key="$route.name" />
            </keep-alive>
          </router-view>
        </div>
      </main>
    </div>

    <!-- Barra inferior (celular): Inicio, Ocupación, Mensualidades, Caja y Más -->
    <nav
      class="md:hidden fixed bottom-0 left-0 right-0 bg-surface/95 backdrop-blur border-t border-border px-1 pt-1 pb-[max(0.375rem,env(safe-area-inset-bottom))] grid z-30"
      :style="{ gridTemplateColumns: `repeat(${barraInferior.length + (masItems.length ? 1 : 0)}, minmax(0, 1fr))` }"
    >
      <router-link
        v-for="item in barraInferior"
        :key="item.to"
        :to="item.to"
        class="flex flex-col items-center gap-0.5 py-1.5 text-2xs whitespace-nowrap rounded-lg min-w-0"
        :class="esActivo(item) ? 'text-primary font-semibold' : 'text-text-muted'"
      >
        <span class="flex items-center justify-center w-12 h-7 rounded-full transition-colors" :class="esActivo(item) ? 'bg-primary/10' : ''">
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" :d="item.icono" /></svg>
        </span>
        <span class="max-w-full truncate px-0.5">{{ item.corto || item.label }}</span>
      </router-link>
      <button
        v-if="masItems.length"
        @click.stop="menuMas = !menuMas"
        class="flex flex-col items-center gap-0.5 py-1.5 text-2xs"
        :class="menuMas || masItems.some(esActivo) ? 'text-primary font-semibold' : 'text-text-muted'"
      >
        <span class="flex items-center justify-center w-12 h-7 rounded-full" :class="menuMas || masItems.some(esActivo) ? 'bg-primary/10' : ''">
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" d="M4 6h16M4 12h16M4 18h16" /></svg>
        </span>
        <span>Más</span>
      </button>
    </nav>

    <div v-if="menuMas" class="md:hidden fixed inset-0 z-20 bg-slate-950/40" @click="menuMas = false">
      <div class="absolute bottom-[calc(4.75rem+env(safe-area-inset-bottom))] left-3 right-3 max-h-[60vh] overflow-y-auto bg-surface border border-border rounded-2xl p-2 space-y-0.5" style="box-shadow: var(--sombra-flotante)" @click.stop>
        <router-link
          v-for="item in masItems"
          :key="item.to"
          :to="item.to"
          @click="menuMas = false"
          class="flex items-center gap-3 px-3 py-3 text-sm rounded-xl"
          :class="claseItem(item)"
        >
          <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.8" :d="item.icono" /></svg>
          <span>{{ item.label }}</span>
        </router-link>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onBeforeUnmount, watch } from 'vue'
import { useRouter, useRoute } from 'vue-router'
import { useTemaStore } from '@/stores/tema'
import { useConexionStore } from '@/stores/conexion'
import { useAuthStore } from '@/stores/auth'
import { cajaService } from '@/modules/caja/services/cajaService'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { mensualidadesService } from '@/modules/mensualidades/services/mensualidadesService'
import { ajustesService } from '@/modules/ajustes/services/ajustesService'
import { dashboardService } from '@/modules/dashboard/services/dashboardService'
import { sincronizarAhora, iniciarSincronizacionAutomatica, medirDesfaseHorario } from '@/offline/sync'
import { formatearFechaHora } from '@/utils/fecha'

const router = useRouter()
const route = useRoute()
const temaStore = useTemaStore()
const conexionStore = useConexionStore()
const authStore = useAuthStore()

const turno = ref(null)
const menuUsuario = ref(false)
const menuMas = ref(false)
let ultimaConsultaTurno = 0

const ICONOS = {
  inicio: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6',
  patio: 'M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4',
  ocupacion: 'M4 5a1 1 0 011-1h4a1 1 0 011 1v5a1 1 0 01-1 1H5a1 1 0 01-1-1V5zm10 0a1 1 0 011-1h4a1 1 0 011 1v2a1 1 0 01-1 1h-4a1 1 0 01-1-1V5zM4 15a1 1 0 011-1h4a1 1 0 011 1v4a1 1 0 01-1 1H5a1 1 0 01-1-1v-4zm10-3a1 1 0 011-1h4a1 1 0 011 1v7a1 1 0 01-1 1h-4a1 1 0 01-1-1v-7z',
  historial: 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z',
  mensual: 'M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z',
  caja: 'M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z',
  turnos: 'M9 5H7a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2V7a2 2 0 00-2-2h-2M9 5a2 2 0 002 2h2a2 2 0 002-2M9 5a2 2 0 012-2h2a2 2 0 012 2m-6 9l2 2 4-4',
  comprobantes: 'M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z',
  reportes: 'M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z',
  ajustes: 'M10.325 4.317c.426-1.756 2.924-1.756 3.35 0a1.724 1.724 0 002.573 1.066c1.543-.94 3.31.826 2.37 2.37a1.724 1.724 0 001.065 2.572c1.756.426 1.756 2.924 0 3.35a1.724 1.724 0 00-1.066 2.573c.94 1.543-.826 3.31-2.37 2.37a1.724 1.724 0 00-2.572 1.065c-.426 1.756-2.924 1.756-3.35 0a1.724 1.724 0 00-2.573-1.066c-1.543.94-3.31-.826-2.37-2.37a1.724 1.724 0 00-1.065-2.572c-1.756-.426-1.756-2.924 0-3.35a1.724 1.724 0 001.066-2.573c-.94-1.543.826-3.31 2.37-2.37.996.608 2.296.07 2.572-1.065z',
  usuarios: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0z',
  edificio: 'M19 21V5a2 2 0 00-2-2H7a2 2 0 00-2 2v16m14 0h2m-2 0h-5m-9 0H3m2 0h5M9 7h1m-1 4h1m4-4h1m-1 4h1m-5 10v-5a1 1 0 011-1h2a1 1 0 011 1v5m-4 0h4'
}

const gruposMenu = computed(() => {
  if (authStore.isSuperadmin) {
    return [{ titulo: 'Administración global', items: [{ to: '/superadmin', name: 'superadmin', label: 'Parqueaderos', icono: ICONOS.edificio }] }]
  }
  const grupos = [{
    titulo: 'Operación',
    items: [
      { to: '/', name: 'dashboard', label: 'Inicio', icono: ICONOS.inicio },
      { to: '/registro', name: 'registro', label: 'Registro y cobro', corto: 'Registro', icono: ICONOS.patio },
      { to: '/ocupacion', name: 'ocupacion', label: 'Ocupación', icono: ICONOS.ocupacion },
      { to: '/mensualidades', name: 'mensualidades', label: 'Mensualidades', corto: 'Mensual', icono: ICONOS.mensual },
      { to: '/caja', name: 'caja', label: 'Caja y turno', corto: 'Caja', icono: ICONOS.caja },
      { to: '/historial', name: 'historial', label: 'Historial', icono: ICONOS.historial, requiereRed: true }
    ]
  }]
  if (authStore.isAdmin) {
    grupos.push({
      titulo: 'Gestión',
      items: [
        { to: '/caja/turnos', name: 'turnos', label: 'Historial de turnos', icono: ICONOS.turnos, requiereRed: true },
        { to: '/comprobantes', name: 'comprobantes', label: 'Comprobantes', icono: ICONOS.comprobantes, requiereRed: true },
        { to: '/reportes', name: 'reportes', label: 'Reportes', icono: ICONOS.reportes, requiereRed: true },
        { to: '/ajustes', name: 'ajustes', label: 'Ajustes', icono: ICONOS.ajustes, requiereRed: true },
        { to: '/usuarios', name: 'usuarios', label: 'Usuarios', icono: ICONOS.usuarios, requiereRed: true }
      ]
    })
  }
  return grupos
})

const todosItems = computed(() => gruposMenu.value.flatMap(g => g.items))
const BARRA = ['dashboard', 'registro', 'ocupacion', 'caja']
const barraInferior = computed(() => authStore.isSuperadmin
  ? todosItems.value
  : todosItems.value.filter(i => BARRA.includes(i.name)))
const masItems = computed(() => authStore.isSuperadmin
  ? []
  : todosItems.value.filter(i => !BARRA.includes(i.name)))

function esActivo(item) {
  return route.name === item.name
}

function claseItem(item) {
  if (item.requiereRed && !conexionStore.isOnline) return 'opacity-40 pointer-events-none text-text-muted'
  return esActivo(item)
    ? 'bg-primary/10 text-primary font-semibold'
    : 'text-text-secondary font-medium hover:bg-surface-elevated hover:text-text-primary'
}

const opcionesTema = [
  { valor: 'light', etiqueta: 'Claro' },
  { valor: 'dark', etiqueta: 'Oscuro' },
  { valor: 'system', etiqueta: 'Sistema' }
]

const iniciales = computed(() => {
  const partes = (authStore.userName || '?').trim().split(/\s+/)
  return ((partes[0]?.[0] || '') + (partes[1]?.[0] || '')).toUpperCase() || '?'
})

const textoConexion = computed(() => {
  if (conexionStore.sincronizando) return 'Sincronizando…'
  if (!conexionStore.isOnline) return `Sin conexión · ${conexionStore.pendingOperationsCount} pendientes`
  if (conexionStore.pendingOperationsCount > 0) return `En línea · ${conexionStore.pendingOperationsCount} pendientes`
  return 'En línea'
})

const textoTurno = computed(() => {
  const t = turno.value
  if (!t) return 'Sin turno de caja'
  const quien = t.profiles?.nombre || 'Operador'
  const desde = formatearFechaHora(t.abierto_at, authStore.zonaHoraria, { day: undefined, month: undefined })
  if (t.estado === 'por_recibir') return `Turno de ${quien} por recibir`
  return `Turno de ${quien} · desde ${desde}`
})

async function refrescarTurno(forzar = false) {
  if (!authStore.parqueaderoId || authStore.isSuperadmin) {
    turno.value = null
    return
  }
  if (!forzar && Date.now() - ultimaConsultaTurno < 30000) return
  ultimaConsultaTurno = Date.now()
  try {
    turno.value = await cajaService.obtenerTurnoActual(authStore.parqueaderoId)
  } catch (e) {
    console.warn('No se pudo consultar el turno:', e)
  }
}

function precalentarDatos(pqId) {
  if (!pqId || authStore.isSuperadmin) return
  const opciones = { diasAviso: authStore.diasAviso, zonaHoraria: authStore.zonaHoraria, esAdmin: authStore.isAdmin }
  // Precarga en segundo plano; también deja copia local para operar sin conexión
  Promise.allSettled([
    ajustesService.listarTiposVehiculo(pqId),
    ajustesService.listarMetodosPago(pqId),
    ajustesService.listarTarifas(pqId),
    ajustesService.listarPlanesMensuales(pqId),
    ocupacionService.obtenerVehiculosDentro(pqId),
    mensualidadesService.listarMensualidades(pqId, opciones),
    dashboardService.obtenerDatosDashboard(pqId, opciones)
  ])
}

async function iniciar() {
  if (authStore.isSuperadmin || !authStore.parqueaderoId) return
  iniciarSincronizacionAutomatica(conexionStore)
  await medirDesfaseHorario()
  conexionStore.checkClockDrift()
  refrescarTurno(true)
  precalentarDatos(authStore.parqueaderoId)
  if (conexionStore.isOnline) sincronizarAhora(conexionStore).catch(() => {})
}

function alVolverLaRed() {
  refrescarTurno(true)
  authStore.refrescarPerfil()
}

watch(() => authStore.parqueaderoId, (nuevo) => {
  if (nuevo) iniciar()
})

watch(() => route.path, (nueva, anterior) => {
  menuMas.value = false
  menuUsuario.value = false
  const tocaCaja = nueva.startsWith('/caja') || (anterior || '').startsWith('/caja')
  refrescarTurno(tocaCaja)
})

// Sesión expirada o cerrada en otra pestaña: volver al login
watch(() => authStore.isAuthenticated, (autenticado) => {
  if (!autenticado) router.push({ name: 'login' })
})

onMounted(() => {
  iniciar()
  window.addEventListener('online', alVolverLaRed)
})

onBeforeUnmount(() => {
  window.removeEventListener('online', alVolverLaRed)
})

async function ejecutarSincronizacion() {
  await sincronizarAhora(conexionStore)
  refrescarTurno(true)
}

async function handleLogout() {
  menuUsuario.value = false
  await authStore.logout()
  router.push('/login')
}
</script>
