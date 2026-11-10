<template>
  <div class="space-y-6">
    <div>
      <h2 class="text-xl md:text-2xl font-bold tracking-tight">Dashboard General</h2>
      <p class="text-sm text-text-secondary">Monitoreo de ingresos, ocupación de patio y estado de mensualidades.</p>
    </div>

    <!-- Tarjetas de prueba del sistema de diseño (tokens de color) -->
    <div class="grid grid-cols-1 sm:grid-cols-3 gap-4">
      <div class="bg-surface p-4 rounded-xl border border-border shadow-sm">
        <span class="text-xs font-semibold text-danger uppercase tracking-wider">Vencidas</span>
        <p class="text-2xl font-bold mt-1 text-danger">0 clientes</p>
        <p class="text-xs text-text-muted mt-1">$0 por cobrar</p>
      </div>

      <div class="bg-surface p-4 rounded-xl border border-border shadow-sm">
        <span class="text-xs font-semibold text-warning uppercase tracking-wider">Por vencer</span>
        <p class="text-2xl font-bold mt-1 text-warning">0 clientes</p>
        <p class="text-xs text-text-muted mt-1">Próximos 5 días</p>
      </div>

      <div class="bg-surface p-4 rounded-xl border border-border shadow-sm">
        <span class="text-xs font-semibold text-success uppercase tracking-wider">Al día</span>
        <p class="text-2xl font-bold mt-1 text-success">0 clientes</p>
        <p class="text-xs text-text-muted mt-1">Sin acciones pendientes</p>
      </div>
    </div>
  </div>
</template>

<script setup>
</script>
