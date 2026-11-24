-- Permisos de tabla explícitos (GRANT) para la API de Supabase.
--
-- Los proyectos de Supabase creados recientemente ya no dan permisos automáticos
-- sobre las tablas que se crean por SQL: sin estos GRANT la app recibe
-- "permission denied for table ...". Los permisos siguen el modelo de seguridad:
-- el GRANT abre la puerta y RLS decide qué filas ve o cambia cada usuario.
--
--   - Tablas operativas: solo lectura. Toda escritura va por RPC SECURITY DEFINER.
--   - Catálogos y parqueaderos: el admin inserta y actualiza (nunca borra).
--   - vehiculos, clientes y profiles: actualización (filtrada por sus políticas).
--   - anon: sin acceso a tablas.
--   - service_role (Edge Function invitar-usuario): acceso completo; ignora RLS.

grant usage on schema public to anon, authenticated, service_role;

-- Lectura para usuarios autenticados (RLS filtra por parqueadero)
grant select on
  public.parqueaderos,
  public.profiles,
  public.tipos_vehiculo,
  public.tarifas,
  public.planes_mensuales,
  public.metodos_pago,
  public.vehiculos,
  public.clientes,
  public.turnos_caja,
  public.movimientos_caja,
  public.registros,
  public.mensualidades,
  public.pagos_mensualidad,
  public.avisos_mensualidad,
  public.operaciones_sync,
  public.comprobantes
to authenticated;

-- Catálogos que el admin edita desde Ajustes
grant insert, update on
  public.parqueaderos,
  public.tipos_vehiculo,
  public.tarifas,
  public.planes_mensuales,
  public.metodos_pago
to authenticated;

-- Datos de contacto editables y perfiles (solo superadmin, por política)
grant update on public.vehiculos, public.clientes, public.profiles to authenticated;

-- Por si un entorno anterior dejó permisos de más: nada de borrar ni de escribir
-- directo en las tablas operativas.
revoke delete, truncate on all tables in schema public from anon, authenticated;
revoke insert, update on
  public.turnos_caja,
  public.movimientos_caja,
  public.registros,
  public.mensualidades,
  public.pagos_mensualidad,
  public.avisos_mensualidad,
  public.operaciones_sync,
  public.comprobantes
from anon, authenticated;
revoke insert on public.vehiculos, public.clientes, public.profiles from anon, authenticated;
revoke all on all tables in schema public from anon;

-- Edge Functions con la service role
grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
