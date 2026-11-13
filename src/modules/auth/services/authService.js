import { supabase } from '@/lib/supabase'
import { syncServerTime } from '@/offline/clockDrift'

const PROFILE_CACHE_KEY = 'parkcontrol_profile_cache'

export const authService = {
  /**
   * Inicia sesión con email y contraseña (HU-02)
   */
  async login(email, password) {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: email.trim(),
      password
    })

    if (error) {
      throw new Error(error.message === 'Invalid login credentials'
        ? 'Correo o contraseña incorrectos'
        : error.message)
    }

    // Cargar perfil y validar estado activo / suspendido
    const perfilInfo = await this.cargarMiPerfil({ permitirCache: false })
    if (!perfilInfo?.activo) {
      await this.logout()
      throw new Error(perfilInfo?.motivo || 'Tu cuenta o parqueadero no están activos')
    }

    return { session: data.session, perfil: perfilInfo }
  },

  /**
   * Sesión de Supabase guardada en el dispositivo (funciona sin conexión:
   * se lee de localStorage y no se invalida aunque no se pueda refrescar el JWT).
   */
  async obtenerSesion() {
    const { data } = await supabase.auth.getSession()
    return data?.session || null
  },

  onCambioSesion(callback) {
    const { data } = supabase.auth.onAuthStateChange((evento, session) => callback(evento, session))
    return () => data?.subscription?.unsubscribe()
  },

  /**
   * Cierra sesión y limpia la caché local
   */
  async logout() {
    try {
      await supabase.auth.signOut()
    } catch (e) {
      console.warn('Error al cerrar sesión remota:', e)
    } finally {
      this.borrarPerfilCacheado()
    }
  },

  /**
   * Solicita recuperación de contraseña
   */
  async recuperarPassword(email) {
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/recuperar`
    })
    if (error) throw error
    return true
  },

  /**
   * Define una nueva contraseña (llegando desde el enlace de invitación o recuperación)
   */
  async definirPassword(password) {
    const { error } = await supabase.auth.updateUser({ password })
    if (error) throw error
    return true
  },

  /**
   * Carga el perfil del usuario autenticado vía RPC segura.
   * Solo si NO hay red se usa la copia en caché (tolerancia offline, HU-02).
   * Si el servidor responde que el usuario o el parqueadero no están activos,
   * se respeta esa respuesta aunque exista caché.
   */
  async cargarMiPerfil({ permitirCache = true } = {}) {
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      return permitirCache ? this.obtenerPerfilCacheado() : null
    }

    try {
      const { data, error } = await supabase.rpc('obtener_mi_perfil')
      if (error) throw error

      if (data?.ahora) syncServerTime(data.ahora)

      if (data?.activo) {
        this.guardarPerfilCacheado(data)
      } else {
        this.borrarPerfilCacheado()
      }
      return data
    } catch (err) {
      const esRed = err?.name === 'TypeError' || String(err?.message || '').includes('fetch')
      if (permitirCache && esRed) {
        const cache = this.obtenerPerfilCacheado()
        if (cache) return cache
      }
      throw err
    }
  },

  guardarPerfilCacheado(data) {
    try {
      localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(data))
    } catch (e) {}
  },

  borrarPerfilCacheado() {
    try {
      localStorage.removeItem(PROFILE_CACHE_KEY)
    } catch (e) {}
  },

  obtenerPerfilCacheado() {
    try {
      const raw = localStorage.getItem(PROFILE_CACHE_KEY)
      return raw ? JSON.parse(raw) : null
    } catch (e) {
      return null
    }
  }
}
