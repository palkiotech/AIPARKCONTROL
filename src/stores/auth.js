import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authService } from '@/modules/auth/services/authService'
import { supabase } from '@/lib/supabase'

export const useAuthStore = defineStore('auth', () => {
  const session = ref(null)
  const profile = ref(null)
  const parqueadero = ref(null)
  const loading = ref(true)

  const isAuthenticated = computed(() => !!session.value)
  const userRole = computed(() => profile.value?.rol || 'operador')
  const parqueaderoId = computed(() => profile.value?.parqueadero_id || null)
  const isSuperadmin = computed(() => userRole.value === 'superadmin')
  const isAdmin = computed(() => userRole.value === 'admin' || isSuperadmin.value)
  const isOperador = computed(() => userRole.value === 'operador')

  /**
   * Inicializa la sesión y recupera perfil
   */
  async function inicializarSesion() {
    loading.value = true
    try {
      const { data: { session: currentSession } } = await supabase.auth.getSession()
      if (currentSession) {
        session.value = currentSession
        const perfilData = await authService.cargarMiPerfil()
        if (perfilData?.activo) {
          profile.value = perfilData.usuario
          parqueadero.value = perfilData.parqueadero
        } else {
          await logout()
        }
      }
    } catch (e) {
      console.warn('Error inicializando sesión:', e)
    } finally {
      loading.value = false
    }
  }

  async function login(email, password) {
    loading.value = true
    try {
      const result = await authService.login(email, password)
      session.value = result.session
      profile.value = result.perfil.usuario
      parqueadero.value = result.perfil.parqueadero
      return result
    } finally {
      loading.value = false
    }
  }

  async function logout() {
    await authService.logout()
    session.value = null
    profile.value = null
    parqueadero.value = null
  }

  return {
    session,
    profile,
    parqueadero,
    loading,
    isAuthenticated,
    userRole,
    parqueaderoId,
    isSuperadmin,
    isAdmin,
    isOperador,
    inicializarSesion,
    login,
    logout
  }
})
