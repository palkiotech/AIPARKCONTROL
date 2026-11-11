import { supabase } from '@/lib/supabase'

export const superadminService = {
  /**
   * Obtiene la lista de parqueaderos con conteo de usuarios (HU-05)
   */
  async listarParqueaderos() {
    const { data, error } = await supabase.rpc('obtener_parqueaderos_superadmin')
    if (error) throw error
    return data || []
  },

  /**
   * Da de alta un nuevo parqueadero (HU-01)
   */
  async crearParqueadero({ nombre, nit, direccion = '', telefono = '' }) {
    const { data, error } = await supabase.rpc('crear_parqueadero', {
      p_nombre: nombre.trim(),
      p_nit: nit.trim(),
      p_direccion: direccion.trim(),
      p_telefono: telefono.trim()
    })
    if (error) throw error
    return data
  },

  /**
   * Suspende o activa un parqueadero (HU-05)
   */
  async cambiarEstado(parqueaderoId, nuevoEstado) {
    const { data, error } = await supabase.rpc('cambiar_estado_parqueadero', {
      p_parqueadero_id: parqueaderoId,
      p_nuevo_estado: nuevoEstado
    })
    if (error) throw error
    return data
  }
}
