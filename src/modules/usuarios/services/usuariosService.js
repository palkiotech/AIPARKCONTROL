import { supabase } from '@/lib/supabase'

/**
 * Gestión de usuarios del parqueadero (HU-03). Solo admin.
 * Las invitaciones pasan por la Edge Function "invitar-usuario" (usa la service
 * key en el servidor, nunca en el navegador).
 */

async function leerErrorFuncion(error) {
  // supabase-js envuelve la respuesta de error de la función en error.context
  try {
    const cuerpo = await error?.context?.json?.()
    if (cuerpo?.error) return cuerpo.error
  } catch (e) {}
  return error?.message || 'No se pudo completar la invitación'
}

export const usuariosService = {
  async listar() {
    const { data, error } = await supabase.rpc('listar_usuarios_parqueadero')
    if (error) throw error
    return data || []
  },

  /**
   * Invita un usuario por correo. Lo usan el admin (a su parqueadero) y el
   * superadmin (al admin de un parqueadero nuevo, enviando parqueaderoId).
   */
  async invitar({ email, nombre, rol = 'operador', parqueaderoId = null }) {
    const { data, error } = await supabase.functions.invoke('invitar-usuario', {
      body: {
        email: email.trim(),
        nombre: nombre.trim(),
        rol,
        parqueadero_id: parqueaderoId,
        redirect_to: `${window.location.origin}/recuperar`
      }
    })
    if (error) throw new Error(await leerErrorFuncion(error))
    if (data?.error) throw new Error(data.error)
    return data
  },

  async actualizar(usuarioId, { nombre = null, rol = null, activo = null }) {
    const { data, error } = await supabase.rpc('actualizar_usuario', {
      p_usuario_id: usuarioId,
      p_nombre: nombre,
      p_rol: rol,
      p_activo: activo
    })
    if (error) throw error
    return data
  },

  /**
   * Reenvía el acceso: correo para definir/restablecer la contraseña.
   */
  async reenviarAcceso(email) {
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/recuperar`
    })
    if (error) throw error
    return true
  }
}
