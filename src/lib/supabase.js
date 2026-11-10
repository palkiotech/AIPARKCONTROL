import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://placeholder.supabase.co'
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'placeholder-anon-key'

export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: typeof navigator !== 'undefined' ? navigator.onLine : true,
    detectSessionInUrl: true,
    storage: typeof window !== 'undefined' ? window.localStorage : undefined
  }
})

// Resiliencia Offline (Recomendación #2):
// Pausar autoRefreshToken sin conexión para evitar que fallos de red invaliden la sesión local
if (typeof window !== 'undefined') {
  window.addEventListener('online', () => {
    try {
      supabase.auth.startAutoRefresh()
    } catch (e) {
      console.warn('Error reanudando autoRefreshToken:', e)
    }
  })

  window.addEventListener('offline', () => {
    try {
      supabase.auth.stopAutoRefresh()
    } catch (e) {
      console.warn('Error pausando autoRefreshToken:', e)
    }
  })
}
