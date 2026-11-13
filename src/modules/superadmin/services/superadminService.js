import { supabase } from '@/lib/supabase'
import { usuariosService } from '@/modules/usuarios/services/usuariosService'

export const superadminService = {
  /**
   * Parqueaderos con email del admin, usuarios, registros del último mes y
   * última actividad (HU-05). No expone clientes, placas ni montos.
   */
  async listarParqueaderos() {
    const { data, error } = await supabase.rpc('obtener_parqueaderos_superadmin')
    if (error) throw error
    return data || []
  },

  /**
   * Da de alta un parqueadero (siembra Carro, Moto, una tarifa y "Efectivo")
   * e invita a su administrador por correo (HU-01).
   * Si la invitación falla (p. ej. correo ya registrado), el parqueadero queda
   * creado sin admin y se informa el motivo para reintentar.
   */
  async crearParqueadero({ nombre, nit, direccion = '', telefono = '', adminNombre, adminEmail }) {
    const { data, error } = await supabase.rpc('crear_parqueadero', {
      p_nombre: nombre.trim(),
      p_nit: nit.trim(),
      p_direccion: direccion.trim(),
      p_telefono: telefono.trim()
    })
    if (error) throw error

    let errorInvitacion = null
    if (adminEmail) {
      try {
        await usuariosService.invitar({
          email: adminEmail,
          nombre: adminNombre || 'Administrador',
          rol: 'admin',
          parqueaderoId: data.parqueadero_id
        })
      } catch (e) {
        errorInvitacion = e.message
      }
    }
    return { ...data, errorInvitacion }
  },

  async invitarAdmin(parqueaderoId, { nombre, email }) {
    return usuariosService.invitar({ email, nombre, rol: 'admin', parqueaderoId })
  },

  async reenviarAcceso(email) {
    return usuariosService.reenviarAcceso(email)
  },

  async cambiarEstado(parqueaderoId, nuevoEstado) {
    const { data, error } = await supabase.rpc('cambiar_estado_parqueadero', {
      p_parqueadero_id: parqueaderoId,
      p_nuevo_estado: nuevoEstado
    })
    if (error) throw error
    return data
  }
}
