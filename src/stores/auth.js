import { defineStore } from 'pinia'
import { ref, computed } from 'vue'

export const useAuthStore = defineStore('auth', () => {
  const session = ref(null)
  const profile = ref(null)
  const loading = ref(true)

  const isAuthenticated = computed(() => !!session.value)
  const userRole = computed(() => profile.value?.rol || 'operador')
  const parqueaderoId = computed(() => profile.value?.parqueadero_id || null)
  const isSuperadmin = computed(() => userRole.value === 'superadmin')
  const isAdmin = computed(() => userRole.value === 'admin' || isSuperadmin.value)

  function setSession(newSession) {
    session.value = newSession
  }

  function setProfile(newProfile) {
    profile.value = newProfile
  }

  function setLoading(state) {
    loading.value = state
  }

  function clearSession() {
    session.value = null
    profile.value = null
  }

  return {
    session,
    profile,
    loading,
    isAuthenticated,
    userRole,
    parqueaderoId,
    isSuperadmin,
    isAdmin,
    setSession,
    setProfile,
    setLoading,
    clearSession
  }
})
