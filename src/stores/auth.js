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
      // 1. Intentar sesión local en caché (para demo u offline)
      const cached = authService.obtenerPerfilCacheado()
      if (cached && cached.activo) {
        profile.value = cached.usuario
        parqueadero.value = cached.parqueadero
        session.value = { user: { id: cached.usuario.id } }
        loading.value = false
        return
      }

      // 2. Si no hay caché, consultar Supabase Auth
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

  /**
   * Acceso rápido de demostración para exploración local
   */
  function entrarComoDemo(rol = 'admin') {
    const perfilesDemo = {
      superadmin: {
        activo: true,
        usuario: { id: 'demo-superadmin', nombre: 'Alejandro (Superadmin)', rol: 'superadmin', parqueadero_id: null },
        parqueadero: null
      },
      admin: {
        activo: true,
        usuario: { id: 'demo-admin', nombre: 'Alejandro (Dueño)', rol: 'admin', parqueadero_id: 'pq-demo-001' },
        parqueadero: { id: 'pq-demo-001', nombre: 'Parqueadero Central', nit: '900.123.456-7', estado: 'activo' }
      },
      operador: {
        activo: true,
        usuario: { id: 'demo-operador', nombre: 'Juan (Portero)', rol: 'operador', parqueadero_id: 'pq-demo-001' },
        parqueadero: { id: 'pq-demo-001', nombre: 'Parqueadero Central', nit: '900.123.456-7', estado: 'activo' }
      }
    }

    const elegido = perfilesDemo[rol] || perfilesDemo.admin
    session.value = { user: { id: elegido.usuario.id, email: `${rol}@parkcontrol.com` } }
    profile.value = elegido.usuario
    parqueadero.value = elegido.parqueadero
    authService.guardarPerfilCacheado(elegido)
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
    entrarComoDemo,
    logout
  }
})
