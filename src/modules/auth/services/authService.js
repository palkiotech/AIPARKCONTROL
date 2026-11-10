import { supabase } from '@/lib/supabase'

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
    const perfilInfo = await this.cargarMiPerfil()
    if (!perfilInfo.activo) {
      await this.logout()
      throw new Error(perfilInfo.motivo || 'Tu cuenta o parqueadero no están activos')
    }

    return { session: data.session, perfil: perfilInfo }
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
      try {
        localStorage.removeItem(PROFILE_CACHE_KEY)
      } catch (e) {}
    }
  },

  /**
   * Solicita recuperación de contraseña
   */
  async recuperarPassword(email) {
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/login`
    })
    if (error) throw error
    return true
  },

  /**
   * Carga el perfil del usuario autenticado vía RPC segura
   * Si está offline, recupera la copia en caché (Recomendación #2)
   */
  async cargarMiPerfil() {
    // Si no hay red, leer caché local
    if (typeof navigator !== 'undefined' && !navigator.onLine) {
      return this.obtenerPerfilCacheado()
    }

    try {
      const { data, error } = await supabase.rpc('obtener_mi_perfil')
      if (error) throw error

      if (data && data.activo) {
        this.guardarPerfilCacheado(data)
      }
      return data
    } catch (err) {
      // Si falla la red, intentar rescate con caché local
      const cache = this.obtenerPerfilCacheado()
      if (cache) return cache
      throw err
    }
  },

  guardarPerfilCacheado(data) {
    try {
      localStorage.setItem(PROFILE_CACHE_KEY, JSON.stringify(data))
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
