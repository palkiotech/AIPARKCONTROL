// Valida las migraciones de ParkControl en Postgres real (PGlite, sin Docker) con
// stubs mínimos de Supabase (roles, auth.users, auth.uid()).
// Uso: npm run test:db
//
// Aplica todas las migraciones en orden y ejecuta pruebas de seguridad (RLS,
// escalada entre parqueaderos), cobro en el servidor (paridad con cobro.js),
// caja, mensualidades, comprobantes, reportes y sincronización offline.
import { PGlite } from '@electric-sql/pglite'
import fs from 'fs'
import path from 'path'
import { fileURLToPath } from 'url'

const repo = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')
const dir = path.join(repo, 'supabase', 'migrations')
const db = new PGlite()

const stubs = `
create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
create schema auth;
create table auth.users (id uuid primary key, email text, last_sign_in_at timestamptz, email_confirmed_at timestamptz);
create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('test.uid', true), '')::uuid $$;
grant usage on schema auth to authenticated, anon, service_role;
grant execute on function auth.uid() to authenticated, anon;
grant usage on schema public to authenticated, anon, service_role;
create publication supabase_realtime;
`
await db.exec(stubs)

for (const f of fs.readdirSync(dir).sort()) {
  const sql = fs.readFileSync(path.join(dir, f), 'utf8')
  try {
    await db.exec(sql)
    console.log('OK  ', f)
  } catch (e) {
    console.log('FAIL', f, '\n   ', e.message)
    process.exit(1)
  }
}
// Sin GRANT globales: los permisos de tabla vienen de las migraciones, como en
// un proyecto nuevo de Supabase (que ya no los da por defecto).

// El seed debe cargar sin errores sobre el esquema actual
try {
  await db.exec(fs.readFileSync(path.join(repo, 'supabase', 'seed.sql'), 'utf8'))
  console.log('OK   seed.sql')
} catch (e) {
  console.log('FAIL seed.sql:', e.message)
  process.exit(1)
}

const fallas = []
async function q(sql, params) { return (await db.query(sql, params)).rows }
async function como(uid, fn) {
  await db.exec(`set test.uid = '${uid}'; set role authenticated;`)
  try { return await fn() } finally { await db.exec(`reset role;`) }
}
function check(nombre, cond, extra = '') {
  console.log(cond ? '  ✓' : '  ✗', nombre, cond ? '' : extra)
  if (!cond) fallas.push(nombre)
}
async function esperaError(nombre, fn, contiene) {
  try { await fn(); check(nombre, false, '(no lanzó error)') }
  catch (e) { check(nombre, !contiene || e.message.includes(contiene), e.message) }
}

console.log('\n== Motor de cobro (paridad con cobro.test.js)')
const b = async (...a) => (await q(`select public.calcular_cobro_base($1,$2,$3,$4,$5,$6) v`, a))[0].v
check('1h10 por_hora = 6000', await b(70, 'por_hora', 3000, 5, 15, null) === 6000)
check('26h tope 25000 = 31000', await b(1560, 'por_hora', 3000, 5, 15, 25000) === 31000)
check('3 días tope = 75000', await b(4320, 'por_hora', 3000, 0, 15, 25000) === 75000)
check('plena 1441 min = 24000', await b(1441, 'plena', 12000, 0, 15, null) === 24000)
check('fracción 30 61min = 4500', await b(61, 'por_fraccion', 1500, 0, 30, null) === 4500)
const tr = (await q(`select public.calcular_cobro_tramos('2026-11-10 17:00-05','2026-11-11 08:00-05',
  '{"modalidad":"por_hora","valor":3000,"minutos_gracia":0}'::jsonb,
  '{"modalidad":"plena","valor":12000,"franja_inicio":"19:00:00","franja_fin":"07:00:00"}'::jsonb,'America/Bogota') r`))[0].r
check('Ejemplo plan nocturna = 21000', tr.valor === 21000, JSON.stringify(tr))
check('Desglose 120/720/60', JSON.stringify(tr.desglose.map(d => d.minutos)) === '[120,720,60]', JSON.stringify(tr.desglose))
const tr2 = (await q(`select public.calcular_cobro_tramos('2026-11-10 18:00-05','2026-11-12 08:00-05',
  '{"modalidad":"por_hora","valor":3000}'::jsonb,
  '{"modalidad":"plena","valor":12000,"franja_inicio":"19:00","franja_fin":"07:00"}'::jsonb,'America/Bogota') r`))[0].r
check('Dos noches = 66000', tr2.valor === 66000, JSON.stringify(tr2))

console.log('\n== Flujo multi-tenant')
const SA = '00000000-0000-0000-0000-00000000000a'
const AD = '00000000-0000-0000-0000-00000000000b'
const OP = '00000000-0000-0000-0000-00000000000c'
const OTRO = '00000000-0000-0000-0000-00000000000d'
await q(`insert into auth.users(id,email) values ($1,'sa@x.co'),($2,'ad@x.co'),($3,'op@x.co'),($4,'otro@x.co')`, [SA, AD, OP, OTRO])
await q(`insert into public.profiles(id,nombre,rol) values ($1,'Super','superadmin')`, [SA])

const pqA = await como(SA, async () => (await q(`select public.crear_parqueadero('Parq A','900-1') r`))[0].r.parqueadero_id)
const pqB = await como(SA, async () => (await q(`select public.crear_parqueadero('Parq B','900-2') r`))[0].r.parqueadero_id)
check('crear_parqueadero siembra tipos/tarifas/efectivo',
  (await q(`select count(*)::int n from public.tarifas where parqueadero_id=$1`, [pqA]))[0].n === 2 &&
  (await q(`select count(*)::int n from public.metodos_pago where parqueadero_id=$1 and es_efectivo`, [pqA]))[0].n === 1)

await q(`insert into public.profiles(id,nombre,rol,parqueadero_id) values ($1,'Admin A','admin',$3),($2,'Op A','operador',$3),($4,'Admin B','admin',$5)`, [AD, OP, pqA, OTRO, pqB])

const sa = await como(SA, async () => q(`select * from public.obtener_parqueaderos_superadmin()`))
check('panel superadmin con email admin', sa.some(r => r.admin_email === 'ad@x.co'), JSON.stringify(sa))

// Escalada: el operador intenta pasarse al parqueadero B
await como(OP, async () => {
  await q(`update public.profiles set parqueadero_id=$1 where id=$2`, [pqB, OP]).catch(() => {})
})
check('operador NO puede cambiar su parqueadero_id', (await q(`select parqueadero_id from public.profiles where id=$1`, [OP]))[0].parqueadero_id === pqA)

await como(OP, async () => {
  await q(`update public.profiles set activo=true, rol='admin' where id=$1`, [OP]).catch(() => {})
})
check('operador NO puede subirse a admin', (await q(`select rol from public.profiles where id=$1`, [OP]))[0].rol === 'operador')

// El admin no puede reactivar un parqueadero suspendido
await como(SA, async () => q(`select public.cambiar_estado_parqueadero($1,'suspendido')`, [pqB]))
await como(OTRO, async () => {
  await q(`update public.parqueaderos set estado='activo' where id=$1`, [pqB]).catch(() => {})
})
check('admin NO puede reactivar su parqueadero', (await q(`select estado from public.parqueaderos where id=$1`, [pqB]))[0].estado === 'suspendido')
await como(SA, async () => q(`select public.cambiar_estado_parqueadero($1,'activo')`, [pqB]))

// Superadmin no ve datos de negocio
const tiposA = (await q(`select id from public.tipos_vehiculo where parqueadero_id=$1 order by orden`, [pqA])).map(r => r.id)
const efectivoA = (await q(`select id from public.metodos_pago where parqueadero_id=$1`, [pqA]))[0].id

console.log('\n== Patio y caja')
await esperaError('salida sin turno con valor > 0 falla', () => como(OP, async () => {
  const e = (await q(`select public.registrar_entrada(null,'abc-123',$1) r`, [tiposA[0]]))[0].r
  await db.exec('reset role')
  await q(`update public.registros set entrada_at = now() - interval '70 minutes' where id=$1`, [e.registro_id])
  await db.exec(`set role authenticated`)
  return q(`select public.registrar_salida($1,$2) r`, [e.registro_id, efectivoA])
}), 'turno')

const ent = await como(OP, async () => (await q(`select public.registrar_entrada(null,'XYZ987',$1) r`, [tiposA[0]]))[0].r)
check('entrada en línea usa hora del servidor', ent.hora_origen === 'servidor', JSON.stringify(ent))
await esperaError('placa ya dentro da mensaje claro', () => como(OP, () => q(`select public.registrar_entrada(null,'XYZ-987',$1)`, [tiposA[0]])), 'ya está dentro')

// Escritura directa bloqueada
await como(OP, async () => {
  await q(`update public.registros set valor = 1 where id=$1`, [ent.registro_id]).catch(() => {})
  await q(`delete from public.registros where id=$1`, [ent.registro_id]).catch(() => {})
})
const regRow = (await q(`select valor, estado from public.registros where id=$1`, [ent.registro_id]))[0]
check('operador NO puede editar/borrar registros directo', regRow && regRow.estado === 'abierto' && regRow.valor === 0, JSON.stringify(regRow))

const turno = await como(OP, async () => (await q(`select public.abrir_turno(10000) r`))[0].r)
check('abrir turno', turno.success)
await esperaError('no se abren dos turnos', () => como(OP, () => q(`select public.abrir_turno(0)`)), 'Ya hay un turno')

await q(`update public.registros set entrada_at = now() - interval '70 minutes' where id=$1`, [ent.registro_id])
const cot = await como(OP, async () => (await q(`select public.calcular_cobro($1) r`, [ent.registro_id]))[0].r)
check('cotización 70 min = 6000', cot.valor === 6000, JSON.stringify(cot))
const sal = await como(OP, async () => (await q(`select public.registrar_salida($1,$2,null,1) r`, [ent.registro_id, efectivoA]))[0].r)
check('salida en línea ignora valor del cliente (cobra 6000)', sal.valor === 6000, JSON.stringify(sal))
const t1 = (await q(`select efectivo_esperado from public.turnos_caja where id=$1`, [turno.turno_id]))[0]
check('efectivo esperado = base + cobro', t1.efectivo_esperado === 16000, JSON.stringify(t1))

const res = await como(OP, async () => (await q(`select public.obtener_resumen_turno() r`))[0].r)
check('resumen de turno', res.salidas === 1 && res.cobros_hora[0].total === 6000, JSON.stringify(res).slice(0, 300))

// Comprobante
await esperaError('operador no anula', () => como(OP, () => q(`select public.anular_registro($1,'motivo largo de prueba')`, [ent.registro_id])), 'administrador')
const c1 = await como(OP, async () => (await q(`select public.crear_comprobante('registro',$1) r`, [ent.registro_id]))[0].r)
const c2 = await como(OP, async () => (await q(`select public.crear_comprobante('registro',$1) r`, [ent.registro_id]))[0].r)
check('comprobante idempotente por origen', c1.consecutivo === 1 && c2.consecutivo === 1 && c2.existente === true)
const det = await como(AD, async () => (await q(`select public.obtener_detalle_comprobante($1) r`, [c1.comprobante_id]))[0].r)
check('detalle real de comprobante', det.detalle.placa === 'XYZ987' && det.detalle.metodo_pago === 'Efectivo', JSON.stringify(det.detalle))
const lista = await como(AD, async () => (await q(`select public.listar_comprobantes(null,null,'xyz') r`))[0].r)
check('listar comprobantes busca por placa', lista.length === 1)

console.log('\n== Mensualidades')
const planId = (await q(`insert into public.planes_mensuales(parqueadero_id,tipo_vehiculo_id,nombre,valor,tipo_periodo,dias_gracia_pago) values ($1,$2,'Mensual carro',150000,'mensual',2) returning id`, [pqA, tiposA[0]]))[0].id
const m = await como(OP, async () => (await q(`select public.crear_mensualidad('Ana','123','310','', 'MEN111',$1,$2,'2026-01-31',$3,true) r`, [tiposA[0], planId, efectivoA]))[0].r)
check('crear mensualidad 31 ene → 28 feb con pago', m.fecha_fin === '2026-02-28' && !!m.pago_id, JSON.stringify(m))
await esperaError('segunda mensualidad misma placa falla', () => como(OP, () => q(`select public.crear_mensualidad('Ana','123','310','', 'MEN111',$1,$2,'2026-02-01',$3,true)`, [tiposA[0], planId, efectivoA])), 'ya tiene')
const p = await como(OP, async () => (await q(`select public.registrar_pago_mensualidad($1,$2,1) r`, [m.mensualidad_id, efectivoA]))[0].r)
check('pago renueva 28 feb → 31 mar y usa valor del plan', p.periodo_hasta === '2026-03-31' && p.valor === 150000, JSON.stringify(p))
const an = await como(AD, async () => (await q(`select public.anular_pago_mensualidad($1,'error de digitación') r`, [p.pago_id]))[0].r)
check('anular pago recalcula vigencia', an.nueva_fecha_fin === '2026-02-28', JSON.stringify(an))
const entM = await como(OP, async () => (await q(`select public.registrar_entrada(null,'MEN111',$1) r`, [tiposA[0]]))[0].r)
check('mensual vencida no queda como mensual', entM.es_mensual === false && entM.mensualidad.vigente === false, JSON.stringify(entM))

console.log('\n== Usuarios y reportes')
const us = await como(AD, async () => (await q(`select public.listar_usuarios_parqueadero() r`))[0].r)
check('admin lista usuarios con email', us.length === 2 && us.some(u => u.email === 'op@x.co'))
await esperaError('admin no se desactiva a sí mismo', () => como(AD, () => q(`select public.actualizar_usuario($1,null,null,false)`, [AD])), 'propio')
await como(AD, () => q(`select public.actualizar_usuario($1,null,null,false)`, [OP]))
check('admin desactiva operador', (await q(`select activo from public.profiles where id=$1`, [OP]))[0].activo === false)
await esperaError('operador desactivado no opera', () => como(OP, () => q(`select public.abrir_turno(0)`)), 'desactivado')
const rep = await como(AD, async () => (await q(`select public.obtener_reporte_ingresos(current_date - 1, current_date + 1) r`))[0].r)
check('reporte suma hora + mensualidad', rep.total_hora === 6000 && rep.total_mensualidades === 150000, JSON.stringify(rep).slice(0, 300))

console.log('\n== Sincronización')
await como(AD, () => q(`select public.actualizar_usuario($1,null,null,true)`, [OP]))
const opId = '11111111-1111-4111-8111-111111111111'
const ops = [{ id: opId, tipo: 'entrada', payload: { placa: 'OFF001', tipoVehiculoId: tiposA[1] }, creada_en_dispositivo_at: new Date(Date.now() - 3600e3).toISOString() },
  { id: '22222222-2222-4222-8222-222222222222', tipo: 'salida', payload: { registroId: opId, metodoPagoId: efectivoA, valorCobrado: 500 }, creada_en_dispositivo_at: new Date().toISOString() },
  { id: 'no-es-uuid', tipo: 'entrada', payload: {} }]
const s1 = await como(OP, async () => (await q(`select public.sincronizar_operaciones($1::jsonb) r`, [JSON.stringify(ops)]))[0].r)
const s2 = await como(OP, async () => (await q(`select public.sincronizar_operaciones($1::jsonb) r`, [JSON.stringify(ops)]))[0].r)
const regOff = (await q(`select valor, valor_servidor, requiere_revision, hora_origen from public.registros where id=$1`, [opId]))[0]
check('sync: entrada+salida aplicadas, id inválido no rompe el lote', s1.procesadas === 2, JSON.stringify(s1))
check('sync idempotente', s2.ignoradas === 2, JSON.stringify(s2))
check('cobro offline distinto queda en revisión', regOff.valor === 500 && regOff.valor_servidor === 1500 && regOff.requiere_revision && regOff.hora_origen === 'dispositivo', JSON.stringify(regOff))

console.log('\n== Cierre de turno')
const tActual = (await q(`select id from public.turnos_caja where parqueadero_id=$1 and estado='abierto'`, [pqA]))[0].id
await como(OP, () => q(`select public.entregar_turno($1, 20000, 'ok')`, [tActual]))
const rec = await como(AD, async () => (await q(`select public.recibir_turno($1, 19000) r`, [tActual]))[0].r)
check('recibir turno registra diferencia de recepción', rec.diferencia_recepcion === -1000, JSON.stringify(rec))
await como(AD, () => q(`select public.cerrar_turno_sin_relevo($1, 19000, 'cierre noche')`, [rec.nuevo_turno_id]))
check('cerrar sin relevo deja sin turno activo', (await q(`select count(*)::int n from public.turnos_caja where parqueadero_id=$1 and estado<>'cerrado'`, [pqA]))[0].n === 0)

console.log('\n== Permisos de tabla (GRANT)')
const leeTodas = await como(AD, async () => {
  for (const t of ['parqueaderos', 'profiles', 'tipos_vehiculo', 'tarifas', 'planes_mensuales', 'metodos_pago', 'vehiculos', 'clientes', 'turnos_caja', 'movimientos_caja', 'registros', 'mensualidades', 'pagos_mensualidad', 'avisos_mensualidad', 'operaciones_sync', 'comprobantes']) {
    try { await q(`select 1 from public.${t} limit 1`) } catch (e) { return `${t}: ${e.message}` }
  }
  return 'ok'
})
check('authenticated puede leer todas las tablas de la app', leeTodas === 'ok', leeTodas)
await esperaError('authenticated no puede insertar en registros', () => como(AD, () => q(`insert into public.registros(parqueadero_id) values ($1)`, [pqA])), 'permission denied')
await esperaError('authenticated no puede borrar tarifas', () => como(AD, () => q(`delete from public.tarifas`)), 'permission denied')
const editaCatalogo = await como(AD, async () => { try { await q(`update public.metodos_pago set orden = orden where parqueadero_id = $1`, [pqA]); return true } catch (e) { return e.message } })
check('admin puede editar su catálogo', editaCatalogo === true, String(editaCatalogo))
await db.exec(`set role anon`)
let anonLee = false
try { await q(`select 1 from public.registros limit 1`); anonLee = true } catch {}
await db.exec(`reset role`)
check('anon no puede leer tablas', !anonLee)

console.log(fallas.length ? `\n${fallas.length} FALLAS` : '\nTODO OK')
process.exit(fallas.length ? 1 : 0)
