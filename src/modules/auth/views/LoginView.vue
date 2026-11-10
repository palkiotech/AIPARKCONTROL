<template>
  <div class="min-h-screen flex items-center justify-center p-4 bg-background">
    <div class="w-full max-w-sm bg-surface p-6 rounded-2xl border border-border shadow-md">
      <div class="text-center mb-6">
        <div class="w-12 h-12 bg-primary text-white rounded-xl mx-auto flex items-center justify-center font-bold text-2xl mb-2">
          P
        </div>
        <h2 class="text-xl font-bold">Iniciar Sesión</h2>
        <p class="text-xs text-text-muted">Acceso a ParkControl</p>
      </div>

      <form class="space-y-4">
        <div>
          <label class="block text-xs font-semibold mb-1">Correo electrónico</label>
          <input 
            type="email" 
            class="w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary"
            placeholder="usuario@parqueadero.com"
          />
        </div>

        <div>
          <label class="block text-xs font-semibold mb-1">Contraseña</label>
          <input 
            type="password" 
            class="w-full px-3 py-2 text-sm rounded-lg bg-surface-elevated border border-border focus:outline-none focus:border-primary"
            placeholder="••••••••"
          />
        </div>

        <button 
          type="button" 
          class="w-full py-2.5 px-4 bg-primary text-white font-semibold rounded-lg text-sm hover:opacity-90 transition-opacity"
        >
          Entrar
        </button>
      </form>
    </div>
  </div>
</template>

<script setup>
</script>
