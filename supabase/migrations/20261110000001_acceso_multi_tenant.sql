-- Migración Sprint 1: Acceso, Usuarios y Arquitectura Multi-Tenant (RLS)
-- Cumple con postgres-best-practices:
-- 1. Todas las funciones security definer fijan search_path = public
-- 2. Funciones de consulta marcadas como STABLE para permitir optimización de query planner
-- 3. Índices en claves foráneas (profiles_parqueadero_id_idx)
-- 4. RLS en todas las tablas con validación estricta por mi_parqueadero_id()

-- 1. TABLA PARQUEADEROS
create table if not exists public.parqueaderos (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  nombre text not null,
  nit text not null,
  direccion text,
  telefono text,
  logo_url text,
  zona_horaria text default 'America/Bogota' not null,
  moneda text default 'COP' not null,
  dias_aviso_vencimiento integer default 5 not null,
  texto_pie_comprobante text,
  modo_ticket text default 'qr' not null check (modo_ticket in ('termica', 'qr', 'ninguno')),
  ancho_ticket_mm integer default 80 not null check (ancho_ticket_mm in (58, 80)),
  estado text default 'activo' not null check (estado in ('activo', 'suspendido'))
);

-- 2. TABLA PROFILES (Vinculada a auth.users)
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz default now() not null,
  parqueadero_id uuid references public.parqueaderos(id) on delete restrict,
  nombre text not null,
  rol text default 'operador' not null check (rol in ('superadmin', 'admin', 'operador')),
  activo boolean default true not null
);

-- Índice de clave foránea crítico para rendimiento de RLS (postgres-best-practices)
create index if not exists profiles_parqueadero_id_idx on public.profiles(parqueadero_id);

-- 3. FUNCIONES DE SEGURIDAD (STABLE + SECURITY DEFINER + SEARCH_PATH)
create or replace function public.mi_parqueadero_id()
returns uuid
language sql
stable
security definer
set search_path = public
as $$
  select parqueadero_id from public.profiles where id = auth.uid() limit 1;
$$;

create or replace function public.mi_rol()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select rol from public.profiles where id = auth.uid() limit 1;
$$;

create or replace function public.es_superadmin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select rol = 'superadmin' from public.profiles where id = auth.uid() limit 1), false);
$$;

grant execute on function public.mi_parqueadero_id() to authenticated;
grant execute on function public.mi_rol() to authenticated;
grant execute on function public.es_superadmin() to authenticated;

-- 4. POLÍTICAS RLS PARA PARQUEADEROS
alter table public.parqueaderos enable row level security;

create policy "parqueaderos_select_isolation"
  on public.parqueaderos
  for select
  to authenticated
  using (
    public.es_superadmin() or id = public.mi_parqueadero_id()
  );

create policy "parqueaderos_insert_superadmin"
  on public.parqueaderos
  for insert
  to authenticated
  with check (
    public.es_superadmin()
  );

create policy "parqueaderos_update_admin_or_superadmin"
  on public.parqueaderos
  for update
  to authenticated
  using (
    public.es_superadmin() or (id = public.mi_parqueadero_id() and public.mi_rol() = 'admin')
  )
  with check (
    public.es_superadmin() or (id = public.mi_parqueadero_id() and public.mi_rol() = 'admin')
  );

-- 5. POLÍTICAS RLS PARA PROFILES
alter table public.profiles enable row level security;

create policy "profiles_select_isolation"
  on public.profiles
  for select
  to authenticated
  using (
    public.es_superadmin()
    or id = auth.uid()
    or (parqueadero_id = public.mi_parqueadero_id() and public.mi_parqueadero_id() is not null)
  );

create policy "profiles_insert_control"
  on public.profiles
  for insert
  to authenticated
  with check (
    public.es_superadmin()
    or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin')
  );

create policy "profiles_update_control"
  on public.profiles
  for update
  to authenticated
  using (
    public.es_superadmin()
    or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin')
    or id = auth.uid()
  )
  with check (
    public.es_superadmin()
    or (
      parqueadero_id = public.mi_parqueadero_id()
      and public.mi_rol() = 'admin'
      and rol != 'superadmin'
    )
    or (id = auth.uid() and rol = (select rol from public.profiles where id = auth.uid()))
  );

-- 6. RPC: OBTENER PERFIL Y VALIDAR ESTADO (HU-02)
create or replace function public.obtener_mi_perfil()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_perfil record;
  v_parqueadero record;
begin
  select p.id, p.nombre, p.rol, p.activo, p.parqueadero_id
  into v_perfil
  from public.profiles p
  where p.id = auth.uid();

  if not found then
    return jsonb_build_object('encontrado', false);
  end if;

  if not v_perfil.activo then
    return jsonb_build_object(
      'encontrado', true,
      'activo', false,
      'motivo', 'Tu usuario se encuentra desactivado. Contacta al administrador.'
    );
  end if;

  if v_perfil.rol = 'superadmin' then
    return jsonb_build_object(
      'encontrado', true,
      'activo', true,
      'usuario', jsonb_build_object(
        'id', v_perfil.id,
        'nombre', v_perfil.nombre,
        'rol', v_perfil.rol,
        'parqueadero_id', null
      ),
      'parqueadero', null
    );
  end if;

  select pq.id, pq.nombre, pq.nit, pq.estado, pq.zona_horaria, pq.moneda, pq.modo_ticket
  into v_parqueadero
  from public.parqueaderos pq
  where pq.id = v_perfil.parqueadero_id;

  if v_parqueadero.estado = 'suspendido' then
    return jsonb_build_object(
      'encontrado', true,
      'activo', false,
      'motivo', 'El parqueadero se encuentra suspendido. Contacta a soporte.'
    );
  end if;

  return jsonb_build_object(
    'encontrado', true,
    'activo', true,
    'usuario', jsonb_build_object(
      'id', v_perfil.id,
      'nombre', v_perfil.nombre,
      'rol', v_perfil.rol,
      'parqueadero_id', v_perfil.parqueadero_id
    ),
    'parqueadero', jsonb_build_object(
      'id', v_parqueadero.id,
      'nombre', v_parqueadero.nombre,
      'nit', v_parqueadero.nit,
      'estado', v_parqueadero.estado,
      'zona_horaria', v_parqueadero.zona_horaria,
      'moneda', v_parqueadero.moneda,
      'modo_ticket', v_parqueadero.modo_ticket
    )
  );
end;
$$;

-- 7. RPC: CREAR PARQUEADERO POR SUPERADMIN (HU-01)
create or replace function public.crear_parqueadero(
  p_nombre text,
  p_nit text,
  p_direccion text default null,
  p_telefono text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_nuevo_parqueadero_id uuid;
begin
  if not public.es_superadmin() then
    raise exception 'Acceso denegado: solo superadmin puede crear parqueaderos';
  end if;

  if trim(coalesce(p_nombre, '')) = '' then
    raise exception 'El nombre del parqueadero es obligatorio';
  end if;
  if trim(coalesce(p_nit, '')) = '' then
    raise exception 'El NIT del parqueadero es obligatorio';
  end if;

  insert into public.parqueaderos (nombre, nit, direccion, telefono, estado)
  values (trim(p_nombre), trim(p_nit), trim(p_direccion), trim(p_telefono), 'activo')
  returning id into v_nuevo_parqueadero_id;

  return jsonb_build_object(
    'success', true,
    'parqueadero_id', v_nuevo_parqueadero_id,
    'mensaje', 'Parqueadero creado exitosamente'
  );
end;
$$;

-- 8. RPC: LISTAR PARQUEADEROS PARA PANEL SUPERADMIN (HU-05)
create or replace function public.obtener_parqueaderos_superadmin()
returns table (
  id uuid,
  nombre text,
  nit text,
  direccion text,
  telefono text,
  estado text,
  created_at timestamptz,
  total_usuarios bigint
)
language sql
security definer
set search_path = public
as $$
  select 
    pq.id,
    pq.nombre,
    pq.nit,
    pq.direccion,
    pq.telefono,
    pq.estado,
    pq.created_at,
    count(pr.id) as total_usuarios
  from public.parqueaderos pq
  left join public.profiles pr on pr.parqueadero_id = pq.id
  where public.es_superadmin()
  group by pq.id
  order by pq.created_at desc;
$$;

-- 9. RPC: CAMBIAR ESTADO DE PARQUEADERO (HU-05)
create or replace function public.cambiar_estado_parqueadero(
  p_parqueadero_id uuid,
  p_nuevo_estado text
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.es_superadmin() then
    raise exception 'Acceso denegado: solo superadmin puede modificar parqueaderos';
  end if;

  if p_nuevo_estado not in ('activo', 'suspendido') then
    raise exception 'Estado inválido: debe ser activo o suspendido';
  end if;

  update public.parqueaderos
  set estado = p_nuevo_estado
  where id = p_parqueadero_id;

  return true;
end;
$$;

grant execute on function public.obtener_mi_perfil() to authenticated;
grant execute on function public.crear_parqueadero(text, text, text, text) to authenticated;
grant execute on function public.obtener_parqueaderos_superadmin() to authenticated;
grant execute on function public.cambiar_estado_parqueadero(uuid, text) to authenticated;
