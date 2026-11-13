<template>
  <div class="min-h-screen grid grid-cols-1 lg:grid-cols-[minmax(0,1fr)_minmax(0,1.1fr)] bg-background">
    <!-- Panel de marca (escritorio) -->
    <aside class="hidden lg:flex flex-col justify-between p-12 bg-[#0b1630] text-white relative overflow-hidden">
      <div class="absolute inset-0 opacity-[0.07] pointer-events-none" style="background-image: linear-gradient(#fff 1px, transparent 1px), linear-gradient(90deg, #fff 1px, transparent 1px); background-size: 48px 48px;"></div>

      <div class="relative flex items-center gap-3">
        <svg class="w-10 h-10" viewBox="0 0 32 32" aria-hidden="true">
          <rect width="32" height="32" rx="8" fill="#2563eb" />
          <path d="M11 24V8h6.25a4.75 4.75 0 0 1 0 9.5H14.5V24H11zm3.5-9.75h2.6a1.75 1.75 0 0 0 0-3.5h-2.6v3.5z" fill="#fff" />
        </svg>
        <span class="text-lg font-semibold tracking-tight">ParkControl</span>
      </div>

      <div class="relative max-w-md">
        <h2 class="text-3xl font-semibold tracking-tight leading-tight">
          La operación de tu parqueadero, en orden y al día.
        </h2>
        <ul class="mt-8 space-y-4 text-sm text-slate-300">
          <li v-for="b in beneficios" :key="b" class="flex items-start gap-3">
            <span class="mt-0.5 flex-shrink-0 w-5 h-5 rounded-full bg-blue-500/20 text-blue-300 flex items-center justify-center">
              <svg class="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3"><path stroke-linecap="round" stroke-linejoin="round" d="M5 13l4 4L19 7" /></svg>
            </span>
            <span>{{ b }}</span>
          </li>
        </ul>
      </div>

      <p class="relative text-xs text-slate-400">© {{ anio }} ParkControl · Hecho para parqueaderos en Colombia</p>
    </aside>

    <!-- Formulario -->
    <main class="flex items-center justify-center p-5 sm:p-8">
      <div class="w-full max-w-sm">
        <div class="lg:hidden flex items-center gap-2.5 mb-8">
          <svg class="w-9 h-9" viewBox="0 0 32 32" aria-hidden="true">
            <rect width="32" height="32" rx="8" class="fill-primary" />
            <path d="M11 24V8h6.25a4.75 4.75 0 0 1 0 9.5H14.5V24H11zm3.5-9.75h2.6a1.75 1.75 0 0 0 0-3.5h-2.6v3.5z" fill="#fff" />
          </svg>
          <span class="text-lg font-semibold tracking-tight">ParkControl</span>
        </div>

        <h1 class="text-2xl font-semibold tracking-tight text-text-primary">{{ titulo }}</h1>
        <p v-if="subtitulo" class="mt-1.5 text-sm text-text-secondary">{{ subtitulo }}</p>

        <div class="mt-7">
          <slot />
        </div>
      </div>
    </main>
  </div>
</template>

<script setup>
defineProps({
  titulo: { type: String, required: true },
  subtitulo: { type: String, default: '' }
})

const anio = new Date().getFullYear()
const beneficios = [
  'Entradas y salidas con cobro automático según tus tarifas.',
  'Caja por turnos con entrega y recepción del efectivo.',
  'Mensualidades con avisos de cobro a tiempo.',
  'Sigue funcionando aunque se caiga el internet.'
]
</script>
