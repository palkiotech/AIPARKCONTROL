import { defineStore } from 'pinia'
import { ref } from 'vue'
import { isClockDriftCritical } from '@/offline/clockDrift'

export const useConexionStore = defineStore('conexion', () => {
  const isOnline = ref(typeof navigator !== 'undefined' ? navigator.onLine : true)
  const pendingOperationsCount = ref(0)
  const hasClockDriftWarning = ref(isClockDriftCritical())

  function updateOnlineStatus() {
    isOnline.value = navigator.onLine
    hasClockDriftWarning.value = isClockDriftCritical()
  }

  function setPendingCount(count) {
    pendingOperationsCount.value = count
  }

  function checkClockDrift() {
    hasClockDriftWarning.value = isClockDriftCritical()
  }

  if (typeof window !== 'undefined') {
    window.addEventListener('online', updateOnlineStatus)
    window.addEventListener('offline', updateOnlineStatus)
  }

  return {
    isOnline,
    pendingOperationsCount,
    hasClockDriftWarning,
    setPendingCount,
    checkClockDrift,
    updateOnlineStatus
  }
})
