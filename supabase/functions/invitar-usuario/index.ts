  // Edge Function: invitar-usuario (HU-01 y HU-03)
  //
  // Invita un usuario por correo y crea su perfil, sin exponer la service key en
  // el navegador. Reglas:
  //  - Un superadmin puede invitar al administrador de cualquier parqueadero.
  //  - Un admin solo puede invitar usuarios (admin u operador) a su parqueadero.
  //  - Si el correo ya existe, responde 409 "Este correo ya está registrado"
  //    (un usuario pertenece a un solo parqueadero).
  //
  // Despliegue:  npx supabase functions deploy invitar-usuario
  // Secretos:    SUPABASE_URL, SUPABASE_ANON_KEY y SUPABASE_SERVICE_ROLE_KEY los
  //              inyecta Supabase automáticamente. Opcional: SITE_URL para el
  //              enlace de la invitación (por defecto el origin de la petición).

  import { createClient } from 'npm:@supabase/supabase-js@2.49.1'

  const cors = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS'
  }

  function responder(status: number, cuerpo: Record<string, unknown>) {
    return new Response(JSON.stringify(cuerpo), {
      status,
      headers: { ...cors, 'Content-Type': 'application/json' }
    })
  }

  Deno.serve(async (req) => {
    if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
    if (req.method !== 'POST') return responder(405, { error: 'Método no permitido' })

    const url = Deno.env.get('SUPABASE_URL')!
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const authHeader = req.headers.get('Authorization') ?? ''
    if (!authHeader.startsWith('Bearer ')) return responder(401, { error: 'Sesión requerida' })

    // Cliente con el JWT del que llama, para identificarlo
    const comoUsuario = createClient(url, anon, { global: { headers: { Authorization: authHeader } } })
    const { data: { user }, error: errUser } = await comoUsuario.auth.getUser()
    if (errUser || !user) return responder(401, { error: 'Sesión inválida' })

    const admin = createClient(url, service, { auth: { persistSession: false } })

    const { data: llamador } = await admin
      .from('profiles')
      .select('id, rol, activo, parqueadero_id')
      .eq('id', user.id)
      .maybeSingle()
    if (!llamador || !llamador.activo) return responder(403, { error: 'Usuario no autorizado' })

    let body: { email?: string; nombre?: string; rol?: string; parqueadero_id?: string; redirect_to?: string }
    try {
      body = await req.json()
    } catch {
      return responder(400, { error: 'Cuerpo inválido' })
    }

    const email = (body.email ?? '').trim().toLowerCase()
    const nombre = (body.nombre ?? '').trim()
    const rol = body.rol ?? 'operador'

    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return responder(400, { error: 'Correo inválido' })
    if (!nombre) return responder(400, { error: 'El nombre es obligatorio' })
    if (!['admin', 'operador'].includes(rol)) return responder(400, { error: 'Rol inválido' })

    let parqueaderoId: string | null = null
    if (llamador.rol === 'superadmin') {
      parqueaderoId = body.parqueadero_id ?? null
      if (!parqueaderoId) return responder(400, { error: 'Falta el parqueadero' })
    } else if (llamador.rol === 'admin') {
      parqueaderoId = llamador.parqueadero_id
    } else {
      return responder(403, { error: 'Solo un administrador puede invitar usuarios' })
    }

    const { data: pq } = await admin.from('parqueaderos').select('id, estado').eq('id', parqueaderoId).maybeSingle()
    if (!pq) return responder(404, { error: 'Parqueadero no encontrado' })

    const redirectTo = Deno.env.get('SITE_URL')
      ? `${Deno.env.get('SITE_URL')}/recuperar`
      : (body.redirect_to ?? undefined)

    const { data: invitado, error: errInv } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { nombre },
      redirectTo
    })

    if (errInv) {
      const msg = errInv.message ?? ''
      if (msg.toLowerCase().includes('already') || msg.toLowerCase().includes('registered')) {
        return responder(409, { error: 'Este correo ya está registrado' })
      }
      return responder(400, { error: msg || 'No se pudo enviar la invitación' })
    }

    const { error: errPerfil } = await admin.from('profiles').insert({
      id: invitado.user.id,
      nombre,
      rol,
      parqueadero_id: parqueaderoId,
      activo: true
    })

    if (errPerfil) {
      // No dejar usuarios de Auth sin perfil
      await admin.auth.admin.deleteUser(invitado.user.id)
      return responder(400, { error: 'No se pudo crear el perfil: ' + errPerfil.message })
    }

    return responder(200, { success: true, usuario_id: invitado.user.id })
  })
