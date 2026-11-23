export default {
  async fetch(request, env) {
    const url = new URL(request.url)
    if (url.pathname === '/api/log' && request.method === 'POST') {
      const body = (await request.text()).slice(0, 4000)
      console.error(JSON.stringify({ tipo: 'error_frontend', datos: body }))
      return new Response(null, { status: 204 })
    }
    return env.ASSETS.fetch(request)
  },
  async scheduled(event, env, ctx) {
    if (!env.SUPABASE_URL || !env.SUPABASE_ANON_KEY) {
      console.error('keep_alive: faltan SUPABASE_URL o SUPABASE_ANON_KEY en las variables del worker')
      return
    }
    const headers = { apikey: env.SUPABASE_ANON_KEY, 'Content-Type': 'application/json' }
    // La clave anon clásica es un JWT y puede ir como Bearer; la nueva
    // (sb_publishable_…) no es JWT y solo se envía en el encabezado apikey.
    if (env.SUPABASE_ANON_KEY.startsWith('eyJ')) headers.Authorization = `Bearer ${env.SUPABASE_ANON_KEY}`
    ctx.waitUntil(
      fetch(`${env.SUPABASE_URL}/rest/v1/rpc/keep_alive`, { method: 'POST', headers, body: '{}' })
        .then((r) => { if (!r.ok) console.error(`keep_alive respondió ${r.status}`) })
        .catch((e) => console.error('keep_alive falló:', e.message))
    )
  }
}
