import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import { authService } from '@/modules/auth/services/authService'
import { limpiarCachesDeSesion } from '@/lib/sesionCaches'
import { borrarReferencias } from '@/offline/referencia'

export const useAuthStore = defineStore('auth', () => {
  const session = ref(null)
  const profile = ref(null)
  const parqueadero = ref(null)
  const loading = ref(true)
  const motivoSalida = ref('')
  let inicializado = false

  const isAuthenticated = computed(() => !!session.value && !!profile.value)
  const userRole = computed(() => profile.value?.rol || null)
  const userName = computed(() => profile.value?.nombre || '')
  const parqueaderoId = computed(() => profile.value?.parqueadero_id || null)
  const zonaHoraria = computed(() => parqueadero.value?.zona_horaria || 'America/Bogota')
  const diasAviso = computed(() => parqueadero.value?.dias_aviso_vencimiento ?? 5)
  const isSuperadmin = computed(() => userRole.value === 'superadmin')
  const isAdmin = computed(() => userRole.value === 'admin')
  const isOperador = computed(() => userRole.value === 'operador')
  const rolLegible = computed(() => ({
    superadmin: 'Superadmin',
    admin: 'Administrador',
    operador: 'Operador'
  }[userRole.value] || ''))

  function aplicarPerfil(perfilData) {
    profile.value = perfilData?.usuario || null
    parqueadero.value = perfilData?.parqueadero || null
  }

  function limpiarEstado() {
    session.value = null
    profile.value = null
    parqueadero.value = null
    limpiarCachesDeSesion()
  }

  /**
   * Inicializa la sesión. La fuente de verdad es la sesión de Supabase:
   * sin sesión no se entra, aunque haya un perfil en caché. Con red, el perfil
   * se valida contra el servidor (usuario activo, parqueadero no suspendido).
   * Sin red, se usa el perfil en caché para no detener la operación (HU-02/HU-26).
   */
  async function inicializarSesion() {
    if (inicializado) return
    loading.value = true
    try {
      const actual = await authService.obtenerSesion()
      if (!actual) {
        authService.borrarPerfilCacheado()
        limpiarEstado()
        return
      }
      session.value = actual
      const perfilData = await authService.cargarMiPerfil()
      if (perfilData?.activo) {
        aplicarPerfil(perfilData)
      } else {
        motivoSalida.value = perfilData?.motivo || ''
        await logout()
      }
    } catch (e) {
      console.warn('Error inicializando sesión:', e)
      limpiarEstado()
    } finally {
      inicializado = true
      loading.value = false
    }

    authService.onCambioSesion((evento, nuevaSesion) => {
      if (evento === 'SIGNED_OUT') {
        if (profile.value) motivoSalida.value = motivoSalida.value || 'Tu sesión expiró. Inicia sesión de nuevo.'
        limpiarEstado()
      } else if (nuevaSesion) {
        session.value = nuevaSesion
      }
    })
  }

  async function login(email, password) {
    loading.value = true
    motivoSalida.value = ''
    try {
      limpiarCachesDeSesion()
      const result = await authService.login(email, password)
      session.value = result.session
      aplicarPerfil(result.perfil)
      inicializado = true
      return result
    } finally {
      loading.value = false
    }
  }

  /**
   * Revalida el perfil contra el servidor (p. ej. al volver la conexión o tras
   * editar los datos del negocio en Ajustes).
   */
  async function refrescarPerfil() {
    if (!session.value) return
    try {
      const perfilData = await authService.cargarMiPerfil()
      if (perfilData?.activo) {
        aplicarPerfil(perfilData)
      } else if (perfilData) {
        motivoSalida.value = perfilData.motivo || ''
        await logout()
      }
    } catch (e) {
      console.warn('No se pudo refrescar el perfil:', e)
    }
  }

  async function logout() {
    await authService.logout()
    await borrarReferencias()
    limpiarEstado()
  }

  return {
    session,
    profile,
    parqueadero,
    loading,
    motivoSalida,
    isAuthenticated,
    userRole,
    userName,
    rolLegible,
    parqueaderoId,
    zonaHoraria,
    diasAviso,
    isSuperadmin,
    isAdmin,
    isOperador,
    inicializarSesion,
    login,
    refrescarPerfil,
    logout
  }
})
