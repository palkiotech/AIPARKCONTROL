import { supabase } from '@/lib/supabase'
import { obtenerOperacionesPendientes, eliminarOperacionesSincronizadas, contarOperacionesPendientes } from './cola'
import { syncServerTime } from './clockDrift'

let sincronizando = false

export async function sincronizarAhora(conexionStore = null) {
  if (sincronizando) return { estado: 'en_progreso' }
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    return { estado: 'sin_red' }
  }

  sincronizando = true

  try {
    const pendientes = await obtenerOperacionesPendientes()
    if (!pendientes.length) {
      if (conexionStore) conexionStore.setPendingCount(0)
      return { estado: 'completado', procesadas: 0 }
    }

    const payloadSincronizacion = pendientes.map(op => ({
      id: op.id,
      tipo: op.tipo,
      payload: op.payload,
      creada_en_dispositivo_at: op.creada_en_dispositivo_at
    }))

    // Invocación a la RPC transaccional e idempotente
    const { data, error } = await supabase.rpc('sincronizar_operaciones', {
      p_operaciones: payloadSincronizacion
    })

    if (error) throw error

    // Eliminar de IndexedDB las operaciones sincronizadas con éxito
    const idsSincronizados = pendientes.map(op => op.id)
    await eliminarOperacionesSincronizadas(idsSincronizados)

    const restantes = await contarOperacionesPendientes()
    if (conexionStore) {
      conexionStore.setPendingCount(restantes)
    }

    // Actualizar clock drift con la hora de respuesta del servidor si está disponible
    syncServerTime(Date.now())

    return {
      estado: 'completado',
      procesadas: data?.procesadas || pendientes.length,
      conflictos: data?.conflictos || 0
    }
  } catch (err) {
    console.warn('Fallo en sincronización:', err)
    return { estado: 'error', error: err.message }
  } finally {
    sincronizando = false
  }
}

// Escuchar evento online para sincronizar de forma automática
if (typeof window !== 'undefined') {
  window.addEventListener('online', () => {
    sincronizarAhora().catch(() => {})
  })
}
