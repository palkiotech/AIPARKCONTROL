import { createApp } from 'vue'
import { createPinia } from 'pinia'
import router from './router'
import App from './App.vue'
import './assets/main.css'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)

// Captura y reporte de errores a Cloudflare Workers Logs (Decisión #14)
function reportError(errorInfo) {
  try {
    if (typeof fetch !== 'undefined') {
      fetch('/api/log', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          timestamp: new Date().toISOString(),
          error: errorInfo
        })
      }).catch(() => {})
    }
  } catch (e) {}
}

app.config.errorHandler = (err, instance, info) => {
  console.error('[ParkControl Vue Error]:', err, info)
  reportError({ tipo: 'vue_error', mensaje: err?.message, stack: err?.stack, info })
}

if (typeof window !== 'undefined') {
  window.addEventListener('unhandledrejection', (event) => {
    reportError({ tipo: 'unhandled_rejection', razon: String(event.reason) })
  })
}

app.mount('#app')
