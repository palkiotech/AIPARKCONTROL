import { defineStore } from 'pinia'
import { ref } from 'vue'
import { isClockDriftCritical, getClockOffsetMs } from '@/offline/clockDrift'

export const useConexionStore = defineStore('conexion', () => {
  const isOnline = ref(typeof navigator !== 'undefined' ? navigator.onLine : true)
  const pendingOperationsCount = ref(0)
  const sincronizando = ref(false)
  const hasClockDriftWarning = ref(isClockDriftCritical())
  const desfaseMinutos = ref(Math.round(getClockOffsetMs() / 60000))

  function updateOnlineStatus() {
    isOnline.value = navigator.onLine
    checkClockDrift()
  }

  function setPendingCount(count) {
    pendingOperationsCount.value = count
  }

  function setSincronizando(valor) {
    sincronizando.value = valor
  }

  function checkClockDrift() {
    hasClockDriftWarning.value = isClockDriftCritical()
    desfaseMinutos.value = Math.round(getClockOffsetMs() / 60000)
  }

  if (typeof window !== 'undefined') {
    window.addEventListener('online', updateOnlineStatus)
    window.addEventListener('offline', updateOnlineStatus)
  }

  return {
    isOnline,
    pendingOperationsCount,
    sincronizando,
    hasClockDriftWarning,
    desfaseMinutos,
    setPendingCount,
    setSincronizando,
    checkClockDrift,
    updateOnlineStatus
  }
})
