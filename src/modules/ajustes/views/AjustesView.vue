<template>
  <div class="space-y-6">
    <div>
      <h2 class="titulo-pagina">Ajustes del parqueadero</h2>
      <p class="subtitulo-pagina">Datos del negocio, tipos de vehículo, tarifas, planes, métodos de pago, ticket y tema.</p>
    </div>

    <div v-if="!conexion.isOnline" class="alerta-aviso">
      Sin conexión: Ajustes requiere internet. Puedes consultar los datos, pero no guardar cambios.
    </div>
    <div v-if="mensajeExito" class="alerta-exito">{{ mensajeExito }}</div>
    <div v-if="errorMensaje" class="alerta-error" role="alert">{{ errorMensaje }}</div>

    <!-- Pestañas -->
    <div class="flex border-b border-border overflow-x-auto gap-1 text-sm" role="tablist">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        role="tab"
        :aria-selected="tabActiva === tab.id"
        @click="cambiarTab(tab.id)"
        class="px-3 md:px-4 py-2.5 -mb-px text-sm font-medium border-b-2 whitespace-nowrap transition-colors"
        :class="tabActiva === tab.id ? 'border-primary text-primary' : 'border-transparent text-text-secondary hover:text-text-primary hover:border-border'"
      >
        {{ tab.label }}
      </button>
    </div>

    <!-- 1. NEGOCIO (HU-06) -->
    <form v-if="tabActiva === 'negocio'" @submit.prevent="guardarNegocio" class="card-craft p-5 space-y-4 max-w-3xl">
      <fieldset :disabled="!conexion.isOnline || guardando" class="space-y-4">
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label for="neg-nombre" class="etiqueta">Nombre del parqueadero *</label>
            <input id="neg-nombre" v-model.trim="negocio.nombre" autocomplete="organization" class="campo" :class="{ 'border-danger': erroresNegocio.nombre }" />
            <p v-if="erroresNegocio.nombre" class="err">{{ erroresNegocio.nombre }}</p>
          </div>
          <div>
            <label for="neg-nit" class="etiqueta">NIT *</label>
            <input id="neg-nit" v-model.trim="negocio.nit" autocomplete="off" class="campo" :class="{ 'border-danger': erroresNegocio.nit }" />
            <p v-if="erroresNegocio.nit" class="err">{{ erroresNegocio.nit }}</p>
          </div>
          <div>
            <label for="neg-direccion" class="etiqueta">Dirección</label>
            <input id="neg-direccion" v-model.trim="negocio.direccion" autocomplete="street-address" class="campo" />
          </div>
          <div>
            <label for="neg-telefono" class="etiqueta">Teléfono</label>
            <input id="neg-telefono" v-model.trim="negocio.telefono" type="tel" autocomplete="tel" class="campo" />
          </div>
          <div>
            <label for="neg-zona" class="etiqueta">Zona horaria</label>
            <select id="neg-zona" v-model="negocio.zona_horaria" class="campo">
              <option v-for="z in ZONAS" :key="z.id" :value="z.id">{{ z.label }}</option>
            </select>
          </div>
          <div>
            <label for="neg-moneda" class="etiqueta">Moneda</label>
            <select id="neg-moneda" v-model="negocio.moneda" class="campo">
              <option value="COP">COP · Peso colombiano</option>
              <option value="USD">USD · Dólar</option>
              <option value="PEN">PEN · Sol peruano</option>
              <option value="MXN">MXN · Peso mexicano</option>
            </select>
          </div>
          <div>
            <label for="neg-dias" class="etiqueta">Días de aviso de vencimiento</label>
            <input id="neg-dias" v-model.number="negocio.dias_aviso_vencimiento" type="number" inputmode="numeric" min="0" max="60" class="campo" :class="{ 'border-danger': erroresNegocio.dias }" />
            <p v-if="erroresNegocio.dias" class="err">{{ erroresNegocio.dias }}</p>
            <p v-else class="hint">Una mensualidad pasa a "Por vencer" esta cantidad de días antes de su fecha de cobro.</p>
          </div>
          <div class="sm:col-span-2">
            <label for="neg-pie" class="etiqueta">Texto del pie del comprobante</label>
            <textarea id="neg-pie" v-model="negocio.texto_pie_comprobante" rows="2" class="campo" placeholder="Gracias por su visita..."></textarea>
          </div>
        </div>

        <div class="pt-3 border-t border-border">
          <label for="neg-logo" class="etiqueta">Logo (PNG o JPG, máximo 1 MB)</label>
          <div class="flex items-center gap-4 flex-wrap">
            <div class="w-20 h-20 shrink-0 rounded-lg border border-border bg-surface-elevated flex items-center justify-center overflow-hidden">
              <img v-if="logoPreview || negocio.logo_url" :src="logoPreview || negocio.logo_url" alt="Logo del parqueadero" class="max-w-full max-h-full object-contain" />
              <span v-else class="text-2xs text-text-muted">Sin logo</span>
            </div>
            <div class="space-y-1 min-w-0 max-w-full">
              <input id="neg-logo" type="file" accept="image/png,image/jpeg" @change="seleccionarLogo" class="block w-full max-w-full text-xs text-text-secondary file:mr-3 file:px-3 file:py-2 sm:file:py-1.5 file:rounded-lg file:border file:border-solid file:border-border file:bg-surface file:text-text-primary file:text-xs file:font-semibold hover:file:bg-surface-elevated" />
              <p v-if="errorLogo" class="err">{{ errorLogo }}</p>
              <button v-if="archivoLogo" type="button" @click="subirLogo" :disabled="subiendoLogo" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0">
                {{ subiendoLogo ? 'Subiendo...' : 'Subir logo' }}
              </button>
            </div>
          </div>
        </div>

        <div class="pt-2">
          <button type="submit" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg w-full sm:w-auto">{{ guardando ? 'Guardando...' : 'Guardar datos del negocio' }}</button>
        </div>
      </fieldset>
    </form>

    <!-- 2. TIPOS DE VEHÍCULO (HU-07) -->
    <div v-if="tabActiva === 'tipos'" class="space-y-4">
      <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-3">
        <p class="text-xs text-text-muted">La capacidad informa, no bloquea las entradas.</p>
        <button @click="editarTipo(null)" :disabled="!conexion.isOnline" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg shrink-0"><svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>Nuevo tipo</button>
      </div>
      <div class="card-craft divide-y divide-border">
        <div v-if="!tipos.length" class="vacio">No hay tipos de vehículo.</div>
        <div v-for="t in tipos" :key="t.id" class="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div class="min-w-0">
            <p class="font-semibold text-sm flex items-center gap-2"><span class="w-8 h-8 rounded-lg bg-primary/10 text-primary flex items-center justify-center shrink-0"><IconoVehiculo :nombre="ICONOS_TIPO[t.icono] || t.nombre" clase="w-4 h-4" /></span><span class="min-w-0 break-words">{{ t.nombre }}</span>
              <span v-if="!t.activo" class="badge-pastel-rose text-2xs px-2 py-0.5 rounded-full ml-1 shrink-0">Inactivo</span>
            </p>
            <p class="text-xs text-text-muted pl-10">Capacidad {{ t.capacidad }} · orden {{ t.orden }}</p>
          </div>
          <div class="flex gap-2 shrink-0">
            <button @click="editarTipo(t)" :disabled="!conexion.isOnline" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0">Editar</button>
            <button @click="alternarTipo(t)" :disabled="!conexion.isOnline || ocupado" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0" :class="t.activo ? 'text-danger' : 'text-success'">
              {{ t.activo ? 'Desactivar' : 'Activar' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- 3. TARIFAS (HU-08) -->
    <div v-if="tabActiva === 'tarifas'" class="space-y-4">
      <div class="flex flex-col sm:flex-row justify-between gap-3">
        <select v-model="filtroTipoTarifa" aria-label="Filtrar por tipo de vehículo" class="campo campo-sm sm:max-w-xs">
          <option value="">Todos los tipos</option>
          <option v-for="t in tipos" :key="t.id" :value="t.id">{{ t.nombre }}</option>
        </select>
        <button @click="editarTarifa(null)" :disabled="!conexion.isOnline || !tiposActivos.length" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg shrink-0"><svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>Nueva tarifa</button>
      </div>

      <div class="card-craft divide-y divide-border">
        <div v-if="!tarifasFiltradas.length" class="vacio">No hay tarifas para este filtro.</div>
        <div v-for="t in tarifasFiltradas" :key="t.id" class="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div class="min-w-0 break-words">
            <p class="font-semibold text-sm">{{ t.nombre }}
              <span class="text-xs font-normal text-text-muted">· {{ t.tipos_vehiculo?.nombre }}</span>
            </p>
            <p class="text-xs text-text-secondary">{{ describirTarifa(t) }}</p>
            <div class="flex gap-1 mt-1 flex-wrap">
              <span v-if="t.es_predeterminada" class="badge-pastel-blue text-2xs px-2 py-0.5 rounded-full">Predeterminada</span>
              <span v-if="t.franja_inicio" class="badge-pastel-amber text-2xs px-2 py-0.5 rounded-full">Nocturna {{ hhmm(t.franja_inicio) }}–{{ hhmm(t.franja_fin) }}</span>
              <span v-if="!t.activa" class="badge-pastel-rose text-2xs px-2 py-0.5 rounded-full">Inactiva</span>
            </div>
          </div>
          <div class="flex gap-2">
            <button @click="editarTarifa(t)" :disabled="!conexion.isOnline" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0">Editar</button>
            <button @click="alternarTarifa(t)" :disabled="!conexion.isOnline || ocupado" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0" :class="t.activa ? 'text-danger' : 'text-success'">
              {{ t.activa ? 'Desactivar' : 'Activar' }}
            </button>
          </div>
        </div>
      </div>

      <!-- Simulador de cobro -->
      <div class="card-craft p-5 space-y-3">
        <h3 class="titulo-seccion">Simulador de cobro</h3>
        <p class="text-xs text-text-muted">Usa el mismo cálculo que la salida. Horas en {{ authStore.zonaHoraria }}. Si el tipo tiene tarifa nocturna activa, se aplica en su franja.</p>
        <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-3">
          <div>
            <label for="sim-tipo" class="etiqueta">Tipo</label>
            <select id="sim-tipo" v-model="sim.tipoId" class="campo campo-sm">
              <option v-for="t in tiposActivos" :key="t.id" :value="t.id">{{ t.nombre }}</option>
            </select>
          </div>
          <div>
            <label for="sim-tarifa" class="etiqueta">Tarifa general</label>
            <select id="sim-tarifa" v-model="sim.tarifaId" class="campo campo-sm">
              <option v-for="t in tarifasGeneralesSim" :key="t.id" :value="t.id">{{ t.nombre }}</option>
            </select>
          </div>
          <div>
            <label for="sim-entrada" class="etiqueta">Entrada</label>
            <input id="sim-entrada" v-model="sim.entrada" type="datetime-local" class="campo campo-sm" />
          </div>
          <div>
            <label for="sim-salida" class="etiqueta">Salida</label>
            <input id="sim-salida" v-model="sim.salida" type="datetime-local" class="campo campo-sm" />
          </div>
        </div>
        <button @click="simularCobro" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg w-full sm:w-auto">Calcular</button>
        <p v-if="sim.error" class="err">{{ sim.error }}</p>
        <div v-if="sim.resultado" class="rounded-lg bg-surface-elevated border border-border p-3 text-xs space-y-1">
          <p class="text-base font-bold num-tabular">{{ pesos(sim.resultado.valorTotal) }} <span class="text-xs font-normal text-text-muted">· {{ duracion(sim.resultado.minutosTotal) }}</span></p>
          <p v-for="(d, i) in sim.resultado.desglose" :key="i" class="text-text-secondary">
            Tramo {{ d.tipo === 'nocturna' ? 'nocturno' : 'general' }}: {{ duracion(d.minutos) }} → <span class="num-tabular font-semibold">{{ pesos(d.valor) }}</span>
          </p>
        </div>
      </div>
    </div>

    <!-- 4. PLANES MENSUALES (HU-09) -->
    <div v-if="tabActiva === 'planes'" class="space-y-4">
      <div class="flex justify-end">
        <button @click="editarPlan(null)" :disabled="!conexion.isOnline || !tiposActivos.length" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg w-full sm:w-auto"><svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>Nuevo plan</button>
      </div>
      <div class="card-craft divide-y divide-border">
        <div v-if="!planes.length" class="vacio">No hay planes mensuales.</div>
        <div v-for="p in planes" :key="p.id" class="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div class="min-w-0 break-words">
            <p class="font-semibold text-sm">{{ p.nombre }} <span class="text-xs font-normal text-text-muted">· {{ p.tipos_vehiculo?.nombre }}</span>
              <span v-if="!p.activo" class="badge-pastel-rose text-2xs px-2 py-0.5 rounded-full ml-1">Inactivo</span>
            </p>
            <p class="text-xs text-text-secondary">
              {{ pesos(p.valor) }} · {{ p.tipo_periodo === 'mensual' ? 'Mensual (mismo día de cada mes)' : `Cada ${p.duracion_dias} días` }} · {{ p.dias_gracia_pago }} día(s) de gracia
            </p>
          </div>
          <div class="flex gap-2">
            <button @click="editarPlan(p)" :disabled="!conexion.isOnline" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0">Editar</button>
            <button @click="alternarPlan(p)" :disabled="!conexion.isOnline || ocupado" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0" :class="p.activo ? 'text-danger' : 'text-success'">
              {{ p.activo ? 'Desactivar' : 'Activar' }}
            </button>
          </div>
        </div>
      </div>

      <div class="card-craft p-5 space-y-3 max-w-2xl">
        <h3 class="titulo-seccion">Simulador de periodos</h3>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 items-end">
          <div>
            <label for="simplan-plan" class="etiqueta">Plan</label>
            <select id="simplan-plan" v-model="simPlan.planId" class="campo campo-sm">
              <option v-for="p in planes" :key="p.id" :value="p.id">{{ p.nombre }}</option>
            </select>
          </div>
          <div>
            <label for="simplan-inicio" class="etiqueta">Fecha de inicio</label>
            <input id="simplan-inicio" v-model="simPlan.fechaInicio" type="date" class="campo campo-sm" />
          </div>
          <button @click="simularPeriodos" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg sm:col-span-2 lg:col-span-1">Ver próximos 3 periodos</button>
        </div>
        <p v-if="simPlan.error" class="err">{{ simPlan.error }}</p>
        <ul v-if="simPlan.periodos.length" class="text-xs space-y-1">
          <li v-for="(per, i) in simPlan.periodos" :key="i" class="flex flex-wrap justify-between gap-x-3 gap-y-0.5 bg-surface-elevated border border-border rounded-lg px-3 py-2">
            <span>Periodo {{ i + 1 }}</span>
            <span class="font-semibold">{{ formatearFechaCorta(per.desde) }} → {{ formatearFechaCorta(per.hasta) }}</span>
          </li>
        </ul>
      </div>
    </div>

    <!-- 5. MÉTODOS DE PAGO (HU-06) -->
    <div v-if="tabActiva === 'pagos'" class="space-y-4">
      <div class="flex flex-col sm:flex-row sm:justify-between sm:items-center gap-3">
        <p class="text-xs text-text-muted">Los métodos marcados como efectivo suman al efectivo esperado del turno. Debe haber al menos uno activo.</p>
        <button @click="editarMetodo(null)" :disabled="!conexion.isOnline" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg shrink-0"><svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M12 4v16m8-8H4" /></svg>Nuevo método</button>
      </div>
      <div class="card-craft divide-y divide-border">
        <div v-if="!metodos.length" class="vacio">No hay métodos de pago.</div>
        <div v-for="(m, i) in metodos" :key="m.id" class="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
          <div class="flex items-center gap-2 min-w-0">
            <div class="flex flex-col shrink-0">
              <button @click="moverMetodo(i, -1)" :disabled="i === 0 || !conexion.isOnline || ocupado" class="w-10 h-10 sm:w-8 sm:h-7 flex items-center justify-center rounded-lg text-text-muted hover:text-primary hover:bg-surface-elevated disabled:opacity-30" aria-label="Subir"><svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M5 15l7-7 7 7" /></svg></button>
              <button @click="moverMetodo(i, 1)" :disabled="i === metodos.length - 1 || !conexion.isOnline || ocupado" class="w-10 h-10 sm:w-8 sm:h-7 flex items-center justify-center rounded-lg text-text-muted hover:text-primary hover:bg-surface-elevated disabled:opacity-30" aria-label="Bajar"><svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M19 9l-7 7-7-7" /></svg></button>
            </div>
            <div class="min-w-0">
              <p class="font-semibold text-sm break-words">{{ m.nombre }}</p>
              <div class="flex gap-1 mt-0.5">
                <span v-if="m.es_efectivo" class="badge-pastel-mint text-2xs px-2 py-0.5 rounded-full">Efectivo</span>
                <span v-if="!m.activo" class="badge-pastel-rose text-2xs px-2 py-0.5 rounded-full">Inactivo</span>
              </div>
            </div>
          </div>
          <div class="flex gap-2">
            <button @click="editarMetodo(m)" :disabled="!conexion.isOnline" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0">Editar</button>
            <button @click="alternarMetodo(m)" :disabled="!conexion.isOnline || ocupado" class="btn-craft-subtle text-xs px-3 py-1.5 rounded-lg min-h-10 sm:min-h-0" :class="m.activo ? 'text-danger' : 'text-success'">
              {{ m.activo ? 'Desactivar' : 'Activar' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- 6. TICKET (HU-27) -->
    <div v-if="tabActiva === 'ticket'" class="grid grid-cols-1 lg:grid-cols-2 gap-6">
      <form @submit.prevent="guardarNegocio" class="card-craft p-5 space-y-4">
        <fieldset :disabled="!conexion.isOnline || guardando" class="space-y-4">
          <div role="radiogroup" aria-labelledby="ticket-modo">
            <p id="ticket-modo" class="etiqueta">Modo de ticket de entrada</p>
            <div class="grid grid-cols-1 gap-2">
              <label v-for="m in MODOS_TICKET" :key="m.id" class="flex items-start gap-2.5 p-3 rounded-lg border cursor-pointer transition-colors" :class="negocio.modo_ticket === m.id ? 'border-primary bg-primary/10' : 'border-border hover:border-primary/50'">
                <input type="radio" :value="m.id" v-model="negocio.modo_ticket" class="mt-0.5" />
                <span class="min-w-0">
                  <span class="block text-sm font-semibold">{{ m.label }}</span>
                  <span class="block text-xs text-text-muted">{{ m.ayuda }}</span>
                </span>
              </label>
            </div>
          </div>
          <div v-if="negocio.modo_ticket === 'termica'">
            <label for="ticket-ancho" class="etiqueta">Ancho del papel</label>
            <select id="ticket-ancho" v-model.number="negocio.ancho_ticket_mm" class="campo">
              <option :value="80">80 mm</option>
              <option :value="58">58 mm</option>
            </select>
          </div>
          <div class="flex flex-col sm:flex-row gap-2">
            <button type="submit" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg">{{ guardando ? 'Guardando...' : 'Guardar ticket' }}</button>
            <button v-if="negocio.modo_ticket === 'termica' || negocio.modo_ticket === 'impresora'" type="button" @click="imprimirPrueba" class="btn-craft-subtle text-sm px-4 py-2.5 sm:py-2 rounded-lg">Imprimir prueba</button>
          </div>
          <p v-if="negocio.modo_ticket === 'impresora'" class="alerta-info">
            Al imprimir se abre el diálogo de impresión del equipo: elija allí su impresora WiFi o Bluetooth. En Android puede requerir el servicio de impresión del fabricante (Mopria); en iPhone y iPad, una impresora compatible con AirPrint.
          </p>
        </fieldset>
      </form>

      <div class="card-craft p-5">
        <p class="etiqueta mb-3">Vista previa</p>
        <div v-if="negocio.modo_ticket === 'ninguno'" class="vacio">
          Sin ticket: la salida se hace consultando la placa.
        </div>
        <div v-else class="overflow-x-auto">
          <!-- El mismo HTML que se imprime (src/lib/ticketImpresion.js) -->
          <div class="mx-auto w-fit bg-white p-3 rounded-sm shadow-sm border border-black/10" v-html="htmlVistaPrevia"></div>
        </div>
      </div>
    </div>

    <!-- 7. TEMA (HU-10) -->
    <div v-if="tabActiva === 'tema'" class="card-craft p-5 max-w-md space-y-3">
      <p class="etiqueta">Tema de la aplicación (se guarda en este dispositivo)</p>
      <div class="grid grid-cols-3 gap-2">
        <button
          v-for="t in TEMAS"
          :key="t.id"
          @click="temaStore.setTheme(t.id)"
          :aria-pressed="temaStore.currentTheme === t.id"
          class="px-2 sm:px-3 py-3 rounded-lg border text-sm font-medium transition-colors"
          :class="temaStore.currentTheme === t.id ? 'border-primary text-primary bg-primary/10' : 'border-border text-text-secondary hover:border-primary/50'"
        >
          {{ t.label }}
        </button>
      </div>
    </div>

    <!-- EDITOR (modal) -->
    <div v-if="editor" class="modal-fondo" @click.self="cerrarEditor">
      <form @submit.prevent="guardarEditor" class="modal-panel max-w-lg" role="dialog" aria-modal="true" aria-labelledby="editor-titulo">
        <div class="modal-encabezado">
          <h3 id="editor-titulo" class="modal-titulo">{{ tituloEditor }}</h3>
          <button type="button" class="btn-icono shrink-0" aria-label="Cerrar" @click="cerrarEditor"><svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg></button>
        </div>

        <!-- Tipo de vehículo -->
        <template v-if="editor.clase === 'tipo'">
          <div>
            <label for="ed-tipo-nombre" class="etiqueta">Nombre *</label>
            <input id="ed-tipo-nombre" v-model.trim="editor.datos.nombre" required autocomplete="off" class="campo" placeholder="Carro, Moto, Camioneta..." />
          </div>
          <div class="grid grid-cols-2 sm:grid-cols-3 gap-3">
            <div class="col-span-2 sm:col-span-1">
              <label for="ed-tipo-icono" class="etiqueta">Ícono</label>
              <select id="ed-tipo-icono" v-model="editor.datos.icono" class="campo">
                <option v-for="(nombreIcono, clave) in ICONOS_TIPO" :key="clave" :value="clave">{{ nombreIcono }}</option>
              </select>
            </div>
            <div>
              <label for="ed-tipo-capacidad" class="etiqueta">Capacidad</label>
              <input id="ed-tipo-capacidad" v-model.number="editor.datos.capacidad" type="number" inputmode="numeric" min="0" required class="campo" />
            </div>
            <div>
              <label for="ed-tipo-orden" class="etiqueta">Orden</label>
              <input id="ed-tipo-orden" v-model.number="editor.datos.orden" type="number" inputmode="numeric" min="0" class="campo" />
            </div>
          </div>
        </template>

        <!-- Tarifa -->
        <template v-if="editor.clase === 'tarifa'">
          <p v-if="editor.vehiculosDentro > 0" class="alerta-aviso">
            Hay {{ editor.vehiculosDentro }} vehículo(s) dentro con esta tarifa: se cobrarán con el valor vigente al salir.
          </p>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label for="ed-tar-tipo" class="etiqueta">Tipo de vehículo *</label>
              <select id="ed-tar-tipo" v-model="editor.datos.tipo_vehiculo_id" required class="campo">
                <option v-for="t in tiposActivos" :key="t.id" :value="t.id">{{ t.nombre }}</option>
              </select>
            </div>
            <div>
              <label for="ed-tar-nombre" class="etiqueta">Nombre *</label>
              <input id="ed-tar-nombre" v-model.trim="editor.datos.nombre" required autocomplete="off" class="campo" placeholder="Por hora, Día pleno..." />
            </div>
            <div>
              <label for="ed-tar-modalidad" class="etiqueta">Modalidad *</label>
              <select id="ed-tar-modalidad" v-model="editor.datos.modalidad" class="campo">
                <option value="por_hora">Por hora</option>
                <option value="por_minuto">Por minuto</option>
                <option value="por_fraccion">Por fracción</option>
                <option value="plena">Tarifa plena (por 24 h)</option>
              </select>
            </div>
            <div>
              <label for="ed-tar-valor" class="etiqueta">Valor ($) *</label>
              <input id="ed-tar-valor" v-model.number="editor.datos.valor" type="number" inputmode="numeric" min="1" step="1" required class="campo num-tabular" />
            </div>
            <div v-if="editor.datos.modalidad === 'por_fraccion'">
              <label for="ed-tar-fraccion" class="etiqueta">Minutos por fracción</label>
              <input id="ed-tar-fraccion" v-model.number="editor.datos.minutos_fraccion" type="number" inputmode="numeric" min="1" max="1440" class="campo" />
            </div>
            <template v-if="editor.datos.modalidad !== 'plena'">
              <div>
                <label for="ed-tar-gracia" class="etiqueta">Minutos de gracia</label>
                <input id="ed-tar-gracia" v-model.number="editor.datos.minutos_gracia" type="number" inputmode="numeric" min="0" class="campo" />
              </div>
              <div>
                <label for="ed-tar-tope" class="etiqueta">Tope por 24 h ($, opcional)</label>
                <input id="ed-tar-tope" v-model.number="editor.datos.tope_por_24h" type="number" inputmode="numeric" min="1" class="campo num-tabular" placeholder="Sin tope" />
              </div>
            </template>
          </div>
          <label class="flex items-start gap-2 text-sm py-1.5 cursor-pointer">
            <input type="checkbox" class="rounded mt-0.5 shrink-0" v-model="editor.datos.conFranja" />
            Aplicar solo en una franja horaria (tarifa nocturna)
          </label>
          <div v-if="editor.datos.conFranja" class="grid grid-cols-2 gap-3">
            <div>
              <label for="ed-tar-desde" class="etiqueta">Desde</label>
              <input id="ed-tar-desde" v-model="editor.datos.franja_inicio" type="time" required class="campo" />
            </div>
            <div>
              <label for="ed-tar-hasta" class="etiqueta">Hasta</label>
              <input id="ed-tar-hasta" v-model="editor.datos.franja_fin" type="time" required class="campo" />
            </div>
            <p class="hint col-span-2">Solo puede haber una tarifa con franja activa por tipo. El resto del tiempo se cobra con la tarifa general.</p>
          </div>
          <label class="flex items-start gap-2 text-sm py-1.5 cursor-pointer" :class="{ 'opacity-50': editor.datos.conFranja }">
            <input type="checkbox" class="rounded mt-0.5 shrink-0" v-model="editor.datos.es_predeterminada" :disabled="editor.datos.conFranja" />
            Tarifa predeterminada del tipo (la anterior deja de serlo)
          </label>
        </template>

        <!-- Plan mensual -->
        <template v-if="editor.clase === 'plan'">
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
            <div>
              <label for="ed-plan-tipo" class="etiqueta">Tipo de vehículo *</label>
              <select id="ed-plan-tipo" v-model="editor.datos.tipo_vehiculo_id" required class="campo">
                <option v-for="t in tiposActivos" :key="t.id" :value="t.id">{{ t.nombre }}</option>
              </select>
            </div>
            <div>
              <label for="ed-plan-nombre" class="etiqueta">Nombre *</label>
              <input id="ed-plan-nombre" v-model.trim="editor.datos.nombre" required autocomplete="off" class="campo" placeholder="Mensual carro" />
            </div>
            <div>
              <label for="ed-plan-valor" class="etiqueta">Valor ($) *</label>
              <input id="ed-plan-valor" v-model.number="editor.datos.valor" type="number" inputmode="numeric" min="1" required class="campo num-tabular" />
            </div>
            <div>
              <label for="ed-plan-periodo" class="etiqueta">Tipo de periodo</label>
              <select id="ed-plan-periodo" v-model="editor.datos.tipo_periodo" class="campo">
                <option value="mensual">Mensual (mismo día cada mes)</option>
                <option value="dias_fijos">Días fijos</option>
              </select>
            </div>
            <div v-if="editor.datos.tipo_periodo === 'dias_fijos'">
              <label for="ed-plan-duracion" class="etiqueta">Duración (días)</label>
              <input id="ed-plan-duracion" v-model.number="editor.datos.duracion_dias" type="number" inputmode="numeric" min="1" required class="campo" />
            </div>
            <div>
              <label for="ed-plan-gracia" class="etiqueta">Días de gracia para el pago</label>
              <input id="ed-plan-gracia" v-model.number="editor.datos.dias_gracia_pago" type="number" inputmode="numeric" min="0" class="campo" />
            </div>
          </div>
          <p class="hint">Los cambios de valor o periodo aplican desde el siguiente pago; no alteran pagos registrados.</p>
        </template>

        <!-- Método de pago -->
        <template v-if="editor.clase === 'metodo'">
          <div>
            <label for="ed-met-nombre" class="etiqueta">Nombre *</label>
            <input id="ed-met-nombre" v-model.trim="editor.datos.nombre" required autocomplete="off" class="campo" placeholder="Nequi, Daviplata, Tarjeta..." />
          </div>
          <label class="flex items-start gap-2 text-sm py-1.5 cursor-pointer">
            <input type="checkbox" class="rounded mt-0.5 shrink-0" v-model="editor.datos.es_efectivo" />
            Es efectivo (suma al efectivo esperado del turno)
          </label>
        </template>

        <label v-if="editor.datos.id" class="flex items-center gap-2 text-sm py-1.5 cursor-pointer">
          <input type="checkbox" class="rounded" v-model="editor.activo" />
          Activo
        </label>

        <p v-if="errorEditor" class="alerta-error" role="alert">{{ errorEditor }}</p>
        <div class="flex flex-col-reverse sm:flex-row sm:justify-end gap-2 pt-2">
          <button type="button" @click="cerrarEditor" class="btn-craft-subtle text-sm px-4 py-2.5 sm:py-2 rounded-lg w-full sm:w-auto">Cancelar</button>
          <button type="submit" :disabled="ocupado || !conexion.isOnline" class="btn-craft-primary text-sm px-4 py-2.5 sm:py-2 rounded-lg w-full sm:w-auto">{{ ocupado ? 'Guardando...' : 'Guardar' }}</button>
        </div>
      </form>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onActivated, onBeforeUnmount, watch } from 'vue'
import QRCode from 'qrcode'
import { ajustesService } from '@/modules/ajustes/services/ajustesService'
import { useAuthStore } from '@/stores/auth'
import { useConexionStore } from '@/stores/conexion'
import { useTemaStore } from '@/stores/tema'
import { mensajeDeError } from '@/lib/sesionCaches'
import { construirHtmlTicket, imprimirTicket, instalarEstiloTicket, textoTarifa } from '@/lib/ticketImpresion'
import IconoVehiculo from '@/components/IconoVehiculo.vue'
import { instanteDesdeLocal, hoyEnZona, formatearFechaCorta, formatearFechaHora } from '@/utils/fecha'

const authStore = useAuthStore()
const conexion = useConexionStore()
const temaStore = useTemaStore()

const tabs = [
  { id: 'negocio', label: 'Negocio' },
  { id: 'tipos', label: 'Tipos de vehículo' },
  { id: 'tarifas', label: 'Tarifas' },
  { id: 'planes', label: 'Planes mensuales' },
  { id: 'pagos', label: 'Métodos de pago' },
  { id: 'ticket', label: 'Ticket' },
  { id: 'tema', label: 'Tema' }
]
const ZONAS = [
  { id: 'America/Bogota', label: 'Colombia (Bogotá)' },
  { id: 'America/Lima', label: 'Perú (Lima)' },
  { id: 'America/Guayaquil', label: 'Ecuador (Guayaquil)' },
  { id: 'America/Panama', label: 'Panamá' },
  { id: 'America/Caracas', label: 'Venezuela (Caracas)' },
  { id: 'America/Mexico_City', label: 'México (CDMX)' },
  { id: 'America/Santiago', label: 'Chile (Santiago)' },
  { id: 'America/Argentina/Buenos_Aires', label: 'Argentina (Buenos Aires)' }
]
const MODOS_TICKET = [
  { id: 'qr', label: 'QR en pantalla', ayuda: 'El cliente toma foto del QR. Recomendado si no hay impresora.' },
  { id: 'impresora', label: 'Impresora normal (láser o tinta)', ayuda: 'Imprime el ticket en hoja carta o A4 para recortar. Sirve cualquier impresora WiFi, Bluetooth o USB que el equipo ya tenga agregada.' },
  { id: 'termica', label: 'Impresora térmica', ayuda: 'Imprime el ticket de 58 u 80 mm (requiere el driver de la impresora).' },
  { id: 'ninguno', label: 'Sin ticket', ayuda: 'No se entrega ticket; la salida se hace por placa.' }
]
const TEMAS = [
  { id: 'light', label: 'Claro' },
  { id: 'dark', label: 'Oscuro' },
  { id: 'system', label: 'Sistema' }
]
// Ícono guardado en BD → nombre legible (IconoVehiculo elige el dibujo por nombre)
const ICONOS_TIPO = { car: 'Carro', bike: 'Moto', truck: 'Camioneta', bicycle: 'Bicicleta', bus: 'Bus' }

const tabActiva = ref('negocio')
const mensajeExito = ref('')
const errorMensaje = ref('')
const guardando = ref(false)
const ocupado = ref(false)

const pqId = computed(() => authStore.parqueaderoId)

// --- Datos ---
const negocio = ref({})
const erroresNegocio = ref({})
const tipos = ref([])
const tarifas = ref([])
const planes = ref([])
const metodos = ref([])

const tiposActivos = computed(() => tipos.value.filter(t => t.activo))

function avisar(texto) {
  errorMensaje.value = ''
  mensajeExito.value = texto
  setTimeout(() => { if (mensajeExito.value === texto) mensajeExito.value = '' }, 4000)
}
function fallar(err, porDefecto) {
  mensajeExito.value = ''
  errorMensaje.value = mensajeDeError(err, porDefecto)
}

function cambiarTab(id) {
  tabActiva.value = id
  errorMensaje.value = ''
}

async function cargarNegocio() {
  const d = await ajustesService.obtenerDatosNegocio(pqId.value)
  negocio.value = {
    ...d,
    zona_horaria: d.zona_horaria || 'America/Bogota',
    moneda: d.moneda || 'COP',
    ancho_ticket_mm: d.ancho_ticket_mm || 80,
    modo_ticket: d.modo_ticket || 'qr'
  }
}

async function cargarCatalogos() {
  const [t, ta, p, m] = await Promise.all([
    ajustesService.listarTiposVehiculo(pqId.value),
    ajustesService.listarTarifas(pqId.value),
    ajustesService.listarPlanesMensuales(pqId.value),
    ajustesService.listarMetodosPago(pqId.value)
  ])
  tipos.value = t
  tarifas.value = ta
  planes.value = p
  metodos.value = [...m].sort((a, b) => (a.orden || 0) - (b.orden || 0))
}

async function cargarTodo() {
  if (!pqId.value) return
  try {
    await Promise.all([
      conexion.isOnline ? cargarNegocio() : Promise.resolve(),
      cargarCatalogos()
    ])
    inicializarSimuladores()
  } catch (err) {
    fallar(err, 'No se pudieron cargar los ajustes')
  }
}

// --- Negocio y ticket ---
function validarNegocio() {
  const e = {}
  if (!negocio.value.nombre?.trim()) e.nombre = 'El nombre es obligatorio'
  if (!negocio.value.nit?.trim()) e.nit = 'El NIT es obligatorio'
  const d = Number(negocio.value.dias_aviso_vencimiento)
  if (!Number.isInteger(d) || d < 0 || d > 60) e.dias = 'Debe ser un número entre 0 y 60'
  erroresNegocio.value = e
  return Object.keys(e).length === 0
}

async function guardarNegocio() {
  if (!validarNegocio()) {
    tabActiva.value = 'negocio'
    return
  }
  guardando.value = true
  try {
    const d = await ajustesService.guardarDatosNegocio(pqId.value, negocio.value)
    negocio.value = { ...negocio.value, ...d }
    await authStore.refrescarPerfil()
    avisar('Cambios guardados')
  } catch (err) {
    fallar(err, 'No se pudieron guardar los datos')
  } finally {
    guardando.value = false
  }
}

const archivoLogo = ref(null)
const logoPreview = ref('')
const errorLogo = ref('')
const subiendoLogo = ref(false)

function liberarPreview() {
  if (logoPreview.value) URL.revokeObjectURL(logoPreview.value)
  logoPreview.value = ''
}

function seleccionarLogo(ev) {
  errorLogo.value = ''
  const f = ev.target.files?.[0]
  archivoLogo.value = null
  liberarPreview()
  if (!f) return
  if (!['image/png', 'image/jpeg'].includes(f.type)) {
    errorLogo.value = 'El logo debe ser PNG o JPG'
    return
  }
  if (f.size > 1024 * 1024) {
    errorLogo.value = 'El logo no puede superar 1 MB'
    return
  }
  archivoLogo.value = f
  logoPreview.value = URL.createObjectURL(f)
}

async function subirLogo() {
  subiendoLogo.value = true
  errorLogo.value = ''
  try {
    const url = await ajustesService.subirLogo(pqId.value, archivoLogo.value)
    negocio.value.logo_url = url
    archivoLogo.value = null
    await authStore.refrescarPerfil()
    avisar('Logo actualizado')
  } catch (err) {
    errorLogo.value = mensajeDeError(err, 'No se pudo subir el logo')
  } finally {
    subiendoLogo.value = false
  }
}

// --- Editor genérico ---
const editor = ref(null)
const errorEditor = ref('')

const tituloEditor = computed(() => {
  if (!editor.value) return ''
  const nuevo = !editor.value.datos.id
  return {
    tipo: nuevo ? 'Nuevo tipo de vehículo' : 'Editar tipo de vehículo',
    tarifa: nuevo ? 'Nueva tarifa' : 'Editar tarifa',
    plan: nuevo ? 'Nuevo plan mensual' : 'Editar plan mensual',
    metodo: nuevo ? 'Nuevo método de pago' : 'Editar método de pago'
  }[editor.value.clase]
})

function abrirEditor(clase, datos, activo = true) {
  errorEditor.value = ''
  editor.value = { clase, datos, activo, vehiculosDentro: 0 }
}

function cerrarEditor() {
  if (!ocupado.value) editor.value = null
}

function editarTipo(t) {
  abrirEditor('tipo', t
    ? { id: t.id, nombre: t.nombre, icono: t.icono || 'car', capacidad: t.capacidad, orden: t.orden }
    : { nombre: '', icono: 'car', capacidad: 10, orden: tipos.value.length + 1 }, t ? t.activo : true)
}

async function editarTarifa(t) {
  const tipoDefecto = filtroTipoTarifa.value || tiposActivos.value[0]?.id || ''
  abrirEditor('tarifa', t
    ? {
        id: t.id,
        tipo_vehiculo_id: t.tipo_vehiculo_id,
        nombre: t.nombre,
        modalidad: t.modalidad,
        valor: t.valor,
        minutos_fraccion: t.minutos_fraccion || 15,
        minutos_gracia: t.minutos_gracia || 0,
        tope_por_24h: t.tope_por_24h || null,
        es_predeterminada: t.es_predeterminada,
        conFranja: !!t.franja_inicio,
        franja_inicio: hhmm(t.franja_inicio) || '19:00',
        franja_fin: hhmm(t.franja_fin) || '07:00'
      }
    : {
        tipo_vehiculo_id: tipoDefecto,
        nombre: '',
        modalidad: 'por_hora',
        valor: null,
        minutos_fraccion: 15,
        minutos_gracia: 0,
        tope_por_24h: null,
        es_predeterminada: false,
        conFranja: false,
        franja_inicio: '19:00',
        franja_fin: '07:00'
      }, t ? t.activa : true)
  if (t) {
    try {
      editor.value.vehiculosDentro = await ajustesService.contarVehiculosConTarifa(pqId.value, t.id)
    } catch (e) {}
  }
}

function editarPlan(p) {
  abrirEditor('plan', p
    ? { id: p.id, tipo_vehiculo_id: p.tipo_vehiculo_id, nombre: p.nombre, valor: p.valor, tipo_periodo: p.tipo_periodo, duracion_dias: p.duracion_dias || 15, dias_gracia_pago: p.dias_gracia_pago || 0 }
    : { tipo_vehiculo_id: tiposActivos.value[0]?.id || '', nombre: '', valor: null, tipo_periodo: 'mensual', duracion_dias: 15, dias_gracia_pago: 0 }, p ? p.activo : true)
}

function editarMetodo(m) {
  abrirEditor('metodo', m
    ? { id: m.id, nombre: m.nombre, es_efectivo: m.es_efectivo, orden: m.orden }
    : { nombre: '', es_efectivo: false, orden: metodos.value.length + 1 }, m ? m.activo : true)
}

async function guardarEditor() {
  const { clase, datos, activo } = editor.value
  ocupado.value = true
  errorEditor.value = ''
  try {
    if (clase === 'tipo') {
      await ajustesService.guardarTipoVehiculo(pqId.value, { ...datos, activo })
    } else if (clase === 'tarifa') {
      await ajustesService.guardarTarifa(pqId.value, {
        ...datos,
        franja_inicio: datos.conFranja ? datos.franja_inicio : null,
        franja_fin: datos.conFranja ? datos.franja_fin : null,
        es_predeterminada: datos.conFranja ? false : datos.es_predeterminada,
        minutos_gracia: datos.modalidad === 'plena' ? 0 : datos.minutos_gracia,
        tope_por_24h: datos.modalidad === 'plena' ? null : datos.tope_por_24h,
        activa: activo
      })
    } else if (clase === 'plan') {
      await ajustesService.guardarPlanMensual(pqId.value, { ...datos, activo })
    } else if (clase === 'metodo') {
      await ajustesService.guardarMetodoPago(pqId.value, { ...datos, activo })
    }
    editor.value = null
    await cargarCatalogos()
    avisar('Cambios guardados')
  } catch (err) {
    errorEditor.value = mensajeDeError(err, 'No se pudo guardar')
  } finally {
    ocupado.value = false
  }
}

async function alternar(accion, porDefecto) {
  ocupado.value = true
  try {
    await accion()
    await cargarCatalogos()
    avisar('Cambios guardados')
  } catch (err) {
    fallar(err, porDefecto)
  } finally {
    ocupado.value = false
  }
}

function alternarTipo(t) {
  return alternar(() => ajustesService.guardarTipoVehiculo(pqId.value, { ...t, activo: !t.activo }), 'No se pudo cambiar el tipo')
}
function alternarTarifa(t) {
  return alternar(() => ajustesService.guardarTarifa(pqId.value, {
    ...t,
    franja_inicio: hhmm(t.franja_inicio),
    franja_fin: hhmm(t.franja_fin),
    activa: !t.activa,
    es_predeterminada: t.activa ? false : t.es_predeterminada
  }), 'No se pudo cambiar la tarifa')
}
function alternarPlan(p) {
  return alternar(() => ajustesService.guardarPlanMensual(pqId.value, { ...p, activo: !p.activo }), 'No se pudo cambiar el plan')
}
function alternarMetodo(m) {
  return alternar(() => ajustesService.guardarMetodoPago(pqId.value, { ...m, activo: !m.activo }), 'No se pudo cambiar el método')
}

function moverMetodo(i, delta) {
  const ids = metodos.value.map(m => m.id)
  const j = i + delta
  if (j < 0 || j >= ids.length) return
  ;[ids[i], ids[j]] = [ids[j], ids[i]]
  return alternar(() => ajustesService.reordenarMetodosPago(pqId.value, ids), 'No se pudo reordenar')
}

// --- Tarifas: listado y simulador ---
const filtroTipoTarifa = ref('')
const tarifasFiltradas = computed(() => filtroTipoTarifa.value
  ? tarifas.value.filter(t => t.tipo_vehiculo_id === filtroTipoTarifa.value)
  : tarifas.value)

const MODALIDAD_TXT = { por_hora: 'por hora', por_minuto: 'por minuto', por_fraccion: 'por fracción', plena: 'plena (24 h)' }

function describirTarifa(t) {
  const partes = [`${pesos(t.valor)} ${MODALIDAD_TXT[t.modalidad] || t.modalidad}`]
  if (t.modalidad === 'por_fraccion') partes.push(`fracción de ${t.minutos_fraccion} min`)
  if (t.minutos_gracia) partes.push(`${t.minutos_gracia} min de gracia`)
  if (t.tope_por_24h) partes.push(`tope ${pesos(t.tope_por_24h)} / 24 h`)
  return partes.join(' · ')
}

const sim = ref({ tipoId: '', tarifaId: '', entrada: '', salida: '', resultado: null, error: '' })
const tarifasGeneralesSim = computed(() => tarifas.value.filter(t => t.tipo_vehiculo_id === sim.value.tipoId && t.activa && !t.franja_inicio))

watch(() => sim.value.tipoId, () => {
  const pred = tarifasGeneralesSim.value.find(t => t.es_predeterminada) || tarifasGeneralesSim.value[0]
  sim.value.tarifaId = pred?.id || ''
  sim.value.resultado = null
})

function inicializarSimuladores() {
  const hoy = hoyEnZona(authStore.zonaHoraria)
  if (!sim.value.tipoId || !tipos.value.some(t => t.id === sim.value.tipoId)) {
    sim.value.tipoId = tiposActivos.value[0]?.id || ''
  }
  if (!sim.value.entrada) sim.value.entrada = `${hoy}T17:00`
  if (!sim.value.salida) sim.value.salida = `${hoy}T20:00`
  if (!simPlan.value.planId) simPlan.value.planId = planes.value[0]?.id || ''
  if (!simPlan.value.fechaInicio) simPlan.value.fechaInicio = hoy
}

function localAInstante(valor) {
  const [fecha, hora] = valor.split('T')
  const [y, m, d] = fecha.split('-').map(Number)
  const [h, mi] = (hora || '00:00').split(':').map(Number)
  return instanteDesdeLocal(y, m, d, h, mi, authStore.zonaHoraria)
}

function simularCobro() {
  sim.value.error = ''
  sim.value.resultado = null
  try {
    const general = tarifas.value.find(t => t.id === sim.value.tarifaId)
    if (!general) throw new Error('Selecciona una tarifa general')
    if (!sim.value.entrada || !sim.value.salida) throw new Error('Indica entrada y salida')
    const nocturna = tarifas.value.find(t => t.tipo_vehiculo_id === sim.value.tipoId && t.activa && t.franja_inicio) || null
    sim.value.resultado = ajustesService.simularCobroTarifa({
      entradaAt: localAInstante(sim.value.entrada),
      salidaAt: localAInstante(sim.value.salida),
      tarifaGeneral: general,
      tarifaNocturna: nocturna,
      zonaHoraria: authStore.zonaHoraria
    })
  } catch (err) {
    sim.value.error = err.message
  }
}

// --- Planes: simulador ---
const simPlan = ref({ planId: '', fechaInicio: '', periodos: [], error: '' })

function simularPeriodos() {
  simPlan.value.error = ''
  simPlan.value.periodos = []
  const plan = planes.value.find(p => p.id === simPlan.value.planId)
  if (!plan) {
    simPlan.value.error = 'Selecciona un plan'
    return
  }
  try {
    simPlan.value.periodos = ajustesService.simularPeriodosPlan({
      tipoPeriodo: plan.tipo_periodo,
      duracionDias: plan.duracion_dias,
      fechaInicio: simPlan.value.fechaInicio
    })
  } catch (err) {
    simPlan.value.error = err.message
  }
}

// --- Ticket: vista previa e impresión de prueba ---
const qrPrueba = ref('')
const ahoraTexto = computed(() => formatearFechaHora(new Date(), authStore.zonaHoraria, { year: 'numeric' }))
const tarifaEjemplo = computed(() => {
  const t = tarifas.value.find(x => x.tipo_vehiculo_id === tiposActivos.value[0]?.id && x.es_predeterminada && x.activa)
  return t ? textoTarifa(t) : 'Por hora'
})

async function generarQrPrueba() {
  try {
    qrPrueba.value = await QRCode.toDataURL('PARKCONTROL-TICKET-PRUEBA', { margin: 1, width: 320 })
  } catch (e) {
    qrPrueba.value = ''
  }
}

function datosTicketPrueba() {
  return {
    parqueadero: { ...authStore.parqueadero, ...negocio.value },
    placa: 'ABC123',
    tipoNombre: tiposActivos.value[0]?.nombre || 'Carro',
    entradaTexto: ahoraTexto.value,
    tarifaTexto: tarifaEjemplo.value,
    referencia: 'PRUEBA01',
    qr: qrPrueba.value,
    prueba: true
  }
}
const opcionesTicket = computed(() => ({
  formato: negocio.value.modo_ticket === 'termica' ? 'termica' : 'hoja',
  ancho: negocio.value.ancho_ticket_mm === 58 ? 58 : 80
}))
const htmlVistaPrevia = computed(() => construirHtmlTicket(datosTicketPrueba(), opcionesTicket.value))

async function imprimirPrueba() {
  try {
    await imprimirTicket(datosTicketPrueba(), opcionesTicket.value)
  } catch (e) {
    fallar(e)
  }
}

// --- Utilidades ---
function pesos(v) {
  return `$${Number(v || 0).toLocaleString('es-CO')}`
}
function hhmm(t) {
  return t ? String(t).slice(0, 5) : ''
}
function duracion(min) {
  const m = Math.max(0, Math.round(min || 0))
  if (m < 60) return `${m} min`
  const h = Math.floor(m / 60)
  return m % 60 ? `${h} h ${m % 60} min` : `${h} h`
}

watch(pqId, (nuevo) => { if (nuevo) cargarTodo() })

// La vista vive en <keep-alive>: onActivated también corre en el primer montaje,
// así que la carga va solo ahí (antes se cargaba dos veces al entrar).
onMounted(() => {
  generarQrPrueba()
  instalarEstiloTicket()
})
onActivated(cargarTodo)
onBeforeUnmount(liberarPreview)
</script>

<style scoped>
.hint {
  @apply text-2xs text-text-muted mt-1;
}
.err {
  @apply text-xs text-danger font-medium mt-1;
}
</style>
