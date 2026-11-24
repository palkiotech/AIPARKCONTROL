<template>
  <div class="space-y-5">
    <!-- Encabezado -->
    <div class="flex flex-col sm:flex-row sm:items-end sm:justify-between gap-3 no-print">
      <div>
        <h2 class="titulo-pagina">Registro y cobro</h2>
        <p class="subtitulo-pagina">Registra entradas y cobra salidas por placa o con el QR del ticket.</p>
      </div>
      <div class="flex flex-wrap items-center gap-2 text-xs">
        <span class="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border font-medium" :class="turnoAbierto ? 'badge-pastel-mint' : 'badge-pastel-amber'">
          <span class="w-1.5 h-1.5 rounded-full" :class="turnoAbierto ? 'bg-success' : 'bg-warning'"></span>
          {{ turnoAbierto ? 'Turno abierto' : (turno?.estado === 'por_recibir' ? 'Turno por recibir' : 'Sin turno') }}
        </span>
        <span class="badge-neutro px-2.5 py-1 rounded-full border font-medium num-tabular">{{ vehiculosDentro.length }} dentro</span>
      </div>
    </div>

    <!-- Feedback -->
    <div v-if="mensajeExito" class="alerta-exito no-print">{{ mensajeExito }}</div>
    <div v-if="errorMensaje" class="alerta-error no-print" role="alert">{{ errorMensaje }}</div>
    <div v-if="!conexionStore.isOnline" class="alerta-aviso no-print">
      Sin conexión: las entradas y salidas se guardan en este dispositivo y se sincronizan al volver internet.
    </div>

    <!-- Bloqueo: sin turno (regla: toda entrada exige turno abierto) -->
    <div v-if="!cargando && !turnoAbierto" class="card-craft p-4 sm:p-5 flex flex-col sm:flex-row sm:items-center gap-3 sm:gap-4 border-warning-border no-print">
      <span class="w-10 h-10 rounded-full bg-warning-bg text-warning flex items-center justify-center shrink-0">
        <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
      </span>
      <div class="flex-1 min-w-0">
        <p class="text-sm font-semibold text-text-primary">
          {{ turno?.estado === 'por_recibir' ? 'El turno anterior está por recibir' : 'No hay un turno de caja abierto' }}
        </p>
        <p class="text-xs text-text-secondary mt-0.5">
          {{ turno?.estado === 'por_recibir'
            ? 'Recíbelo en Caja para continuar. Mientras tanto no se pueden registrar placas ni cobrar.'
            : 'Debes iniciar un turno para registrar placas y cobrar salidas.' }}
        </p>
      </div>
      <router-link :to="{ name: 'caja' }" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg shrink-0">
        {{ turno?.estado === 'por_recibir' ? 'Ir a Caja' : 'Iniciar turno' }}
      </router-link>
    </div>

    <!-- Bloqueo: sin tarifas -->
    <div v-if="!cargando && tiposActivos.length && !tiposConTarifa.length" class="alerta-error flex-col sm:flex-row sm:items-center no-print" role="alert">
      <p class="flex-1">
        <strong class="font-semibold">No hay tarifas definidas.</strong>
        No se pueden registrar vehículos hasta que {{ authStore.isAdmin ? 'configures' : 'un administrador configure' }} al menos una tarifa activa en Ajustes.
      </p>
      <router-link v-if="authStore.isAdmin" :to="{ name: 'ajustes' }" class="btn-craft-subtle text-sm px-3 py-2 rounded-lg shrink-0">Ir a Ajustes</router-link>
    </div>

    <div class="grid grid-cols-1 lg:grid-cols-2 gap-4 sm:gap-5 no-print">
      <!-- ENTRADA (HU-11) -->
      <section class="card-craft p-4 sm:p-5 space-y-4" aria-labelledby="titulo-entrada">
        <div class="flex items-center justify-between gap-2">
          <h3 id="titulo-entrada" class="titulo-seccion flex items-center gap-2">
            <span class="w-7 h-7 rounded-lg bg-success-bg text-success flex items-center justify-center">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4" /></svg>
            </span>
            Entrada
          </h3>
          <span v-if="motivoBloqueoEntrada" class="text-2xs px-2 py-0.5 rounded-full badge-pastel-amber">Bloqueada</span>
        </div>

        <form @submit.prevent="confirmarEntrada(false)">
          <fieldset :disabled="!!motivoBloqueoEntrada" class="space-y-4 disabled:opacity-60">
            <div>
              <label for="entrada-placa" class="etiqueta">Placa</label>
              <input
                id="entrada-placa"
                ref="inputPlaca"
                v-model="entrada.placa"
                type="text"
                autocomplete="off"
                autocapitalize="characters"
                spellcheck="false"
                maxlength="10"
                placeholder="ABC123"
                class="campo px-4 py-3 text-2xl text-center uppercase font-mono font-bold tracking-[0.2em]"
                @input="entrada.avisoCapacidad = false; entrada.error = ''"
              />
              <!-- Atajo: la placa ya está dentro -->
              <div v-if="placaEntradaDentro" class="mt-2 alerta-info flex-col sm:flex-row sm:items-center">
                <p class="flex-1">{{ placaEntradaDentro.placa }} ya está dentro desde las {{ formatearHora(placaEntradaDentro.entrada_at) }}.</p>
                <button type="button" @click="abrirCobro(placaEntradaDentro); entrada.placa = ''" class="btn-craft-primary text-xs px-3 py-2 rounded-lg shrink-0">Cobrar salida</button>
              </div>
            </div>

            <div>
              <span class="etiqueta">Tipo de vehículo</span>
              <div class="grid grid-cols-2 sm:grid-cols-3 gap-2">
                <button
                  v-for="t in tiposActivos"
                  :key="t.id"
                  type="button"
                  @click="seleccionarTipo(t.id)"
                  :disabled="!tarifasGeneralesDe(t.id).length"
                  :title="tarifasGeneralesDe(t.id).length ? t.nombre : 'Sin tarifa activa'"
                  class="py-3 px-2 rounded-lg border text-sm font-semibold transition-colors flex flex-col items-center gap-1 disabled:opacity-50 disabled:cursor-not-allowed"
                  :class="entrada.tipoId === t.id ? 'border-primary bg-primary/10 text-primary ring-1 ring-primary' : 'border-border text-text-secondary hover:border-primary/50 hover:text-text-primary'"
                >
                  <IconoVehiculo :nombre="t.nombre" clase="w-6 h-6" />
                  <span class="max-w-full break-words text-center">{{ t.nombre }}</span>
                  <span class="text-2xs font-medium num-tabular" :class="tarifasGeneralesDe(t.id).length ? 'text-text-muted' : 'text-warning'">
                    {{ tarifasGeneralesDe(t.id).length ? `${ocupadosTipo(t.id)}/${t.capacidad}` : 'Sin tarifa' }}
                  </span>
                </button>
              </div>
              <p v-if="!cargando && !tiposActivos.length" class="text-sm text-text-muted">No hay tipos de vehículo activos. Un administrador debe configurarlos en Ajustes.</p>
            </div>

            <div v-if="tarifasDelTipoEntrada.length > 1">
              <label for="entrada-tarifa" class="etiqueta">Tarifa</label>
              <select id="entrada-tarifa" v-model="entrada.tarifaId" class="campo">
                <option v-for="t in tarifasDelTipoEntrada" :key="t.id" :value="t.id">
                  {{ t.nombre }} · {{ pesos(t.valor) }} ({{ nombreModalidad(t.modalidad) }}){{ t.es_predeterminada ? ' · predeterminada' : '' }}
                </option>
              </select>
            </div>

            <!-- Aviso de capacidad: nunca bloquea -->
            <div v-if="entrada.avisoCapacidad" class="alerta-aviso flex-col">
              <p class="font-semibold">
                {{ tipoSeleccionado?.nombre }} {{ ocupadosTipo(entrada.tipoId) }}/{{ tipoSeleccionado?.capacidad }}: ya está lleno según la capacidad.
              </p>
              <div class="flex flex-col-reverse sm:flex-row gap-2 w-full">
                <button type="button" @click="entrada.avisoCapacidad = false" class="flex-1 btn-craft-subtle text-sm sm:text-xs px-3 py-2.5 sm:py-2 rounded-lg">Cancelar</button>
                <button type="button" @click="confirmarEntrada(true)" class="flex-1 btn-craft-primary text-sm sm:text-xs px-3 py-2.5 sm:py-2 rounded-lg" :disabled="entrada.guardando">
                  Registrar de todas formas
                </button>
              </div>
            </div>

            <p v-if="entrada.error" class="alerta-error" role="alert">{{ entrada.error }}</p>

            <button
              v-if="!entrada.avisoCapacidad"
              type="submit"
              :disabled="entrada.guardando"
              class="w-full btn-craft-success text-sm px-4 py-3 rounded-lg"
            >
              {{ entrada.guardando ? 'Registrando...' : 'Registrar entrada' }}
            </button>
          </fieldset>
          <p v-if="motivoBloqueoEntrada" class="mt-3 text-xs text-text-muted">{{ motivoBloqueoEntrada }}</p>
        </form>
      </section>

      <!-- SALIDA Y COBRO (HU-13) -->
      <section class="card-craft p-4 sm:p-5 space-y-4" aria-labelledby="titulo-salida">
        <div class="flex items-center justify-between gap-2">
          <h3 id="titulo-salida" class="titulo-seccion flex items-center gap-2">
            <span class="w-7 h-7 rounded-lg bg-primary/10 text-primary flex items-center justify-center">
              <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" /></svg>
            </span>
            Salida y cobro
          </h3>
          <button type="button" @click="abrirEscaner" class="btn-craft-subtle text-xs px-3 py-2 rounded-lg">
            <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7V5a1 1 0 011-1h2m10 0h2a1 1 0 011 1v2m0 10v2a1 1 0 01-1 1h-2M7 20H5a1 1 0 01-1-1v-2m4-5h8" /></svg>
            <span>Escanear QR</span>
          </button>
        </div>

        <form @submit.prevent="buscarPorPlaca" class="flex gap-2">
          <input
            ref="inputPlacaSalida"
            v-model="salida.placa"
            type="text"
            autocomplete="off"
            autocapitalize="characters"
            spellcheck="false"
            maxlength="10"
            aria-label="Placa para la salida"
            placeholder="Placa a cobrar"
            class="campo flex-1 min-w-0 px-4 py-3 text-xl text-center uppercase font-mono font-bold tracking-[0.15em]"
            @input="salida.error = ''"
          />
          <button type="submit" class="btn-craft-primary text-sm px-4 rounded-lg shrink-0">Cobrar</button>
        </form>
        <p v-if="salida.error" class="alerta-error" role="alert">{{ salida.error }}</p>

        <div>
          <p class="rotulo mb-2">{{ normalizarPlaca(salida.placa) ? 'Coincidencias' : 'Últimas entradas' }}</p>
          <div v-if="sugerencias.length" class="divide-y divide-border-subtle border border-border rounded-lg overflow-hidden">
            <button
              v-for="v in sugerencias"
              :key="v.id"
              type="button"
              @click="abrirCobro(v)"
              class="w-full flex items-center justify-between gap-3 px-3 py-2.5 text-left hover:bg-surface-elevated transition-colors"
            >
              <span class="flex items-center gap-2 min-w-0">
                <span class="plate-colombia text-xs shrink-0" :class="clasePlaca(nombreTipo(v))">{{ v.placa }}</span>
                <span class="text-xs text-text-secondary truncate num-tabular">{{ nombreTipo(v) }} · {{ formatearDuracion(minutosTranscurridos(v.entrada_at)) }}</span>
              </span>
              <span class="text-sm font-semibold text-text-primary num-tabular shrink-0">{{ textoEstimado(v) }}</span>
            </button>
          </div>
          <p v-else class="text-sm text-text-muted py-3 text-center">
            {{ normalizarPlaca(salida.placa) ? 'Ninguna placa dentro coincide.' : 'No hay vehículos dentro.' }}
          </p>
        </div>
      </section>
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
        <span class="plate-colombia text-lg inline-block max-w-full break-all" :class="clasePlaca(ticket.datos.tipoNombre)">{{ ticket.datos.placa }}</span>
        <p class="text-xs text-text-secondary">{{ ticket.datos.tipoNombre }} · {{ formatearFechaHora(ticket.datos.entrada_at, zona) }}</p>

        <p v-if="ticket.datos.es_mensual" class="alerta-exito justify-center">
          Mensualidad al día hasta {{ formatearFechaCorta(ticket.datos.mensualidad?.fecha_fin) }}
        </p>
        <p v-else-if="ticket.datos.mensualidad && ticket.datos.mensualidad.vigente === false" class="alerta-error text-left">
          La mensualidad de esta placa está vencida (venció el {{ formatearFechaCorta(ticket.datos.mensualidad.fecha_fin) }}). Se registró como cobro por hora.
        </p>
        <p v-if="ticket.datos.sobrecupo" class="alerta-aviso justify-center">Registrado en sobrecupo.</p>

        <template v-if="ticket.mostrarQR && ticket.qr">
          <img :src="ticket.qr" alt="QR del ticket" class="mx-auto w-full max-w-56 aspect-square rounded-lg border border-border bg-white p-2" />
          <p class="text-xs text-text-muted">El cliente puede tomarle foto al QR para la salida.</p>
          <button @click="compartirQR" class="w-full btn-craft-subtle text-sm px-3 py-2.5 rounded-lg">Compartir / descargar QR</button>
        </template>

        <div v-if="modoTicket === 'termica'" class="flex flex-col sm:flex-row gap-2">
          <button @click="imprimirTicket" class="flex-1 btn-craft-primary text-sm px-3 py-2.5 rounded-lg">Imprimir ticket</button>
          <button v-if="!ticket.mostrarQR" @click="ticket.mostrarQR = true" class="flex-1 btn-craft-subtle text-sm px-3 py-2.5 rounded-lg">Mostrar QR</button>
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
        <p v-else class="text-xs text-text-muted text-center">Apunta la cámara al QR del ticket. Si no hay ticket, escribe la placa.</p>
      </div>
    </div>

    <!-- MODAL COBRO DE SALIDA (HU-13) -->
    <div v-if="cobro.abierto" class="modal-fondo no-print">
      <div class="modal-panel max-w-md">
        <div class="modal-encabezado">
          <div class="flex items-center gap-2 min-w-0">
            <h3 class="modal-titulo">Salida</h3>
            <span class="plate-colombia text-xs truncate" :class="clasePlaca(nombreTipo(cobro.registro))">{{ cobro.registro.placa }}</span>
          </div>
          <button type="button" @click="cerrarCobro" class="btn-icono shrink-0" aria-label="Cerrar">
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
              <dd class="font-medium text-text-primary mt-0.5 break-words">{{ cobro.cotizacion.es_mensual ? 'Mensualidad vigente' : (cobro.cotizacion.tarifa_nombre || '—') }}</dd>
            </div>
          </dl>

          <div v-if="!cobro.cotizacion.es_mensual && tarifasDelTipoCobro.length > 1">
            <label for="cobro-tarifa" class="etiqueta">Cambiar tarifa</label>
            <select id="cobro-tarifa" v-model="cobro.tarifaId" @change="cotizar" class="campo">
              <option v-for="t in tarifasDelTipoCobro" :key="t.id" :value="t.id">{{ t.nombre }} · {{ pesos(t.valor) }}</option>
            </select>
          </div>

          <div v-if="(cobro.cotizacion.desglose || []).length > 1" class="text-xs text-text-secondary space-y-1">
            <p v-for="(d, i) in cobro.cotizacion.desglose" :key="i" class="flex justify-between gap-2">
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
            <p class="font-semibold">No hay un turno de caja abierto. Inicia el turno para poder cobrar.</p>
            <router-link :to="{ name: 'caja' }" class="w-full btn-craft-primary text-sm px-3 py-2.5 rounded-lg" @click="cerrarCobro">Iniciar turno</router-link>
          </div>

          <template v-else-if="cobro.cotizacion.valor > 0">
            <div>
              <span class="etiqueta">Método de pago</span>
              <div class="grid grid-cols-2 gap-2">
                <button
                  v-for="m in metodosActivos"
                  :key="m.id"
                  type="button"
                  @click="cobro.metodoPagoId = m.id"
                  class="py-2.5 px-3 rounded-lg border text-sm font-medium transition-colors break-words"
                  :class="cobro.metodoPagoId === m.id ? 'border-primary bg-primary/10 text-primary ring-1 ring-primary' : 'border-border text-text-secondary hover:border-primary/50 hover:text-text-primary'"
                >
                  {{ m.nombre }}
                </button>
              </div>
              <p v-if="metodosActivos.length === 0" class="alerta-error mt-2">No hay métodos de pago activos. Configúralos en Ajustes.</p>
            </div>

            <div v-if="metodoEsEfectivo" class="space-y-2">
              <label for="cobro-paga-con" class="etiqueta mb-0">Paga con</label>
              <div class="grid grid-cols-5 gap-1.5">
                <button type="button" @click="cobro.pagaCon = cobro.cotizacion.valor" class="btn-craft-subtle text-xs px-1 py-2.5 sm:py-1.5 rounded-lg">Exacto</button>
                <button v-for="b in billetes" :key="b" type="button" @click="cobro.pagaCon = b" class="btn-craft-subtle text-xs px-1 py-2.5 sm:py-1.5 rounded-lg num-tabular">${{ b / 1000 }}k</button>
              </div>
              <input
                id="cobro-paga-con"
                v-model.number="cobro.pagaCon"
                type="number"
                inputmode="numeric"
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
          <span class="plate-colombia text-sm inline-block mt-1 max-w-full break-all" :class="clasePlaca(salidaOk.datos.tipoNombre)">{{ salidaOk.datos.placa }}</span>
          <p class="text-3xl font-semibold tracking-tight num-tabular text-text-primary mt-1 break-words">{{ pesos(salidaOk.datos.valor) }}</p>
          <p class="text-xs text-text-secondary">{{ formatearDuracion(salidaOk.datos.minutos) }}<span v-if="salidaOk.datos.metodo"> · {{ salidaOk.datos.metodo }}</span></p>
          <p v-if="salidaOk.datos.vuelto > 0" class="text-sm font-semibold text-success num-tabular">Vuelto: {{ pesos(salidaOk.datos.vuelto) }}</p>
        </div>

        <div v-if="salidaOk.datos.valor > 0" class="space-y-2 pt-3 border-t border-border">
          <p class="rotulo">Comprobante (opcional)</p>
          <input v-model="salidaOk.clienteNombre" type="text" autocomplete="off" aria-label="Nombre del cliente" placeholder="Nombre (Consumidor final)" class="campo" />
          <input v-model="salidaOk.clienteDocumento" type="text" autocomplete="off" aria-label="Documento o NIT del cliente" placeholder="Documento / NIT" class="campo" />
          <p v-if="salidaOk.error" class="alerta-error" role="alert">{{ salidaOk.error }}</p>
          <button @click="generarComprobante" :disabled="salidaOk.generando" class="w-full btn-craft-subtle text-sm px-4 py-2.5 rounded-lg">
            {{ salidaOk.generando ? 'Generando...' : (comprobanteProvisional ? 'Comprobante provisional (sin conexión)' : 'Generar comprobante PDF') }}
          </button>
        </div>

        <button @click="cerrarSalidaOk" class="w-full btn-craft-success text-sm px-4 py-2.5 rounded-lg">Listo</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, nextTick, onActivated, onDeactivated, onUnmounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import QRCode from 'qrcode'
import { useConexionStore } from '@/stores/conexion'
import { ocupacionService } from '@/modules/ocupacion/services/ocupacionService'
import { comprobanteService } from '@/modules/comprobantes/services/comprobanteService'
import { mensajeDeError } from '@/lib/sesionCaches'
import { normalizarPlaca, esPlacaValida } from '@/utils/placa'
import { formatearFechaHora, formatearFechaCorta } from '@/utils/fecha'
import { usePatio } from '@/modules/ocupacion/composables/usePatio'
import IconoVehiculo from '@/components/IconoVehiculo.vue'

const route = useRoute()
const router = useRouter()
const conexionStore = useConexionStore()
const {
  authStore, zona, tarifas, vehiculosDentro, turno, cargando, errorMensaje,
  pesos, formatearHora, formatearDuracion, minutosTranscurridos, nombreTipo, clasePlaca, nombreModalidad,
  tiposActivos, tiposConTarifa, metodosActivos, turnoAbierto, tarifasGeneralesDe, ocupadosTipo,
  textoEstimado, cargarDatos, refrescarTurno, quitarDelPatio, tomarPatioDeCache
} = usePatio()

const modoTicket = computed(() => authStore.parqueadero?.modo_ticket || 'qr')
const anchoTicket = computed(() => (authStore.parqueadero?.ancho_ticket_mm === 58 ? 58 : 80))
const billetes = [10000, 20000, 50000, 100000]

const mensajeExito = ref('')
const inputPlaca = ref(null)
const inputPlacaSalida = ref(null)
const videoEscaner = ref(null)

function avisar(msg) {
  mensajeExito.value = msg
  setTimeout(() => { if (mensajeExito.value === msg) mensajeExito.value = '' }, 4000)
}
function enfocarEntrada() {
  nextTick(() => { if (!motivoBloqueoEntrada.value) inputPlaca.value?.focus() })
}

// ---------- Entrada (HU-11) ----------
const entrada = reactive({ placa: '', tipoId: '', tarifaId: '', avisoCapacidad: false, guardando: false, error: '' })
const tipoSeleccionado = computed(() => tiposActivos.value.find(t => t.id === entrada.tipoId))
const tarifasDelTipoEntrada = computed(() => entrada.tipoId ? tarifasGeneralesDe(entrada.tipoId) : [])
const placaEntradaDentro = computed(() => {
  const placa = normalizarPlaca(entrada.placa)
  return placa.length >= 3 ? vehiculosDentro.value.find(v => v.placa === placa) : null
})

// Reglas: sin turno abierto o sin tarifas no se registra ninguna placa
const motivoBloqueoEntrada = computed(() => {
  if (cargando.value) return ''
  if (!turnoAbierto.value) return 'Inicia un turno de caja para registrar placas.'
  if (!tiposConTarifa.value.length) return 'No hay tarifas definidas para ningún tipo de vehículo.'
  return ''
})

function seleccionarTipo(tipoId) {
  entrada.tipoId = tipoId
  entrada.avisoCapacidad = false
  const lista = tarifasGeneralesDe(tipoId)
  entrada.tarifaId = (lista.find(t => t.es_predeterminada) || lista[0])?.id || ''
}

// Mantener un tipo válido (con tarifa) seleccionado cuando cambian los catálogos
watch([tiposConTarifa, tarifas], () => {
  if (!tiposConTarifa.value.some(t => t.id === entrada.tipoId)) {
    if (tiposConTarifa.value[0]) seleccionarTipo(tiposConTarifa.value[0].id)
    else Object.assign(entrada, { tipoId: '', tarifaId: '' })
  } else if (!tarifasDelTipoEntrada.value.some(t => t.id === entrada.tarifaId)) {
    seleccionarTipo(entrada.tipoId)
  }
}, { immediate: true })

async function confirmarEntrada(forzar) {
  entrada.error = ''
  // El turno pudo cerrarse en otro dispositivo: confirmar antes de registrar
  await refrescarTurno()
  if (!turnoAbierto.value) {
    entrada.error = 'No hay un turno de caja abierto. Inicia el turno en Caja para registrar placas.'
    return
  }
  if (!esPlacaValida(entrada.placa)) {
    entrada.error = 'Ingresa una placa válida (3 a 10 letras o números)'
    return
  }
  if (!entrada.tipoId) {
    entrada.error = 'Selecciona el tipo de vehículo'
    return
  }
  if (!tarifasGeneralesDe(entrada.tipoId).length) {
    entrada.error = 'Este tipo de vehículo no tiene una tarifa activa. Configúrala en Ajustes.'
    return
  }
  if (placaEntradaDentro.value) {
    entrada.error = `La placa ${placaEntradaDentro.value.placa} ya está dentro.`
    return
  }
  const tipo = tipoSeleccionado.value
  if (!forzar && tipo && ocupadosTipo(tipo.id) >= (tipo.capacidad || 0)) {
    entrada.avisoCapacidad = true
    return
  }

  entrada.guardando = true
  try {
    const tarifa = tarifas.value.find(t => t.id === entrada.tarifaId)
    const res = await ocupacionService.registrarEntrada({
      parqueaderoId: authStore.parqueaderoId,
      placa: entrada.placa,
      tipoVehiculoId: entrada.tipoId,
      tarifaId: entrada.tarifaId || null,
      tipoNombre: tipo?.nombre || ''
    })
    entrada.placa = ''
    entrada.avisoCapacidad = false
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
    if (res.offline) tomarPatioDeCache()
    else cargarDatos()
  } catch (err) {
    entrada.avisoCapacidad = false
    entrada.error = mensajeDeError(err, 'No se pudo registrar la entrada')
    // El servidor pudo rechazarla por turno o tarifas: actualizar el estado
    cargarDatos()
  } finally {
    entrada.guardando = false
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
      enfocarEntrada()
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
  enfocarEntrada()
}

// ---------- Búsqueda por placa / QR ----------
const salida = reactive({ placa: '', error: '' })
const sugerencias = computed(() => {
  const placa = normalizarPlaca(salida.placa)
  const lista = placa
    ? vehiculosDentro.value.filter(v => v.placa.includes(placa))
    : [...vehiculosDentro.value].sort((a, b) => new Date(b.entrada_at) - new Date(a.entrada_at))
  return lista.slice(0, 6)
})

function buscarPorPlaca() {
  const placa = normalizarPlaca(salida.placa)
  if (!placa) {
    salida.error = 'Escribe la placa del vehículo que sale'
    return
  }
  const v = vehiculosDentro.value.find(x => x.placa === placa) || (sugerencias.value.length === 1 ? sugerencias.value[0] : null)
  if (!v) {
    salida.error = `La placa ${placa} no está dentro del parqueadero`
    return
  }
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
    if (!escaner.abierto) return
    if (!(await QrScanner.hasCamera())) {
      escaner.error = 'Este dispositivo no tiene cámara disponible. Escribe la placa.'
      return
    }
    if (!escaner.abierto || !videoEscaner.value) return
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
    // Si el modal se cerró mientras la cámara arrancaba, liberarla
    if (!escaner.abierto) cerrarEscaner()
  } catch (e) {
    const msg = String(e?.message || e || '')
    escaner.error = msg.toLowerCase().includes('permission') || e?.name === 'NotAllowedError'
      ? 'No hay permiso para usar la cámara. Habilítalo en el navegador o escribe la placa.'
      : 'No se pudo iniciar la cámara. Escribe la placa.'
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

// Si el cobro se abrió antes de cargar los métodos (llegada directa), preseleccionar el primero
watch(metodosActivos, (lista) => {
  if (cobro.abierto && !cobro.metodoPagoId && lista[0]) cobro.metodoPagoId = lista[0].id
})

async function abrirCobro(v) {
  salida.error = ''
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
  refrescarTurno()
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
    salida.placa = ''
    quitarDelPatio(registro.id)
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

function cerrarSalidaOk() {
  salidaOk.abierto = false
  nextTick(() => inputPlacaSalida.value?.focus())
}

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

// ---------- Llegada desde Ocupación con ?salida=<registro> ----------
async function abrirSalidaDeRuta(id) {
  if (!id || route.name !== 'registro') return
  router.replace({ name: 'registro' })
  let v = vehiculosDentro.value.find(x => x.id === id)
  if (!v) {
    await cargarDatos()
    v = vehiculosDentro.value.find(x => x.id === id)
  }
  if (v) abrirCobro(v)
  else salida.error = 'Ese vehículo ya no está dentro del parqueadero.'
}
watch(() => route.query.salida, (id) => abrirSalidaDeRuta(id), { immediate: true })

onActivated(() => {
  if (!route.query.salida && !cobro.abierto && !ticket.abierto && !salidaOk.abierto) enfocarEntrada()
})
// Al terminar la primera carga, enfocar la placa si la entrada quedó habilitada
watch(cargando, (c) => { if (!c && !cobro.abierto) enfocarEntrada() })
onDeactivated(cerrarEscaner)
onUnmounted(cerrarEscaner)
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
