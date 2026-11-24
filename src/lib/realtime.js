import { supabase } from '@/lib/supabase'
import { registrarLimpieza } from '@/lib/sesionCaches'

/**
 * Suscripciones Realtime compartidas: un solo canal por tabla y parqueadero,
 * con varios oyentes (vistas) encima.
 *
 * Por qué: supabase.channel() devuelve el canal existente si el nombre se
 * repite. Las vistas que se suscribían después de la primera no recibían
 * eventos y la primera que se desmontaba cerraba el canal de todas. Además, un
 * canal por tabla reduce conexiones y mensajes del plan gratuito.
 *
 * Cada oyente recibe el payload de postgres_changes, o { reconectado: true }
 * cuando el canal vuelve a quedar suscrito tras una caída (pudo perder eventos).
 */
const canales = new Map()

function crearCanal(clave, tablas, parqueaderoId) {
  const entrada = { oyentes: new Set(), estado: 'CONECTANDO', yaSuscrito: false, canal: null }
  const avisar = (payload) => {
    for (const oyente of entrada.oyentes) {
      try { oyente(payload) } catch (e) { console.warn('Error en oyente Realtime:', e) }
    }
  }
  // Nombre único: un canal recién cerrado con el mismo nombre no se reutiliza
  let canal = supabase.channel(`${clave}-${crypto.randomUUID()}`)
  for (const tabla of tablas) {
    canal = canal.on('postgres_changes', { event: '*', schema: 'public', table: tabla, filter: `parqueadero_id=eq.${parqueaderoId}` }, avisar)
  }
  entrada.canal = canal.subscribe((estado) => {
    entrada.estado = estado
    if (estado === 'SUBSCRIBED') {
      if (entrada.yaSuscrito) avisar({ reconectado: true })
      entrada.yaSuscrito = true
    }
  })
  return entrada
}

/**
 * Escucha cambios de una o varias tablas del parqueadero.
 * @returns {() => void} función para dejar de escuchar
 */
export function escucharTablas(tablas, parqueaderoId, oyente) {
  if (!parqueaderoId) return () => {}
  const clave = `${tablas.join('+')}-${parqueaderoId}`
  let entrada = canales.get(clave)
  if (!entrada) {
    entrada = crearCanal(clave, tablas, parqueaderoId)
    canales.set(clave, entrada)
  }
  entrada.oyentes.add(oyente)
  return () => {
    entrada.oyentes.delete(oyente)
    if (entrada.oyentes.size === 0 && canales.get(clave) === entrada) {
      canales.delete(clave)
      supabase.removeChannel(entrada.canal)
    }
  }
}

registrarLimpieza(() => {
  for (const entrada of canales.values()) supabase.removeChannel(entrada.canal)
  canales.clear()
})
