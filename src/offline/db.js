import Dexie from 'dexie'

export const db = new Dexie('ParkControlOfflineDB')

db.version(1).stores({
  cola_operaciones: '++localId, id, tipo, estado, creada_en_dispositivo_at',
  cache_referencia: 'clave, actualizado_at'
})
