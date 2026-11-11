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

    <!-- TARJETAS DE OCUPACIÓN Y CAPACIDAD CON SOBRECUPO (HU-12) CON PALETA PASTEL DE MOVILIDAD -->
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
      <div 
        v-for="tipo in resumenOcupacion" 
        :key="tipo.id"
        class="card-craft p-4 sm:p-5 relative overflow-hidden transition-all"
        :class="[
          tipo.nombre.toLowerCase().includes('moto') ? 'pastel-card-sky' : (tipo.nombre.toLowerCase().includes('bici') ? 'pastel-card-mint' : 'pastel-card-amber'),
          tipo.ocupados >= tipo.capacidad ? 'ring-2 ring-amber-500/60' : ''
        ]"
      >
        <div class="flex justify-between items-start">
          <div class="flex items-center space-x-2">
            <!-- Icono temático del vehículo -->
            <div class="w-8 h-8 rounded-xl flex items-center justify-center shadow-xs"
              :class="tipo.nombre.toLowerCase().includes('moto') ? 'bg-sky-100 text-sky-800 dark:bg-sky-900/60 dark:text-sky-200' : (tipo.nombre.toLowerCase().includes('bici') ? 'bg-emerald-100 text-emerald-800 dark:bg-emerald-900/60 dark:text-emerald-200' : 'bg-amber-100 text-amber-800 dark:bg-amber-900/60 dark:text-amber-200')"
            >
              <!-- Carro -->
              <svg v-if="!tipo.nombre.toLowerCase().includes('moto') && !tipo.nombre.toLowerCase().includes('bici')" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 17a2 2 0 100-4 2 2 0 000 4zm8 0a2 2 0 100-4 2 2 0 000 4zM5 11l1.5-4.5A2 2 0 018.4 5h7.2a2 2 0 011.9 1.5L19 11M3 13h18M5 17H3v-4m18 4h-2v-4" />
              </svg>
              <!-- Moto -->
              <svg v-else-if="tipo.nombre.toLowerCase().includes('moto')" class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8c-2 0-3 1-4 3l-2 1m12-4c2 0 3 1 4 3l2 1m-4 5a3 3 0 11-6 0 3 3 0 016 0zm-8 0a3 3 0 11-6 0 3 3 0 016 0z" />
              </svg>
              <!-- Bici -->
              <svg v-else class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18a4 4 0 100-8 4 4 0 000 8zm12 0a4 4 0 100-8 4 4 0 000 8zm-7-9l3 5m0 0h4m-4 0l-3 4" />
              </svg>
            </div>
            <span class="text-xs font-black uppercase tracking-wider text-text-primary">{{ tipo.nombre }}</span>
          </div>

          <span 
            class="text-[10px] font-bold px-2.5 py-0.5 rounded-full shadow-xs"
            :class="tipo.ocupados >= tipo.capacidad ? 'badge-pastel-rose' : 'badge-pastel-mint'"
          >
            {{ tipo.ocupados >= tipo.capacidad ? 'Sobrecupo' : `${tipo.capacidad - tipo.ocupados} libres` }}
          </span>
        </div>
        
        <div class="mt-3 flex items-baseline space-x-2">
          <span class="text-3xl sm:text-4xl font-black text-text-primary num-tabular">{{ tipo.ocupados }}</span>
          <span class="text-xs font-bold text-text-muted">/ {{ tipo.capacidad }} cupos</span>
        </div>

        <!-- Barra visual de capacidad con micro-gradiente -->
        <div class="mt-3.5 w-full bg-slate-200/70 dark:bg-slate-700/50 h-2 rounded-full overflow-hidden p-0.5">
          <div 
            class="h-full rounded-full transition-all duration-500"
            :class="tipo.ocupados >= tipo.capacidad ? 'bg-rose-500' : (tipo.nombre.toLowerCase().includes('moto') ? 'bg-sky-500' : (tipo.nombre.toLowerCase().includes('bici') ? 'bg-emerald-500' : 'bg-amber-500'))"
            :style="{ width: Math.min(100, Math.round((tipo.ocupados / (tipo.capacidad || 1)) * 100)) + '%' }"
          ></div>
        </div>
      </div>
    </div>

    <!-- FILTRO Y LISTA DE VEHÍCULOS DENTRO -->
    <div class="card-craft overflow-hidden space-y-3 p-4 sm:p-5">
      <div class="flex flex-col sm:flex-row sm:items-center justify-between gap-3 pb-2 border-b border-border/60">
        <div>
          <h3 class="font-black text-sm tracking-tight text-text-primary flex items-center space-x-2">
            <span>Vehículos en Patio</span>
            <span class="badge-pastel-blue text-[11px] font-black px-2 py-0.5 rounded-full">{{ vehiculosDentro.length }}</span>
          </h3>
          <p class="text-[11px] text-text-muted">Control activo con cálculo de tiempo y cobro en tiempo real.</p>
        </div>
        <div class="relative w-full sm:w-64">
          <input 
            v-model="filtroPlaca"
            type="text" 
            placeholder="Buscar por placa..."
            class="w-full px-3 py-1.5 text-xs rounded-xl bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary uppercase font-mono font-bold tracking-wider"
          />
        </div>
      </div>

      <div v-if="cargando" class="text-center py-10 text-xs text-text-muted flex flex-col items-center justify-center space-y-2">
        <div class="w-6 h-6 border-2 border-primary/20 border-t-primary rounded-full animate-spin"></div>
        <span>Consultando vehículos en patio...</span>
      </div>

      <div v-else-if="vehiculosFiltrados.length === 0" class="text-center py-12 text-xs text-text-muted space-y-2">
        <div class="w-10 h-10 mx-auto rounded-full bg-surface-elevated flex items-center justify-center text-lg">🚗</div>
        <p class="font-semibold text-text-primary">No hay vehículos dentro con ese criterio</p>
        <p class="text-[11px]">Cuando ingresen autos o motos aparecerán aquí en vivo.</p>
      </div>

      <!-- Tabla Estilizada con Relieve y Placas Auténticas -->
      <div v-else class="overflow-x-auto">
        <table class="w-full text-left text-xs">
          <thead class="bg-surface-elevated/70 text-text-secondary uppercase border-b border-border text-[10px] tracking-wider font-bold">
            <tr>
              <th class="px-4 py-3">Placa</th>
              <th class="px-4 py-3">Tipo</th>
              <th class="px-4 py-3">Hora Entrada</th>
              <th class="px-4 py-3">Tiempo Estancia</th>
              <th class="px-4 py-3">Est. Cobro</th>
              <th class="px-4 py-3 text-right">Acción</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-border/60">
            <tr v-for="v in vehiculosFiltrados" :key="v.id" class="hover:bg-surface-elevated/40 transition-colors">
              <td class="px-4 py-3.5">
                <div class="flex items-center space-x-2.5">
                  <span 
                    class="plate-colombia text-xs font-mono font-black" 
                    :class="(v.tipos_vehiculo?.nombre || '').toLowerCase().includes('moto') ? 'plate-moto' : ((v.tipos_vehiculo?.nombre || '').toLowerCase().includes('bici') ? 'plate-bici' : 'plate-carro')"
                  >
                    {{ v.placa }}
                  </span>
                  <span v-if="v.isOffline || v.estado === 'pendiente_sync'" class="text-[9px] font-bold px-2 py-0.5 rounded-full badge-pastel-amber">
                    Offline
                  </span>
                </div>
              </td>
              <td class="px-4 py-3.5 font-semibold text-text-secondary">
                <span class="inline-flex items-center space-x-1.5">
                  <span>{{ (v.tipos_vehiculo?.nombre || '').toLowerCase().includes('moto') ? '🏍️' : ((v.tipos_vehiculo?.nombre || '').toLowerCase().includes('bici') ? '🚲' : '🚗') }}</span>
                  <span>{{ v.tipos_vehiculo?.nombre || 'Vehículo' }}</span>
                </span>
              </td>
              <td class="px-4 py-3.5 text-text-secondary num-tabular font-mono font-medium">{{ formatearHora(v.entrada_at) }}</td>
              <td class="px-4 py-3.5 font-semibold num-tabular">
                <span class="inline-flex items-center px-2.5 py-1 rounded-full badge-pastel-blue text-[11px] font-mono font-bold space-x-1">
                  <span class="w-1.5 h-1.5 rounded-full bg-sky-500 animate-pulse"></span>
                  <span>{{ formatearTiempoEstancia(calcularMinutos(v.entrada_at)) }}</span>
                </span>
              </td>
              <td class="px-4 py-3.5 font-mono font-black text-sm text-emerald-600 dark:text-emerald-400 num-tabular">
                ${{ estimarCobro(v).toLocaleString() }}
              </td>
              <td class="px-4 py-3.5 text-right space-x-2">
                <button 
                  @click="abrirModalCobro(v)"
                  class="px-4 py-1.5 rounded-lg btn-craft-primary text-xs font-bold shadow-xs transition-all active:scale-95 inline-flex items-center space-x-1"
                >
                  <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 9V7a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2m2 4h10a2 2 0 002-2v-6a2 2 0 00-2-2H9a2 2 0 00-2 2v6a2 2 0 002 2zm7-5a2 2 0 11-4 0 2 2 0 014 0z" />
                  </svg>
                  <span>Cobrar</span>
                </button>
                <button 
                  v-if="authStore.isAdmin"
                  @click="abrirModalAnular(v)"
                  class="px-2.5 py-1.5 rounded-lg border border-border text-danger hover:bg-danger-bg text-[11px] font-semibold transition-colors"
                  title="Anular registro con motivo"
                >
                  Anular
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <!-- MODAL REGISTRO RÁPIDO DE ENTRADA (< 10 segs, HU-11) CON PREVIEW DE PLACA -->
    <div v-if="mostrarModalEntrada" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-sm w-full shadow-2xl space-y-4">
        <div class="flex justify-between items-center pb-2 border-b border-border/60">
          <div class="flex items-center space-x-2">
            <h3 class="text-base font-black text-text-primary">Registrar Entrada</h3>
            <span class="badge-pastel-mint text-[10px] font-bold px-2 py-0.5 rounded-full">En Patio</span>
          </div>
          <button @click="mostrarModalEntrada = false" class="w-7 h-7 rounded-lg bg-surface-elevated text-text-muted hover:text-text-primary flex items-center justify-center text-sm font-bold transition-colors">✕</button>
        </div>

        <form @submit.prevent="confirmarEntrada" class="space-y-4">
          <!-- Campo Placa enfocado y con Live Preview -->
          <div class="space-y-2">
            <label class="block text-xs font-bold text-text-secondary">Placa del Vehículo *</label>
            <input 
              v-model="entradaForm.placa"
              type="text" 
              required
              autofocus
              maxlength="10"
              placeholder="ABC123"
              class="w-full text-center text-2xl font-mono font-black tracking-widest px-3 py-2.5 rounded-xl bg-surface-elevated border-2 border-primary/50 focus:border-primary focus:outline-none uppercase text-text-primary"
            />
            <!-- Previsualización auténtica en tiempo real -->
            <div class="flex justify-center pt-1">
              <span 
                class="plate-colombia text-sm font-mono font-black shadow-sm"
                :class="tiposDisponibles.find(t => t.id === entradaForm.tipoVehiculoId)?.nombre?.toLowerCase().includes('moto') ? 'plate-moto' : (tiposDisponibles.find(t => t.id === entradaForm.tipoVehiculoId)?.nombre?.toLowerCase().includes('bici') ? 'plate-bici' : 'plate-carro')"
              >
                {{ entradaForm.placa || 'PLACA' }}
              </span>
            </div>
          </div>

          <!-- Selector táctil de Tipo de Vehículo con pasteles temáticos -->
          <div>
            <label class="block text-xs font-bold mb-1.5 text-text-secondary">Tipo de Vehículo</label>
            <div class="grid grid-cols-3 gap-2">
              <button 
                v-for="t in tiposDisponibles" 
                :key="t.id"
                type="button"
                @click="entradaForm.tipoVehiculoId = t.id"
                class="py-2.5 px-2 rounded-xl border text-xs font-bold transition-all text-center flex flex-col items-center justify-center space-y-1 shadow-xs"
                :class="entradaForm.tipoVehiculoId === t.id ? (t.nombre.toLowerCase().includes('moto') ? 'badge-pastel-blue border-sky-400 font-black' : (t.nombre.toLowerCase().includes('bici') ? 'badge-pastel-mint border-emerald-400 font-black' : 'badge-pastel-amber border-amber-400 font-black')) : 'bg-surface-elevated border-border text-text-secondary hover:text-text-primary'"
              >
                <span class="text-base">{{ t.nombre.toLowerCase().includes('moto') ? '🏍️' : (t.nombre.toLowerCase().includes('bici') ? '🚲' : '🚗') }}</span>
                <span class="truncate">{{ t.nombre }}</span>
              </button>
            </div>
          </div>

          <!-- Advertencia de sobrecupo (Informativa, no bloqueante, HU-11) -->
          <div v-if="verificarSobrecupo(entradaForm.tipoVehiculoId)" class="p-2.5 rounded-xl badge-pastel-amber text-xs font-semibold">
            ⚠️ <strong>Capacidad alcanzada:</strong> Este tipo ya está lleno, pero el sistema permite sobrecupo.
          </div>

          <div class="flex space-x-2 pt-2">
            <button 
              type="button" 
              @click="mostrarModalEntrada = false" 
              class="w-1/3 py-2.5 text-xs font-semibold rounded-xl border border-border text-text-secondary hover:bg-surface-elevated transition-colors"
            >
              Cancelar
            </button>
            <button 
              type="submit" 
              :disabled="guardandoEntrada"
              class="w-2/3 py-2.5 text-xs font-bold rounded-xl btn-craft-primary text-white shadow-md disabled:opacity-50 flex items-center justify-center space-x-1.5"
            >
              <svg v-if="guardandoEntrada" class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
                <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
              </svg>
              <span>{{ guardandoEntrada ? 'Registrando...' : 'Confirmar Entrada' }}</span>
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

    <!-- MODAL DE COBRO Y SALIDA (HU-13) CON CALCULADORA TÁCTIL Y PASTEL ATELIER -->
    <div v-if="modalCobro" class="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm">
      <div class="bg-surface rounded-2xl border border-border p-5 max-w-sm w-full shadow-2xl space-y-4">
        <div class="flex justify-between items-center pb-2 border-b border-border/60">
          <div class="flex items-center space-x-2">
            <span class="text-base font-black text-text-primary">Cobrar y Salida</span>
            <span class="badge-pastel-blue text-[10px] font-bold px-2 py-0.5 rounded-full">Liquidación</span>
          </div>
          <button @click="modalCobro = null" class="w-7 h-7 rounded-lg bg-surface-elevated text-text-muted hover:text-text-primary flex items-center justify-center text-sm font-bold transition-colors">✕</button>
        </div>

        <!-- Ficha del Vehículo con Placa Auténtica -->
        <div class="card-craft p-3.5 space-y-2.5">
          <div class="flex items-center justify-between">
            <span 
              class="plate-colombia text-sm font-mono font-black shadow-sm"
              :class="(modalCobro.registro.tipos_vehiculo?.nombre || '').toLowerCase().includes('moto') ? 'plate-moto' : 'plate-carro'"
            >
              {{ modalCobro.registro.placa }}
            </span>
            <span class="text-xs font-bold text-text-secondary">
              {{ modalCobro.registro.tipos_vehiculo?.nombre || 'Vehículo' }}
            </span>
          </div>

          <div class="grid grid-cols-2 gap-2 text-xs pt-1 border-t border-border/60">
            <div>
              <span class="text-[10px] font-bold uppercase text-text-muted">Entrada</span>
              <p class="font-mono font-semibold text-text-primary">{{ formatearHora(modalCobro.registro.entrada_at) }}</p>
            </div>
            <div>
              <span class="text-[10px] font-bold uppercase text-text-muted">Estancia</span>
              <p class="font-mono font-bold text-sky-700 dark:text-sky-300">{{ formatearTiempoEstancia(modalCobro.minutos) }}</p>
            </div>
          </div>
        </div>

        <!-- Banner de Total a Cobrar en Pastel Menta Iluminado -->
        <div class="pastel-card-mint p-4 rounded-xl text-center shadow-xs">
          <span class="text-[10px] font-bold uppercase tracking-wider text-emerald-800 dark:text-emerald-300">Total Liquidado</span>
          <div class="text-3xl font-black text-emerald-700 dark:text-emerald-400 font-mono num-tabular tracking-tight">
            ${{ modalCobro.valorTotal.toLocaleString() }} <span class="text-xs font-bold font-sans">COP</span>
          </div>
        </div>

        <!-- Método de Pago -->
        <div>
          <label class="block text-xs font-bold mb-1 text-text-secondary">Método de Pago</label>
          <select v-model="modalCobro.metodoPagoId" class="w-full px-3 py-2 text-xs font-semibold rounded-xl bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary">
            <option v-for="m in metodosPagoDisponibles" :key="m.id" :value="m.id">
              {{ m.nombre }} {{ m.es_efectivo ? '(Efectivo)' : '' }}
            </option>
          </select>
        </div>

        <!-- Si es efectivo: Billetes Rápidos Colombianos y Vuelto Dinámico -->
        <div v-if="esMetodoEfectivo" class="space-y-2">
          <div class="flex items-center justify-between">
            <label class="text-xs font-bold text-text-secondary">Efectivo Recibido</label>
            <span class="text-[10px] font-semibold text-text-muted">Billetes rápidos</span>
          </div>

          <div class="grid grid-cols-5 gap-1.5">
            <button type="button" @click="modalCobro.pagaCon = modalCobro.valorTotal" class="py-1 px-1 text-[10px] font-black rounded-lg border border-border bg-surface hover:bg-surface-elevated text-text-primary transition-all">Exacto</button>
            <button type="button" @click="modalCobro.pagaCon = 10000" class="py-1 px-1 text-[10px] font-black rounded-lg border border-border bg-surface hover:bg-surface-elevated text-text-primary transition-all">$10k</button>
            <button type="button" @click="modalCobro.pagaCon = 20000" class="py-1 px-1 text-[10px] font-black rounded-lg border border-border bg-surface hover:bg-surface-elevated text-text-primary transition-all">$20k</button>
            <button type="button" @click="modalCobro.pagaCon = 50000" class="py-1 px-1 text-[10px] font-black rounded-lg border border-border bg-surface hover:bg-surface-elevated text-text-primary transition-all">$50k</button>
            <button type="button" @click="modalCobro.pagaCon = 100000" class="py-1 px-1 text-[10px] font-black rounded-lg border border-border bg-surface hover:bg-surface-elevated text-text-primary transition-all">$100k</button>
          </div>

          <input 
            v-model.number="modalCobro.pagaCon" 
            type="number" 
            class="w-full px-3 py-2 text-sm font-black text-center font-mono rounded-xl bg-surface-elevated border border-border focus:outline-none focus:border-primary text-text-primary"
            placeholder="Monto entregado por cliente..."
          />

          <!-- Cálculo Dinámico de Vuelto / Cambio -->
          <div v-if="modalCobro.pagaCon >= modalCobro.valorTotal" class="p-2.5 rounded-xl badge-pastel-mint flex items-center justify-between shadow-xs">
            <span class="text-xs font-bold flex items-center space-x-1.5">
              <span>💵</span>
              <span>Cambio a Devolver:</span>
            </span>
            <span class="font-mono font-black text-sm num-tabular">${{ (modalCobro.pagaCon - modalCobro.valorTotal).toLocaleString() }}</span>
          </div>
          <div v-else-if="modalCobro.pagaCon > 0" class="p-2 rounded-xl badge-pastel-amber text-xs font-bold text-center">
            Faltan ${{ (modalCobro.valorTotal - modalCobro.pagaCon).toLocaleString() }} para completar el total
          </div>
        </div>

        <div class="flex space-x-2 pt-2">
          <button 
            type="button" 
            @click="modalCobro = null" 
            class="w-1/3 py-2.5 text-xs font-semibold rounded-xl border border-border text-text-secondary hover:bg-surface-elevated transition-colors"
          >
            Cancelar
          </button>
          <button 
            @click="confirmarSalida"
            :disabled="guardandoSalida"
            class="w-2/3 py-2.5 text-xs font-bold rounded-xl btn-craft-success text-white shadow-md disabled:opacity-50 flex items-center justify-center space-x-1.5"
          >
            <svg v-if="guardandoSalida" class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
              <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4"></circle>
              <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8v8H4z"></path>
            </svg>
            <span>{{ guardandoSalida ? 'Cobrando...' : 'Confirmar Salida y Cobro' }}</span>
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

function formatearTiempoEstancia(min) {
  if (!min || min < 1) return '1 min'
  if (min < 60) return `${min} min`
  const h = Math.floor(min / 60)
  const m = min % 60
  return m === 0 ? `${h}h` : `${h}h ${m}m`
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
      tarifaId: infoCobro.registro.tarifa_id || infoCobro.registro.tarifas?.id || null,
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
