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
    ctx.waitUntil(fetch(`${env.SUPABASE_URL}/rest/v1/rpc/keep_alive`, {
      method: 'POST',
      headers: {
        apikey: env.SUPABASE_ANON_KEY,
        Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
        'Content-Type': 'application/json'
      },
      body: '{}'
    }))
  }
}
