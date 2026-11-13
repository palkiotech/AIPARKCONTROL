import { createApp } from 'vue'
import { createPinia } from 'pinia'
import { aplicarTemaInicial } from './stores/tema'
import router from './router'
import App from './App.vue'
import './assets/main.css'

// Tema antes de montar para evitar parpadeo (HU-10)
aplicarTemaInicial()

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)

// Errores del navegador → Cloudflare Workers Logs (decisión #14)
let enviados = 0
function reportError(errorInfo) {
  // Límite simple para no inundar los logs con un error en bucle
  if (enviados >= 20) return
  enviados++
  try {
    fetch('/api/log', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        timestamp: new Date().toISOString(),
        ruta: typeof window !== 'undefined' ? window.location.pathname : '',
        error: errorInfo
      }),
      keepalive: true
    }).catch(() => {})
  } catch (e) {}
}

app.config.errorHandler = (err, instance, info) => {
  console.error('[ParkControl Vue Error]:', err, info)
  reportError({ tipo: 'vue_error', mensaje: err?.message, stack: err?.stack, info })
}

if (typeof window !== 'undefined') {
  window.addEventListener('error', (event) => {
    reportError({
      tipo: 'window_error',
      mensaje: event.message,
      archivo: event.filename,
      linea: event.lineno,
      columna: event.colno,
      stack: event.error?.stack
    })
  })
  window.addEventListener('unhandledrejection', (event) => {
    reportError({ tipo: 'unhandled_rejection', razon: String(event.reason?.message || event.reason) })
  })
}

app.mount('#app')
