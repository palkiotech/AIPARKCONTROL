<template>
  <div class="space-y-6">
    <!-- Encabezado -->
    <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-4 no-print">
      <div>
        <h2 class="titulo-pagina">Patio de parqueo</h2>
        <p class="subtitulo-pagina">Control de entradas, salidas y capacidad en tiempo real.</p>
      </div>

      <div class="grid grid-cols-2 sm:flex gap-2">
        <button
          @click="abrirEntrada"
          class="col-span-2 sm:col-span-1 btn-craft-primary text-sm px-4 py-2 rounded-lg"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" />
          </svg>
          <span>Nueva entrada</span>
        </button>
        <button
          @click="abrirSalidaPorPlaca"
          class="btn-craft-subtle text-sm px-4 py-2 rounded-lg"
        >
          Salida por placa
        </button>
        <button
          @click="abrirEscaner"
          class="btn-craft-subtle text-sm px-4 py-2 rounded-lg"
        >
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7V5a1 1 0 011-1h2m10 0h2a1 1 0 011 1v2m0 10v2a1 1 0 01-1 1h-2M7 20H5a1 1 0 01-1-1v-2m4-5h8" />
          </svg>
          <span>Escanear QR</span>
        </button>
      </div>
    </div>

    <!-- Feedback -->
    <div v-if="mensajeExito" class="alerta-exito no-print">
      {{ mensajeExito }}
    </div>
    <div v-if="errorMensaje" class="alerta-error no-print" role="alert">
      {{ errorMensaje }}
    </div>
    <div v-if="!conexionStore.isOnline" class="alerta-aviso no-print">
      Sin conexión: las entradas y salidas se guardan en este dispositivo y se sincronizan al volver internet.
    </div>

    <!-- Ocupación por tipo (HU-12) -->
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4 no-print">
      <div
        v-for="tipo in resumenOcupacion"
        :key="tipo.id"
        class="card-craft p-4 sm:p-5"
        :class="tipo.ocupados > tipo.capacidad ? 'pastel-card-amber' : ''"
      >
        <div class="flex justify-between items-start gap-2">
          <div class="flex items-center gap-2 min-w-0">
            <span class="w-8 h-8 rounded-lg bg-surface-elevated border border-border flex items-center justify-center text-text-secondary shrink-0">
              <IconoVehiculo :nombre="tipo.nombre" clase="w-4 h-4" />
            </span>
            <span class="text-sm font-semibold text-text-primary truncate">{{ tipo.nombre }}</span>
          </div>
          <span
            class="text-2xs px-2 py-0.5 rounded-full shrink-0"
            :class="tipo.ocupados > tipo.capacidad ? 'badge-pastel-amber' : (tipo.ocupados === tipo.capacidad ? 'badge-pastel-rose' : 'badge-pastel-mint')"
          >
            {{ tipo.ocupados > tipo.capacidad ? `Sobrecupo +${tipo.ocupados - tipo.capacidad}` : (tipo.ocupados === tipo.capacidad ? 'Lleno' : `${tipo.capacidad - tipo.ocupados} libres`) }}
          </span>
        </div>

        <div class="mt-4 flex items-baseline gap-1.5">
          <span class="text-3xl font-semibold tracking-tight num-tabular" :class="tipo.ocupados > tipo.capacidad ? 'text-warning' : 'text-text-primary'">{{ tipo.ocupados }}</span>
          <span class="text-sm text-text-muted">/ {{ tipo.capacidad }} cupos</span>
        </div>
        <p class="mt-0.5 text-xs text-text-secondary">
          {{ tipo.mensualesDentro }} mensual(es) dentro
        </p>

        <div class="mt-3 w-full bg-border h-1.5 rounded-full overflow-hidden">
          <div
            class="h-full rounded-full transition-all duration-500"
            :class="tipo.ocupados > tipo.capacidad ? 'bg-warning' : (tipo.ocupados === tipo.capacidad ? 'bg-danger' : 'bg-success')"
            :style="{ width: Math.min(100, Math.round((tipo.ocupados / (tipo.capacidad || 1)) * 100)) + '%' }"
          ></div>
        </div>
      </div>
      <div v-if="!cargando && resumenOcupacion.length === 0" class="card-craft p-4 text-sm text-text-muted sm:col-span-2 lg:col-span-3">
        No hay tipos de vehículo activos. Un administrador debe configurarlos en Ajustes.
      </div>
    </div>

    <!-- Lista de vehículos dentro -->
    <div class="card-craft overflow-hidden no-print">
      <div class="flex flex-col lg:flex-row lg:items-center justify-between gap-3 p-4 sm:px-5 border-b border-border">
        <div>
          <h3 class="titulo-seccion flex items-center gap-2">
            <span>Vehículos en patio</span>
            <span class="badge-neutro text-2xs px-2 py-0.5 rounded-full num-tabular">{{ vehiculosDentro.length }}</span>
          </h3>
          <p class="text-xs text-text-muted mt-0.5">El valor es una estimación; el cobro final lo calcula el servidor.</p>
        </div>
        <div class="flex flex-col sm:flex-row gap-2 w-full lg:w-auto">
          <div class="relative w-full sm:w-56">
            <svg class="w-4 h-4 absolute left-2.5 top-1/2 -translate-y-1/2 text-text-muted pointer-events-none" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-4.35-4.35M17 11a6 6 0 11-12 0 6 6 0 0112 0z" />
            </svg>
            <input
              v-model="filtroPlaca"
              type="text"
              placeholder="Buscar por placa..."
              class="campo campo-sm pl-8 uppercase font-mono tracking-wider"
            />
          </div>
          <select
            v-model="filtroTipo"
            class="campo campo-sm sm:w-44"
          >
            <option value="">Todos los tipos</option>
            <option v-for="t in tiposActivos" :key="t.id" :value="t.id">{{ t.nombre }}</option>
          </select>
        </div>
      </div>

      <div v-if="cargando" class="vacio">
        <div class="spinner"></div>
        <span>Consultando vehículos en patio...</span>
      </div>

      <div v-else-if="vehiculosFiltrados.length === 0" class="vacio py-12">
        <div class="w-11 h-11 rounded-full bg-surface-elevated border border-border flex items-center justify-center text-text-muted">
          <IconoVehiculo nombre="carro" clase="w-5 h-5" />
        </div>
        <p class="font-medium text-text-primary">No hay vehículos dentro con ese criterio</p>
      </div>

      <template v-else>
        <!-- Tabla (escritorio) -->
        <div class="hidden sm:block overflow-x-auto">
          <table class="tabla">
            <thead>
              <tr>
                <th>Placa</th>
                <th>Tipo</th>
                <th>Entrada</th>
                <th>Tiempo</th>
                <th class="text-right">Est. cobro</th>
                <th class="text-right">Acción</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="v in vehiculosFiltrados" :key="v.id">
                <td>
                  <div class="flex items-center flex-wrap gap-1.5">
                    <span class="plate-colombia text-xs" :class="clasePlaca(nombreTipo(v))">{{ v.placa }}</span>
                    <span v-if="v.es_mensual" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-mint">Mensual</span>
                    <span v-if="v.pendiente_sync" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-amber">Pendiente de sincronizar</span>
                  </div>
                </td>
                <td class="text-text-secondary">
                  <span class="inline-flex items-center gap-1.5">
                    <IconoVehiculo :nombre="nombreTipo(v)" clase="w-4 h-4 text-text-muted" />
                    {{ nombreTipo(v) || 'Vehículo' }}
                  </span>
                </td>
                <td class="text-text-secondary num-tabular">{{ formatearHora(v.entrada_at) }}</td>
                <td class="text-text-secondary num-tabular">
                  {{ formatearDuracion(minutosTranscurridos(v.entrada_at)) }}
                </td>
                <td class="text-right font-semibold text-text-primary num-tabular">
                  {{ textoEstimado(v) }}
                </td>
                <td class="text-right whitespace-nowrap space-x-2">
                  <button
                    v-if="authStore.isAdmin && !v.pendiente_sync"
                    @click="abrirAnular(v)"
                    class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg text-danger"
                  >
                    Anular
                  </button>
                  <button @click="abrirCobro(v)" class="btn-craft-primary text-xs px-3 py-1.5 rounded-lg">
                    {{ v.es_mensual ? 'Dar salida' : 'Cobrar' }}
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>

        <!-- Tarjetas (celular) -->
        <div class="sm:hidden divide-y divide-border-subtle">
          <div v-for="v in vehiculosFiltrados" :key="v.id" class="p-4 space-y-2.5">
            <div class="flex items-center justify-between gap-2">
              <span class="plate-colombia text-sm" :class="clasePlaca(nombreTipo(v))">{{ v.placa }}</span>
              <span class="font-semibold text-sm text-text-primary num-tabular">{{ textoEstimado(v) }}</span>
            </div>
            <div class="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-text-secondary">
              <span class="inline-flex items-center gap-1">
                <IconoVehiculo :nombre="nombreTipo(v)" clase="w-3.5 h-3.5 text-text-muted" />
                {{ nombreTipo(v) }}
              </span>
              <span class="num-tabular">· {{ formatearHora(v.entrada_at) }}</span>
              <span class="num-tabular">· {{ formatearDuracion(minutosTranscurridos(v.entrada_at)) }}</span>
              <span v-if="v.es_mensual" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-mint">Mensual</span>
              <span v-if="v.pendiente_sync" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-amber">Pendiente de sincronizar</span>
            </div>
            <div class="flex gap-2">
              <button @click="abrirCobro(v)" class="flex-1 btn-craft-primary text-sm px-4 py-2 rounded-lg">
                {{ v.es_mensual ? 'Dar salida' : 'Cobrar' }}
              </button>
              <button
                v-if="authStore.isAdmin && !v.pendiente_sync"
                @click="abrirAnular(v)"
                class="btn-craft-subtle text-sm px-4 py-2 rounded-lg text-danger"
              >
                Anular
              </button>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- MODAL ENTRADA (HU-11) -->
    <div v-if="modalEntrada.abierto" class="modal-fondo no-print">
      <div class="modal-panel max-w-md">
        <div class="modal-encabezado">
          <h3 class="modal-titulo">Registrar entrada</h3>
          <button type="button" @click="cerrarEntrada" class="btn-icono" aria-label="Cerrar">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>

        <form @submit.prevent="confirmarEntrada(false)" class="space-y-4">
          <div>
            <label class="etiqueta">Placa</label>
            <input
              ref="inputPlaca"
              v-model="modalEntrada.placa"
              type="text"
              autocomplete="off"
              maxlength="10"
              placeholder="ABC123"
              class="campo px-4 py-3 text-2xl text-center uppercase font-mono font-bold tracking-[0.2em]"
            />
          </div>

          <div>
            <label class="etiqueta">Tipo de vehículo</label>
            <div class="grid grid-cols-2 gap-2">
              <button
                v-for="t in tiposActivos"
                :key="t.id"
                type="button"
                @click="seleccionarTipo(t.id)"
                class="py-3 px-2 rounded-lg border text-sm font-semibold transition-colors flex flex-col items-center gap-1"
                :class="modalEntrada.tipoId === t.id ? 'border-primary bg-primary/10 text-primary ring-1 ring-primary' : 'border-border text-text-secondary hover:border-primary/50 hover:text-text-primary'"
              >
                <IconoVehiculo :nombre="t.nombre" clase="w-6 h-6" />
                <span>{{ t.nombre }}</span>
                <span class="text-2xs font-medium text-text-muted num-tabular">{{ ocupadosTipo(t.id) }}/{{ t.capacidad }}</span>
              </button>
            </div>
          </div>

          <div v-if="tarifasDelTipoEntrada.length > 1">
            <label class="etiqueta">Tarifa</label>
            <select
              v-model="modalEntrada.tarifaId"
              class="campo"
            >
              <option v-for="t in tarifasDelTipoEntrada" :key="t.id" :value="t.id">
                {{ t.nombre }} · {{ pesos(t.valor) }} ({{ nombreModalidad(t.modalidad) }}){{ t.es_predeterminada ? ' · predeterminada' : '' }}
              </option>
            </select>
          </div>
          <p v-else-if="modalEntrada.tipoId && tarifasDelTipoEntrada.length === 0" class="alerta-aviso">
            Este tipo no tiene tarifa activa: la salida no se podrá cobrar hasta configurarla en Ajustes.
          </p>

          <!-- Aviso de capacidad: nunca bloquea -->
          <div v-if="modalEntrada.avisoCapacidad" class="alerta-aviso flex-col">
            <p class="font-semibold">
              {{ tipoSeleccionado?.nombre }} {{ ocupadosTipo(modalEntrada.tipoId) }}/{{ tipoSeleccionado?.capacidad }}: ya está lleno según la capacidad.
            </p>
            <div class="flex gap-2 w-full">
              <button type="button" @click="modalEntrada.avisoCapacidad = false" class="flex-1 btn-craft-subtle text-xs px-3 py-2 rounded-lg">
                Cancelar
              </button>
              <button type="button" @click="confirmarEntrada(true)" class="flex-1 btn-craft-primary text-xs px-3 py-2 rounded-lg" :disabled="modalEntrada.guardando">
                Registrar de todas formas
              </button>
            </div>
          </div>

          <p v-if="modalEntrada.error" class="alerta-error" role="alert">{{ modalEntrada.error }}</p>

          <button
            v-if="!modalEntrada.avisoCapacidad"
            type="submit"
            :disabled="modalEntrada.guardando"
            class="w-full btn-craft-success text-sm px-4 py-2.5 rounded-lg"
          >
            {{ modalEntrada.guardando ? 'Registrando...' : 'Registrar entrada' }}
          </button>
        </form>
      </div>
    </div>

    <!-- MODAL RESULTADO DE ENTRADA / TICKET (HU-27) -->
    <div v-if="ticket.abierto" class="modal-fondo no-print">
      <div class="modal-panel max-w-sm text-center space-y-3">
        <div class="flex flex-col items-center gap-2">
          <span class="w-10 h-10 rounded-full bg-success-bg text-success flex items-center justify-center">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7" /></svg>
          </span>
          <p class="text-sm font-semibold text-text-primary">Entrada registrada</p>
          <p v-if="ticket.datos.offline" class="text-xs text-warning">Sin conexión, pendiente de sincronizar</p>
        </div>
        <span class="plate-colombia text-lg inline-block" :class="clasePlaca(ticket.datos.tipoNombre)">{{ ticket.datos.placa }}</span>
        <p class="text-xs text-text-secondary">{{ ticket.datos.tipoNombre }} · {{ formatearFechaHora(ticket.datos.entrada_at, zona) }}</p>

        <p v-if="ticket.datos.es_mensual" class="alerta-exito justify-center">
          Mensualidad al día hasta {{ formatearFechaCorta(ticket.datos.mensualidad?.fecha_fin) }}
        </p>
        <p v-else-if="ticket.datos.mensualidad && ticket.datos.mensualidad.vigente === false" class="alerta-error text-left">
          La mensualidad de esta placa está vencida (venció el {{ formatearFechaCorta(ticket.datos.mensualidad.fecha_fin) }}). Se registró como cobro por hora.
        </p>
        <p v-if="ticket.datos.sobrecupo" class="alerta-aviso justify-center">Registrado en sobrecupo.</p>

        <template v-if="ticket.mostrarQR && ticket.qr">
          <img :src="ticket.qr" alt="QR del ticket" class="mx-auto w-56 h-56 rounded-lg border border-border bg-white p-2" />
          <p class="text-xs text-text-muted">El cliente puede tomarle foto al QR para la salida.</p>
          <button @click="compartirQR" class="w-full btn-craft-subtle text-xs px-3 py-2 rounded-lg">Compartir / descargar QR</button>
        </template>

        <div v-if="modoTicket === 'termica'" class="flex gap-2">
          <button @click="imprimirTicket" class="flex-1 btn-craft-primary text-xs px-3 py-2 rounded-lg">Imprimir ticket</button>
          <button v-if="!ticket.mostrarQR" @click="ticket.mostrarQR = true" class="flex-1 btn-craft-subtle text-xs px-3 py-2 rounded-lg">Mostrar QR</button>
        </div>
        <button @click="cerrarTicket" class="w-full btn-craft-success text-sm px-4 py-2.5 rounded-lg">Listo</button>
      </div>
    </div>

    <!-- Ticket térmico imprimible (oculto en pantalla) -->
    <div v-if="ticket.datos" id="pc-ticket-termico" class="pc-ticket-termico" :style="{ width: (anchoTicket - 4) + 'mm' }">
      <p class="pc-t-centro pc-t-negrita">{{ authStore.parqueadero?.nombre }}</p>
      <p v-if="authStore.parqueadero?.nit" class="pc-t-centro">NIT {{ authStore.parqueadero.nit }}</p>
      <p class="pc-t-centro">--------------------------------</p>
      <p class="pc-t-centro pc-t-placa">{{ ticket.datos.placa }}</p>
      <p>Tipo: {{ ticket.datos.tipoNombre }}</p>
      <p>Entrada: {{ formatearFechaHora(ticket.datos.entrada_at, zona, { year: 'numeric' }) }}</p>
      <p v-if="ticket.datos.tarifaNombre">Tarifa: {{ ticket.datos.tarifaNombre }}</p>
      <img v-if="ticket.qr" :src="ticket.qr" alt="" class="pc-t-qr" />
      <p v-if="authStore.parqueadero?.texto_pie_comprobante" class="pc-t-centro pc-t-pie">{{ authStore.parqueadero.texto_pie_comprobante }}</p>
    </div>

    <!-- MODAL SALIDA POR PLACA -->
    <div v-if="modalPlaca.abierto" class="modal-fondo no-print">
      <form @submit.prevent="buscarPorPlaca" class="modal-panel max-w-sm">
        <div class="modal-encabezado">
          <h3 class="modal-titulo">Salida por placa</h3>
          <button type="button" @click="modalPlaca.abierto = false" class="btn-icono" aria-label="Cerrar">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <input
          ref="inputPlacaSalida"
          v-model="modalPlaca.placa"
          type="text"
          placeholder="ABC123"
          class="campo px-4 py-3 text-xl text-center uppercase font-mono font-bold tracking-[0.2em]"
        />
        <p v-if="modalPlaca.error" class="alerta-error" role="alert">{{ modalPlaca.error }}</p>
        <button type="submit" class="w-full btn-craft-primary text-sm px-4 py-2.5 rounded-lg">Buscar</button>
      </form>
    </div>

    <!-- MODAL ESCÁNER QR -->
    <div v-if="escaner.abierto" class="modal-fondo no-print">
      <div class="modal-panel max-w-sm">
        <div class="modal-encabezado">
          <h3 class="modal-titulo">Escanear ticket</h3>
          <button type="button" @click="cerrarEscaner" class="btn-icono" aria-label="Cerrar">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <video ref="videoEscaner" class="w-full rounded-lg bg-black aspect-square object-cover"></video>
        <p v-if="escaner.error" class="alerta-error" role="alert">{{ escaner.error }}</p>
        <p v-else class="text-xs text-text-muted text-center">Apunta la cámara al QR del ticket. Si no hay ticket, usa "Salida por placa".</p>
      </div>
    </div>

    <!-- MODAL COBRO DE SALIDA (HU-13) -->
    <div v-if="cobro.abierto" class="modal-fondo no-print">
      <div class="modal-panel max-w-md">
        <div class="modal-encabezado">
          <div class="flex items-center gap-2">
            <h3 class="modal-titulo">Salida</h3>
            <span class="plate-colombia text-xs" :class="clasePlaca(nombreTipo(cobro.registro))">{{ cobro.registro.placa }}</span>
          </div>
          <button type="button" @click="cerrarCobro" class="btn-icono" aria-label="Cerrar">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>

        <div v-if="cobro.cargando" class="vacio">
          <div class="spinner"></div>
          <span>Calculando cobro...</span>
        </div>

        <template v-else-if="cobro.cotizacion">
          <dl class="grid grid-cols-2 gap-2 text-sm">
            <div class="p-3 rounded-lg bg-surface-elevated border border-border-subtle">
              <dt class="rotulo">Entrada</dt>
              <dd class="font-medium text-text-primary mt-0.5 num-tabular">{{ formatearFechaHora(cobro.registro.entrada_at, zona) }}</dd>
            </div>
            <div class="p-3 rounded-lg bg-surface-elevated border border-border-subtle">
              <dt class="rotulo">Salida</dt>
              <dd class="font-medium text-text-primary mt-0.5 num-tabular">{{ formatearFechaHora(cobro.cotizacion.salida_at, zona) }}</dd>
            </div>
            <div class="p-3 rounded-lg bg-surface-elevated border border-border-subtle">
              <dt class="rotulo">Tiempo</dt>
              <dd class="font-medium text-text-primary mt-0.5 num-tabular">{{ formatearDuracion(cobro.cotizacion.minutos) }}</dd>
            </div>
            <div class="p-3 rounded-lg bg-surface-elevated border border-border-subtle">
              <dt class="rotulo">Tarifa</dt>
              <dd class="font-medium text-text-primary mt-0.5">{{ cobro.cotizacion.es_mensual ? 'Mensualidad vigente' : (cobro.cotizacion.tarifa_nombre || '—') }}</dd>
            </div>
          </dl>

          <div v-if="!cobro.cotizacion.es_mensual && tarifasDelTipoCobro.length > 1">
            <label class="etiqueta">Cambiar tarifa</label>
            <select
              v-model="cobro.tarifaId"
              @change="cotizar"
              class="campo"
            >
              <option v-for="t in tarifasDelTipoCobro" :key="t.id" :value="t.id">{{ t.nombre }} · {{ pesos(t.valor) }}</option>
            </select>
          </div>

          <div v-if="(cobro.cotizacion.desglose || []).length > 1" class="text-xs text-text-secondary space-y-1">
            <p v-for="(d, i) in cobro.cotizacion.desglose" :key="i" class="flex justify-between">
              <span>{{ d.tipo === 'nocturna' ? 'Tramo nocturno' : 'Tramo general' }} · {{ formatearDuracion(d.minutos) }}</span>
              <span class="font-medium text-text-primary num-tabular">{{ pesos(d.valor) }}</span>
            </p>
          </div>

          <div class="p-4 rounded-lg bg-surface-elevated border border-border text-center">
            <p class="rotulo">Total a cobrar</p>
            <p class="text-3xl font-semibold tracking-tight num-tabular text-text-primary mt-1">{{ pesos(cobro.cotizacion.valor) }}</p>
            <p v-if="cobro.cotizacion.offline" class="text-xs text-warning font-medium mt-1">Calculado sin conexión; el servidor lo verificará al sincronizar.</p>
          </div>

          <!-- Sin turno no se cobra -->
          <div v-if="cobro.cotizacion.valor > 0 && !turnoAbierto" class="alerta-error flex-col">
            <p class="font-semibold">No hay un turno de caja abierto. Abre el turno para poder cobrar.</p>
            <router-link to="/caja" class="w-full btn-craft-primary text-xs px-3 py-2 rounded-lg" @click="cerrarCobro">Abrir turno</router-link>
          </div>

          <template v-else-if="cobro.cotizacion.valor > 0">
            <div>
              <label class="etiqueta">Método de pago</label>
              <div class="grid grid-cols-2 gap-2">
                <button
                  v-for="m in metodosActivos"
                  :key="m.id"
                  type="button"
                  @click="cobro.metodoPagoId = m.id"
                  class="py-2 px-3 rounded-lg border text-sm font-medium transition-colors"
                  :class="cobro.metodoPagoId === m.id ? 'border-primary bg-primary/10 text-primary ring-1 ring-primary' : 'border-border text-text-secondary hover:border-primary/50 hover:text-text-primary'"
                >
                  {{ m.nombre }}
                </button>
              </div>
              <p v-if="metodosActivos.length === 0" class="alerta-error mt-2">No hay métodos de pago activos. Configúralos en Ajustes.</p>
            </div>

            <div v-if="metodoEsEfectivo" class="space-y-2">
              <label class="etiqueta mb-0">Paga con</label>
              <div class="grid grid-cols-5 gap-1.5">
                <button type="button" @click="cobro.pagaCon = cobro.cotizacion.valor" class="btn-craft-subtle text-xs px-1 py-1.5 rounded-lg">Exacto</button>
                <button v-for="b in billetes" :key="b" type="button" @click="cobro.pagaCon = b" class="btn-craft-subtle text-xs px-1 py-1.5 rounded-lg num-tabular">${{ b / 1000 }}k</button>
              </div>
              <input
                v-model.number="cobro.pagaCon"
                type="number"
                min="0"
                step="100"
                placeholder="Valor recibido"
                class="campo num-tabular"
              />
              <p v-if="cobro.pagaCon > 0" class="p-2.5 rounded-lg text-sm font-semibold text-center num-tabular" :class="vuelto >= 0 ? 'bg-success-bg text-success' : 'bg-danger-bg text-danger'">
                {{ vuelto >= 0 ? `Vuelto: ${pesos(vuelto)}` : `Faltan ${pesos(-vuelto)}` }}
              </p>
            </div>
          </template>

          <p v-if="cobro.cotizacion.es_mensual" class="alerta-exito justify-center">
            Vehículo mensual con mensualidad vigente: sale sin cobro.
          </p>
        </template>

        <p v-if="cobro.error" class="alerta-error" role="alert">{{ cobro.error }}</p>

        <button
          v-if="cobro.cotizacion"
          @click="confirmarSalida"
          :disabled="!puedeConfirmarSalida || cobro.guardando"
          class="w-full btn-craft-success text-sm px-4 py-2.5 rounded-lg"
        >
          {{ cobro.guardando ? 'Registrando...' : (cobro.cotizacion.valor > 0 ? `Cobrar ${pesos(cobro.cotizacion.valor)}` : 'Registrar salida') }}
        </button>
      </div>
    </div>

    <!-- MODAL SALIDA EXITOSA + COMPROBANTE (HU-20) -->
    <div v-if="salidaOk.abierto" class="modal-fondo no-print">
      <div class="modal-panel max-w-sm space-y-3">
        <div class="text-center flex flex-col items-center gap-1.5">
          <span class="w-10 h-10 rounded-full bg-success-bg text-success flex items-center justify-center">
            <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2.5" d="M5 13l4 4L19 7" /></svg>
          </span>
          <p class="text-sm font-semibold text-text-primary">Salida registrada</p>
          <p v-if="salidaOk.datos.offline" class="text-xs text-warning">Pendiente de sincronizar</p>
          <span class="plate-colombia text-sm inline-block mt-1" :class="clasePlaca(salidaOk.datos.tipoNombre)">{{ salidaOk.datos.placa }}</span>
          <p class="text-3xl font-semibold tracking-tight num-tabular text-text-primary mt-1">{{ pesos(salidaOk.datos.valor) }}</p>
          <p class="text-xs text-text-secondary">{{ formatearDuracion(salidaOk.datos.minutos) }}<span v-if="salidaOk.datos.metodo"> · {{ salidaOk.datos.metodo }}</span></p>
          <p v-if="salidaOk.datos.vuelto > 0" class="text-sm font-semibold text-success num-tabular">Vuelto: {{ pesos(salidaOk.datos.vuelto) }}</p>
        </div>

        <div v-if="salidaOk.datos.valor > 0" class="space-y-2 pt-3 border-t border-border">
          <p class="rotulo">Comprobante (opcional)</p>
          <input v-model="salidaOk.clienteNombre" type="text" placeholder="Nombre (Consumidor final)" class="campo" />
          <input v-model="salidaOk.clienteDocumento" type="text" placeholder="Documento / NIT" class="campo" />
          <p v-if="salidaOk.error" class="alerta-error" role="alert">{{ salidaOk.error }}</p>
          <button @click="generarComprobante" :disabled="salidaOk.generando" class="w-full btn-craft-subtle text-sm px-4 py-2 rounded-lg">
            {{ salidaOk.generando ? 'Generando...' : (comprobanteProvisional ? 'Comprobante provisional (sin conexión)' : 'Generar comprobante PDF') }}
          </button>
        </div>

        <button @click="salidaOk.abierto = false" class="w-full btn-craft-success text-sm px-4 py-2.5 rounded-lg">Listo</button>
      </div>
    </div>

    <!-- MODAL ANULAR (HU-15) -->
    <div v-if="anular.abierto" class="modal-fondo no-print">
      <form @submit.prevent="confirmarAnular" class="modal-panel max-w-sm space-y-3">
        <div class="modal-encabezado">
          <h3 class="modal-titulo">Anular registro {{ anular.registro?.placa }}</h3>
          <button type="button" @click="anular.abierto = false" class="btn-icono" aria-label="Cerrar">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <p class="text-sm text-text-secondary">El registro no se borra: queda anulado con el motivo y tu usuario.</p>
        <div>
          <label class="etiqueta">Motivo</label>
          <textarea
            v-model="anular.motivo"
            rows="3"
            placeholder="Motivo (mínimo 10 caracteres)"
            class="campo"
          ></textarea>
          <p class="text-xs text-text-muted mt-1 num-tabular">{{ anular.motivo.trim().length }}/10 caracteres mínimos</p>
        </div>
        <p v-if="anular.error" class="alerta-error" role="alert">{{ anular.error }}</p>
        <div class="flex gap-2">
          <button type="button" @click="anular.abierto = false" class="flex-1 btn-craft-subtle text-sm px-4 py-2 rounded-lg">Cancelar</button>
          <button type="submit" :disabled="anular.motivo.trim().length < 10 || anular.guardando" class="flex-1 btn-craft-danger text-sm px-4 py-2 rounded-lg">
            {{ anular.guardando ? 'Anulando...' : 'Anular' }}
          </button>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, nextTick, onMounted, onUnmounted, onActivated, onDeactivated } from 'vue'
import QRCode from 'qrcode'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { ajustesService } from '@/modules/ajustes/services/ajustesService'
import { cajaService } from '@/modules/caja/services/cajaService'
import { comprobanteService } from '@/modules/comprobantes/services/comprobanteService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { calcularCobroConFranja, resolverTarifas } from '@/domain/cobro'
import { normalizarPlaca, esPlacaValida } from '@/utils/placa'
import { formatearFechaHora, formatearFechaCorta } from '@/utils/fecha'
import IconoVehiculo from '@/components/IconoVehiculo.vue'

const authStore = useAuthStore()
const conexionStore = useConexionStore()

const zona = computed(() => authStore.zonaHoraria)
const modoTicket = computed(() => authStore.parqueadero?.modo_ticket || 'qr')
const anchoTicket = computed(() => (authStore.parqueadero?.ancho_ticket_mm === 58 ? 58 : 80))
const billetes = [10000, 20000, 50000, 100000]

const tipos = ref([])
const tarifas = ref([])
const metodos = ref([])
const vehiculosDentro = ref(ocupacionService.obtenerVehiculosDentroCache() || [])
const turno = ref(null)
const cargando = ref(!ocupacionService.obtenerVehiculosDentroCache())
const errorMensaje = ref('')
const mensajeExito = ref('')
const filtroPlaca = ref('')
const filtroTipo = ref('')
const ahora = ref(Date.now())

const inputPlaca = ref(null)
const inputPlacaSalida = ref(null)
const videoEscaner = ref(null)

// ---------- Utilidades de presentación ----------
function pesos(v) {
  return `$${Number(v || 0).toLocaleString('es-CO')}`
}
function formatearHora(iso) {
  return formatearFechaHora(iso, zona.value, { day: undefined, month: undefined })
}
function formatearDuracion(min) {
  const m = Math.max(0, Math.round(min || 0))
  if (m < 60) return `${m} min`
  const h = Math.floor(m / 60)
  const r = m % 60
  return r === 0 ? `${h}h` : `${h}h ${r}m`
}
function minutosTranscurridos(iso) {
  return Math.max(0, Math.floor((ahora.value - new Date(iso).getTime()) / 60000))
}
function nombreTipo(v) {
  return v?.tipos_vehiculo?.nombre || tipos.value.find(t => t.id === v?.tipo_vehiculo_id)?.nombre || ''
}
function esMoto(n) { return (n || '').toLowerCase().includes('moto') }
function esBici(n) { return (n || '').toLowerCase().includes('bici') }
function clasePlaca(n) { return esMoto(n) ? 'plate-moto' : (esBici(n) ? 'plate-bici' : 'plate-carro') }
function nombreModalidad(m) {
  return { por_minuto: 'por minuto', por_hora: 'por hora', por_fraccion: 'por fracción', plena: 'plena' }[m] || m
}
function avisar(msg) {
  mensajeExito.value = msg
  setTimeout(() => { if (mensajeExito.value === msg) mensajeExito.value = '' }, 4000)
}

// ---------- Datos derivados ----------
const tiposActivos = computed(() => tipos.value.filter(t => t.activo !== false))
const metodosActivos = computed(() => metodos.value.filter(m => m.activo !== false).sort((a, b) => (a.orden || 0) - (b.orden || 0)))
const turnoAbierto = computed(() => !!turno.value && turno.value.estado === 'abierto')

function tarifasGeneralesDe(tipoId) {
  return tarifas.value.filter(t => t.tipo_vehiculo_id === tipoId && t.activa !== false && !t.franja_inicio)
}
function ocupadosTipo(tipoId) {
  return vehiculosDentro.value.filter(v => v.tipo_vehiculo_id === tipoId).length
}

const resumenOcupacion = computed(() => tiposActivos.value.map(t => {
  const delTipo = vehiculosDentro.value.filter(v => v.tipo_vehiculo_id === t.id)
  return {
    id: t.id,
    nombre: t.nombre,
    capacidad: t.capacidad || 0,
    ocupados: delTipo.length,
    mensualesDentro: delTipo.filter(v => v.es_mensual).length
  }
}))

const vehiculosFiltrados = computed(() => {
  const placa = normalizarPlaca(filtroPlaca.value)
  return vehiculosDentro.value.filter(v =>
    (!placa || v.placa.includes(placa)) && (!filtroTipo.value || v.tipo_vehiculo_id === filtroTipo.value)
  )
})

// Estimación local (el valor definitivo lo calcula el servidor al salir)
const estimaciones = computed(() => {
  const mapa = {}
  for (const v of vehiculosDentro.value) {
    if (v.es_mensual) { mapa[v.id] = 0; continue }
    try {
      const delTipo = tarifas.value.filter(t => t.tipo_vehiculo_id === v.tipo_vehiculo_id)
      const { general, nocturna } = resolverTarifas(delTipo.length ? delTipo : [v.tarifas].filter(Boolean), v.tarifa_id)
      if (!general) { mapa[v.id] = null; continue }
      const entrada = new Date(v.entrada_at).getTime()
      mapa[v.id] = calcularCobroConFranja({
        entradaAt: v.entrada_at,
        salidaAt: new Date(Math.max(ahora.value, entrada)),
        tarifaGeneral: general,
        tarifaNocturna: nocturna,
        zonaHoraria: zona.value
      }).valorTotal
    } catch (e) {
      mapa[v.id] = null
    }
  }
  return mapa
})

function textoEstimado(v) {
  if (v.es_mensual) return 'Mensual · $0'
  const e = estimaciones.value[v.id]
  return e === null || e === undefined ? '—' : pesos(e)
}

// ---------- Carga ----------
let cargaEnCurso = null
async function cargarDatos() {
  const pqId = authStore.parqueaderoId
  if (!pqId) return
  if (cargaEnCurso) return cargaEnCurso
  cargaEnCurso = (async () => {
    try {
      const [t, ta, m, dentro, tu] = await Promise.all([
        ajustesService.listarTiposVehiculo(pqId),
        ajustesService.listarTarifas(pqId),
        ajustesService.listarMetodosPago(pqId),
        ocupacionService.obtenerVehiculosDentro(pqId),
        cajaService.obtenerTurnoActual(pqId)
      ])
      tipos.value = t
      tarifas.value = ta
      metodos.value = m
      vehiculosDentro.value = dentro
      turno.value = tu
      errorMensaje.value = ''
    } catch (err) {
      errorMensaje.value = mensajeDeError(err, 'No se pudo cargar el patio')
    } finally {
      cargando.value = false
      ahora.value = Date.now()
      cargaEnCurso = null
    }
  })()
  return cargaEnCurso
}

let temporizadorRecarga = null
function recargarConRetardo() {
  clearTimeout(temporizadorRecarga)
  temporizadorRecarga = setTimeout(cargarDatos, 400)
}

let intervalo = null
let intervaloReloj = null
function iniciarRefresco() {
  detenerRefresco()
  intervalo = setInterval(cargarDatos, 60000)
  intervaloReloj = setInterval(() => { ahora.value = Date.now() }, 30000)
}
function detenerRefresco() {
  clearInterval(intervalo)
  clearInterval(intervaloReloj)
  intervalo = null
  intervaloReloj = null
}

let cancelarSuscripcion = null
onMounted(() => {
  cargarDatos()
  iniciarRefresco()
  cancelarSuscripcion = ocupacionService.suscribirCambios(authStore.parqueaderoId, recargarConRetardo)
})
onActivated(() => {
  cargarDatos()
  iniciarRefresco()
})
onDeactivated(() => {
  detenerRefresco()
  cerrarEscaner()
})
onUnmounted(() => {
  detenerRefresco()
  cerrarEscaner()
  clearTimeout(temporizadorRecarga)
  if (cancelarSuscripcion) cancelarSuscripcion()
})

// ---------- Entrada (HU-11) ----------
const modalEntrada = reactive({ abierto: false, placa: '', tipoId: '', tarifaId: '', avisoCapacidad: false, guardando: false, error: '' })
const tipoSeleccionado = computed(() => tiposActivos.value.find(t => t.id === modalEntrada.tipoId))
const tarifasDelTipoEntrada = computed(() => modalEntrada.tipoId ? tarifasGeneralesDe(modalEntrada.tipoId) : [])

function seleccionarTipo(tipoId) {
  modalEntrada.tipoId = tipoId
  modalEntrada.avisoCapacidad = false
  const lista = tarifasGeneralesDe(tipoId)
  modalEntrada.tarifaId = (lista.find(t => t.es_predeterminada) || lista[0])?.id || ''
}

function abrirEntrada() {
  Object.assign(modalEntrada, { abierto: true, placa: '', avisoCapacidad: false, guardando: false, error: '' })
  if (!modalEntrada.tipoId || !tiposActivos.value.some(t => t.id === modalEntrada.tipoId)) {
    if (tiposActivos.value[0]) seleccionarTipo(tiposActivos.value[0].id)
  } else {
    seleccionarTipo(modalEntrada.tipoId)
  }
  nextTick(() => inputPlaca.value?.focus())
}
function cerrarEntrada() {
  modalEntrada.abierto = false
}

async function confirmarEntrada(forzar) {
  modalEntrada.error = ''
  if (!esPlacaValida(modalEntrada.placa)) {
    modalEntrada.error = 'Ingresa una placa válida (3 a 10 letras o números)'
    return
  }
  if (!modalEntrada.tipoId) {
    modalEntrada.error = 'Selecciona el tipo de vehículo'
    return
  }
  const tipo = tipoSeleccionado.value
  if (!forzar && tipo && ocupadosTipo(tipo.id) >= (tipo.capacidad || 0)) {
    modalEntrada.avisoCapacidad = true
    return
  }

  modalEntrada.guardando = true
  try {
    const tarifa = tarifas.value.find(t => t.id === modalEntrada.tarifaId)
    const res = await ocupacionService.registrarEntrada({
      parqueaderoId: authStore.parqueaderoId,
      placa: modalEntrada.placa,
      tipoVehiculoId: modalEntrada.tipoId,
      tarifaId: modalEntrada.tarifaId || null,
      tipoNombre: tipo?.nombre || ''
    })
    modalEntrada.abierto = false
    modalEntrada.avisoCapacidad = false
    await mostrarTicket({
      registro_id: res.registro_id,
      placa: res.placa,
      tipoNombre: tipo?.nombre || '',
      entrada_at: res.entrada_at,
      tarifaNombre: tarifa?.nombre || '',
      es_mensual: !!res.es_mensual,
      mensualidad: res.mensualidad || null,
      sobrecupo: !!res.sobrecupo,
      offline: !!res.offline
    })
    if (res.offline) {
      vehiculosDentro.value = ocupacionService.obtenerVehiculosDentroCache() || vehiculosDentro.value
    } else {
      cargarDatos()
    }
  } catch (err) {
    modalEntrada.avisoCapacidad = false
    modalEntrada.error = mensajeDeError(err, 'No se pudo registrar la entrada')
  } finally {
    modalEntrada.guardando = false
  }
}

// ---------- Ticket (HU-27) ----------
const ticket = reactive({ abierto: false, datos: null, qr: '', mostrarQR: false })

async function mostrarTicket(datos) {
  ticket.datos = datos
  ticket.qr = ''
  ticket.mostrarQR = modoTicket.value === 'qr'
  if (modoTicket.value !== 'ninguno' && datos.registro_id) {
    try {
      ticket.qr = await QRCode.toDataURL(String(datos.registro_id), { width: 320, margin: 1 })
    } catch (e) {
      ticket.qr = ''
    }
  }

  if (modoTicket.value === 'ninguno') {
    // Sin ticket: solo informar (y mostrar avisos de mensualidad si los hay)
    if (datos.es_mensual || datos.mensualidad || datos.sobrecupo) {
      ticket.abierto = true
    } else {
      avisar(`Entrada registrada: ${datos.placa}${datos.offline ? ' (pendiente de sincronizar)' : ''}`)
    }
    return
  }

  ticket.abierto = true
  if (modoTicket.value === 'termica') {
    await nextTick()
    imprimirTicket()
  }
}

function imprimirTicket() {
  try {
    let estilo = document.getElementById('pc-ticket-page')
    if (!estilo) {
      estilo = document.createElement('style')
      estilo.id = 'pc-ticket-page'
      document.head.appendChild(estilo)
    }
    estilo.textContent = `@media print { @page { size: ${anchoTicket.value}mm auto; margin: 0; } }`
    document.body.classList.add('pc-imprimiendo-ticket')
    const limpiar = () => {
      document.body.classList.remove('pc-imprimiendo-ticket')
      window.removeEventListener('afterprint', limpiar)
    }
    window.addEventListener('afterprint', limpiar)
    window.print()
    setTimeout(limpiar, 1500)
  } catch (e) {
    // Si la impresión falla, se muestra el QR en pantalla
    ticket.mostrarQR = true
  }
}

async function compartirQR() {
  if (!ticket.qr) return
  const nombre = `ticket-${ticket.datos?.placa || 'parqueadero'}.png`
  try {
    const blob = await (await fetch(ticket.qr)).blob()
    const archivo = new File([blob], nombre, { type: 'image/png' })
    if (navigator.canShare && navigator.canShare({ files: [archivo] })) {
      await navigator.share({ files: [archivo], title: `Ticket ${ticket.datos?.placa}` })
      return
    }
  } catch (e) {
    if (e?.name === 'AbortError') return
  }
  const a = document.createElement('a')
  a.href = ticket.qr
  a.download = nombre
  a.click()
}

function cerrarTicket() {
  ticket.abierto = false
}

// ---------- Búsqueda por placa / QR ----------
const modalPlaca = reactive({ abierto: false, placa: '', error: '' })
function abrirSalidaPorPlaca() {
  Object.assign(modalPlaca, { abierto: true, placa: '', error: '' })
  nextTick(() => inputPlacaSalida.value?.focus())
}
function buscarPorPlaca() {
  const placa = normalizarPlaca(modalPlaca.placa)
  const v = vehiculosDentro.value.find(x => x.placa === placa)
  if (!v) {
    modalPlaca.error = `La placa ${placa || ''} no está dentro del parqueadero`
    return
  }
  modalPlaca.abierto = false
  abrirCobro(v)
}

const escaner = reactive({ abierto: false, error: '' })
let instanciaEscaner = null
async function abrirEscaner() {
  escaner.abierto = true
  escaner.error = ''
  await nextTick()
  try {
    const { default: QrScanner } = await import('qr-scanner')
    if (!(await QrScanner.hasCamera())) {
      escaner.error = 'Este dispositivo no tiene cámara disponible. Usa "Salida por placa".'
      return
    }
    instanciaEscaner = new QrScanner(videoEscaner.value, resultado => {
      const id = String(resultado?.data || resultado || '').trim()
      const v = vehiculosDentro.value.find(x => x.id === id)
      if (v) {
        cerrarEscaner()
        abrirCobro(v)
      } else {
        escaner.error = 'Este ticket no corresponde a un vehículo dentro (puede que ya haya salido).'
      }
    }, { returnDetailedScanResult: true, highlightScanRegion: true })
    await instanciaEscaner.start()
  } catch (e) {
    const msg = String(e?.message || e || '')
    escaner.error = msg.toLowerCase().includes('permission') || e?.name === 'NotAllowedError'
      ? 'No hay permiso para usar la cámara. Habilítalo en el navegador o usa "Salida por placa".'
      : 'No se pudo iniciar la cámara. Usa "Salida por placa".'
  }
}
function cerrarEscaner() {
  if (instanciaEscaner) {
    try {
      instanciaEscaner.stop()
      instanciaEscaner.destroy()
    } catch (e) {}
    instanciaEscaner = null
  }
  escaner.abierto = false
}

// ---------- Salida y cobro (HU-13) ----------
const cobro = reactive({ abierto: false, registro: null, tarifaId: null, cotizacion: null, cargando: false, guardando: false, error: '', metodoPagoId: null, pagaCon: null })
const tarifasDelTipoCobro = computed(() => cobro.registro ? tarifasGeneralesDe(cobro.registro.tipo_vehiculo_id) : [])
const metodoSeleccionado = computed(() => metodosActivos.value.find(m => m.id === cobro.metodoPagoId))
const metodoEsEfectivo = computed(() => !!metodoSeleccionado.value?.es_efectivo)
const vuelto = computed(() => (Number(cobro.pagaCon) || 0) - (cobro.cotizacion?.valor || 0))
const puedeConfirmarSalida = computed(() => {
  const c = cobro.cotizacion
  if (!c) return false
  if (c.valor === 0) return true
  if (!turnoAbierto.value || !cobro.metodoPagoId) return false
  if (metodoEsEfectivo.value && cobro.pagaCon && vuelto.value < 0) return false
  return true
})

async function abrirCobro(v) {
  Object.assign(cobro, {
    abierto: true,
    registro: v,
    tarifaId: v.tarifa_id || null,
    cotizacion: null,
    error: '',
    guardando: false,
    pagaCon: null,
    metodoPagoId: metodosActivos.value[0]?.id || null
  })
  // Asegurar estado de caja actualizado antes de cobrar
  cajaService.obtenerTurnoActual(authStore.parqueaderoId).then(t => { turno.value = t }).catch(() => {})
  await cotizar()
}

async function cotizar() {
  cobro.cargando = true
  cobro.error = ''
  try {
    cobro.cotizacion = await ocupacionService.cotizarSalida({
      parqueaderoId: authStore.parqueaderoId,
      registro: cobro.registro,
      tarifaId: cobro.tarifaId,
      zonaHoraria: zona.value
    })
    if (cobro.cotizacion?.tarifa_id && !cobro.tarifaId) cobro.tarifaId = cobro.cotizacion.tarifa_id
  } catch (err) {
    cobro.cotizacion = null
    cobro.error = mensajeDeError(err, 'No se pudo calcular el cobro')
  } finally {
    cobro.cargando = false
  }
}

function cerrarCobro() {
  cobro.abierto = false
}

async function confirmarSalida() {
  if (!puedeConfirmarSalida.value) return
  cobro.guardando = true
  cobro.error = ''
  const c = cobro.cotizacion
  const registro = cobro.registro
  try {
    const res = await ocupacionService.registrarSalida({
      parqueaderoId: authStore.parqueaderoId,
      registroId: registro.id,
      metodoPagoId: c.valor > 0 ? cobro.metodoPagoId : null,
      tarifaId: cobro.tarifaId,
      valorCobradoOffline: c.offline ? c.valor : null,
      salidaAtOffline: c.offline ? c.salida_at : null
    })
    const valor = res.valor ?? c.valor
    const metodo = c.valor > 0 ? metodoSeleccionado.value?.nombre : null
    Object.assign(salidaOk, {
      abierto: true,
      generando: false,
      error: '',
      clienteNombre: '',
      clienteDocumento: '',
      datos: {
        registroId: registro.id,
        placa: registro.placa,
        tipoNombre: nombreTipo(registro),
        valor,
        minutos: res.minutos ?? c.minutos,
        metodo,
        vuelto: metodoEsEfectivo.value && cobro.pagaCon ? (Number(cobro.pagaCon) || 0) - valor : 0,
        entrada_at: registro.entrada_at,
        salida_at: res.salida_at || c.salida_at,
        tarifa: res.tarifa_nombre || c.tarifa_nombre || '',
        offline: !!res.offline
      }
    })
    cobro.abierto = false
    vehiculosDentro.value = vehiculosDentro.value.filter(v => v.id !== registro.id)
    if (!res.offline) cargarDatos()
  } catch (err) {
    cobro.error = mensajeDeError(err, 'No se pudo registrar la salida')
  } finally {
    cobro.guardando = false
  }
}

// ---------- Comprobante (HU-20) ----------
const salidaOk = reactive({ abierto: false, datos: {}, clienteNombre: '', clienteDocumento: '', generando: false, error: '' })
const comprobanteProvisional = computed(() => !conexionStore.isOnline || !!salidaOk.datos?.offline)
const esCelular = () => typeof window !== 'undefined' && window.matchMedia('(max-width: 640px)').matches

async function generarComprobante() {
  salidaOk.generando = true
  salidaOk.error = ''
  const d = salidaOk.datos
  try {
    if (comprobanteProvisional.value) {
      await comprobanteService.descargarProvisional({
        parqueadero: authStore.parqueadero,
        valor: d.valor,
        clienteNombre: salidaOk.clienteNombre,
        clienteDocumento: salidaOk.clienteDocumento,
        detalle: {
          tipo: 'hora',
          placa: d.placa,
          tipo_vehiculo: d.tipoNombre,
          entrada_at: d.entrada_at,
          salida_at: d.salida_at,
          minutos: d.minutos,
          tarifa: d.tarifa,
          metodo_pago: d.metodo,
          usuario: authStore.userName
        }
      })
    } else {
      const r = await comprobanteService.emitir({
        origen: 'registro',
        origenId: d.registroId,
        clienteNombre: salidaOk.clienteNombre,
        clienteDocumento: salidaOk.clienteDocumento
      })
      await comprobanteService.descargarPDF({
        parqueadero: r.parqueadero,
        comprobante: r.comprobante,
        detalle: r.detalle,
        esCopia: r.existente,
        compartir: esCelular()
      })
    }
  } catch (err) {
    salidaOk.error = mensajeDeError(err, 'No se pudo generar el comprobante')
  } finally {
    salidaOk.generando = false
  }
}

// ---------- Anular (HU-15) ----------
const anular = reactive({ abierto: false, registro: null, motivo: '', guardando: false, error: '' })
function abrirAnular(v) {
  Object.assign(anular, { abierto: true, registro: v, motivo: '', guardando: false, error: '' })
}
async function confirmarAnular() {
  if (anular.motivo.trim().length < 10) {
    anular.error = 'El motivo debe tener al menos 10 caracteres'
    return
  }
  anular.guardando = true
  anular.error = ''
  try {
    await ocupacionService.anularRegistro(anular.registro.id, anular.motivo)
    vehiculosDentro.value = vehiculosDentro.value.filter(v => v.id !== anular.registro.id)
    anular.abierto = false
    avisar(`Registro ${anular.registro.placa} anulado`)
    cargarDatos()
  } catch (err) {
    anular.error = mensajeDeError(err, 'No se pudo anular el registro')
  } finally {
    anular.guardando = false
  }
}
</script>

<style>
/* Ticket térmico (HU-27): oculto en pantalla, visible solo al imprimir el ticket */
.pc-ticket-termico {
  display: none;
}

@media print {
  body.pc-imprimiendo-ticket * {
    visibility: hidden !important;
  }
  body.pc-imprimiendo-ticket .pc-ticket-termico,
  body.pc-imprimiendo-ticket .pc-ticket-termico * {
    visibility: visible !important;
  }
  body.pc-imprimiendo-ticket .pc-ticket-termico {
    display: block !important;
    position: absolute;
    left: 0;
    top: 0;
    padding: 2mm;
    font-family: 'Courier New', monospace;
    font-size: 10pt;
    line-height: 1.25;
    color: #000;
    background: #fff;
  }
  .pc-ticket-termico p {
    margin: 0 0 1mm 0;
    word-break: break-word;
  }
  .pc-t-centro {
    text-align: center;
  }
  .pc-t-negrita {
    font-weight: bold;
  }
  .pc-t-placa {
    font-size: 16pt;
    font-weight: bold;
    letter-spacing: 2px;
  }
  .pc-t-qr {
    display: block;
    width: 70%;
    margin: 2mm auto;
  }
  .pc-t-pie {
    font-size: 8pt;
  }
}
</style>
