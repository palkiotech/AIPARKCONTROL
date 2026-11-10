import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export const useTemaStore = defineStore('tema', () => {
  const currentTheme = ref(localStorage.getItem('parkcontrol_theme') || 'system')

  const isDark = computed(() => {
    if (currentTheme.value === 'dark') return true
    if (currentTheme.value === 'light') return false
    return window.matchMedia('(prefers-color-scheme: dark)').matches
  })

  function applyTheme() {
    if (typeof document === 'undefined') return
    if (isDark.value) {
      document.documentElement.classList.add('dark')
    } else {
      document.documentElement.classList.remove('dark')
    }
  }

  function setTheme(theme) {
    currentTheme.value = theme
    try {
      localStorage.setItem('parkcontrol_theme', theme)
    } catch (e) {}
    applyTheme()
  }

  // Escuchar cambios de preferencia del sistema si está en 'system'
  if (typeof window !== 'undefined') {
    window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change', () => {
      if (currentTheme.value === 'system') {
        applyTheme()
      }
    })
    applyTheme()
  }

  return {
    currentTheme,
    isDark,
    setTheme,
    applyTheme
  }
})
