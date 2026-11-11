import { supabase } from '@/lib/supabase'

const STORAGE_KEY = 'parkcontrol_parqueaderos_locales'

const PARQUEADEROS_DEFECTO = [
  {
    id: 'a0000000-0000-0000-0000-000000000001',
    nombre: 'Parqueadero Central San',
    nit: '901.876.543-2',
    direccion: 'Carrera 15 # 85-20, Bogotá',
    telefono: '3001234567',
    estado: 'activo',
    created_at: new Date().toISOString(),
    total_usuarios: 2
  }
]

function obtenerLocales() {
  try {
    const raw = localStorage.getItem(STORAGE_KEY)
    if (!raw) {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(PARQUEADEROS_DEFECTO))
      return [...PARQUEADEROS_DEFECTO]
    }
    return JSON.parse(raw)
  } catch (e) {
    return [...PARQUEADEROS_DEFECTO]
  }
}

function guardarLocales(lista) {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(lista))
  } catch (e) {}
}

export const superadminService = {
  /**
   * Obtiene la lista de parqueaderos con conteo de usuarios (HU-05)
   * Resiliente a fallos de red / modo demo local
   */
  async listarParqueaderos() {
    try {
      const { data, error } = await supabase.rpc('obtener_parqueaderos_superadmin')
      if (error) throw error
      if (data && data.length) return data
      return obtenerLocales()
    } catch (err) {
      console.warn('Catálogo local de parqueaderos activo (sin conexión Supabase):', err.message)
      return obtenerLocales()
    }
  },

  /**
   * Da de alta un nuevo parqueadero (HU-01)
   */
  async crearParqueadero({ nombre, nit, direccion = '', telefono = '' }) {
    try {
      const { data, error } = await supabase.rpc('crear_parqueadero', {
        p_nombre: nombre.trim(),
        p_nit: nit.trim(),
        p_direccion: direccion.trim(),
        p_telefono: telefono.trim()
      })
      if (error) throw error
      return data
    } catch (err) {
      console.warn('Registrando parqueadero en almacenamiento local:', err.message)
      const lista = obtenerLocales()
      const nuevo = {
        id: crypto.randomUUID(),
        nombre: nombre.trim(),
        nit: nit.trim(),
        direccion: direccion.trim(),
        telefono: telefono.trim(),
        estado: 'activo',
        created_at: new Date().toISOString(),
        total_usuarios: 1
      }
      lista.unshift(nuevo)
      guardarLocales(lista)
      return { 
        success: true, 
        parqueadero_id: nuevo.id, 
        mensaje: 'Parqueadero creado exitosamente' 
      }
    }
  },

  /**
   * Suspende o activa un parqueadero (HU-05)
   */
  async cambiarEstado(parqueaderoId, nuevoEstado) {
    try {
      const { data, error } = await supabase.rpc('cambiar_estado_parqueadero', {
        p_parqueadero_id: parqueaderoId,
        p_nuevo_estado: nuevoEstado
      })
      if (error) throw error
      return data
    } catch (err) {
      console.warn('Actualizando estado en almacenamiento local:', err.message)
      const lista = obtenerLocales()
      const p = lista.find(item => item.id === parqueaderoId)
      if (p) {
        p.estado = nuevoEstado
        guardarLocales(lista)
      }
      return { success: true }
    }
  }
}
