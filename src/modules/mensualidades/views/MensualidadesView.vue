<template>
  <div class="space-y-5 max-w-5xl">
    <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3">
      <div>
        <h2 class="titulo-pagina">Mensualidades</h2>
        <p class="subtitulo-pagina">Agenda de vencimientos, calendario de cobros y clientes mensuales.</p>
      </div>
      <button
        class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg"
        :disabled="!conexionStore.isOnline"
        :title="conexionStore.isOnline ? '' : 'Crear una mensualidad requiere conexión'"
        @click="abrirNueva"
      >
        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>
        <span>Nueva mensualidad</span>
      </button>
    </div>

    <div v-if="mensaje.texto" :class="mensaje.tipo === 'error' ? 'alerta-error' : 'alerta-exito'" role="status">
      {{ mensaje.texto }}
    </div>

    <!-- CONTADORES -->
    <div class="grid grid-cols-2 lg:grid-cols-5 gap-2 md:gap-3">
      <button v-for="c in contadores" :key="c.clave" type="button"
        class="card-craft card-interactiva p-3 md:p-4 text-left"
        :class="[c.clase, filtroAgenda === c.clave ? 'ring-2 ring-primary ring-offset-2 ring-offset-background' : '']"
        :aria-pressed="filtroAgenda === c.clave"
        @click="seleccionarContador(c.clave)">
        <p class="rotulo">{{ c.titulo }}</p>
        <p class="mt-1 text-2xl font-semibold tracking-tight num-tabular">{{ c.count }}</p>
      </button>
      <div class="card-craft p-3 md:p-4 col-span-2 lg:col-span-1 min-w-0">
        <p class="rotulo">Esperado 7 días</p>
        <p class="mt-1 text-xl font-semibold tracking-tight num-tabular truncate">{{ pesos(esperado7Dias) }}</p>
      </div>
    </div>

    <!-- PESTAÑAS -->
    <div class="flex gap-1 border-b border-border" role="tablist">
      <button v-for="t in pestanas" :key="t.clave" type="button" role="tab"
        class="px-3 py-2.5 text-sm font-medium border-b-2 -mb-px transition-colors"
        :class="pestana === t.clave ? 'border-primary text-primary' : 'border-transparent text-text-muted hover:text-text-primary'"
        :aria-selected="pestana === t.clave"
        @click="pestana = t.clave">{{ t.texto }}</button>
    </div>

    <div v-if="cargando && !mensualidades.length" class="vacio py-16">
      <div class="spinner"></div>
      <span class="text-xs">Cargando…</span>
    </div>

    <div v-else-if="!mensualidades.length && pestana !== 'todas'" class="card-craft vacio">
      <p class="font-medium text-text-primary">Aún no hay mensualidades activas</p>
      <p class="text-xs">Registra el primer cliente mensual con "Nueva mensualidad".</p>
    </div>

    <!-- AGENDA -->
    <div v-else-if="pestana === 'agenda'" class="space-y-4">
      <p v-if="filtroAgenda" class="text-xs text-text-secondary">
        Mostrando: <span class="font-semibold text-text-primary">{{ contadores.find(c => c.clave === filtroAgenda)?.titulo }}</span>
        <button type="button" class="ml-1 px-2 py-1.5 text-primary font-medium hover:underline" @click="filtroAgenda = null">Ver todo</button>
      </p>
      <template v-for="g in gruposAgenda" :key="g.clave">
        <section v-if="g.items.length" class="card-craft p-4 md:p-5 space-y-2">
          <h3 class="titulo-seccion flex items-center gap-2">
            <span class="w-2 h-2 rounded-full" :class="g.punto"></span>
            {{ g.titulo }} <span class="badge-neutro text-2xs px-2 py-0.5 rounded-full num-tabular">{{ g.items.length }}</span>
          </h3>
          <ul class="divide-y divide-border-subtle">
            <li v-for="m in g.items" :key="m.id" class="py-3">
              <FilaMensualidad :m="m" />
            </li>
          </ul>
        </section>
      </template>
    </div>

    <!-- CALENDARIO -->
    <div v-else-if="pestana === 'calendario'" class="card-craft p-4 md:p-5 space-y-3">
      <div class="flex items-center justify-between gap-2">
        <button type="button" class="btn-icono border border-border" aria-label="Mes anterior" @click="moverMes(-1)">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M15 19l-7-7 7-7" /></svg>
        </button>
        <h3 class="titulo-seccion capitalize text-center min-w-0 truncate">{{ nombreMes }}</h3>
        <button type="button" class="btn-icono border border-border" aria-label="Mes siguiente" @click="moverMes(1)">
          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M9 5l7 7-7 7" /></svg>
        </button>
      </div>
      <div class="grid grid-cols-7 gap-1 text-center rotulo">
        <span v-for="d in ['L', 'M', 'X', 'J', 'V', 'S', 'D']" :key="d">{{ d }}</span>
      </div>
      <div class="grid grid-cols-7 gap-1">
        <button v-for="(celda, i) in celdasMes" :key="i" type="button" :disabled="!celda"
          class="min-h-[56px] min-w-0 overflow-hidden rounded-lg border p-1 sm:p-1.5 text-left flex flex-col transition-colors"
          :class="[
            !celda ? 'border-transparent' : 'border-border hover:border-primary/50',
            celda && celda.items.length ? 'bg-warning-bg' : '',
            celda && celda.fecha === hoy ? 'ring-1 ring-primary' : '',
            celda && diaSeleccionado === celda.fecha ? '!border-primary bg-primary/10' : ''
          ]"
          @click="celda && (diaSeleccionado = celda.fecha)">
          <template v-if="celda">
            <span class="text-2xs font-semibold num-tabular" :class="celda.fecha === hoy ? 'text-primary' : 'text-text-secondary'">{{ celda.dia }}</span>
            <span v-if="celda.items.length" class="text-2xs font-semibold text-warning leading-tight">{{ celda.items.length }}</span>
            <span v-if="celda.items.length" class="hidden sm:block text-2xs text-text-secondary num-tabular leading-tight">{{ pesosCorto(celda.valor) }}</span>
          </template>
        </button>
      </div>
      <div v-if="diaSeleccionado" class="border-t border-border pt-3 space-y-2">
        <h4 class="titulo-seccion">Vencen el {{ formatearFechaCorta(diaSeleccionado) }}</h4>
        <p v-if="!itemsDiaSeleccionado.length" class="text-xs text-text-muted">Ninguna mensualidad vence este día.</p>
        <ul class="divide-y divide-border-subtle">
          <li v-for="m in itemsDiaSeleccionado" :key="m.id" class="py-3"><FilaMensualidad :m="m" /></li>
        </ul>
      </div>
    </div>

    <!-- TODAS -->
    <div v-else class="card-craft p-4 md:p-5 space-y-3">
      <div class="flex flex-col sm:flex-row sm:items-center gap-2">
        <input v-model="busqueda" type="search" placeholder="Buscar por nombre, documento o placa" aria-label="Buscar"
          class="campo flex-1" />
        <select v-model="orden" class="campo sm:w-56" aria-label="Orden">
          <option value="asc">Vencimiento más próximo</option>
          <option value="desc">Vencimiento más lejano</option>
        </select>
        <label v-if="authStore.isAdmin" class="flex items-center gap-2 py-1.5 text-xs font-medium text-text-secondary whitespace-nowrap cursor-pointer">
          <input v-model="incluirInactivas" type="checkbox" class="rounded" @change="cargarTodas" /> Incluir inactivas
        </label>
      </div>
      <p v-if="!listaTodas.length" class="vacio">No hay resultados.</p>
      <ul class="divide-y divide-border-subtle">
        <li v-for="m in listaTodas" :key="m.id" class="py-3"><FilaMensualidad :m="m" /></li>
      </ul>
    </div>

    <!-- MODAL NUEVA MENSUALIDAD -->
    <div v-if="nueva.abierto" class="modal-fondo" @click.self="nueva.abierto = false">
      <form class="modal-panel max-w-lg" @submit.prevent="guardarNueva">
        <div class="modal-encabezado">
          <h3 class="modal-titulo">Nueva mensualidad</h3>
          <button type="button" class="btn-icono" aria-label="Cerrar" @click="nueva.abierto = false">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <div v-if="!turnoAbierto" class="alerta-aviso">
          <span>
            No hay un turno de caja abierto: el primer pago no se puede registrar.
            <router-link to="/caja" class="underline font-semibold">Abrir turno</router-link>
          </span>
        </div>
        <p class="rotulo">Cliente</p>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div><label for="nm-nombre" class="etiqueta">Nombre completo</label><input id="nm-nombre" v-model="nueva.nombre" required class="campo" /></div>
          <div><label for="nm-doc" class="etiqueta">Documento</label><input id="nm-doc" v-model="nueva.documento" required class="campo" /></div>
          <div><label for="nm-tel" class="etiqueta">Teléfono</label><input id="nm-tel" v-model="nueva.telefono" type="tel" inputmode="tel" autocomplete="off" class="campo" /></div>
          <div><label for="nm-email" class="etiqueta">Email (opcional)</label><input id="nm-email" v-model="nueva.email" type="email" autocomplete="off" autocapitalize="off" class="campo" /></div>
        </div>
        <p class="rotulo pt-1">Vehículo y plan</p>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div><label for="nm-placa" class="etiqueta">Placa</label><input id="nm-placa" v-model="nueva.placa" required placeholder="ABC123" autocapitalize="characters" autocomplete="off" autocorrect="off" spellcheck="false" class="campo uppercase font-mono tracking-wider" /></div>
          <div>
            <label for="nm-tipo" class="etiqueta">Tipo de vehículo</label>
            <select id="nm-tipo" v-model="nueva.tipoVehiculoId" required class="campo" @change="nueva.planId = ''">
              <option value="" disabled>Selecciona</option>
              <option v-for="t in tiposActivos" :key="t.id" :value="t.id">{{ t.nombre }}</option>
            </select>
          </div>
          <div>
            <label for="nm-plan" class="etiqueta">Plan</label>
            <select id="nm-plan" v-model="nueva.planId" required class="campo" :disabled="!nueva.tipoVehiculoId">
              <option value="" disabled>{{ planesDelTipo.length || !nueva.tipoVehiculoId ? 'Selecciona' : 'Sin planes para este tipo' }}</option>
              <option v-for="p in planesDelTipo" :key="p.id" :value="p.id">{{ p.nombre }} · {{ pesos(p.valor) }}</option>
            </select>
          </div>
          <div>
            <label for="nm-inicio" class="etiqueta">Fecha de inicio (día de cobro)</label>
            <input id="nm-inicio" v-model="nueva.fechaInicio" type="date" required class="campo" />
          </div>
        </div>
        <div v-if="previaPeriodo" class="alerta-info flex-col gap-0.5">
          <p class="font-semibold">Primer periodo: {{ formatearFechaCorta(previaPeriodo.desde) }} – {{ formatearFechaCorta(previaPeriodo.hasta) }} · {{ pesos(planNueva?.valor) }}</p>
          <p class="font-normal">Siguientes: {{ previaSiguientes }}</p>
        </div>
        <p class="rotulo pt-1">Primer pago</p>
        <div>
          <label for="nm-metodo" class="etiqueta">Método de pago</label>
          <select id="nm-metodo" v-model="nueva.metodoPagoId" required class="campo">
            <option value="" disabled>Selecciona</option>
            <option v-for="mp in metodosActivos" :key="mp.id" :value="mp.id">{{ mp.nombre }}</option>
          </select>
        </div>
        <div v-if="nueva.error" class="alerta-error">{{ nueva.error }}</div>
        <div class="flex flex-col-reverse sm:flex-row gap-2 sm:justify-end pt-1">
          <button type="button" class="btn-craft-subtle w-full sm:w-auto text-sm px-4 py-2.5 sm:py-2 rounded-lg" @click="nueva.abierto = false">Cancelar</button>
          <button type="submit" class="btn-craft-primary w-full sm:w-auto text-sm px-4 py-2.5 sm:py-2 rounded-lg" :disabled="nueva.guardando || !turnoAbierto">
            {{ nueva.guardando ? 'Guardando…' : 'Crear y cobrar' }}
          </button>
        </div>
      </form>
    </div>

    <!-- MODAL DETALLE -->
    <div v-if="detalle.abierto" class="modal-fondo z-40" @click.self="detalle.abierto = false">
      <div class="modal-panel max-w-lg">
        <div class="modal-encabezado items-start">
          <div class="min-w-0">
            <h3 class="modal-titulo break-words">{{ detalle.m.clientes?.nombre }}</h3>
            <p class="text-xs text-text-secondary break-words">Doc. {{ detalle.m.clientes?.documento }}</p>
            <p class="text-xs mt-0.5 flex flex-wrap gap-x-1">
              <a v-if="detalle.m.clientes?.telefono" :href="`tel:${detalle.m.clientes.telefono}`" class="inline-block py-1.5 pr-2 text-primary font-medium num-tabular hover:underline">{{ detalle.m.clientes.telefono }}</a>
              <a v-if="whatsapp(detalle.m)" :href="whatsapp(detalle.m)" target="_blank" rel="noopener" class="inline-block py-1.5 pr-2 font-medium text-success hover:underline">WhatsApp</a>
            </p>
          </div>
          <div class="flex items-center gap-2 shrink-0">
            <span class="plate-colombia plate-carro text-sm">{{ detalle.m.vehiculos?.placa }}</span>
            <button type="button" class="btn-icono" aria-label="Cerrar" @click="detalle.abierto = false">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
            </button>
          </div>
        </div>
        <dl class="grid grid-cols-2 gap-3 text-xs [&_dd]:break-words">
          <div><dt class="text-text-muted">Plan</dt><dd class="font-semibold">{{ detalle.m.planes_mensuales?.nombre }} · {{ pesos(detalle.m.planes_mensuales?.valor) }}</dd></div>
          <div><dt class="text-text-muted">Estado</dt><dd class="font-semibold" :class="claseEstado(detalle.m)">{{ textoEstado(detalle.m) }}</dd></div>
          <div><dt class="text-text-muted">Vence / próximo cobro</dt><dd class="font-semibold">{{ formatearFechaCorta(detalle.m.fecha_fin) }}</dd></div>
          <div><dt class="text-text-muted">Día de cobro</dt><dd class="font-semibold">{{ detalle.m.dia_corte }}</dd></div>
        </dl>
        <div v-if="detalle.m.activa !== false" class="flex flex-wrap gap-2">
          <button type="button" class="btn-craft-primary text-xs px-3 py-2.5 sm:py-1.5 rounded-lg" @click="abrirPago(detalle.m)">Registrar pago</button>
          <button type="button" class="btn-craft-subtle text-xs px-3 py-2.5 sm:py-1.5 rounded-lg" @click="abrirAviso(detalle.m)">Marcar avisado</button>
          <button v-if="authStore.isAdmin" type="button" class="btn-craft-subtle text-xs px-3 py-2.5 sm:py-1.5 rounded-lg !text-danger" @click="detalle.confirmarDesactivar = true">Desactivar</button>
        </div>
        <div v-if="detalle.confirmarDesactivar" class="alerta-error flex-col gap-2">
          <p>¿Desactivar esta mensualidad? El cliente dejará de aparecer en la agenda; sus pagos se conservan.</p>
          <div class="flex flex-wrap gap-2">
            <button type="button" class="btn-craft-subtle text-xs px-3 py-2.5 sm:py-1.5 rounded-lg" @click="detalle.confirmarDesactivar = false">Cancelar</button>
            <button type="button" class="btn-craft-danger text-xs px-3 py-2.5 sm:py-1.5 rounded-lg" @click="desactivar">Sí, desactivar</button>
          </div>
        </div>

        <div class="space-y-2 pt-1">
          <h4 class="rotulo">Pagos</h4>
          <p v-if="detalle.cargandoPagos" class="text-xs text-text-muted">Cargando…</p>
          <p v-else-if="!detalle.pagos.length" class="text-xs text-text-muted">Sin pagos registrados.</p>
          <ul class="divide-y divide-border-subtle">
            <li v-for="p in detalle.pagos" :key="p.id" class="py-2 text-xs flex flex-wrap items-center justify-between gap-2">
              <div class="min-w-0" :class="p.anulado ? 'line-through text-text-muted' : ''">
                <p class="font-semibold num-tabular">{{ formatearFechaCorta(p.periodo_desde) }} – {{ formatearFechaCorta(p.periodo_hasta) }} · {{ pesos(p.valor) }}</p>
                <p class="text-text-secondary">{{ p.metodos_pago?.nombre }} · {{ p.profiles?.nombre }}</p>
              </div>
              <span v-if="p.anulado" class="badge-pastel-rose px-2 py-0.5 rounded-full text-2xs" :title="p.motivo_anulacion">Anulado</span>
              <div v-else class="flex gap-1">
                <button type="button" class="px-2 py-2 font-medium text-primary hover:underline" @click="descargarComprobantePago(p.id, detalle.m)">Comprobante</button>
                <button v-if="authStore.isAdmin" type="button" class="px-2 py-2 font-medium text-danger hover:underline" @click="anulacion = { abierto: true, pago: p, motivo: '', error: '', guardando: false }">Anular</button>
              </div>
            </li>
          </ul>
        </div>

        <div class="space-y-1">
          <h4 class="rotulo">Avisos</h4>
          <p v-if="!(detalle.m.avisos_mensualidad || []).length" class="text-xs text-text-muted">Sin avisos registrados.</p>
          <p v-for="a in avisosOrdenados(detalle.m)" :key="a.id" class="text-xs text-text-secondary break-words">
            {{ formatearFechaHora(a.created_at, authStore.zonaHoraria) }} · {{ textoMedio(a.medio) }}<span v-if="a.profiles?.nombre"> · {{ a.profiles.nombre }}</span><span v-if="a.nota" class="text-text-muted"> — {{ a.nota }}</span>
          </p>
        </div>
        <div class="flex sm:justify-end pt-1">
          <button type="button" class="btn-craft-subtle w-full sm:w-auto text-sm px-4 py-2.5 sm:py-2 rounded-lg" @click="detalle.abierto = false">Cerrar</button>
        </div>
      </div>
    </div>

    <!-- MODAL ANULAR PAGO -->
    <div v-if="anulacion.abierto" class="modal-fondo" @click.self="anulacion.abierto = false">
      <form class="modal-panel max-w-sm" @submit.prevent="anularPago">
        <div class="modal-encabezado">
          <h3 class="modal-titulo min-w-0">Anular pago de <span class="num-tabular">{{ pesos(anulacion.pago?.valor) }}</span></h3>
          <button type="button" class="btn-icono shrink-0" aria-label="Cerrar" @click="anulacion.abierto = false">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <p class="text-xs text-text-secondary">La vigencia se recalculará con los pagos restantes.</p>
        <div>
          <label for="an-motivo" class="etiqueta">Motivo (mínimo 10 caracteres)</label>
          <textarea id="an-motivo" v-model="anulacion.motivo" rows="3" minlength="10" required class="campo"></textarea>
        </div>
        <div v-if="anulacion.error" class="alerta-error">{{ anulacion.error }}</div>
        <div class="flex flex-col-reverse sm:flex-row gap-2 sm:justify-end pt-1">
          <button type="button" class="btn-craft-subtle w-full sm:w-auto text-sm px-4 py-2.5 sm:py-2 rounded-lg" @click="anulacion.abierto = false">Cancelar</button>
          <button type="submit" class="btn-craft-danger w-full sm:w-auto text-sm px-4 py-2.5 sm:py-2 rounded-lg" :disabled="anulacion.guardando || anulacion.motivo.trim().length < 10">Anular</button>
        </div>
      </form>
    </div>

    <!-- MODAL REGISTRAR PAGO -->
    <div v-if="pago.abierto" class="modal-fondo" @click.self="pago.abierto = false">
      <form class="modal-panel max-w-sm" @submit.prevent="guardarPago">
        <div class="modal-encabezado">
          <div class="min-w-0">
            <h3 class="modal-titulo">Registrar pago</h3>
            <p class="text-xs text-text-secondary truncate">{{ pago.m.clientes?.nombre }} · <span class="font-mono">{{ pago.m.vehiculos?.placa }}</span></p>
          </div>
          <button type="button" class="btn-icono shrink-0" aria-label="Cerrar" @click="pago.abierto = false">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <div v-if="!turnoAbierto && conexionStore.isOnline" class="alerta-aviso">
          <span>No hay turno de caja abierto. <router-link to="/caja" class="underline font-semibold">Abrir turno</router-link></span>
        </div>
        <div class="text-xs">
          <p class="text-text-muted">Plan</p>
          <p class="font-semibold">{{ pago.m.planes_mensuales?.nombre }}</p>
        </div>
        <div>
          <label for="pg-valor" class="etiqueta">Valor</label>
          <input v-if="authStore.isAdmin" id="pg-valor" v-model.number="pago.valor" type="number" min="0" step="1" inputmode="numeric" class="campo num-tabular" />
          <p v-else class="text-2xl font-semibold tracking-tight num-tabular">{{ pesos(pago.valor) }}</p>
        </div>
        <fieldset v-if="pago.m.clasificacion?.estado === 'vencida'" class="space-y-2 text-xs">
          <legend class="font-semibold text-danger mb-1">La mensualidad está vencida. ¿Desde cuándo se cobra?</legend>
          <label class="flex items-start gap-2 py-1 text-text-secondary cursor-pointer"><input v-model="pago.reiniciar" type="radio" :value="false" class="mt-0.5" />
            <span>Desde la fecha de vencimiento ({{ formatearFechaCorta(pago.m.fecha_fin) }}); conserva su día de cobro</span></label>
          <label class="flex items-start gap-2 py-1 text-text-secondary cursor-pointer"><input v-model="pago.reiniciar" type="radio" :value="true" class="mt-0.5" />
            <span>Reiniciar desde hoy; el día de cobro pasa a ser hoy</span></label>
        </fieldset>
        <div>
          <label for="pg-metodo" class="etiqueta">Método de pago</label>
          <select id="pg-metodo" v-model="pago.metodoPagoId" required class="campo">
            <option value="" disabled>Selecciona</option>
            <option v-for="mp in metodosActivos" :key="mp.id" :value="mp.id">{{ mp.nombre }}</option>
          </select>
        </div>
        <div v-if="pago.error" class="alerta-error">{{ pago.error }}</div>
        <div class="flex flex-col-reverse sm:flex-row gap-2 sm:justify-end pt-1">
          <button type="button" class="btn-craft-subtle w-full sm:w-auto text-sm px-4 py-2.5 sm:py-2 rounded-lg" @click="pago.abierto = false">Cancelar</button>
          <button type="submit" class="btn-craft-success w-full sm:w-auto text-sm px-4 py-2.5 sm:py-2 rounded-lg" :disabled="pago.guardando || (conexionStore.isOnline && !turnoAbierto)">
            {{ pago.guardando ? 'Registrando…' : 'Registrar pago' }}
          </button>
        </div>
      </form>
    </div>

    <!-- MODAL MARCAR AVISADO -->
    <div v-if="aviso.abierto" class="modal-fondo" @click.self="aviso.abierto = false">
      <form class="modal-panel max-w-sm" @submit.prevent="guardarAviso">
        <div class="modal-encabezado">
          <div class="min-w-0">
            <h3 class="modal-titulo">Marcar avisado</h3>
            <p class="text-xs text-text-secondary truncate">{{ aviso.m?.clientes?.nombre }} · <span class="font-mono">{{ aviso.m?.vehiculos?.placa }}</span></p>
          </div>
          <button type="button" class="btn-icono shrink-0" aria-label="Cerrar" @click="aviso.abierto = false">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
          </button>
        </div>
        <div>
          <span class="etiqueta">Medio</span>
          <div class="grid grid-cols-3 gap-2">
            <button v-for="op in medios" :key="op.valor" type="button"
              class="text-xs px-2 py-2.5 rounded-lg border font-medium transition-colors"
              :class="aviso.medio === op.valor ? 'border-primary bg-primary/10 text-primary' : 'border-border text-text-secondary hover:bg-surface-elevated'"
              @click="aviso.medio = op.valor">{{ op.texto }}</button>
          </div>
        </div>
        <div>
          <label for="av-nota" class="etiqueta">Nota (opcional)</label>
          <textarea id="av-nota" v-model="aviso.nota" rows="2" class="campo"></textarea>
        </div>
        <div v-if="aviso.error" class="alerta-error">{{ aviso.error }}</div>
        <div class="flex flex-col-reverse sm:flex-row gap-2 sm:justify-end pt-1">
          <button type="button" class="btn-craft-subtle w-full sm:w-auto text-sm px-4 py-2.5 sm:py-2 rounded-lg" @click="aviso.abierto = false">Cancelar</button>
          <button type="submit" class="btn-craft-primary w-full sm:w-auto text-sm px-4 py-2.5 sm:py-2 rounded-lg" :disabled="aviso.guardando">Guardar aviso</button>
        </div>
      </form>
    </div>

    <!-- RESULTADO / COMPROBANTE -->
    <div v-if="resultado.abierto" class="modal-fondo" @click.self="resultado.abierto = false">
      <div class="modal-panel max-w-sm text-center">
        <div class="mx-auto w-12 h-12 rounded-full bg-success-bg border border-success-border text-success flex items-center justify-center">
          <svg class="w-6 h-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2.5" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
        </div>
        <h3 class="modal-titulo">{{ resultado.titulo }}</h3>
        <p class="text-sm text-text-secondary num-tabular break-words">{{ resultado.detalle }}</p>
        <div v-if="resultado.error" class="alerta-error text-left">{{ resultado.error }}</div>
        <div class="flex flex-col gap-2 pt-1">
          <button v-if="resultado.pagoId" type="button" class="btn-craft-primary text-sm px-4 py-2.5 rounded-lg" :disabled="resultado.generando"
            @click="descargarComprobantePago(resultado.pagoId, resultado.m)">
            {{ resultado.generando ? 'Generando…' : 'Descargar comprobante' }}
          </button>
          <button type="button" class="btn-craft-subtle text-sm px-4 py-2.5 rounded-lg" @click="resultado.abierto = false">Cerrar</button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, h, watch, onMounted, onActivated, onDeactivated, onBeforeUnmount } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { mensualidadesService } from '@/modules/mensualidades/services/mensualidadesService'
import { ajustesService } from '@/modules/ajustes/services/ajustesService'
import { cajaService } from '@/modules/caja/services/cajaService'
import { comprobanteService } from '@/modules/comprobantes/services/comprobanteService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { generarProximosPeriodos } from '@/domain/periodo'
import { hoyEnZona, sumarDias, formatearFechaCorta, formatearFechaHora } from '@/utils/fecha'

const authStore = useAuthStore()
const conexionStore = useConexionStore()
const route = useRoute()
const router = useRouter()

const mensualidades = ref(mensualidadesService.obtenerMensualidadesCache() || [])
const todas = ref(null) // con inactivas (solo admin)
const cargando = ref(false)
const mensaje = ref({ tipo: '', texto: '' })
const pestana = ref('agenda')
const pestanas = [
  { clave: 'agenda', texto: 'Agenda' },
  { clave: 'calendario', texto: 'Calendario' },
  { clave: 'todas', texto: 'Todas' }
]
const filtroAgenda = ref(null)
const busqueda = ref('')
const orden = ref('asc')
const incluirInactivas = ref(false)

const tipos = ref([])
const planes = ref([])
const metodos = ref([])
const turnoAbierto = ref(false)

const medios = [
  { valor: 'llamada', texto: 'Llamada' },
  { valor: 'en_persona', texto: 'En persona' },
  { valor: 'mensaje', texto: 'Mensaje' }
]

const hoy = computed(() => hoyEnZona(authStore.zonaHoraria))
const tiposActivos = computed(() => tipos.value.filter(t => t.activo !== false))
const metodosActivos = computed(() => metodos.value.filter(m => m.activo !== false))

function pesos(v) {
  return `$${Number(v || 0).toLocaleString('es-CO')}`
}
function pesosCorto(v) {
  const n = Number(v || 0)
  return n >= 1000 ? `$${Math.round(n / 1000)}k` : `$${n}`
}
function textoMedio(medio) {
  return medios.find(x => x.valor === medio)?.texto.toLowerCase() || medio
}
function textoEstado(m) {
  if (m.activa === false) return 'Inactiva'
  const c = m.clasificacion
  if (!c) return ''
  if (c.estado === 'vencida') return `Vencida · ${c.diasMora} ${c.diasMora === 1 ? 'día' : 'días'} de mora`
  if (c.estado === 'por_vencer') return c.esHoy ? 'Vence hoy' : `Por vencer · ${c.diasRestantes} ${c.diasRestantes === 1 ? 'día' : 'días'}`
  return 'Al día'
}
function claseEstado(m) {
  if (m.activa === false) return 'text-text-muted'
  return { rojo: 'text-danger', amarillo: 'text-warning', verde: 'text-success' }[m.clasificacion?.color] || ''
}
function puntoColor(m) {
  if (m.activa === false) return 'bg-text-muted'
  return { rojo: 'bg-danger', amarillo: 'bg-warning', verde: 'bg-success' }[m.clasificacion?.color] || 'bg-text-muted'
}
function textoAviso(m) {
  const a = m.ultimoAviso
  if (!a) return 'Sin avisar'
  const fecha = formatearFechaHora(a.created_at, authStore.zonaHoraria, { hour: undefined, minute: undefined })
  return `Avisado ${fecha} · ${textoMedio(a.medio)}${a.profiles?.nombre ? ' · ' + a.profiles.nombre : ''}`
}
function avisosOrdenados(m) {
  return [...(m.avisos_mensualidad || [])].sort((a, b) => new Date(b.created_at) - new Date(a.created_at))
}
function whatsapp(m) {
  const tel = (m.clientes?.telefono || '').replace(/\D/g, '')
  if (tel.length < 10) return null
  const numero = tel.length === 10 ? `57${tel}` : tel
  const estado = m.clasificacion?.estado === 'vencida'
    ? `venció el ${formatearFechaCorta(m.fecha_fin)}`
    : `vence el ${formatearFechaCorta(m.fecha_fin)}`
  const texto = `Hola ${m.clientes?.nombre || ''}, le recordamos que la mensualidad del vehículo ${m.vehiculos?.placa || ''} ${estado}. Valor: ${pesos(m.planes_mensuales?.valor)}. ¡Gracias!`
  return `https://wa.me/${numero}?text=${encodeURIComponent(texto)}`
}

// Fila reutilizable (render function para no crear archivos nuevos)
const FilaMensualidad = (props) => {
  const m = props.m
  return h('div', { class: 'flex flex-col md:flex-row md:items-center gap-2' }, [
    h('button', { type: 'button', class: 'flex items-start gap-2.5 flex-1 min-w-0 text-left rounded-md hover:opacity-80', onClick: () => abrirDetalle(m) }, [
      h('span', { class: `w-2 h-2 rounded-full mt-2 shrink-0 ${puntoColor(m)}` }),
      h('div', { class: 'min-w-0' }, [
        h('p', { class: 'text-sm font-semibold text-text-primary truncate' }, [`${m.clientes?.nombre || ''} · `, h('span', { class: 'font-mono tracking-wide' }, m.vehiculos?.placa || '')]),
        h('p', { class: 'text-xs text-text-secondary break-words' },
          `${m.planes_mensuales?.nombre || ''} · ${pesos(m.planes_mensuales?.valor)} · día de cobro ${m.dia_corte} · vence ${formatearFechaCorta(m.fecha_fin)}`),
        h('p', { class: `text-2xs font-medium ${claseEstado(m)}` }, `${textoEstado(m)} · ${textoAviso(m)}`)
      ])
    ]),
    h('div', { class: 'flex flex-wrap gap-2 shrink-0 items-center pl-[18px] md:pl-0' }, [
      m.clientes?.telefono ? h('a', { href: `tel:${m.clientes.telefono}`, class: 'py-2 pr-1 text-xs text-primary font-medium num-tabular hover:underline' }, m.clientes.telefono) : null,
      m.activa !== false ? h('button', { type: 'button', class: 'btn-craft-subtle text-xs px-3 py-2.5 md:py-1.5 rounded-lg', onClick: () => abrirAviso(m) }, 'Avisado') : null,
      m.activa !== false ? h('button', { type: 'button', class: 'btn-craft-primary text-xs px-3 py-2.5 md:py-1.5 rounded-lg', onClick: () => abrirPago(m) }, 'Pagar') : null
    ])
  ])
}
FilaMensualidad.props = ['m']

// --- Agenda y contadores ---
function grupoDe(m) {
  const d = m.clasificacion?.diasRestantes ?? 0
  if (m.clasificacion?.estado === 'vencida') return 'vencidas'
  if (d < 0) return 'hoy' // dentro de los días de gracia: se cobra ya
  if (d === 0) return 'hoy'
  if (d === 1) return 'manana'
  if (d <= 7) return 'semana'
  return 'adelante'
}

const contadores = computed(() => {
  const lista = mensualidades.value
  const n = clave => lista.filter(m => clave(m)).length
  return [
    { clave: 'vencidas', titulo: 'Vencidas', count: n(m => grupoDe(m) === 'vencidas'), clase: 'pastel-card-rose' },
    { clave: 'hoy', titulo: 'Vencen hoy', count: n(m => grupoDe(m) === 'hoy'), clase: 'pastel-card-amber' },
    { clave: 'proximos7', titulo: 'Próximos 7 días', count: n(m => ['manana', 'semana'].includes(grupoDe(m))), clase: 'pastel-card-sky' },
    { clave: 'aldia', titulo: 'Al día', count: n(m => m.clasificacion?.estado === 'al_dia'), clase: 'pastel-card-mint' }
  ]
})

const esperado7Dias = computed(() => {
  const limite = sumarDias(hoy.value, 7)
  return mensualidades.value.filter(m => m.fecha_fin <= limite).reduce((s, m) => s + (m.planes_mensuales?.valor || 0), 0)
})

function seleccionarContador(clave) {
  pestana.value = clave === 'aldia' ? 'todas' : 'agenda'
  filtroAgenda.value = filtroAgenda.value === clave ? null : clave
}

const gruposAgenda = computed(() => {
  const defs = [
    { clave: 'vencidas', titulo: 'Vencidas', punto: 'bg-danger' },
    { clave: 'hoy', titulo: 'Vencen hoy', punto: 'bg-warning' },
    { clave: 'manana', titulo: 'Vencen mañana', punto: 'bg-warning/60' },
    { clave: 'semana', titulo: 'Próximos 7 días', punto: 'bg-primary' },
    { clave: 'adelante', titulo: 'Más adelante', punto: 'bg-success' }
  ]
  const filtro = filtroAgenda.value
  const visibles = filtro === 'proximos7' ? ['manana', 'semana'] : filtro && filtro !== 'aldia' ? [filtro] : null
  return defs
    .filter(d => !visibles || visibles.includes(d.clave))
    .map(d => ({ ...d, items: mensualidades.value.filter(m => grupoDe(m) === d.clave) }))
})

// --- Calendario ---
const mesActual = ref(hoy.value.slice(0, 7))
const diaSeleccionado = ref(null)
const nombreMes = computed(() => {
  const [y, m] = mesActual.value.split('-').map(Number)
  return new Intl.DateTimeFormat('es-CO', { month: 'long', year: 'numeric', timeZone: 'UTC' }).format(new Date(Date.UTC(y, m - 1, 1)))
})
function moverMes(delta) {
  const [y, m] = mesActual.value.split('-').map(Number)
  const d = new Date(Date.UTC(y, m - 1 + delta, 1))
  mesActual.value = `${d.getUTCFullYear()}-${String(d.getUTCMonth() + 1).padStart(2, '0')}`
  diaSeleccionado.value = null
}
const celdasMes = computed(() => {
  const [y, m] = mesActual.value.split('-').map(Number)
  const dias = new Date(Date.UTC(y, m, 0)).getUTCDate()
  const offset = (new Date(Date.UTC(y, m - 1, 1)).getUTCDay() + 6) % 7 // lunes primero
  const celdas = Array(offset).fill(null)
  for (let d = 1; d <= dias; d++) {
    const fecha = `${mesActual.value}-${String(d).padStart(2, '0')}`
    const items = mensualidades.value.filter(x => x.fecha_fin === fecha)
    celdas.push({ dia: d, fecha, items, valor: items.reduce((s, x) => s + (x.planes_mensuales?.valor || 0), 0) })
  }
  return celdas
})
const itemsDiaSeleccionado = computed(() => mensualidades.value.filter(x => x.fecha_fin === diaSeleccionado.value))

// --- Todas ---
const listaTodas = computed(() => {
  const base = incluirInactivas.value && todas.value ? todas.value : mensualidades.value
  const q = busqueda.value.trim().toLowerCase()
  const qPlaca = q.replace(/[^a-z0-9]/g, '')
  let lista = base
  if (filtroAgenda.value === 'aldia') lista = lista.filter(m => m.clasificacion?.estado === 'al_dia' && m.activa !== false)
  if (q) {
    lista = lista.filter(m =>
      (m.clientes?.nombre || '').toLowerCase().includes(q) ||
      (m.clientes?.documento || '').toLowerCase().includes(q) ||
      (qPlaca && (m.vehiculos?.placa || '').toLowerCase().includes(qPlaca)))
  }
  return [...lista].sort((a, b) => orden.value === 'asc' ? a.fecha_fin.localeCompare(b.fecha_fin) : b.fecha_fin.localeCompare(a.fecha_fin))
})

async function cargarTodas() {
  if (!incluirInactivas.value) return
  try {
    todas.value = await mensualidadesService.listarMensualidades(authStore.parqueaderoId, {
      diasAviso: authStore.diasAviso, zonaHoraria: authStore.zonaHoraria, incluirInactivas: true
    })
  } catch (e) {
    mostrar('error', mensajeDeError(e, 'No se pudieron cargar las mensualidades inactivas'))
  }
}

// --- Carga ---
function mostrar(tipo, texto) {
  mensaje.value = { tipo, texto }
  if (tipo !== 'error') setTimeout(() => { if (mensaje.value.texto === texto) mensaje.value = { tipo: '', texto: '' } }, 5000)
}

async function cargar() {
  const pq = authStore.parqueaderoId
  if (!pq) return
  cargando.value = true
  try {
    const [lista, t, p, mp, turno] = await Promise.all([
      mensualidadesService.listarMensualidades(pq, { diasAviso: authStore.diasAviso, zonaHoraria: authStore.zonaHoraria }),
      ajustesService.listarTiposVehiculo(pq),
      ajustesService.listarPlanesMensuales(pq),
      ajustesService.listarMetodosPago(pq),
      cajaService.obtenerTurnoActual(pq).catch(() => null)
    ])
    mensualidades.value = lista
    tipos.value = t
    planes.value = p
    metodos.value = mp
    turnoAbierto.value = turno?.estado === 'abierto'
    if (incluirInactivas.value) await cargarTodas()
    if (detalle.value.abierto) {
      const act = lista.find(x => x.id === detalle.value.m.id)
      if (act) detalle.value.m = act
    }
    abrirPagoDesdeRuta()
  } catch (e) {
    mostrar('error', mensajeDeError(e, 'No se pudieron cargar las mensualidades'))
  } finally {
    cargando.value = false
  }
}

function abrirPagoDesdeRuta() {
  const id = route.query.pagar
  if (!id) return
  const m = mensualidades.value.find(x => x.id === id)
  router.replace({ query: { ...route.query, pagar: undefined } })
  if (m) abrirPago(m)
}
watch(() => route.query.pagar, v => { if (v && mensualidades.value.length) abrirPagoDesdeRuta() })

// --- Nueva mensualidad ---
const nueva = ref({ abierto: false })
function abrirNueva() {
  nueva.value = {
    abierto: true, nombre: '', documento: '', telefono: '', email: '', placa: '',
    tipoVehiculoId: tiposActivos.value.length === 1 ? tiposActivos.value[0].id : '',
    planId: '', fechaInicio: hoy.value,
    metodoPagoId: metodosActivos.value.find(m => m.es_efectivo)?.id || '',
    guardando: false, error: ''
  }
}
const planesDelTipo = computed(() => planes.value.filter(p => p.activo !== false && p.tipo_vehiculo_id === nueva.value.tipoVehiculoId))
const planNueva = computed(() => planes.value.find(p => p.id === nueva.value.planId))
const periodosPrevios = computed(() => {
  if (!planNueva.value || !nueva.value.fechaInicio) return []
  try {
    return generarProximosPeriodos({
      tipoPeriodo: planNueva.value.tipo_periodo,
      duracionDias: planNueva.value.duracion_dias,
      fechaInicio: nueva.value.fechaInicio,
      cantidad: 3
    })
  } catch (e) {
    return []
  }
})
const previaPeriodo = computed(() => periodosPrevios.value[0] || null)
const previaSiguientes = computed(() => periodosPrevios.value.slice(1).map(p => `${formatearFechaCorta(p.desde)} – ${formatearFechaCorta(p.hasta)}`).join(', '))

async function guardarNueva() {
  nueva.value.guardando = true
  nueva.value.error = ''
  try {
    const n = nueva.value
    const res = await mensualidadesService.crearMensualidad({
      nombre: n.nombre, documento: n.documento, telefono: n.telefono, email: n.email,
      placa: n.placa, tipoVehiculoId: n.tipoVehiculoId, planId: n.planId,
      fechaInicio: n.fechaInicio, metodoPagoId: n.metodoPagoId, registrarPrimerPago: true
    })
    nueva.value.abierto = false
    await cargar()
    const m = mensualidades.value.find(x => x.id === res.mensualidad_id) || { clientes: { nombre: n.nombre, documento: n.documento } }
    resultado.value = {
      abierto: true,
      titulo: 'Mensualidad creada',
      detalle: `Periodo ${formatearFechaCorta(res.fecha_inicio)} – ${formatearFechaCorta(res.fecha_fin)} · ${pesos(res.valor)}`,
      pagoId: res.pago_id, m, generando: false, error: ''
    }
  } catch (e) {
    nueva.value.error = mensajeDeError(e, 'No se pudo crear la mensualidad')
  } finally {
    nueva.value.guardando = false
  }
}

// --- Detalle ---
const detalle = ref({ abierto: false, m: null, pagos: [], cargandoPagos: false, confirmarDesactivar: false })
async function abrirDetalle(m) {
  detalle.value = { abierto: true, m, pagos: [], cargandoPagos: true, confirmarDesactivar: false }
  await recargarPagos()
}
async function recargarPagos() {
  if (!detalle.value.m) return
  detalle.value.cargandoPagos = true
  try {
    detalle.value.pagos = conexionStore.isOnline ? await mensualidadesService.listarPagos(detalle.value.m.id) : []
  } catch (e) {
    mostrar('error', mensajeDeError(e, 'No se pudieron cargar los pagos'))
  } finally {
    detalle.value.cargandoPagos = false
  }
}
async function desactivar() {
  try {
    await mensualidadesService.desactivarMensualidad(detalle.value.m.id)
    detalle.value.abierto = false
    mostrar('ok', 'Mensualidad desactivada')
    await cargar()
  } catch (e) {
    mostrar('error', mensajeDeError(e, 'No se pudo desactivar'))
  }
}

const anulacion = ref({ abierto: false, pago: null, motivo: '', error: '', guardando: false })
async function anularPago() {
  anulacion.value.guardando = true
  anulacion.value.error = ''
  try {
    await mensualidadesService.anularPago(anulacion.value.pago.id, anulacion.value.motivo)
    anulacion.value.abierto = false
    mostrar('ok', 'Pago anulado y vigencia recalculada')
    await cargar()
    await recargarPagos()
  } catch (e) {
    anulacion.value.error = mensajeDeError(e, 'No se pudo anular el pago')
  } finally {
    anulacion.value.guardando = false
  }
}

// --- Registrar pago ---
const pago = ref({ abierto: false, m: null })
function abrirPago(m) {
  pago.value = {
    abierto: true, m,
    valor: m.planes_mensuales?.valor || 0,
    valorOriginal: m.planes_mensuales?.valor || 0,
    reiniciar: false,
    metodoPagoId: metodosActivos.value.find(x => x.es_efectivo)?.id || '',
    guardando: false, error: ''
  }
}
async function guardarPago() {
  pago.value.guardando = true
  pago.value.error = ''
  try {
    const p = pago.value
    const editado = authStore.isAdmin && Number(p.valor) !== Number(p.valorOriginal)
    const res = await mensualidadesService.registrarPago({
      mensualidadId: p.m.id,
      metodoPagoId: p.metodoPagoId,
      valor: editado ? parseInt(p.valor, 10) : null,
      reiniciar: p.m.clasificacion?.estado === 'vencida' ? p.reiniciar : false
    })
    pago.value.abierto = false
    if (res.offline) {
      resultado.value = {
        abierto: true, titulo: 'Pago guardado sin conexión',
        detalle: 'Se sincronizará al volver la red. El comprobante oficial se emite después de sincronizar.',
        pagoId: null, m: p.m, generando: false, error: ''
      }
    } else {
      resultado.value = {
        abierto: true, titulo: 'Pago registrado',
        detalle: `Periodo ${formatearFechaCorta(res.periodo_desde)} – ${formatearFechaCorta(res.periodo_hasta)} · ${pesos(res.valor)}`,
        pagoId: res.pago_id, m: p.m, generando: false, error: ''
      }
      await cargar()
      if (detalle.value.abierto) await recargarPagos()
    }
  } catch (e) {
    pago.value.error = mensajeDeError(e, 'No se pudo registrar el pago')
  } finally {
    pago.value.guardando = false
  }
}

// --- Comprobante (HU-21): siempre con el id del pago ---
const resultado = ref({ abierto: false })
async function descargarComprobantePago(pagoId, m) {
  resultado.value.generando = true
  resultado.value.error = ''
  try {
    const datos = await comprobanteService.emitir({
      origen: 'pago_mensualidad',
      origenId: pagoId,
      clienteNombre: m?.clientes?.nombre,
      clienteDocumento: m?.clientes?.documento
    })
    await comprobanteService.descargarPDF({
      parqueadero: { ...authStore.parqueadero, ...datos.parqueadero },
      comprobante: datos.comprobante,
      detalle: datos.detalle,
      esCopia: datos.existente,
      compartir: true
    })
  } catch (e) {
    const msg = mensajeDeError(e, 'No se pudo generar el comprobante')
    if (resultado.value.abierto) resultado.value.error = msg
    else mostrar('error', msg)
  } finally {
    resultado.value.generando = false
  }
}

// --- Avisos ---
const aviso = ref({ abierto: false })
function abrirAviso(m) {
  aviso.value = { abierto: true, m, medio: 'llamada', nota: '', guardando: false, error: '' }
}
async function guardarAviso() {
  aviso.value.guardando = true
  aviso.value.error = ''
  try {
    const res = await mensualidadesService.registrarAviso({
      mensualidadId: aviso.value.m.id,
      medio: aviso.value.medio,
      nota: aviso.value.nota,
      periodoHasta: aviso.value.m.fecha_fin
    })
    aviso.value.abierto = false
    mostrar('ok', res.offline ? 'Aviso guardado sin conexión; se sincronizará después' : 'Aviso registrado')
    await cargar()
  } catch (e) {
    aviso.value.error = mensajeDeError(e, 'No se pudo registrar el aviso')
  } finally {
    aviso.value.guardando = false
  }
}

// --- Ciclo de vida: Realtime + recarga al volver a la vista ---
let cancelarSuscripcion = null
let debounce = null
function suscribir() {
  if (cancelarSuscripcion || !authStore.parqueaderoId) return
  cancelarSuscripcion = mensualidadesService.suscribirCambios(authStore.parqueaderoId, () => {
    clearTimeout(debounce)
    debounce = setTimeout(cargar, 800)
  })
}
function desuscribir() {
  if (cancelarSuscripcion) { cancelarSuscripcion(); cancelarSuscripcion = null }
  clearTimeout(debounce)
}

let primeraActivacion = true
onMounted(() => {
  cargar()
  suscribir()
})
onActivated(() => {
  if (primeraActivacion) {
    primeraActivacion = false
    return
  }
  cargar()
  suscribir()
})
onDeactivated(desuscribir)
onBeforeUnmount(desuscribir)
</script>

