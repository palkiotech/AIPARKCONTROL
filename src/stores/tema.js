import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

const CLAVE = 'parkcontrol_theme'
const TEMAS = ['light', 'dark', 'system']

function leerTemaGuardado() {
  try {
    const t = localStorage.getItem(CLAVE)
    return TEMAS.includes(t) ? t : 'system'
  } catch (e) {
    return 'system'
  }
}

const mediaOscuro = typeof window !== 'undefined' && window.matchMedia
  ? window.matchMedia('(prefers-color-scheme: dark)')
  : null

/**
 * Aplica el tema a <html> antes de montar la app (evita parpadeo, HU-10).
 */
export function aplicarTemaInicial() {
  if (typeof document === 'undefined') return
  const tema = leerTemaGuardado()
  const oscuro = tema === 'dark' || (tema === 'system' && !!mediaOscuro?.matches)
  document.documentElement.classList.toggle('dark', oscuro)
}

export const useTemaStore = defineStore('tema', () => {
  const currentTheme = ref(leerTemaGuardado())
  const sistemaOscuro = ref(!!mediaOscuro?.matches)

  const isDark = computed(() => {
    if (currentTheme.value === 'dark') return true
    if (currentTheme.value === 'light') return false
    return sistemaOscuro.value
  })

  function applyTheme() {
    if (typeof document === 'undefined') return
    document.documentElement.classList.toggle('dark', isDark.value)
  }

  /**
   * @param {'light'|'dark'|'system'} theme
   */
  function setTheme(theme) {
    currentTheme.value = TEMAS.includes(theme) ? theme : 'system'
    try {
      localStorage.setItem(CLAVE, currentTheme.value)
    } catch (e) {}
    applyTheme()
  }

  if (mediaOscuro) {
    mediaOscuro.addEventListener('change', (e) => {
      sistemaOscuro.value = e.matches
      if (currentTheme.value === 'system') applyTheme()
    })
  }
  applyTheme()

  return {
    currentTheme,
    isDark,
    setTheme,
    applyTheme
  }
})
