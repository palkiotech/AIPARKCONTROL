<template>
  <svg
    :class="clase"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.8"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <template v-if="tipo === 'moto'">
      <circle cx="5.5" cy="16.5" r="3" />
      <circle cx="18.5" cy="16.5" r="3" />
      <path d="M5.5 16.5 9 10h5l2.5 6.5M14 10l1.5-3H18M9 10 7.5 7H5" />
    </template>
    <template v-else-if="tipo === 'bici'">
      <circle cx="5.5" cy="16.5" r="3.5" />
      <circle cx="18.5" cy="16.5" r="3.5" />
      <path d="M5.5 16.5 9 9h6l3.5 7.5M12 16.5 9 9M15 9l-1-3h-2.5" />
    </template>
    <template v-else>
      <path d="M5 17H3.5a1 1 0 0 1-1-1v-3.2a2 2 0 0 1 .6-1.4L5 9.5l1.6-3.2A2 2 0 0 1 8.4 5h7.2a2 2 0 0 1 1.8 1.3L19 9.5l1.9 1.9a2 2 0 0 1 .6 1.4V16a1 1 0 0 1-1 1H19" />
      <path d="M5 9.5h14" />
      <circle cx="7.5" cy="17" r="2" />
      <circle cx="16.5" cy="17" r="2" />
      <path d="M9.5 17h5" />
    </template>
  </svg>
</template>

<script setup>
import { computed } from 'vue'

// Ícono por tipo de vehículo. Acepta el nombre del tipo ("Moto", "Bicicleta",
// "Carro", "Camioneta"...) o directamente 'moto' | 'bici' | 'carro'.
const props = defineProps({
  nombre: { type: String, default: '' },
  clase: { type: String, default: 'w-5 h-5' }
})

const tipo = computed(() => {
  const n = (props.nombre || '').toLowerCase()
  if (n.includes('moto')) return 'moto'
  if (n.includes('bici') || n.includes('cicla')) return 'bici'
  return 'carro'
})
</script>
