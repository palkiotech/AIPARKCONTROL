import { supabase } from '@/lib/supabase'
import { obtenerOperacionesPendientes, eliminarOperacionesSincronizadas, contarOperacionesPendientes } from './cola'
import { syncServerTime } from './clockDrift'

let sincronizando = false
let intentosFallidos = 0
let temporizadorReintento = null

const ESPERA_MAX_MS = 5 * 60 * 1000

/**
 * Mide el desfase entre el reloj del dispositivo y el del servidor
 * (decisión #8). Usa el punto medio del viaje de ida y vuelta.
 */
export async function medirDesfaseHorario() {
  if (typeof navigator !== 'undefined' && !navigator.onLine) return null
  try {
    const t0 = Date.now()
    const { data, error } = await supabase.rpc('hora_servidor')
    const t1 = Date.now()
    if (error || !data) return null
    const servidorMs = new Date(data).getTime()
    // El servidor respondió aproximadamente a mitad del viaje de ida y vuelta
    syncServerTime(servidorMs, (t0 + t1) / 2)
    return true
  } catch (e) {
    return null
  }
}

function programarReintento(conexionStore) {
  if (temporizadorReintento) clearTimeout(temporizadorReintento)
  const espera = Math.min(ESPERA_MAX_MS, 5000 * Math.pow(2, intentosFallidos))
  temporizadorReintento = setTimeout(() => {
    temporizadorReintento = null
    sincronizarAhora(conexionStore).catch(() => {})
  }, espera)
}

export async function sincronizarAhora(conexionStore = null) {
  if (sincronizando) return { estado: 'en_progreso' }
  if (typeof navigator !== 'undefined' && !navigator.onLine) {
    return { estado: 'sin_red' }
  }

  sincronizando = true
  if (conexionStore?.setSincronizando) conexionStore.setSincronizando(true)

  try {
    const pendientes = await obtenerOperacionesPendientes()
    if (!pendientes.length) {
      if (conexionStore) conexionStore.setPendingCount(0)
      intentosFallidos = 0
      return { estado: 'completado', procesadas: 0 }
    }

    const { data, error } = await supabase.rpc('sincronizar_operaciones', {
      p_operaciones: pendientes.map(op => ({
        id: op.id,
        tipo: op.tipo,
        payload: op.payload,
        creada_en_dispositivo_at: op.creada_en_dispositivo_at
      }))
    })

    if (error) throw error

    // El servidor registra cada operación en operaciones_sync (ok, conflicto o
    // error) e ignora las repetidas, así que todas las enviadas ya quedaron
    // asentadas y se pueden quitar de la cola local.
    const asentadas = (data?.resultados || []).map(r => r.id)
    await eliminarOperacionesSincronizadas(asentadas.length ? asentadas : pendientes.map(op => op.id))

    const restantes = await contarOperacionesPendientes()
    if (conexionStore) conexionStore.setPendingCount(restantes)

    if (data?.ahora) syncServerTime(data.ahora)
    intentosFallidos = 0

    return {
      estado: 'completado',
      procesadas: data?.procesadas ?? pendientes.length,
      conflictos: data?.conflictos ?? 0
    }
  } catch (err) {
    console.warn('Fallo en sincronización:', err)
    intentosFallidos++
    programarReintento(conexionStore)
    reportarFalloSync(err)
    return { estado: 'error', error: err.message }
  } finally {
    sincronizando = false
    if (conexionStore?.setSincronizando) conexionStore.setSincronizando(false)
  }
}

function reportarFalloSync(err) {
  try {
    fetch('/api/log', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tipo: 'fallo_sync', mensaje: err?.message, timestamp: new Date().toISOString() })
    }).catch(() => {})
  } catch (e) {}
}

let conexionStoreRegistrado = null

/**
 * Registra el store de conexión y sincroniza automáticamente al volver la red.
 */
export function iniciarSincronizacionAutomatica(conexionStore) {
  conexionStoreRegistrado = conexionStore
  contarOperacionesPendientes().then(n => conexionStore.setPendingCount(n)).catch(() => {})
}

if (typeof window !== 'undefined') {
  window.addEventListener('online', () => {
    medirDesfaseHorario().finally(() => {
      sincronizarAhora(conexionStoreRegistrado).catch(() => {})
    })
  })
}
