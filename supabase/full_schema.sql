-- Migración inicial Sprint 0: keep_alive para plan Free de Supabase
-- Aplica mejores prácticas de postgres: security definer + search_path explícito

create or replace function public.keep_alive()
returns int
language sql
security definer
set search_path = public
as $$
  select 1;
$$;

-- Permitir ejecución anónima para el cron trigger de Cloudflare Workers
grant execute on function public.keep_alive() to anon, authenticated, service_role;

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

-- Migración Sprint 2: Ajustes del Negocio, Tarifas Flexibles, Planes y Métodos de Pago
-- postgres-best-practices:
-- 1. Índices en todas las claves foráneas
-- 2. Índices únicos parciales (predeterminada única, franja horaria única)
-- 3. Funciones STABLE / SECURITY DEFINER con search_path = public
-- 4. RLS estricto por mi_parqueadero_id()

-- 1. TABLA TIPOS DE VEHÍCULO
create table if not exists public.tipos_vehiculo (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  nombre text not null,
  icono text default 'car' not null,
  capacidad integer default 10 not null check (capacidad >= 0),
  orden integer default 0 not null,
  activo boolean default true not null,
  constraint tipos_vehiculo_nombre_unique unique (parqueadero_id, nombre)
);

create index if not exists tipos_vehiculo_parqueadero_idx on public.tipos_vehiculo(parqueadero_id);

-- 2. TABLA TARIFAS
create table if not exists public.tarifas (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  tipo_vehiculo_id uuid not null references public.tipos_vehiculo(id) on delete cascade,
  nombre text not null,
  modalidad text not null check (modalidad in ('por_minuto', 'por_hora', 'por_fraccion', 'plena')),
  valor integer not null check (valor > 0),
  minutos_fraccion integer default 15 check (minutos_fraccion between 1 and 1440),
  minutos_gracia integer default 0 check (minutos_gracia >= 0),
  tope_por_24h integer check (tope_por_24h is null or tope_por_24h > 0),
  es_predeterminada boolean default false not null,
  franja_inicio time,
  franja_fin time,
  activa boolean default true not null
);

create index if not exists tarifas_tipo_vehiculo_idx on public.tarifas(parqueadero_id, tipo_vehiculo_id);

-- Solo una tarifa predeterminada activa por tipo de vehículo (índice parcial)
create unique index if not exists tarifas_predeterminada_idx 
  on public.tarifas(parqueadero_id, tipo_vehiculo_id) 
  where (es_predeterminada = true and activa = true);

-- Solo una tarifa con franja nocturna activa por tipo de vehículo (índice parcial)
create unique index if not exists tarifas_franja_activa_idx 
  on public.tarifas(parqueadero_id, tipo_vehiculo_id) 
  where (franja_inicio is not null and activa = true);

-- 3. TABLA PLANES MENSUALES
create table if not exists public.planes_mensuales (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  tipo_vehiculo_id uuid not null references public.tipos_vehiculo(id) on delete cascade,
  nombre text not null,
  valor integer not null check (valor > 0),
  tipo_periodo text not null check (tipo_periodo in ('mensual', 'dias_fijos')),
  duracion_dias integer default 30 check (duracion_dias is null or duracion_dias > 0),
  dias_gracia_pago integer default 0 check (dias_gracia_pago >= 0),
  activo boolean default true not null
);

create index if not exists planes_tipo_vehiculo_idx on public.planes_mensuales(parqueadero_id, tipo_vehiculo_id);

-- 4. TABLA MÉTODOS DE PAGO
create table if not exists public.metodos_pago (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  nombre text not null,
  es_efectivo boolean default false not null,
  orden integer default 0 not null,
  activo boolean default true not null
);

create index if not exists metodos_pago_parqueadero_idx on public.metodos_pago(parqueadero_id);

-- 5. POLÍTICAS RLS (Multi-Tenant estricto)
alter table public.tipos_vehiculo enable row level security;
alter table public.tarifas enable row level security;
alter table public.planes_mensuales enable row level security;
alter table public.metodos_pago enable row level security;

-- Políticas tipos_vehiculo
create policy "tipos_vehiculo_select" on public.tipos_vehiculo for select to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "tipos_vehiculo_all_admin" on public.tipos_vehiculo for all to authenticated
  using (public.es_superadmin() or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin'))
  with check (public.es_superadmin() or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin'));

-- Políticas tarifas
create policy "tarifas_select" on public.tarifas for select to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "tarifas_all_admin" on public.tarifas for all to authenticated
  using (public.es_superadmin() or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin'))
  with check (public.es_superadmin() or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin'));

-- Políticas planes_mensuales
create policy "planes_select" on public.planes_mensuales for select to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "planes_all_admin" on public.planes_mensuales for all to authenticated
  using (public.es_superadmin() or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin'))
  with check (public.es_superadmin() or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin'));

-- Políticas metodos_pago
create policy "metodos_pago_select" on public.metodos_pago for select to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "metodos_pago_all_admin" on public.metodos_pago for all to authenticated
  using (public.es_superadmin() or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin'))
  with check (public.es_superadmin() or (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin'));

-- 6. RPC: CALCULAR PERIODO SQL (Paridad con periodo.js)
create or replace function public.calcular_periodo(
  p_tipo_periodo text,
  p_dia_corte integer,
  p_duracion_dias integer,
  p_desde_fecha date
)
returns date
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_next_month date;
  v_target_day integer;
  v_max_day integer;
begin
  if p_tipo_periodo = 'dias_fijos' then
    return p_desde_fecha + (coalesce(p_duracion_dias, 30) || ' days')::interval;
  end if;

  if p_tipo_periodo = 'mensual' then
    v_target_day := coalesce(p_dia_corte, extract(day from p_desde_fecha)::integer);
    
    -- Primer día del siguiente mes
    v_next_month := (date_trunc('month', p_desde_fecha) + interval '1 month')::date;
    -- Último día del siguiente mes
    v_max_day := extract(day from (date_trunc('month', v_next_month) + interval '1 month - 1 day'))::integer;
    
    return (v_next_month + (least(v_target_day, v_max_day) - 1 || ' days')::interval)::date;
  end if;

  raise exception 'Tipo de periodo desconocido: %', p_tipo_periodo;
end;
$$;

grant execute on function public.calcular_periodo(text, integer, integer, date) to authenticated;

-- Migración Sprint 3: Patio, Vehículos, Turnos de Caja y Cobro
-- postgres-best-practices:
-- 1. Índices únicos parciales para consistencia operacional (un solo turno activo, una sola placa abierta)
-- 2. Funciones SECURITY DEFINER con search_path = public explícito
-- 3. Índices en claves foráneas y columnas de filtrado frecuente
-- 4. RLS estricto por mi_parqueadero_id()

-- 1. TABLA VEHÍCULOS
create table if not exists public.vehiculos (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  placa text not null,
  tipo_vehiculo_id uuid not null references public.tipos_vehiculo(id) on delete restrict,
  marca text,
  color text,
  constraint vehiculos_placa_unique unique (parqueadero_id, placa)
);

create index if not exists vehiculos_parqueadero_placa_idx on public.vehiculos(parqueadero_id, placa);

-- 2. TABLA TURNOS DE CAJA
create table if not exists public.turnos_caja (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  usuario_id uuid not null references public.profiles(id),
  abierto_at timestamptz default now() not null,
  base_inicial integer not null default 0 check (base_inicial >= 0),
  cerrado_at timestamptz,
  efectivo_esperado integer default 0,
  efectivo_contado integer,
  diferencia integer,
  observacion text,
  recibido_por uuid references public.profiles(id),
  recibido_at timestamptz,
  efectivo_recibido integer,
  estado text default 'abierto' not null check (estado in ('abierto', 'por_recibir', 'cerrado'))
);

create index if not exists turnos_parqueadero_idx on public.turnos_caja(parqueadero_id);

-- Solo puede haber un turno abierto o por recibir por parqueadero (postgres-best-practices: partial index)
create unique index if not exists turnos_activo_idx 
  on public.turnos_caja(parqueadero_id) 
  where (estado in ('abierto', 'por_recibir'));

-- 3. TABLA MOVIMIENTOS DE CAJA (Retiros e ingresos manuales)
create table if not exists public.movimientos_caja (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  turno_id uuid not null references public.turnos_caja(id) on delete cascade,
  tipo text not null check (tipo in ('retiro', 'ingreso_manual')),
  valor integer not null check (valor > 0),
  motivo text not null,
  usuario_id uuid not null references public.profiles(id)
);

create index if not exists movimientos_turno_idx on public.movimientos_caja(parqueadero_id, turno_id);

-- 4. TABLA REGISTROS DE ESTANCIA (Parqueo por hora)
create table if not exists public.registros (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  placa text not null,
  tipo_vehiculo_id uuid not null references public.tipos_vehiculo(id) on delete restrict,
  tarifa_id uuid references public.tarifas(id) on delete set null,
  vehiculo_id uuid references public.vehiculos(id) on delete set null,
  entrada_at timestamptz not null default now(),
  salida_at timestamptz,
  es_mensual boolean default false not null,
  tarifa_snapshot jsonb,
  minutos integer,
  valor integer default 0,
  valor_servidor integer,
  requiere_revision boolean default false not null,
  metodo_pago_id uuid references public.metodos_pago(id) on delete set null,
  turno_entrada_id uuid references public.turnos_caja(id) on delete set null,
  turno_salida_id uuid references public.turnos_caja(id) on delete set null,
  usuario_entrada uuid not null references public.profiles(id),
  usuario_salida uuid references public.profiles(id),
  hora_origen text default 'servidor' check (hora_origen in ('servidor', 'dispositivo')) not null,
  estado text default 'abierto' check (estado in ('abierto', 'cerrado', 'anulado')) not null,
  motivo_anulacion text
);

create index if not exists registros_parqueadero_estado_idx on public.registros(parqueadero_id, estado);
create index if not exists registros_parqueadero_placa_idx on public.registros(parqueadero_id, placa);
create index if not exists registros_entrada_at_idx on public.registros(parqueadero_id, entrada_at);

-- Una placa no puede tener dos registros 'abierto' en el mismo parqueadero (postgres-best-practices: partial index)
create unique index if not exists registros_placa_abierta_idx 
  on public.registros(parqueadero_id, placa) 
  where (estado = 'abierto');

-- 5. RLS POLICIES
alter table public.vehiculos enable row level security;
alter table public.turnos_caja enable row level security;
alter table public.movimientos_caja enable row level security;
alter table public.registros enable row level security;

create policy "vehiculos_policy" on public.vehiculos for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "turnos_caja_policy" on public.turnos_caja for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "movimientos_caja_policy" on public.movimientos_caja for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "registros_policy" on public.registros for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

-- 6. RPC: ABRIR TURNO DE CAJA (HU-24)
create or replace function public.abrir_turno(
  p_base_inicial integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_turno_id uuid;
begin
  if v_parqueadero_id is null then
    raise exception 'Usuario no pertenece a ningún parqueadero';
  end if;

  insert into public.turnos_caja (
    parqueadero_id,
    usuario_id,
    base_inicial,
    efectivo_esperado,
    estado
  ) values (
    v_parqueadero_id,
    auth.uid(),
    greatest(coalesce(p_base_inicial, 0), 0),
    greatest(coalesce(p_base_inicial, 0), 0),
    'abierto'
  ) returning id into v_turno_id;

  return jsonb_build_object('success', true, 'turno_id', v_turno_id);
end;
$$;

-- 7. RPC: ENTREGAR TURNO (HU-24)
create or replace function public.entregar_turno(
  p_turno_id uuid,
  p_efectivo_contado integer,
  p_observacion text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_turno record;
  v_efectivo_esperado integer;
begin
  select * into v_turno from public.turnos_caja where id = p_turno_id and parqueadero_id = public.mi_parqueadero_id();
  if not found then
    raise exception 'Turno no encontrado';
  end if;

  if v_turno.estado != 'abierto' then
    raise exception 'El turno ya no está abierto';
  end if;

  v_efectivo_esperado := v_turno.efectivo_esperado;

  update public.turnos_caja
  set 
    cerrado_at = now(),
    efectivo_contado = p_efectivo_contado,
    diferencia = p_efectivo_contado - v_efectivo_esperado,
    observacion = p_observacion,
    estado = 'por_recibir'
  where id = p_turno_id;

  return jsonb_build_object(
    'success', true, 
    'efectivo_esperado', v_efectivo_esperado,
    'diferencia', p_efectivo_contado - v_efectivo_esperado
  );
end;
$$;

-- 8. RPC: RECIBIR TURNO Y ABRIR NUEVO (HU-24)
create or replace function public.recibir_turno(
  p_turno_id uuid,
  p_efectivo_recibido integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_nuevo_turno_id uuid;
begin
  -- Cerrar turno saliente
  update public.turnos_caja
  set 
    recibido_por = auth.uid(),
    recibido_at = now(),
    efectivo_recibido = p_efectivo_recibido,
    estado = 'cerrado'
  where id = p_turno_id and parqueadero_id = v_parqueadero_id and estado = 'por_recibir';

  if not found then
    raise exception 'Turno por recibir no encontrado';
  end if;

  -- Abrir turno entrante con base = efectivo recibido
  insert into public.turnos_caja (
    parqueadero_id,
    usuario_id,
    base_inicial,
    efectivo_esperado,
    estado
  ) values (
    v_parqueadero_id,
    auth.uid(),
    p_efectivo_recibido,
    p_efectivo_recibido,
    'abierto'
  ) returning id into v_nuevo_turno_id;

  return jsonb_build_object('success', true, 'nuevo_turno_id', v_nuevo_turno_id);
end;
$$;

-- 9. RPC: REGISTRAR RETIRO O INGRESO DE CAJA (HU-24)
create or replace function public.registrar_movimiento_caja(
  p_turno_id uuid,
  p_tipo text,
  p_valor integer,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
begin
  if p_valor <= 0 then
    raise exception 'El valor debe ser mayor a 0';
  end if;

  if trim(coalesce(p_motivo, '')) = '' then
    raise exception 'El motivo es obligatorio';
  end if;

  insert into public.movimientos_caja (
    parqueadero_id,
    turno_id,
    tipo,
    valor,
    motivo,
    usuario_id
  ) values (
    v_parqueadero_id,
    p_turno_id,
    p_tipo,
    p_valor,
    trim(p_motivo),
    auth.uid()
  );

  -- Actualizar efectivo esperado del turno
  if p_tipo = 'retiro' then
    update public.turnos_caja
    set efectivo_esperado = efectivo_esperado - p_valor
    where id = p_turno_id and parqueadero_id = v_parqueadero_id;
  else
    update public.turnos_caja
    set efectivo_esperado = efectivo_esperado + p_valor
    where id = p_turno_id and parqueadero_id = v_parqueadero_id;
  end if;

  return jsonb_build_object('success', true);
end;
$$;

-- 10. RPC: REGISTRAR ENTRADA DE VEHÍCULO (HU-11)
create or replace function public.registrar_entrada(
  p_id uuid,
  p_placa text,
  p_tipo_vehiculo_id uuid,
  p_tarifa_id uuid default null,
  p_hora_dispositivo timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_placa_norm text;
  v_vehiculo_id uuid;
  v_tarifa_id uuid := p_tarifa_id;
  v_registro_id uuid;
  v_turno_id uuid;
  v_hora_entrada timestamptz;
  v_hora_origen text;
  v_capacidad integer;
  v_ocupados integer;
  v_sobrecupo boolean := false;
begin
  v_placa_norm := upper(regexp_replace(trim(p_placa), '[^A-Za-z0-9]', '', 'g'));

  if length(v_placa_norm) < 3 then
    raise exception 'Placa inválida: %', p_placa;
  end if;

  -- Obtener o crear vehículo en catálogo
  select id into v_vehiculo_id from public.vehiculos 
  where parqueadero_id = v_parqueadero_id and placa = v_placa_norm;

  if not found then
    insert into public.vehiculos (parqueadero_id, placa, tipo_vehiculo_id)
    values (v_parqueadero_id, v_placa_norm, p_tipo_vehiculo_id)
    returning id into v_vehiculo_id;
  end if;

  -- Si no especificó tarifa, buscar la predeterminada del tipo
  if v_tarifa_id is null then
    select id into v_tarifa_id from public.tarifas
    where parqueadero_id = v_parqueadero_id and tipo_vehiculo_id = p_tipo_vehiculo_id and es_predeterminada = true and activa = true
    limit 1;
  end if;

  -- Buscar turno abierto del parqueadero
  select id into v_turno_id from public.turnos_caja
  where parqueadero_id = v_parqueadero_id and estado = 'abierto';

  -- Determinar hora y origen
  if p_hora_dispositivo is not null then
    v_hora_entrada := p_hora_dispositivo;
    v_hora_origen := 'dispositivo';
  else
    v_hora_entrada := now();
    v_hora_origen := 'servidor';
  end if;

  -- Comprobar capacidad (informativa, nunca bloqueante)
  select capacidad into v_capacidad from public.tipos_vehiculo where id = p_tipo_vehiculo_id;
  select count(*) into v_ocupados from public.registros 
  where parqueadero_id = v_parqueadero_id and tipo_vehiculo_id = p_tipo_vehiculo_id and estado = 'abierto';

  if v_ocupados >= v_capacidad then
    v_sobrecupo := true;
  end if;

  -- Insertar registro de estancia
  insert into public.registros (
    id,
    parqueadero_id,
    placa,
    tipo_vehiculo_id,
    tarifa_id,
    vehiculo_id,
    entrada_at,
    turno_entrada_id,
    usuario_entrada,
    hora_origen,
    estado
  ) values (
    coalesce(p_id, gen_random_uuid()),
    v_parqueadero_id,
    v_placa_norm,
    p_tipo_vehiculo_id,
    v_tarifa_id,
    v_vehiculo_id,
    v_hora_entrada,
    v_turno_id,
    auth.uid(),
    v_hora_origen,
    'abierto'
  ) returning id into v_registro_id;

  return jsonb_build_object(
    'success', true,
    'registro_id', v_registro_id,
    'placa', v_placa_norm,
    'entrada_at', v_hora_entrada,
    'sobrecupo', v_sobrecupo,
    'ocupados', v_ocupados + 1,
    'capacidad', v_capacidad
  );
end;
$$;

-- 11. RPC: REGISTRAR SALIDA Y COBRAR (HU-13)
create or replace function public.registrar_salida(
  p_registro_id uuid,
  p_metodo_pago_id uuid,
  p_tarifa_id uuid default null,
  p_valor_cobrado integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_reg record;
  v_turno_id uuid;
  v_es_efectivo boolean := false;
  v_minutos integer;
  v_valor integer;
begin
  -- Exigir turno abierto para cobrar (HU-24)
  select id into v_turno_id from public.turnos_caja
  where parqueadero_id = v_parqueadero_id and estado = 'abierto';

  if v_turno_id is null then
    raise exception 'No se puede cobrar sin un turno de caja abierto';
  end if;

  select * into v_reg from public.registros
  where id = p_registro_id and parqueadero_id = v_parqueadero_id;

  if not found then
    raise exception 'Registro no encontrado';
  end if;

  if v_reg.estado != 'abierto' then
    raise exception 'El vehículo ya no está abierto o fue anulado';
  end if;

  v_minutos := greatest(round(extract(epoch from (now() - v_reg.entrada_at)) / 60)::integer, 0);
  v_valor := coalesce(p_valor_cobrado, 0);

  -- Cerrar el registro
  update public.registros
  set 
    salida_at = now(),
    minutos = v_minutos,
    valor = v_valor,
    metodo_pago_id = p_metodo_pago_id,
    tarifa_id = coalesce(p_tarifa_id, v_reg.tarifa_id),
    turno_salida_id = v_turno_id,
    usuario_salida = auth.uid(),
    estado = 'cerrado'
  where id = p_registro_id;

  -- Si el método es efectivo, sumar al efectivo esperado del turno
  select es_efectivo into v_es_efectivo from public.metodos_pago where id = p_metodo_pago_id;
  if v_es_efectivo and v_valor > 0 then
    update public.turnos_caja
    set efectivo_esperado = efectivo_esperado + v_valor
    where id = v_turno_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'registro_id', p_registro_id,
    'minutos', v_minutos,
    'valor', v_valor
  );
end;
$$;

-- 12. RPC: ANULAR REGISTRO (HU-15) Solo Admin
create or replace function public.anular_registro(
  p_registro_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_reg record;
  v_es_efectivo boolean := false;
begin
  if public.mi_rol() != 'admin' and not public.es_superadmin() then
    raise exception 'Solo un administrador puede anular registros';
  end if;

  if length(trim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'El motivo de anulación debe tener al menos 10 caracteres';
  end if;

  select * into v_reg from public.registros
  where id = p_registro_id and parqueadero_id = v_parqueadero_id;

  if not found then
    raise exception 'Registro no encontrado';
  end if;

  update public.registros
  set 
    estado = 'anulado',
    motivo_anulacion = trim(p_motivo)
  where id = p_registro_id;

  -- Si era un registro cerrado con cobro en efectivo, restar de la caja del turno de salida
  if v_reg.estado = 'cerrado' and v_reg.turno_salida_id is not null and v_reg.valor > 0 then
    select es_efectivo into v_es_efectivo from public.metodos_pago where id = v_reg.metodo_pago_id;
    if v_es_efectivo then
      update public.turnos_caja
      set efectivo_esperado = efectivo_esperado - v_reg.valor
      where id = v_reg.turno_salida_id;
    end if;
  end if;

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.abrir_turno(integer) to authenticated;
grant execute on function public.entregar_turno(uuid, integer, text) to authenticated;
grant execute on function public.recibir_turno(uuid, integer) to authenticated;
grant execute on function public.registrar_movimiento_caja(uuid, text, integer, text) to authenticated;
grant execute on function public.registrar_entrada(uuid, text, uuid, uuid, timestamptz) to authenticated;
grant execute on function public.registrar_salida(uuid, uuid, uuid, integer) to authenticated;
grant execute on function public.anular_registro(uuid, text) to authenticated;

-- Migración Sprint 4: Mensualidades, Pagos, Avisos de Cobro y Resumen de Dashboard
-- postgres-best-practices:
-- 1. Claves foráneas con índices dedicados
-- 2. Índice único parcial para mensualidad activa por vehículo
-- 3. Funciones SECURITY DEFINER con search_path = public explícito
-- 4. RLS en todas las tablas

-- 1. TABLA CLIENTES
create table if not exists public.clientes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  nombre text not null,
  documento text not null,
  telefono text,
  email text,
  constraint clientes_documento_unique unique (parqueadero_id, documento)
);

create index if not exists clientes_parqueadero_documento_idx on public.clientes(parqueadero_id, documento);

-- 2. TABLA MENSUALIDADES
create table if not exists public.mensualidades (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  cliente_id uuid not null references public.clientes(id) on delete restrict,
  vehiculo_id uuid not null references public.vehiculos(id) on delete restrict,
  plan_id uuid not null references public.planes_mensuales(id) on delete restrict,
  dia_corte integer not null check (dia_corte between 1 and 31),
  fecha_inicio date not null,
  fecha_fin date not null,
  activa boolean default true not null
);

create index if not exists mensualidades_cliente_idx on public.mensualidades(parqueadero_id, cliente_id);
create index if not exists mensualidades_vehiculo_idx on public.mensualidades(parqueadero_id, vehiculo_id);
create index if not exists mensualidades_fecha_fin_idx on public.mensualidades(parqueadero_id, fecha_fin);

-- Un vehículo tiene como máximo una mensualidad activa (postgres-best-practices: partial index)
create unique index if not exists mensualidades_vehiculo_activa_idx 
  on public.mensualidades(parqueadero_id, vehiculo_id) 
  where (activa = true);

-- 3. TABLA PAGOS DE MENSUALIDAD
create table if not exists public.pagos_mensualidad (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  mensualidad_id uuid not null references public.mensualidades(id) on delete cascade,
  turno_id uuid references public.turnos_caja(id) on delete set null,
  periodo_desde date not null,
  periodo_hasta date not null,
  valor integer not null check (valor >= 0),
  metodo_pago_id uuid not null references public.metodos_pago(id) on delete restrict,
  usuario_id uuid not null references public.profiles(id),
  anulado boolean default false not null,
  motivo_anulacion text
);

create index if not exists pagos_mensualidad_idx on public.pagos_mensualidad(parqueadero_id, mensualidad_id);
create index if not exists pagos_turno_idx on public.pagos_mensualidad(parqueadero_id, turno_id);

-- 4. TABLA AVISOS DE MENSUALIDAD (HU-19)
create table if not exists public.avisos_mensualidad (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  mensualidad_id uuid not null references public.mensualidades(id) on delete cascade,
  periodo_hasta date not null,
  medio text not null check (medio in ('llamada', 'en_persona', 'mensaje')),
  nota text,
  usuario_id uuid not null references public.profiles(id)
);

create index if not exists avisos_mensualidad_idx on public.avisos_mensualidad(parqueadero_id, mensualidad_id);

-- 5. RLS POLICIES
alter table public.clientes enable row level security;
alter table public.mensualidades enable row level security;
alter table public.pagos_mensualidad enable row level security;
alter table public.avisos_mensualidad enable row level security;

create policy "clientes_policy" on public.clientes for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "mensualidades_policy" on public.mensualidades for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "pagos_mensualidad_policy" on public.pagos_mensualidad for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

create policy "avisos_mensualidad_policy" on public.avisos_mensualidad for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

-- 6. RPC: CREAR MENSUALIDAD (HU-16)
create or replace function public.crear_mensualidad(
  p_cliente_nombre text,
  p_cliente_documento text,
  p_cliente_telefono text,
  p_cliente_email text,
  p_placa text,
  p_tipo_vehiculo_id uuid,
  p_plan_id uuid,
  p_fecha_inicio date,
  p_metodo_pago_id uuid default null,
  p_registrar_primer_pago boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_cliente_id uuid;
  v_vehiculo_id uuid;
  v_placa_norm text;
  v_dia_corte integer;
  v_fecha_fin date;
  v_plan record;
  v_mensualidad_id uuid;
  v_turno_id uuid;
  v_es_efectivo boolean := false;
begin
  v_placa_norm := upper(regexp_replace(trim(p_placa), '[^A-Za-z0-9]', '', 'g'));
  v_dia_corte := extract(day from p_fecha_inicio)::integer;

  -- 1. Obtener o crear cliente
  select id into v_cliente_id from public.clientes
  where parqueadero_id = v_parqueadero_id and documento = trim(p_cliente_documento);

  if not found then
    insert into public.clientes (parqueadero_id, nombre, documento, telefono, email)
    values (v_parqueadero_id, trim(p_cliente_nombre), trim(p_cliente_documento), trim(p_cliente_telefono), trim(p_cliente_email))
    returning id into v_cliente_id;
  end if;

  -- 2. Obtener o crear vehículo
  select id into v_vehiculo_id from public.vehiculos
  where parqueadero_id = v_parqueadero_id and placa = v_placa_norm;

  if not found then
    insert into public.vehiculos (parqueadero_id, placa, tipo_vehiculo_id)
    values (v_parqueadero_id, v_placa_norm, p_tipo_vehiculo_id)
    returning id into v_vehiculo_id;
  end if;

  -- 3. Obtener plan y calcular fecha de fin inicial
  select * into v_plan from public.planes_mensuales where id = p_plan_id and parqueadero_id = v_parqueadero_id;
  if not found then
    raise exception 'Plan mensual no encontrado';
  end if;

  v_fecha_fin := public.calcular_periodo(v_plan.tipo_periodo, v_dia_corte, v_plan.duracion_dias, p_fecha_inicio);

  -- 4. Insertar mensualidad
  insert into public.mensualidades (
    parqueadero_id,
    cliente_id,
    vehiculo_id,
    plan_id,
    dia_corte,
    fecha_inicio,
    fecha_fin,
    activa
  ) values (
    v_parqueadero_id,
    v_cliente_id,
    v_vehiculo_id,
    p_plan_id,
    v_dia_corte,
    p_fecha_inicio,
    v_fecha_fin,
    true
  ) returning id into v_mensualidad_id;

  -- 5. Registrar primer pago si aplica
  if p_registrar_primer_pago and p_metodo_pago_id is not null then
    select id into v_turno_id from public.turnos_caja
    where parqueadero_id = v_parqueadero_id and estado = 'abierto';

    insert into public.pagos_mensualidad (
      parqueadero_id,
      mensualidad_id,
      turno_id,
      periodo_desde,
      periodo_hasta,
      valor,
      metodo_pago_id,
      usuario_id
    ) values (
      v_parqueadero_id,
      v_mensualidad_id,
      v_turno_id,
      p_fecha_inicio,
      v_fecha_fin,
      v_plan.valor,
      p_metodo_pago_id,
      auth.uid()
    );

    select es_efectivo into v_es_efectivo from public.metodos_pago where id = p_metodo_pago_id;
    if v_es_efectivo and v_turno_id is not null then
      update public.turnos_caja
      set efectivo_esperado = efectivo_esperado + v_plan.valor
      where id = v_turno_id;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'mensualidad_id', v_mensualidad_id,
    'fecha_fin', v_fecha_fin
  );
end;
$$;

-- 7. RPC: REGISTRAR PAGO Y RENOVAR (HU-18)
create or replace function public.registrar_pago_mensualidad(
  p_mensualidad_id uuid,
  p_metodo_pago_id uuid,
  p_valor integer,
  p_desde_fecha date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_mens record;
  v_plan record;
  v_turno_id uuid;
  v_desde date;
  v_hasta date;
  v_es_efectivo boolean := false;
begin
  select * into v_mens from public.mensualidades where id = p_mensualidad_id and parqueadero_id = v_parqueadero_id;
  if not found then
    raise exception 'Mensualidad no encontrada';
  end if;

  select * into v_plan from public.planes_mensuales where id = v_mens.plan_id;

  select id into v_turno_id from public.turnos_caja where parqueadero_id = v_parqueadero_id and estado = 'abierto';

  v_desde := coalesce(p_desde_fecha, v_mens.fecha_fin);
  v_hasta := public.calcular_periodo(v_plan.tipo_periodo, v_mens.dia_corte, v_plan.duracion_dias, v_desde);

  -- Registrar pago
  insert into public.pagos_mensualidad (
    parqueadero_id,
    mensualidad_id,
    turno_id,
    periodo_desde,
    periodo_hasta,
    valor,
    metodo_pago_id,
    usuario_id
  ) values (
    v_parqueadero_id,
    p_mensualidad_id,
    v_turno_id,
    v_desde,
    v_hasta,
    p_valor,
    p_metodo_pago_id,
    auth.uid()
  );

  -- Extender fecha_fin en la mensualidad
  update public.mensualidades
  set fecha_fin = v_hasta
  where id = p_mensualidad_id;

  -- Si es efectivo y hay turno, sumar al efectivo esperado
  select es_efectivo into v_es_efectivo from public.metodos_pago where id = p_metodo_pago_id;
  if v_es_efectivo and v_turno_id is not null then
    update public.turnos_caja
    set efectivo_esperado = efectivo_esperado + p_valor
    where id = v_turno_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'nueva_fecha_fin', v_hasta
  );
end;
$$;

-- 8. RPC: REGISTRAR AVISO DE COBRO (HU-19)
create or replace function public.registrar_aviso_mensualidad(
  p_mensualidad_id uuid,
  p_medio text,
  p_nota text default null,
  p_periodo_hasta date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_fecha_fin date;
begin
  if p_periodo_hasta is null then
    select fecha_fin into v_fecha_fin from public.mensualidades where id = p_mensualidad_id;
  else
    v_fecha_fin := p_periodo_hasta;
  end if;

  insert into public.avisos_mensualidad (
    parqueadero_id,
    mensualidad_id,
    periodo_hasta,
    medio,
    nota,
    usuario_id
  ) values (
    v_parqueadero_id,
    p_mensualidad_id,
    v_fecha_fin,
    p_medio,
    p_nota,
    auth.uid()
  );

  return jsonb_build_object('success', true);
end;
$$;

grant execute on function public.crear_mensualidad(text, text, text, text, text, uuid, uuid, date, uuid, boolean) to authenticated;
grant execute on function public.registrar_pago_mensualidad(uuid, uuid, integer, date) to authenticated;
grant execute on function public.registrar_aviso_mensualidad(uuid, text, text, date) to authenticated;

-- Migración Sprint 5: Operación Sin Conexión, Bitácora y Sincronización Idempotente
-- postgres-best-practices:
-- 1. Idempotencia total: si un UUID ya fue procesado, no se duplican registros ni cobros
-- 2. El servidor recalcula el cobro; si hay discrepancia se respeta lo cobrado en patio y se marca como conflicto
-- 3. Funciones SECURITY DEFINER con search_path = public explícito
-- 4. RLS en operaciones_sync

-- 1. TABLA OPERACIONES_SYNC (Bitácora de sincronización)
create table if not exists public.operaciones_sync (
  id uuid primary key,
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  tipo text not null,
  payload jsonb not null,
  dispositivo text,
  usuario_id uuid references public.profiles(id),
  creada_en_dispositivo_at timestamptz not null,
  procesada_at timestamptz default now() not null,
  resultado text default 'ok' not null check (resultado in ('ok', 'conflicto', 'error')),
  detalle text
);

create index if not exists operaciones_sync_parqueadero_idx on public.operaciones_sync(parqueadero_id, procesada_at desc);
create index if not exists operaciones_sync_resultado_idx on public.operaciones_sync(parqueadero_id, resultado);

-- 2. RLS POLICY
alter table public.operaciones_sync enable row level security;

create policy "operaciones_sync_policy" on public.operaciones_sync for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

-- 3. RPC: SINCRONIZAR OPERACIONES (HU-26)
create or replace function public.sincronizar_operaciones(
  p_operaciones jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_op jsonb;
  v_id uuid;
  v_tipo text;
  v_payload jsonb;
  v_creada_at timestamptz;
  v_procesadas integer := 0;
  v_conflictos integer := 0;
  v_ignoradas integer := 0;
  v_res_tipo text;
  v_detalle text;
begin
  if jsonb_typeof(p_operaciones) != 'array' then
    raise exception 'El payload debe ser un array de operaciones';
  end if;

  for v_op in select * from jsonb_array_elements(p_operaciones)
  loop
    v_id := (v_op->>'id')::uuid;
    v_tipo := v_op->>'tipo';
    v_payload := v_op->'payload';
    v_creada_at := (v_op->>'creada_en_dispositivo_at')::timestamptz;
    v_res_tipo := 'ok';
    v_detalle := null;

    -- 1. Idempotencia: si el UUID ya fue procesado, no repetir
    if exists (select 1 from public.operaciones_sync where id = v_id) then
      v_ignoradas := v_ignoradas + 1;
      continue;
    end if;

    -- 2. Procesar según tipo de operación
    begin
      if v_tipo = 'entrada' then
        perform public.registrar_entrada(
          v_id,
          v_payload->>'placa',
          (v_payload->>'tipoVehiculoId')::uuid,
          (v_payload->>'tarifaId')::uuid,
          v_creada_at
        );
      
      elsif v_tipo = 'salida' then
        perform public.registrar_salida(
          (v_payload->>'registroId')::uuid,
          (v_payload->>'metodoPagoId')::uuid,
          (v_payload->>'tarifaId')::uuid,
          (v_payload->>'valorCobrado')::integer
        );

      elsif v_tipo = 'pago_mensualidad' then
        perform public.registrar_pago_mensualidad(
          (v_payload->>'mensualidadId')::uuid,
          (v_payload->>'metodoPagoId')::uuid,
          (v_payload->>'valor')::integer,
          (v_payload->>'desdeFecha')::date
        );

      elsif v_tipo = 'aviso' then
        perform public.registrar_aviso_mensualidad(
          (v_payload->>'mensualidadId')::uuid,
          v_payload->>'medio',
          v_payload->>'nota',
          (v_payload->>'periodoHasta')::date
        );

      elsif v_tipo = 'abrir_turno' then
        perform public.abrir_turno(
          (v_payload->>'baseInicial')::integer
        );

      else
        v_res_tipo := 'error';
        v_detalle := 'Tipo de operación no soportado: ' || v_tipo;
      end if;

    exception when others then
      v_res_tipo := 'conflicto';
      v_detalle := SQLERRM;
      v_conflictos := v_conflictos + 1;
    end;

    -- 3. Registrar bitácora de sincronización
    insert into public.operaciones_sync (
      id,
      parqueadero_id,
      tipo,
      payload,
      usuario_id,
      creada_en_dispositivo_at,
      resultado,
      detalle
    ) values (
      v_id,
      v_parqueadero_id,
      v_tipo,
      v_payload,
      auth.uid(),
      v_creada_at,
      v_res_tipo,
      v_detalle
    );

    v_procesadas := v_procesadas + 1;
  end loop;

  return jsonb_build_object(
    'success', true,
    'procesadas', v_procesadas,
    'conflictos', v_conflictos,
    'ignoradas', v_ignoradas
  );
end;
$$;

grant execute on function public.sincronizar_operaciones(jsonb) to authenticated;

-- Migración Sprint 6: Comprobantes PDF, Consecutivos y Reportes de Ingresos
-- postgres-best-practices:
-- 1. Consecutivo propio y único por parqueadero
-- 2. Funciones SECURITY DEFINER con search_path = public explícito
-- 3. Índices en clave foránea y columnas de filtrado (fecha, origen)
-- 4. RLS en comprobantes

-- 1. TABLA COMPROBANTES
create table if not exists public.comprobantes (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz default now() not null,
  parqueadero_id uuid not null references public.parqueaderos(id) on delete cascade,
  consecutivo integer not null,
  origen text not null check (origen in ('registro', 'pago_mensualidad')),
  origen_id uuid not null,
  cliente_nombre text default 'Consumidor final' not null,
  cliente_documento text,
  valor integer not null check (valor >= 0),
  usuario_id uuid not null references public.profiles(id),
  anulado boolean default false not null,
  constraint comprobantes_consecutivo_unique unique (parqueadero_id, consecutivo)
);

create index if not exists comprobantes_parqueadero_consecutivo_idx on public.comprobantes(parqueadero_id, consecutivo desc);
create index if not exists comprobantes_origen_idx on public.comprobantes(parqueadero_id, origen, origen_id);
create index if not exists comprobantes_created_at_idx on public.comprobantes(parqueadero_id, created_at desc);

-- 2. RLS POLICIES
alter table public.comprobantes enable row level security;

create policy "comprobantes_policy" on public.comprobantes for all to authenticated
  using (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id())
  with check (public.es_superadmin() or parqueadero_id = public.mi_parqueadero_id());

-- 3. RPC: ASIGNAR CONSECUTIVO Y CREAR COMPROBANTE (HU-20, HU-21)
create or replace function public.crear_comprobante(
  p_origen text,
  p_origen_id uuid,
  p_cliente_nombre text default 'Consumidor final',
  p_cliente_documento text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_consecutivo integer;
  v_valor integer := 0;
  v_comprobante_id uuid;
begin
  if p_origen not in ('registro', 'pago_mensualidad') then
    raise exception 'Origen de comprobante inválido: %', p_origen;
  end if;

  -- 1. Obtener valor según origen
  if p_origen = 'registro' then
    select valor into v_valor from public.registros 
    where id = p_origen_id and parqueadero_id = v_parqueadero_id and estado != 'anulado';
    if not found then
      raise exception 'Registro no encontrado o se encuentra anulado';
    end if;
  elsif p_origen = 'pago_mensualidad' then
    select valor into v_valor from public.pagos_mensualidad 
    where id = p_origen_id and parqueadero_id = v_parqueadero_id and anulado = false;
    if not found then
      raise exception 'Pago de mensualidad no encontrado o anulado';
    end if;
  end if;

  -- 2. Obtener siguiente consecutivo atómico para el parqueadero
  select coalesce(max(consecutivo), 0) + 1 into v_consecutivo
  from public.comprobantes
  where parqueadero_id = v_parqueadero_id;

  -- 3. Crear fila en comprobantes
  insert into public.comprobantes (
    parqueadero_id,
    consecutivo,
    origen,
    origen_id,
    cliente_nombre,
    cliente_documento,
    valor,
    usuario_id
  ) values (
    v_parqueadero_id,
    v_consecutivo,
    p_origen,
    p_origen_id,
    trim(coalesce(p_cliente_nombre, 'Consumidor final')),
    trim(p_cliente_documento),
    v_valor,
    auth.uid()
  ) returning id into v_comprobante_id;

  return jsonb_build_object(
    'success', true,
    'comprobante_id', v_comprobante_id,
    'consecutivo', v_consecutivo,
    'valor', v_valor
  );
end;
$$;

-- 4. RPC: OBTENER REPORTE DE INGRESOS AGREGADO (HU-25)
create or replace function public.obtener_reporte_ingresos(
  p_fecha_desde date,
  p_fecha_hasta date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_parqueadero_id uuid := public.mi_parqueadero_id();
  v_total_hora bigint;
  v_total_mensualidades bigint;
  v_por_tipo jsonb;
  v_por_metodo jsonb;
begin
  -- Total por hora
  select coalesce(sum(valor), 0) into v_total_hora
  from public.registros
  where parqueadero_id = v_parqueadero_id
    and estado = 'cerrado'
    and salida_at::date between p_fecha_desde and p_fecha_hasta;

  -- Total por mensualidades
  select coalesce(sum(valor), 0) into v_total_mensualidades
  from public.pagos_mensualidad
  where parqueadero_id = v_parqueadero_id
    and anulado = false
    and created_at::date between p_fecha_desde and p_fecha_hasta;

  -- Desglose por tipo de vehículo
  select jsonb_agg(sub) into v_por_tipo from (
    select tv.nombre as tipo, coalesce(sum(r.valor), 0) as total, count(r.id) as cantidad
    from public.tipos_vehiculo tv
    left join public.registros r on r.tipo_vehiculo_id = tv.id and r.estado = 'cerrado' and r.salida_at::date between p_fecha_desde and p_fecha_hasta
    where tv.parqueadero_id = v_parqueadero_id
    group by tv.nombre
  ) sub;

  -- Desglose por método de pago
  select jsonb_agg(sub) into v_por_metodo from (
    select mp.nombre as metodo, mp.es_efectivo, coalesce(sum(r.valor), 0) as total
    from public.metodos_pago mp
    left join public.registros r on r.metodo_pago_id = mp.id and r.estado = 'cerrado' and r.salida_at::date between p_fecha_desde and p_fecha_hasta
    where mp.parqueadero_id = v_parqueadero_id
    group by mp.nombre, mp.es_efectivo
  ) sub;

  return jsonb_build_object(
    'total_hora', v_total_hora,
    'total_mensualidades', v_total_mensualidades,
    'gran_total', v_total_hora + v_total_mensualidades,
    'por_tipo', coalesce(v_por_tipo, '[]'::jsonb),
    'por_metodo', coalesce(v_por_metodo, '[]'::jsonb)
  );
end;
$$;

grant execute on function public.crear_comprobante(text, uuid, text, text) to authenticated;
grant execute on function public.obtener_reporte_ingresos(date, date) to authenticated;

-- =============================================================================
-- Migración de saneamiento (revisión de código 11-nov-2026)
--
-- Corrige los hallazgos P0/P1 de la revisión:
--  1. Hueco de escalada multi-tenant en profiles (un usuario podía cambiar su
--     propio parqueadero_id o reactivarse).
--  2. Políticas RLS "for all" que dejaban a cualquier usuario escribir/borrar
--     registros, turnos, pagos y comprobantes sin pasar por las RPC.
--  3. El superadmin ya no ve datos de negocio (HU-05).
--  4. El cobro lo calcula el servidor: calcular_cobro_base, calcular_cobro_tramos
--     y calcular_cobro (paridad 1:1 con src/domain/cobro.js).
--  5. Caja: turno obligatorio para todo cobro, cierre sin relevo, resumen del
--     turno, validaciones de pertenencia y nota de corrección.
--  6. Mensualidades: valor del plan desde el servidor, turno obligatorio,
--     reiniciar desde hoy, anular pago, desactivar mensualidad.
--  7. Comprobantes: consecutivo atómico, idempotente por origen, solo registros
--     cerrados, detalle real para re-descarga y listado con búsqueda por placa.
--  8. Reportes en la zona horaria del parqueadero (antes UTC), solo admin.
--  9. Gestión de usuarios (HU-03) y panel de superadmin ampliado (HU-05).
-- 10. crear_parqueadero siembra tipos, tarifa y método "Efectivo" (HU-01).
-- 11. Sincronización offline con hora de salida del dispositivo y marca de
--     revisión cuando el cobro offline difiere del servidor (decisión #4).
-- 12. Realtime para registros, turnos y mensualidades.
--
-- No modifica migraciones anteriores: solo reemplaza funciones y políticas.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. COLUMNAS NUEVAS (auditoría de anulaciones y caja)
-- -----------------------------------------------------------------------------
alter table public.registros add column if not exists anulado_por uuid references public.profiles(id);
alter table public.registros add column if not exists anulado_at timestamptz;

alter table public.pagos_mensualidad add column if not exists anulado_por uuid references public.profiles(id);
alter table public.pagos_mensualidad add column if not exists anulado_at timestamptz;

alter table public.turnos_caja add column if not exists diferencia_recepcion integer;
alter table public.turnos_caja add column if not exists cerrado_sin_relevo boolean not null default false;
alter table public.turnos_caja add column if not exists nota_correccion text;

create index if not exists comprobantes_origen_unico_idx
  on public.comprobantes(parqueadero_id, origen, origen_id);

-- -----------------------------------------------------------------------------
-- 1. PROFILES: cerrar escalada entre parqueaderos
--    Ningún usuario puede editar su perfil directamente. Los cambios de rol y
--    estado pasan por la RPC actualizar_usuario (admin) y las altas por la Edge
--    Function invitar-usuario (service role).
-- -----------------------------------------------------------------------------
drop policy if exists "profiles_insert_control" on public.profiles;
drop policy if exists "profiles_update_control" on public.profiles;

create policy "profiles_update_superadmin" on public.profiles
  for update to authenticated
  using (public.es_superadmin())
  with check (public.es_superadmin());

-- -----------------------------------------------------------------------------
-- 2. PARQUEADEROS: el admin edita sus datos pero no puede cambiar su estado
-- -----------------------------------------------------------------------------
create or replace function public.proteger_campos_parqueadero()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if current_user in ('postgres', 'service_role', 'supabase_admin') then
    return new;
  end if;
  if new.estado is distinct from old.estado and not public.es_superadmin() then
    raise exception 'Solo el superadmin puede activar o suspender un parqueadero';
  end if;
  if new.id is distinct from old.id then
    raise exception 'No se puede cambiar el identificador del parqueadero';
  end if;
  return new;
end;
$$;

drop trigger if exists parqueaderos_proteger_campos on public.parqueaderos;
create trigger parqueaderos_proteger_campos
  before update on public.parqueaderos
  for each row execute function public.proteger_campos_parqueadero();

-- -----------------------------------------------------------------------------
-- 3. RLS DE NEGOCIO: lectura por parqueadero, escritura solo vía RPC
--    (las RPC son security definer y no dependen de estas políticas)
-- -----------------------------------------------------------------------------

-- Catálogos de Ajustes: lectura del parqueadero; alta/edición solo admin; sin borrado
drop policy if exists "tipos_vehiculo_select" on public.tipos_vehiculo;
drop policy if exists "tipos_vehiculo_all_admin" on public.tipos_vehiculo;
drop policy if exists "tarifas_select" on public.tarifas;
drop policy if exists "tarifas_all_admin" on public.tarifas;
drop policy if exists "planes_select" on public.planes_mensuales;
drop policy if exists "planes_all_admin" on public.planes_mensuales;
drop policy if exists "metodos_pago_select" on public.metodos_pago;
drop policy if exists "metodos_pago_all_admin" on public.metodos_pago;

create policy "tipos_vehiculo_select" on public.tipos_vehiculo for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "tipos_vehiculo_insert_admin" on public.tipos_vehiculo for insert to authenticated
  with check (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin');
create policy "tipos_vehiculo_update_admin" on public.tipos_vehiculo for update to authenticated
  using (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin')
  with check (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin');

create policy "tarifas_select" on public.tarifas for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "tarifas_insert_admin" on public.tarifas for insert to authenticated
  with check (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin');
create policy "tarifas_update_admin" on public.tarifas for update to authenticated
  using (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin')
  with check (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin');

create policy "planes_select" on public.planes_mensuales for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "planes_insert_admin" on public.planes_mensuales for insert to authenticated
  with check (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin');
create policy "planes_update_admin" on public.planes_mensuales for update to authenticated
  using (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin')
  with check (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin');

create policy "metodos_pago_select" on public.metodos_pago for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "metodos_pago_insert_admin" on public.metodos_pago for insert to authenticated
  with check (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin');
create policy "metodos_pago_update_admin" on public.metodos_pago for update to authenticated
  using (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin')
  with check (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin');

-- Datos operativos: solo lectura desde la API (escritura exclusiva por RPC)
drop policy if exists "vehiculos_policy" on public.vehiculos;
drop policy if exists "turnos_caja_policy" on public.turnos_caja;
drop policy if exists "movimientos_caja_policy" on public.movimientos_caja;
drop policy if exists "registros_policy" on public.registros;
drop policy if exists "clientes_policy" on public.clientes;
drop policy if exists "mensualidades_policy" on public.mensualidades;
drop policy if exists "pagos_mensualidad_policy" on public.pagos_mensualidad;
drop policy if exists "avisos_mensualidad_policy" on public.avisos_mensualidad;
drop policy if exists "operaciones_sync_policy" on public.operaciones_sync;
drop policy if exists "comprobantes_policy" on public.comprobantes;

create policy "vehiculos_select" on public.vehiculos for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "vehiculos_update" on public.vehiculos for update to authenticated
  using (parqueadero_id = public.mi_parqueadero_id())
  with check (parqueadero_id = public.mi_parqueadero_id());

create policy "clientes_select" on public.clientes for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "clientes_update" on public.clientes for update to authenticated
  using (parqueadero_id = public.mi_parqueadero_id())
  with check (parqueadero_id = public.mi_parqueadero_id());

create policy "turnos_caja_select" on public.turnos_caja for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "movimientos_caja_select" on public.movimientos_caja for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "registros_select" on public.registros for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "mensualidades_select" on public.mensualidades for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "pagos_mensualidad_select" on public.pagos_mensualidad for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "avisos_mensualidad_select" on public.avisos_mensualidad for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());
create policy "operaciones_sync_select" on public.operaciones_sync for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id() and public.mi_rol() = 'admin');
create policy "comprobantes_select" on public.comprobantes for select to authenticated
  using (parqueadero_id = public.mi_parqueadero_id());

-- -----------------------------------------------------------------------------
-- 4. HELPERS
-- -----------------------------------------------------------------------------
create or replace function public.requerir_parqueadero()
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_id uuid := public.mi_parqueadero_id();
begin
  if v_id is null then
    raise exception 'Tu usuario no pertenece a ningún parqueadero';
  end if;
  if exists (select 1 from public.profiles where id = auth.uid() and activo = false) then
    raise exception 'Tu usuario está desactivado';
  end if;
  if exists (select 1 from public.parqueaderos where id = v_id and estado = 'suspendido') then
    raise exception 'El parqueadero está suspendido';
  end if;
  return v_id;
end;
$$;

create or replace function public.zona_parqueadero(p_parqueadero_id uuid)
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce((select zona_horaria from public.parqueaderos where id = p_parqueadero_id), 'America/Bogota');
$$;

create or replace function public.requerir_admin()
returns void
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if coalesce(public.mi_rol(), '') <> 'admin' then
    raise exception 'Esta acción solo la puede hacer un administrador';
  end if;
end;
$$;

create or replace function public.hora_servidor()
returns timestamptz
language sql
volatile
as $$
  select clock_timestamp();
$$;

-- -----------------------------------------------------------------------------
-- 5. MOTOR DE COBRO EN EL SERVIDOR (paridad con src/domain/cobro.js)
-- -----------------------------------------------------------------------------
create or replace function public.cobro_sin_tope(
  p_minutos integer, p_modalidad text, p_valor integer, p_fraccion integer
)
returns bigint
language plpgsql
immutable
set search_path = public
as $$
begin
  if p_minutos <= 0 then
    return 0;
  end if;
  case p_modalidad
    when 'por_minuto' then return p_minutos::bigint * p_valor;
    when 'por_hora' then return ceil(p_minutos / 60.0)::bigint * p_valor;
    when 'por_fraccion' then return ceil(p_minutos::numeric / p_fraccion)::bigint * p_valor;
    when 'plena' then return ceil(p_minutos / 1440.0)::bigint * p_valor;
    else raise exception 'Modalidad no soportada: %', p_modalidad;
  end case;
end;
$$;

create or replace function public.calcular_cobro_base(
  p_minutos integer,
  p_modalidad text,
  p_valor integer,
  p_minutos_gracia integer default 0,
  p_minutos_fraccion integer default 15,
  p_tope_por_24h integer default null
)
returns integer
language plpgsql
immutable
set search_path = public
as $$
declare
  v_min integer := greatest(coalesce(p_minutos, 0), 0);
  v_frac integer := case when coalesce(p_minutos_fraccion, 0) > 0 then p_minutos_fraccion else 15 end;
begin
  if p_modalidad not in ('por_minuto', 'por_hora', 'por_fraccion', 'plena') then
    raise exception 'Modalidad no soportada: %', p_modalidad;
  end if;
  if v_min <= coalesce(p_minutos_gracia, 0) then
    return 0;
  end if;
  if p_modalidad = 'plena' or p_tope_por_24h is null then
    return public.cobro_sin_tope(v_min, p_modalidad, p_valor, v_frac);
  end if;
  return (v_min / 1440) * least(p_tope_por_24h, public.cobro_sin_tope(1440, p_modalidad, p_valor, v_frac))
       + least(p_tope_por_24h, public.cobro_sin_tope(v_min % 1440, p_modalidad, p_valor, v_frac));
end;
$$;

-- Parte la estancia en tramos generales / nocturnos en la zona del parqueadero.
-- p_general y p_nocturna son filas de tarifas en jsonb (to_jsonb(t)).
create or replace function public.calcular_cobro_tramos(
  p_entrada timestamptz,
  p_salida timestamptz,
  p_general jsonb,
  p_nocturna jsonb default null,
  p_zona text default 'America/Bogota'
)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_min_total integer;
  v_puntos timestamptz[];
  v_dia date;
  v_ultimo date;
  v_corte timestamptz;
  v_ini time;
  v_fin time;
  v_p1 timestamptz;
  v_p2 timestamptz;
  v_dur integer;
  v_hora time;
  v_tipo text;
  v_tipos text[] := '{}';
  v_mins integer[] := '{}';
  v_n integer;
  v_valor integer;
  v_total integer := 0;
  v_desglose jsonb := '[]'::jsonb;
  i integer;
begin
  if p_general is null then
    raise exception 'No hay tarifa general configurada';
  end if;
  if p_salida < p_entrada then
    raise exception 'La fecha de salida no puede ser anterior a la de entrada';
  end if;

  v_min_total := round(extract(epoch from (p_salida - p_entrada)) / 60.0)::integer;

  if v_min_total <= coalesce((p_general->>'minutos_gracia')::integer, 0) then
    return jsonb_build_object('minutos', v_min_total, 'valor', 0,
      'desglose', jsonb_build_array(jsonb_build_object('tipo', 'general', 'minutos', v_min_total, 'valor', 0)));
  end if;

  if p_nocturna is null or p_nocturna->>'franja_inicio' is null or p_nocturna->>'franja_fin' is null then
    v_valor := public.calcular_cobro_base(
      v_min_total, p_general->>'modalidad', (p_general->>'valor')::integer, 0,
      (p_general->>'minutos_fraccion')::integer, (p_general->>'tope_por_24h')::integer);
    return jsonb_build_object('minutos', v_min_total, 'valor', v_valor,
      'desglose', jsonb_build_array(jsonb_build_object('tipo', 'general', 'minutos', v_min_total, 'valor', v_valor)));
  end if;

  v_ini := (p_nocturna->>'franja_inicio')::time;
  v_fin := (p_nocturna->>'franja_fin')::time;
  v_puntos := array[p_entrada, p_salida];
  v_dia := (p_entrada at time zone p_zona)::date - 1;
  v_ultimo := (p_salida at time zone p_zona)::date + 1;

  while v_dia <= v_ultimo loop
    v_corte := (v_dia + v_ini) at time zone p_zona;
    if v_corte > p_entrada and v_corte < p_salida then
      v_puntos := v_puntos || v_corte;
    end if;
    v_corte := (v_dia + v_fin) at time zone p_zona;
    if v_corte > p_entrada and v_corte < p_salida then
      v_puntos := v_puntos || v_corte;
    end if;
    v_dia := v_dia + 1;
  end loop;

  select array_agg(x order by x) into v_puntos from unnest(v_puntos) as x;

  for i in 1 .. array_length(v_puntos, 1) - 1 loop
    v_p1 := v_puntos[i];
    v_p2 := v_puntos[i + 1];
    v_dur := round(extract(epoch from (v_p2 - v_p1)) / 60.0)::integer;
    continue when v_dur <= 0;
    v_hora := ((v_p1 + (v_p2 - v_p1) / 2) at time zone p_zona)::time;
    if v_ini > v_fin then
      v_tipo := case when v_hora >= v_ini or v_hora < v_fin then 'nocturna' else 'general' end;
    else
      v_tipo := case when v_hora >= v_ini and v_hora < v_fin then 'nocturna' else 'general' end;
    end if;
    v_n := coalesce(array_length(v_tipos, 1), 0);
    if v_n > 0 and v_tipos[v_n] = v_tipo then
      v_mins[v_n] := v_mins[v_n] + v_dur;
    else
      v_tipos := v_tipos || v_tipo;
      v_mins := v_mins || v_dur;
    end if;
  end loop;

  for i in 1 .. coalesce(array_length(v_tipos, 1), 0) loop
    if v_tipos[i] = 'nocturna' then
      if p_nocturna->>'modalidad' = 'plena' then
        v_valor := (p_nocturna->>'valor')::integer;
      else
        v_valor := public.calcular_cobro_base(
          v_mins[i], p_nocturna->>'modalidad', (p_nocturna->>'valor')::integer, 0,
          (p_nocturna->>'minutos_fraccion')::integer, (p_nocturna->>'tope_por_24h')::integer);
      end if;
    else
      v_valor := public.calcular_cobro_base(
        v_mins[i], p_general->>'modalidad', (p_general->>'valor')::integer, 0,
        (p_general->>'minutos_fraccion')::integer, (p_general->>'tope_por_24h')::integer);
    end if;
    v_total := v_total + v_valor;
    v_desglose := v_desglose || jsonb_build_object('tipo', v_tipos[i], 'minutos', v_mins[i], 'valor', v_valor);
  end loop;

  return jsonb_build_object('minutos', v_min_total, 'valor', v_total, 'desglose', v_desglose);
end;
$$;

-- Mensualidad vigente de un vehículo: vigente hasta fecha_fin + días de gracia del plan
create or replace function public.mensualidad_de_vehiculo(p_vehiculo_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_m record;
  v_hoy date;
begin
  if p_vehiculo_id is null then
    return null;
  end if;
  select m.id, m.fecha_fin, m.parqueadero_id, coalesce(p.dias_gracia_pago, 0) as gracia
  into v_m
  from public.mensualidades m
  join public.planes_mensuales p on p.id = m.plan_id
  where m.vehiculo_id = p_vehiculo_id and m.activa = true
  limit 1;

  if not found then
    return null;
  end if;

  v_hoy := (now() at time zone public.zona_parqueadero(v_m.parqueadero_id))::date;
  return jsonb_build_object(
    'mensualidad_id', v_m.id,
    'fecha_fin', v_m.fecha_fin,
    'vigente', v_hoy <= v_m.fecha_fin + v_m.gracia
  );
end;
$$;

-- Cotiza (sin cerrar) el cobro de un registro abierto. Lo usa la pantalla de
-- salida para mostrar el valor del servidor y registrar_salida para cobrar.
create or replace function public.calcular_cobro(
  p_registro_id uuid,
  p_tarifa_id uuid default null,
  p_salida_at timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_reg record;
  v_salida timestamptz;
  v_general public.tarifas;
  v_nocturna public.tarifas;
  v_mens jsonb;
  v_res jsonb;
  v_es_mensual boolean := false;
begin
  select * into v_reg from public.registros where id = p_registro_id and parqueadero_id = v_pq;
  if not found then
    raise exception 'Registro no encontrado';
  end if;
  if v_reg.estado <> 'abierto' then
    raise exception 'El vehículo ya salió o el registro fue anulado';
  end if;

  v_salida := greatest(coalesce(p_salida_at, now()), v_reg.entrada_at);

  -- Tarifa general: la elegida (si no tiene franja), la del registro, o la predeterminada
  select * into v_general from public.tarifas
  where parqueadero_id = v_pq and tipo_vehiculo_id = v_reg.tipo_vehiculo_id
    and activa = true and franja_inicio is null
    and id = coalesce(p_tarifa_id, v_reg.tarifa_id);

  if v_general.id is null then
    select * into v_general from public.tarifas
    where parqueadero_id = v_pq and tipo_vehiculo_id = v_reg.tipo_vehiculo_id
      and activa = true and franja_inicio is null
    order by es_predeterminada desc, created_at
    limit 1;
  end if;

  select * into v_nocturna from public.tarifas
  where parqueadero_id = v_pq and tipo_vehiculo_id = v_reg.tipo_vehiculo_id
    and activa = true and franja_inicio is not null and franja_fin is not null
  limit 1;

  v_mens := public.mensualidad_de_vehiculo(v_reg.vehiculo_id);
  v_es_mensual := coalesce((v_mens->>'vigente')::boolean, false);

  if v_es_mensual then
    v_res := jsonb_build_object(
      'minutos', round(extract(epoch from (v_salida - v_reg.entrada_at)) / 60.0)::integer,
      'valor', 0,
      'desglose', jsonb_build_array(jsonb_build_object('tipo', 'mensualidad', 'minutos', 0, 'valor', 0)));
  else
    if v_general.id is null then
      raise exception 'El tipo de vehículo no tiene una tarifa activa. Configúrela en Ajustes';
    end if;
    v_res := public.calcular_cobro_tramos(
      v_reg.entrada_at, v_salida, to_jsonb(v_general),
      case when v_nocturna.id is null then null else to_jsonb(v_nocturna) end,
      public.zona_parqueadero(v_pq));
  end if;

  return v_res || jsonb_build_object(
    'registro_id', v_reg.id,
    'placa', v_reg.placa,
    'entrada_at', v_reg.entrada_at,
    'salida_at', v_salida,
    'es_mensual', v_es_mensual,
    'mensualidad', v_mens,
    'tarifa_id', v_general.id,
    'tarifa_nombre', v_general.nombre,
    'tarifa_nocturna_id', v_nocturna.id,
    'snapshot', jsonb_build_object(
      'general', case when v_general.id is null then null else to_jsonb(v_general) end,
      'nocturna', case when v_nocturna.id is null then null else to_jsonb(v_nocturna) end)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 6. PATIO: ENTRADA, SALIDA Y ANULACIÓN
-- -----------------------------------------------------------------------------
create or replace function public.registrar_entrada(
  p_id uuid,
  p_placa text,
  p_tipo_vehiculo_id uuid,
  p_tarifa_id uuid default null,
  p_hora_dispositivo timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_zona text := public.zona_parqueadero(v_pq);
  v_placa text;
  v_tipo record;
  v_vehiculo_id uuid;
  v_tarifa_id uuid := p_tarifa_id;
  v_existente record;
  v_registro_id uuid := coalesce(p_id, gen_random_uuid());
  v_turno_id uuid;
  v_hora timestamptz;
  v_origen text;
  v_ocupados integer;
  v_mens jsonb;
  v_es_mensual boolean := false;
begin
  -- Idempotencia: reenviar la misma entrada no crea otra
  select * into v_existente from public.registros where id = v_registro_id;
  if found then
    if v_existente.parqueadero_id <> v_pq then
      raise exception 'Identificador de registro inválido';
    end if;
    return jsonb_build_object('success', true, 'ya_existia', true, 'registro_id', v_existente.id,
      'placa', v_existente.placa, 'entrada_at', v_existente.entrada_at, 'es_mensual', v_existente.es_mensual);
  end if;

  v_placa := upper(regexp_replace(trim(coalesce(p_placa, '')), '[^A-Za-z0-9]', '', 'g'));
  if length(v_placa) < 3 then
    raise exception 'Placa inválida: %', p_placa;
  end if;

  select * into v_tipo from public.tipos_vehiculo
  where id = p_tipo_vehiculo_id and parqueadero_id = v_pq and activo = true;
  if not found then
    raise exception 'Tipo de vehículo no válido o desactivado';
  end if;

  select * into v_existente from public.registros
  where parqueadero_id = v_pq and placa = v_placa and estado = 'abierto';
  if found then
    raise exception 'Este vehículo ya está dentro desde las %',
      to_char(v_existente.entrada_at at time zone v_zona, 'HH24:MI');
  end if;

  if v_tarifa_id is not null and not exists (
    select 1 from public.tarifas
    where id = v_tarifa_id and parqueadero_id = v_pq and tipo_vehiculo_id = p_tipo_vehiculo_id and activa = true
  ) then
    raise exception 'La tarifa elegida no corresponde al tipo de vehículo';
  end if;

  if v_tarifa_id is null then
    select id into v_tarifa_id from public.tarifas
    where parqueadero_id = v_pq and tipo_vehiculo_id = p_tipo_vehiculo_id
      and activa = true and franja_inicio is null
    order by es_predeterminada desc, created_at
    limit 1;
  end if;

  select id into v_vehiculo_id from public.vehiculos where parqueadero_id = v_pq and placa = v_placa;
  if not found then
    insert into public.vehiculos (parqueadero_id, placa, tipo_vehiculo_id)
    values (v_pq, v_placa, p_tipo_vehiculo_id)
    returning id into v_vehiculo_id;
  end if;

  v_mens := public.mensualidad_de_vehiculo(v_vehiculo_id);
  v_es_mensual := coalesce((v_mens->>'vigente')::boolean, false);

  select id into v_turno_id from public.turnos_caja where parqueadero_id = v_pq and estado = 'abierto';

  -- En línea la hora la pone el servidor; solo las entradas sincronizadas traen hora del dispositivo
  if p_hora_dispositivo is not null then
    v_hora := least(p_hora_dispositivo, now());
    v_origen := 'dispositivo';
  else
    v_hora := now();
    v_origen := 'servidor';
  end if;

  select count(*) into v_ocupados from public.registros
  where parqueadero_id = v_pq and tipo_vehiculo_id = p_tipo_vehiculo_id and estado = 'abierto';

  insert into public.registros (
    id, parqueadero_id, placa, tipo_vehiculo_id, tarifa_id, vehiculo_id, entrada_at,
    es_mensual, turno_entrada_id, usuario_entrada, hora_origen, estado
  ) values (
    v_registro_id, v_pq, v_placa, p_tipo_vehiculo_id, v_tarifa_id, v_vehiculo_id, v_hora,
    v_es_mensual, v_turno_id, auth.uid(), v_origen, 'abierto'
  );

  return jsonb_build_object(
    'success', true,
    'registro_id', v_registro_id,
    'placa', v_placa,
    'entrada_at', v_hora,
    'hora_origen', v_origen,
    'tarifa_id', v_tarifa_id,
    'es_mensual', v_es_mensual,
    'mensualidad', v_mens,
    'sobrecupo', v_ocupados + 1 > v_tipo.capacidad,
    'ocupados', v_ocupados + 1,
    'capacidad', v_tipo.capacidad
  );
end;
$$;

drop function if exists public.registrar_salida(uuid, uuid, uuid, integer);

create or replace function public.registrar_salida(
  p_registro_id uuid,
  p_metodo_pago_id uuid default null,
  p_tarifa_id uuid default null,
  p_valor_cobrado integer default null,
  p_salida_dispositivo timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_reg record;
  v_cobro jsonb;
  v_salida timestamptz;
  v_valor_servidor integer;
  v_valor integer;
  v_revision boolean := false;
  v_turno_id uuid;
  v_es_efectivo boolean := false;
begin
  select * into v_reg from public.registros
  where id = p_registro_id and parqueadero_id = v_pq
  for update;
  if not found then
    raise exception 'Registro no encontrado';
  end if;
  if v_reg.estado <> 'abierto' then
    raise exception 'El vehículo ya salió o el registro fue anulado';
  end if;

  v_salida := greatest(coalesce(least(p_salida_dispositivo, now()), now()), v_reg.entrada_at);
  v_cobro := public.calcular_cobro(p_registro_id, p_tarifa_id, v_salida);
  v_valor_servidor := (v_cobro->>'valor')::integer;

  -- El servidor tiene la última palabra. Solo un cobro hecho sin conexión
  -- (sincronizado) respeta lo cobrado y queda marcado para revisión si difiere.
  if p_salida_dispositivo is not null and p_valor_cobrado is not null then
    v_valor := greatest(p_valor_cobrado, 0);
    v_revision := v_valor <> v_valor_servidor;
  else
    v_valor := v_valor_servidor;
  end if;

  select id into v_turno_id from public.turnos_caja where parqueadero_id = v_pq and estado = 'abierto';

  if v_valor > 0 then
    if v_turno_id is null then
      raise exception 'No se puede cobrar sin un turno de caja abierto';
    end if;
    select es_efectivo into v_es_efectivo from public.metodos_pago
    where id = p_metodo_pago_id and parqueadero_id = v_pq and activo = true;
    if not found then
      raise exception 'Seleccione un método de pago válido';
    end if;
  end if;

  update public.registros set
    salida_at = v_salida,
    minutos = (v_cobro->>'minutos')::integer,
    valor = v_valor,
    valor_servidor = v_valor_servidor,
    requiere_revision = v_revision,
    metodo_pago_id = case when v_valor > 0 then p_metodo_pago_id else null end,
    tarifa_id = coalesce((v_cobro->>'tarifa_id')::uuid, v_reg.tarifa_id),
    tarifa_snapshot = (v_cobro->'snapshot') || jsonb_build_object('desglose', v_cobro->'desglose'),
    es_mensual = (v_cobro->>'es_mensual')::boolean,
    turno_salida_id = v_turno_id,
    usuario_salida = auth.uid(),
    estado = 'cerrado'
  where id = p_registro_id;

  if v_valor > 0 and v_es_efectivo then
    update public.turnos_caja set efectivo_esperado = efectivo_esperado + v_valor where id = v_turno_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'registro_id', p_registro_id,
    'salida_at', v_salida,
    'minutos', (v_cobro->>'minutos')::integer,
    'valor', v_valor,
    'valor_servidor', v_valor_servidor,
    'requiere_revision', v_revision,
    'es_mensual', (v_cobro->>'es_mensual')::boolean,
    'desglose', v_cobro->'desglose',
    'tarifa_nombre', v_cobro->>'tarifa_nombre'
  );
end;
$$;

create or replace function public.anular_registro(
  p_registro_id uuid,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_reg record;
  v_es_efectivo boolean := false;
begin
  perform public.requerir_admin();

  if length(trim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'El motivo de anulación debe tener al menos 10 caracteres';
  end if;

  select * into v_reg from public.registros where id = p_registro_id and parqueadero_id = v_pq for update;
  if not found then
    raise exception 'Registro no encontrado';
  end if;
  if v_reg.estado = 'anulado' then
    raise exception 'El registro ya estaba anulado';
  end if;

  update public.registros set
    estado = 'anulado',
    motivo_anulacion = trim(p_motivo),
    anulado_por = auth.uid(),
    anulado_at = now()
  where id = p_registro_id;

  -- Los turnos cerrados no se editan: solo se descuenta si el turno sigue abierto
  if v_reg.estado = 'cerrado' and v_reg.valor > 0 and v_reg.turno_salida_id is not null then
    select es_efectivo into v_es_efectivo from public.metodos_pago where id = v_reg.metodo_pago_id;
    if coalesce(v_es_efectivo, false) then
      update public.turnos_caja set efectivo_esperado = efectivo_esperado - v_reg.valor
      where id = v_reg.turno_salida_id and estado = 'abierto';
    end if;
  end if;

  return jsonb_build_object('success', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- 7. CAJA Y TURNOS
-- -----------------------------------------------------------------------------
create or replace function public.abrir_turno(p_base_inicial integer default 0)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_turno_id uuid;
begin
  if coalesce(p_base_inicial, 0) < 0 then
    raise exception 'La base inicial no puede ser negativa';
  end if;
  if exists (select 1 from public.turnos_caja where parqueadero_id = v_pq and estado in ('abierto', 'por_recibir')) then
    raise exception 'Ya hay un turno abierto o pendiente por recibir';
  end if;

  insert into public.turnos_caja (parqueadero_id, usuario_id, base_inicial, efectivo_esperado, estado)
  values (v_pq, auth.uid(), coalesce(p_base_inicial, 0), coalesce(p_base_inicial, 0), 'abierto')
  returning id into v_turno_id;

  return jsonb_build_object('success', true, 'turno_id', v_turno_id);
end;
$$;

create or replace function public.entregar_turno(
  p_turno_id uuid,
  p_efectivo_contado integer,
  p_observacion text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_turno record;
begin
  if p_efectivo_contado is null or p_efectivo_contado < 0 then
    raise exception 'Ingrese el efectivo contado';
  end if;
  select * into v_turno from public.turnos_caja where id = p_turno_id and parqueadero_id = v_pq for update;
  if not found then
    raise exception 'Turno no encontrado';
  end if;
  if v_turno.estado <> 'abierto' then
    raise exception 'El turno ya no está abierto';
  end if;

  update public.turnos_caja set
    cerrado_at = now(),
    efectivo_contado = p_efectivo_contado,
    diferencia = p_efectivo_contado - v_turno.efectivo_esperado,
    observacion = nullif(trim(coalesce(p_observacion, '')), ''),
    estado = 'por_recibir'
  where id = p_turno_id;

  return jsonb_build_object('success', true,
    'efectivo_esperado', v_turno.efectivo_esperado,
    'diferencia', p_efectivo_contado - v_turno.efectivo_esperado);
end;
$$;

create or replace function public.recibir_turno(
  p_turno_id uuid,
  p_efectivo_recibido integer
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_turno record;
  v_nuevo uuid;
begin
  if p_efectivo_recibido is null or p_efectivo_recibido < 0 then
    raise exception 'Ingrese el efectivo recibido';
  end if;
  select * into v_turno from public.turnos_caja
  where id = p_turno_id and parqueadero_id = v_pq and estado = 'por_recibir'
  for update;
  if not found then
    raise exception 'Turno por recibir no encontrado';
  end if;

  update public.turnos_caja set
    recibido_por = auth.uid(),
    recibido_at = now(),
    efectivo_recibido = p_efectivo_recibido,
    diferencia_recepcion = p_efectivo_recibido - coalesce(v_turno.efectivo_contado, 0),
    estado = 'cerrado'
  where id = p_turno_id;

  insert into public.turnos_caja (parqueadero_id, usuario_id, base_inicial, efectivo_esperado, estado)
  values (v_pq, auth.uid(), p_efectivo_recibido, p_efectivo_recibido, 'abierto')
  returning id into v_nuevo;

  return jsonb_build_object('success', true, 'nuevo_turno_id', v_nuevo,
    'diferencia_recepcion', p_efectivo_recibido - coalesce(v_turno.efectivo_contado, 0));
end;
$$;

-- Cierre sin relevo (el parqueadero cierra o nadie recibe). El próximo turno pide base.
create or replace function public.cerrar_turno_sin_relevo(
  p_turno_id uuid,
  p_efectivo_contado integer default null,
  p_observacion text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_turno record;
  v_contado integer;
begin
  select * into v_turno from public.turnos_caja
  where id = p_turno_id and parqueadero_id = v_pq and estado in ('abierto', 'por_recibir')
  for update;
  if not found then
    raise exception 'Turno no encontrado o ya cerrado';
  end if;

  v_contado := coalesce(p_efectivo_contado, v_turno.efectivo_contado);
  if v_contado is null or v_contado < 0 then
    raise exception 'Ingrese el efectivo contado';
  end if;

  update public.turnos_caja set
    cerrado_at = coalesce(cerrado_at, now()),
    efectivo_contado = v_contado,
    diferencia = v_contado - v_turno.efectivo_esperado,
    observacion = coalesce(nullif(trim(coalesce(p_observacion, '')), ''), observacion),
    cerrado_sin_relevo = true,
    estado = 'cerrado'
  where id = p_turno_id;

  return jsonb_build_object('success', true, 'diferencia', v_contado - v_turno.efectivo_esperado);
end;
$$;

create or replace function public.registrar_movimiento_caja(
  p_turno_id uuid,
  p_tipo text,
  p_valor integer,
  p_motivo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
begin
  if p_tipo not in ('retiro', 'ingreso_manual') then
    raise exception 'Tipo de movimiento inválido';
  end if;
  if coalesce(p_valor, 0) <= 0 then
    raise exception 'El valor debe ser mayor a 0';
  end if;
  if trim(coalesce(p_motivo, '')) = '' then
    raise exception 'El motivo es obligatorio';
  end if;
  if not exists (select 1 from public.turnos_caja where id = p_turno_id and parqueadero_id = v_pq and estado = 'abierto') then
    raise exception 'El turno no está abierto';
  end if;

  insert into public.movimientos_caja (parqueadero_id, turno_id, tipo, valor, motivo, usuario_id)
  values (v_pq, p_turno_id, p_tipo, p_valor, trim(p_motivo), auth.uid());

  update public.turnos_caja
  set efectivo_esperado = efectivo_esperado + case when p_tipo = 'retiro' then -p_valor else p_valor end
  where id = p_turno_id;

  return jsonb_build_object('success', true);
end;
$$;

-- Los turnos cerrados no se editan: el admin agrega notas de corrección
create or replace function public.agregar_nota_turno(p_turno_id uuid, p_nota text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
begin
  perform public.requerir_admin();
  if trim(coalesce(p_nota, '')) = '' then
    raise exception 'La nota no puede estar vacía';
  end if;
  update public.turnos_caja
  set nota_correccion = concat_ws(E'\n', nota_correccion,
    to_char(now() at time zone public.zona_parqueadero(v_pq), 'YYYY-MM-DD HH24:MI') || ' · ' || trim(p_nota))
  where id = p_turno_id and parqueadero_id = v_pq;
  if not found then
    raise exception 'Turno no encontrado';
  end if;
  return jsonb_build_object('success', true);
end;
$$;

-- Resumen en vivo / histórico de un turno (HU-24)
create or replace function public.obtener_resumen_turno(p_turno_id uuid default null)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_turno record;
begin
  if p_turno_id is null then
    select * into v_turno from public.turnos_caja
    where parqueadero_id = v_pq and estado in ('abierto', 'por_recibir')
    limit 1;
  else
    select * into v_turno from public.turnos_caja where id = p_turno_id and parqueadero_id = v_pq;
  end if;

  if v_turno.id is null then
    return null;
  end if;

  return jsonb_build_object(
    'turno', to_jsonb(v_turno) || jsonb_build_object(
      'usuario_nombre', (select nombre from public.profiles where id = v_turno.usuario_id),
      'recibido_por_nombre', (select nombre from public.profiles where id = v_turno.recibido_por)),
    'entradas', (select count(*) from public.registros where turno_entrada_id = v_turno.id),
    'salidas', (select count(*) from public.registros where turno_salida_id = v_turno.id and estado = 'cerrado'),
    'cobros_hora', coalesce((
      select jsonb_agg(jsonb_build_object('metodo', mp.nombre, 'es_efectivo', mp.es_efectivo, 'cantidad', x.cantidad, 'total', x.total) order by mp.orden)
      from (
        select metodo_pago_id, count(*) as cantidad, sum(valor) as total
        from public.registros
        where turno_salida_id = v_turno.id and estado = 'cerrado' and valor > 0
        group by metodo_pago_id
      ) x join public.metodos_pago mp on mp.id = x.metodo_pago_id), '[]'::jsonb),
    'pagos_mensualidad', coalesce((
      select jsonb_agg(jsonb_build_object('metodo', mp.nombre, 'es_efectivo', mp.es_efectivo, 'cantidad', x.cantidad, 'total', x.total) order by mp.orden)
      from (
        select metodo_pago_id, count(*) as cantidad, sum(valor) as total
        from public.pagos_mensualidad
        where turno_id = v_turno.id and anulado = false
        group by metodo_pago_id
      ) x join public.metodos_pago mp on mp.id = x.metodo_pago_id), '[]'::jsonb),
    'movimientos', coalesce((
      select jsonb_agg(jsonb_build_object('id', m.id, 'tipo', m.tipo, 'valor', m.valor, 'motivo', m.motivo,
        'created_at', m.created_at, 'usuario', p.nombre) order by m.created_at)
      from public.movimientos_caja m left join public.profiles p on p.id = m.usuario_id
      where m.turno_id = v_turno.id), '[]'::jsonb),
    'vehiculos_dentro', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', tv.nombre, 'cantidad', x.cantidad) order by tv.orden)
      from (
        select tipo_vehiculo_id, count(*) as cantidad
        from public.registros where parqueadero_id = v_pq and estado = 'abierto'
        group by tipo_vehiculo_id
      ) x join public.tipos_vehiculo tv on tv.id = x.tipo_vehiculo_id), '[]'::jsonb)
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 8. MENSUALIDADES
-- -----------------------------------------------------------------------------
create or replace function public.crear_mensualidad(
  p_cliente_nombre text,
  p_cliente_documento text,
  p_cliente_telefono text,
  p_cliente_email text,
  p_placa text,
  p_tipo_vehiculo_id uuid,
  p_plan_id uuid,
  p_fecha_inicio date,
  p_metodo_pago_id uuid default null,
  p_registrar_primer_pago boolean default true
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_cliente_id uuid;
  v_vehiculo_id uuid;
  v_placa text;
  v_plan record;
  v_metodo record;
  v_fecha_inicio date;
  v_fecha_fin date;
  v_mensualidad_id uuid;
  v_turno_id uuid;
  v_pago_id uuid;
begin
  if trim(coalesce(p_cliente_nombre, '')) = '' or trim(coalesce(p_cliente_documento, '')) = '' then
    raise exception 'Nombre y documento del cliente son obligatorios';
  end if;

  v_placa := upper(regexp_replace(trim(coalesce(p_placa, '')), '[^A-Za-z0-9]', '', 'g'));
  if length(v_placa) < 3 then
    raise exception 'Placa inválida: %', p_placa;
  end if;

  if not exists (select 1 from public.tipos_vehiculo where id = p_tipo_vehiculo_id and parqueadero_id = v_pq and activo = true) then
    raise exception 'Tipo de vehículo no válido';
  end if;

  select * into v_plan from public.planes_mensuales
  where id = p_plan_id and parqueadero_id = v_pq and activo = true;
  if not found then
    raise exception 'Plan mensual no encontrado o inactivo';
  end if;
  if v_plan.tipo_vehiculo_id <> p_tipo_vehiculo_id then
    raise exception 'El plan no corresponde al tipo de vehículo';
  end if;

  v_fecha_inicio := coalesce(p_fecha_inicio, (now() at time zone public.zona_parqueadero(v_pq))::date);

  if p_registrar_primer_pago then
    select * into v_metodo from public.metodos_pago where id = p_metodo_pago_id and parqueadero_id = v_pq and activo = true;
    if not found then
      raise exception 'Seleccione un método de pago válido';
    end if;
    select id into v_turno_id from public.turnos_caja where parqueadero_id = v_pq and estado = 'abierto';
    if v_turno_id is null and v_plan.valor > 0 then
      raise exception 'Abra un turno de caja para registrar el pago';
    end if;
  end if;

  -- Cliente: reutilizar por documento
  select id into v_cliente_id from public.clientes where parqueadero_id = v_pq and documento = trim(p_cliente_documento);
  if not found then
    insert into public.clientes (parqueadero_id, nombre, documento, telefono, email)
    values (v_pq, trim(p_cliente_nombre), trim(p_cliente_documento), nullif(trim(coalesce(p_cliente_telefono, '')), ''), nullif(trim(coalesce(p_cliente_email, '')), ''))
    returning id into v_cliente_id;
  else
    update public.clientes set
      nombre = trim(p_cliente_nombre),
      telefono = coalesce(nullif(trim(coalesce(p_cliente_telefono, '')), ''), telefono),
      email = coalesce(nullif(trim(coalesce(p_cliente_email, '')), ''), email)
    where id = v_cliente_id;
  end if;

  -- Vehículo: reutilizar por placa y vincular al cliente
  select id into v_vehiculo_id from public.vehiculos where parqueadero_id = v_pq and placa = v_placa;
  if not found then
    insert into public.vehiculos (parqueadero_id, placa, tipo_vehiculo_id)
    values (v_pq, v_placa, p_tipo_vehiculo_id)
    returning id into v_vehiculo_id;
  else
    update public.vehiculos set tipo_vehiculo_id = p_tipo_vehiculo_id where id = v_vehiculo_id;
  end if;

  if exists (select 1 from public.mensualidades where vehiculo_id = v_vehiculo_id and activa = true) then
    raise exception 'La placa % ya tiene una mensualidad activa', v_placa;
  end if;

  v_fecha_fin := public.calcular_periodo(v_plan.tipo_periodo, extract(day from v_fecha_inicio)::integer, v_plan.duracion_dias, v_fecha_inicio);

  insert into public.mensualidades (parqueadero_id, cliente_id, vehiculo_id, plan_id, dia_corte, fecha_inicio, fecha_fin, activa)
  values (v_pq, v_cliente_id, v_vehiculo_id, p_plan_id, extract(day from v_fecha_inicio)::integer, v_fecha_inicio, v_fecha_fin, true)
  returning id into v_mensualidad_id;

  if p_registrar_primer_pago then
    insert into public.pagos_mensualidad (parqueadero_id, mensualidad_id, turno_id, periodo_desde, periodo_hasta, valor, metodo_pago_id, usuario_id)
    values (v_pq, v_mensualidad_id, v_turno_id, v_fecha_inicio, v_fecha_fin, v_plan.valor, p_metodo_pago_id, auth.uid())
    returning id into v_pago_id;

    if v_metodo.es_efectivo and v_turno_id is not null then
      update public.turnos_caja set efectivo_esperado = efectivo_esperado + v_plan.valor where id = v_turno_id;
    end if;
  end if;

  return jsonb_build_object(
    'success', true,
    'mensualidad_id', v_mensualidad_id,
    'pago_id', v_pago_id,
    'fecha_inicio', v_fecha_inicio,
    'fecha_fin', v_fecha_fin,
    'valor', v_plan.valor
  );
end;
$$;

drop function if exists public.registrar_pago_mensualidad(uuid, uuid, integer, date);

create or replace function public.registrar_pago_mensualidad(
  p_mensualidad_id uuid,
  p_metodo_pago_id uuid,
  p_valor integer default null,
  p_desde_fecha date default null,
  p_reiniciar boolean default false,
  p_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_mens record;
  v_plan record;
  v_metodo record;
  v_turno_id uuid;
  v_valor integer;
  v_desde date;
  v_hasta date;
  v_dia_corte integer;
  v_pago_id uuid := coalesce(p_id, gen_random_uuid());
  v_existente record;
begin
  select * into v_existente from public.pagos_mensualidad where id = v_pago_id;
  if found then
    if v_existente.parqueadero_id <> v_pq then
      raise exception 'Identificador de pago inválido';
    end if;
    return jsonb_build_object('success', true, 'ya_existia', true, 'pago_id', v_existente.id,
      'periodo_desde', v_existente.periodo_desde, 'periodo_hasta', v_existente.periodo_hasta, 'valor', v_existente.valor);
  end if;

  select * into v_mens from public.mensualidades where id = p_mensualidad_id and parqueadero_id = v_pq for update;
  if not found then
    raise exception 'Mensualidad no encontrada';
  end if;
  if not v_mens.activa then
    raise exception 'La mensualidad está desactivada';
  end if;

  select * into v_plan from public.planes_mensuales where id = v_mens.plan_id;

  -- El valor lo pone el plan; solo un administrador puede registrar un valor distinto
  v_valor := case when public.mi_rol() = 'admin' and p_valor is not null then p_valor else v_plan.valor end;
  if v_valor < 0 then
    raise exception 'Valor inválido';
  end if;

  select * into v_metodo from public.metodos_pago where id = p_metodo_pago_id and parqueadero_id = v_pq and activo = true;
  if not found then
    raise exception 'Seleccione un método de pago válido';
  end if;

  select id into v_turno_id from public.turnos_caja where parqueadero_id = v_pq and estado = 'abierto';
  if v_turno_id is null and v_valor > 0 then
    raise exception 'No se puede registrar el pago sin un turno de caja abierto';
  end if;

  if p_reiniciar then
    v_desde := (now() at time zone public.zona_parqueadero(v_pq))::date;
    v_dia_corte := extract(day from v_desde)::integer;
  else
    v_desde := coalesce(p_desde_fecha, v_mens.fecha_fin);
    v_dia_corte := v_mens.dia_corte;
  end if;

  v_hasta := public.calcular_periodo(v_plan.tipo_periodo, v_dia_corte, v_plan.duracion_dias, v_desde);

  insert into public.pagos_mensualidad (id, parqueadero_id, mensualidad_id, turno_id, periodo_desde, periodo_hasta, valor, metodo_pago_id, usuario_id)
  values (v_pago_id, v_pq, p_mensualidad_id, v_turno_id, v_desde, v_hasta, v_valor, p_metodo_pago_id, auth.uid());

  update public.mensualidades set fecha_fin = v_hasta, dia_corte = v_dia_corte where id = p_mensualidad_id;

  if v_metodo.es_efectivo and v_turno_id is not null and v_valor > 0 then
    update public.turnos_caja set efectivo_esperado = efectivo_esperado + v_valor where id = v_turno_id;
  end if;

  return jsonb_build_object('success', true, 'pago_id', v_pago_id,
    'periodo_desde', v_desde, 'periodo_hasta', v_hasta, 'nueva_fecha_fin', v_hasta, 'valor', v_valor);
end;
$$;

create or replace function public.anular_pago_mensualidad(p_pago_id uuid, p_motivo text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_pago record;
  v_es_efectivo boolean;
  v_nueva_fin date;
begin
  perform public.requerir_admin();
  if length(trim(coalesce(p_motivo, ''))) < 10 then
    raise exception 'El motivo de anulación debe tener al menos 10 caracteres';
  end if;

  select * into v_pago from public.pagos_mensualidad where id = p_pago_id and parqueadero_id = v_pq for update;
  if not found then
    raise exception 'Pago no encontrado';
  end if;
  if v_pago.anulado then
    raise exception 'El pago ya estaba anulado';
  end if;

  update public.pagos_mensualidad set anulado = true, motivo_anulacion = trim(p_motivo), anulado_por = auth.uid(), anulado_at = now()
  where id = p_pago_id;

  -- La vigencia se recalcula con los pagos que quedan
  select coalesce(max(periodo_hasta), (select fecha_inicio from public.mensualidades where id = v_pago.mensualidad_id))
  into v_nueva_fin
  from public.pagos_mensualidad where mensualidad_id = v_pago.mensualidad_id and anulado = false;

  update public.mensualidades set fecha_fin = v_nueva_fin where id = v_pago.mensualidad_id;

  select es_efectivo into v_es_efectivo from public.metodos_pago where id = v_pago.metodo_pago_id;
  if coalesce(v_es_efectivo, false) and v_pago.turno_id is not null then
    update public.turnos_caja set efectivo_esperado = efectivo_esperado - v_pago.valor
    where id = v_pago.turno_id and estado = 'abierto';
  end if;

  return jsonb_build_object('success', true, 'nueva_fecha_fin', v_nueva_fin);
end;
$$;

create or replace function public.desactivar_mensualidad(p_mensualidad_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
begin
  perform public.requerir_admin();
  update public.mensualidades set activa = false where id = p_mensualidad_id and parqueadero_id = v_pq;
  if not found then
    raise exception 'Mensualidad no encontrada';
  end if;
  return jsonb_build_object('success', true);
end;
$$;

create or replace function public.registrar_aviso_mensualidad(
  p_mensualidad_id uuid,
  p_medio text,
  p_nota text default null,
  p_periodo_hasta date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_fecha_fin date;
begin
  if p_medio not in ('llamada', 'en_persona', 'mensaje') then
    raise exception 'Medio de aviso inválido';
  end if;
  select fecha_fin into v_fecha_fin from public.mensualidades where id = p_mensualidad_id and parqueadero_id = v_pq;
  if not found then
    raise exception 'Mensualidad no encontrada';
  end if;

  insert into public.avisos_mensualidad (parqueadero_id, mensualidad_id, periodo_hasta, medio, nota, usuario_id)
  values (v_pq, p_mensualidad_id, coalesce(p_periodo_hasta, v_fecha_fin), p_medio, nullif(trim(coalesce(p_nota, '')), ''), auth.uid());

  return jsonb_build_object('success', true);
end;
$$;

-- -----------------------------------------------------------------------------
-- 9. COMPROBANTES
-- -----------------------------------------------------------------------------
create or replace function public.crear_comprobante(
  p_origen text,
  p_origen_id uuid,
  p_cliente_nombre text default 'Consumidor final',
  p_cliente_documento text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_valor integer;
  v_existente record;
  v_consecutivo integer;
  v_id uuid;
  v_estado text;
begin
  if p_origen not in ('registro', 'pago_mensualidad') then
    raise exception 'Origen de comprobante inválido: %', p_origen;
  end if;

  if p_origen = 'registro' then
    select valor, estado into v_valor, v_estado from public.registros where id = p_origen_id and parqueadero_id = v_pq;
    if not found then
      raise exception 'Registro no encontrado';
    end if;
    if v_estado <> 'cerrado' then
      raise exception 'Solo se emite comprobante de un registro cerrado (no abierto ni anulado)';
    end if;
  else
    select valor into v_valor from public.pagos_mensualidad where id = p_origen_id and parqueadero_id = v_pq and anulado = false;
    if not found then
      raise exception 'Pago de mensualidad no encontrado o anulado';
    end if;
  end if;

  -- Consecutivo atómico por parqueadero
  perform pg_advisory_xact_lock(hashtext('comprobantes:' || v_pq::text));

  -- Un origen tiene un solo comprobante; volver a pedirlo devuelve el mismo
  select * into v_existente from public.comprobantes
  where parqueadero_id = v_pq and origen = p_origen and origen_id = p_origen_id
  order by consecutivo limit 1;
  if found then
    return jsonb_build_object('success', true, 'existente', true, 'comprobante', to_jsonb(v_existente),
      'comprobante_id', v_existente.id, 'consecutivo', v_existente.consecutivo, 'valor', v_existente.valor);
  end if;

  select coalesce(max(consecutivo), 0) + 1 into v_consecutivo from public.comprobantes where parqueadero_id = v_pq;

  insert into public.comprobantes (parqueadero_id, consecutivo, origen, origen_id, cliente_nombre, cliente_documento, valor, usuario_id)
  values (v_pq, v_consecutivo, p_origen, p_origen_id,
    coalesce(nullif(trim(coalesce(p_cliente_nombre, '')), ''), 'Consumidor final'),
    nullif(trim(coalesce(p_cliente_documento, '')), ''), v_valor, auth.uid())
  returning id into v_id;

  return jsonb_build_object('success', true, 'existente', false,
    'comprobante', (select to_jsonb(c) from public.comprobantes c where c.id = v_id),
    'comprobante_id', v_id, 'consecutivo', v_consecutivo, 'valor', v_valor);
end;
$$;

-- Detalle real para generar o re-descargar el PDF (HU-20/21/22)
create or replace function public.obtener_detalle_comprobante(p_comprobante_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_c record;
  v_detalle jsonb;
  v_anulado boolean := false;
begin
  select * into v_c from public.comprobantes where id = p_comprobante_id and parqueadero_id = v_pq;
  if not found then
    raise exception 'Comprobante no encontrado';
  end if;

  if v_c.origen = 'registro' then
    select jsonb_build_object(
      'tipo', 'hora',
      'placa', r.placa,
      'tipo_vehiculo', tv.nombre,
      'entrada_at', r.entrada_at,
      'salida_at', r.salida_at,
      'minutos', r.minutos,
      'tarifa', t.nombre,
      'metodo_pago', mp.nombre,
      'usuario', pr.nombre,
      'desglose', r.tarifa_snapshot->'desglose'),
      r.estado = 'anulado'
    into v_detalle, v_anulado
    from public.registros r
    left join public.tipos_vehiculo tv on tv.id = r.tipo_vehiculo_id
    left join public.tarifas t on t.id = r.tarifa_id
    left join public.metodos_pago mp on mp.id = r.metodo_pago_id
    left join public.profiles pr on pr.id = r.usuario_salida
    where r.id = v_c.origen_id;
  else
    select jsonb_build_object(
      'tipo', 'mensualidad',
      'placa', v.placa,
      'tipo_vehiculo', tv.nombre,
      'plan', pl.nombre,
      'periodo_desde', pg.periodo_desde,
      'periodo_hasta', pg.periodo_hasta,
      'metodo_pago', mp.nombre,
      'usuario', pr.nombre,
      'cliente', cl.nombre),
      pg.anulado
    into v_detalle, v_anulado
    from public.pagos_mensualidad pg
    join public.mensualidades m on m.id = pg.mensualidad_id
    join public.vehiculos v on v.id = m.vehiculo_id
    left join public.tipos_vehiculo tv on tv.id = v.tipo_vehiculo_id
    left join public.planes_mensuales pl on pl.id = m.plan_id
    left join public.clientes cl on cl.id = m.cliente_id
    left join public.metodos_pago mp on mp.id = pg.metodo_pago_id
    left join public.profiles pr on pr.id = pg.usuario_id
    where pg.id = v_c.origen_id;
  end if;

  return jsonb_build_object(
    'comprobante', to_jsonb(v_c) || jsonb_build_object('anulado', coalesce(v_anulado, false) or v_c.anulado),
    'detalle', v_detalle,
    'parqueadero', (select jsonb_build_object('nombre', nombre, 'nit', nit, 'direccion', direccion, 'telefono', telefono,
      'logo_url', logo_url, 'texto_pie_comprobante', texto_pie_comprobante, 'ancho_ticket_mm', ancho_ticket_mm,
      'zona_horaria', zona_horaria) from public.parqueaderos where id = v_pq)
  );
end;
$$;

create or replace function public.listar_comprobantes(
  p_desde date default null,
  p_hasta date default null,
  p_busqueda text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_zona text := public.zona_parqueadero(v_pq);
  v_busq text := nullif(upper(regexp_replace(trim(coalesce(p_busqueda, '')), '[^A-Za-z0-9]', '', 'g')), '');
begin
  perform public.requerir_admin();
  return coalesce((
    select jsonb_agg(to_jsonb(x) order by x.consecutivo desc)
    from (
      select c.id, c.consecutivo, c.origen, c.origen_id, c.cliente_nombre, c.cliente_documento, c.valor, c.created_at,
        coalesce(r.placa, v.placa) as placa,
        (c.anulado or coalesce(r.estado = 'anulado', false) or coalesce(pg.anulado, false)) as anulado
      from public.comprobantes c
      left join public.registros r on c.origen = 'registro' and r.id = c.origen_id
      left join public.pagos_mensualidad pg on c.origen = 'pago_mensualidad' and pg.id = c.origen_id
      left join public.mensualidades m on m.id = pg.mensualidad_id
      left join public.vehiculos v on v.id = m.vehiculo_id
      where c.parqueadero_id = v_pq
        and (p_desde is null or (c.created_at at time zone v_zona)::date >= p_desde)
        and (p_hasta is null or (c.created_at at time zone v_zona)::date <= p_hasta)
        and (v_busq is null or c.consecutivo::text = v_busq or coalesce(r.placa, v.placa) like '%' || v_busq || '%')
      order by c.consecutivo desc
      limit 500
    ) x), '[]'::jsonb);
end;
$$;

-- -----------------------------------------------------------------------------
-- 10. REPORTES (zona horaria del parqueadero, solo admin)
-- -----------------------------------------------------------------------------
create or replace function public.obtener_reporte_ingresos(
  p_fecha_desde date,
  p_fecha_hasta date
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_zona text := public.zona_parqueadero(v_pq);
  v_hora bigint;
  v_mens bigint;
begin
  perform public.requerir_admin();

  create temp table if not exists _rep_hora on commit drop as
    select r.* from public.registros r where false;
  truncate _rep_hora;
  insert into _rep_hora
    select r.* from public.registros r
    where r.parqueadero_id = v_pq and r.salida_at is not null
      and (r.salida_at at time zone v_zona)::date between p_fecha_desde and p_fecha_hasta;

  create temp table if not exists _rep_mens on commit drop as
    select pg.* from public.pagos_mensualidad pg where false;
  truncate _rep_mens;
  insert into _rep_mens
    select pg.* from public.pagos_mensualidad pg
    where pg.parqueadero_id = v_pq
      and (pg.created_at at time zone v_zona)::date between p_fecha_desde and p_fecha_hasta;

  select coalesce(sum(valor), 0) into v_hora from _rep_hora where estado = 'cerrado';
  select coalesce(sum(valor), 0) into v_mens from _rep_mens where anulado = false;

  return jsonb_build_object(
    'total_hora', v_hora,
    'total_mensualidades', v_mens,
    'gran_total', v_hora + v_mens,
    'por_dia', coalesce((
      select jsonb_agg(jsonb_build_object('fecha', d.fecha, 'hora', d.hora, 'mensualidades', d.mens, 'total', d.hora + d.mens) order by d.fecha)
      from (
        select fecha, sum(hora) as hora, sum(mens) as mens from (
          select (salida_at at time zone v_zona)::date as fecha, valor as hora, 0 as mens from _rep_hora where estado = 'cerrado'
          union all
          select (created_at at time zone v_zona)::date, 0, valor from _rep_mens where anulado = false
        ) u group by fecha
      ) d), '[]'::jsonb),
    'por_tipo', coalesce((
      select jsonb_agg(jsonb_build_object('tipo', tv.nombre, 'cantidad', x.cantidad, 'total', x.total) order by tv.orden)
      from (select tipo_vehiculo_id, count(*) as cantidad, sum(valor) as total from _rep_hora where estado = 'cerrado' group by tipo_vehiculo_id) x
      join public.tipos_vehiculo tv on tv.id = x.tipo_vehiculo_id), '[]'::jsonb),
    'por_metodo', coalesce((
      select jsonb_agg(jsonb_build_object('metodo', mp.nombre, 'es_efectivo', mp.es_efectivo,
        'hora', coalesce(h.total, 0), 'mensualidades', coalesce(m.total, 0), 'total', coalesce(h.total, 0) + coalesce(m.total, 0)) order by mp.orden)
      from public.metodos_pago mp
      left join (select metodo_pago_id, sum(valor) as total from _rep_hora where estado = 'cerrado' and valor > 0 group by metodo_pago_id) h on h.metodo_pago_id = mp.id
      left join (select metodo_pago_id, sum(valor) as total from _rep_mens where anulado = false group by metodo_pago_id) m on m.metodo_pago_id = mp.id
      where mp.parqueadero_id = v_pq and (h.total is not null or m.total is not null)), '[]'::jsonb),
    'por_origen', jsonb_build_array(
      jsonb_build_object('origen', 'Parqueo por hora', 'total', v_hora),
      jsonb_build_object('origen', 'Mensualidades', 'total', v_mens)),
    'anulados', coalesce((
      select jsonb_agg(a order by a->>'fecha')
      from (
        select jsonb_build_object('origen', 'registro', 'fecha', anulado_at, 'placa', placa, 'valor', valor, 'motivo', motivo_anulacion) as a
        from _rep_hora where estado = 'anulado'
        union all
        select jsonb_build_object('origen', 'pago_mensualidad', 'fecha', anulado_at, 'placa', null, 'valor', valor, 'motivo', motivo_anulacion)
        from _rep_mens where anulado = true
      ) z), '[]'::jsonb),
    'requieren_revision', (select count(*) from _rep_hora where requiere_revision),
    'conflictos_sync', (select count(*) from public.operaciones_sync where parqueadero_id = v_pq and resultado <> 'ok')
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 11. PERFIL, USUARIOS (HU-03) Y SUPERADMIN (HU-01, HU-05)
-- -----------------------------------------------------------------------------
create or replace function public.obtener_mi_perfil()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_perfil record;
  v_pq record;
begin
  select p.id, p.nombre, p.rol, p.activo, p.parqueadero_id into v_perfil
  from public.profiles p where p.id = auth.uid();

  if not found then
    return jsonb_build_object('encontrado', false, 'activo', false,
      'motivo', 'Tu usuario no tiene un perfil asignado. Contacta al administrador.');
  end if;

  if not v_perfil.activo then
    return jsonb_build_object('encontrado', true, 'activo', false,
      'motivo', 'Tu usuario se encuentra desactivado. Contacta al administrador.');
  end if;

  if v_perfil.rol = 'superadmin' then
    return jsonb_build_object('encontrado', true, 'activo', true, 'ahora', clock_timestamp(),
      'usuario', jsonb_build_object('id', v_perfil.id, 'nombre', v_perfil.nombre, 'rol', v_perfil.rol, 'parqueadero_id', null),
      'parqueadero', null);
  end if;

  select * into v_pq from public.parqueaderos where id = v_perfil.parqueadero_id;
  if not found then
    return jsonb_build_object('encontrado', true, 'activo', false,
      'motivo', 'Tu usuario no está asociado a un parqueadero.');
  end if;

  if v_pq.estado = 'suspendido' then
    return jsonb_build_object('encontrado', true, 'activo', false,
      'motivo', 'El parqueadero se encuentra suspendido. Contacta a soporte.');
  end if;

  return jsonb_build_object(
    'encontrado', true,
    'activo', true,
    'ahora', clock_timestamp(),
    'usuario', jsonb_build_object('id', v_perfil.id, 'nombre', v_perfil.nombre, 'rol', v_perfil.rol, 'parqueadero_id', v_perfil.parqueadero_id),
    'parqueadero', jsonb_build_object(
      'id', v_pq.id, 'nombre', v_pq.nombre, 'nit', v_pq.nit, 'direccion', v_pq.direccion, 'telefono', v_pq.telefono,
      'logo_url', v_pq.logo_url, 'estado', v_pq.estado, 'zona_horaria', v_pq.zona_horaria, 'moneda', v_pq.moneda,
      'dias_aviso_vencimiento', v_pq.dias_aviso_vencimiento, 'texto_pie_comprobante', v_pq.texto_pie_comprobante,
      'modo_ticket', v_pq.modo_ticket, 'ancho_ticket_mm', v_pq.ancho_ticket_mm)
  );
end;
$$;

create or replace function public.listar_usuarios_parqueadero()
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
begin
  perform public.requerir_admin();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', p.id, 'nombre', p.nombre, 'rol', p.rol, 'activo', p.activo, 'created_at', p.created_at,
      'email', u.email, 'ultimo_ingreso', u.last_sign_in_at, 'invitacion_pendiente', u.email_confirmed_at is null,
      'es_yo', p.id = auth.uid()) order by p.rol, p.nombre)
    from public.profiles p
    join auth.users u on u.id = p.id
    where p.parqueadero_id = v_pq), '[]'::jsonb);
end;
$$;

create or replace function public.actualizar_usuario(
  p_usuario_id uuid,
  p_nombre text default null,
  p_rol text default null,
  p_activo boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_obj record;
begin
  perform public.requerir_admin();

  select * into v_obj from public.profiles where id = p_usuario_id and parqueadero_id = v_pq for update;
  if not found then
    raise exception 'Usuario no encontrado en tu parqueadero';
  end if;
  if v_obj.rol = 'superadmin' then
    raise exception 'No se puede modificar un superadmin';
  end if;
  if p_rol is not null and p_rol not in ('admin', 'operador') then
    raise exception 'Rol inválido';
  end if;
  if p_usuario_id = auth.uid() and (p_activo = false or (p_rol is not null and p_rol <> v_obj.rol)) then
    raise exception 'No puedes desactivarte ni cambiar tu propio rol';
  end if;

  update public.profiles set
    nombre = coalesce(nullif(trim(coalesce(p_nombre, '')), ''), nombre),
    rol = coalesce(p_rol, rol),
    activo = coalesce(p_activo, activo)
  where id = p_usuario_id;

  return jsonb_build_object('success', true);
end;
$$;

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
  v_id uuid;
  v_carro uuid;
  v_moto uuid;
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

  insert into public.parqueaderos (nombre, nit, direccion, telefono, estado, modo_ticket)
  values (trim(p_nombre), trim(p_nit), nullif(trim(coalesce(p_direccion, '')), ''), nullif(trim(coalesce(p_telefono, '')), ''), 'activo', 'qr')
  returning id into v_id;

  -- Datos de ejemplo editables (HU-01): Carro y Moto, una tarifa por hora y "Efectivo"
  insert into public.tipos_vehiculo (parqueadero_id, nombre, icono, capacidad, orden)
  values (v_id, 'Carro', 'car', 20, 1) returning id into v_carro;
  insert into public.tipos_vehiculo (parqueadero_id, nombre, icono, capacidad, orden)
  values (v_id, 'Moto', 'bike', 20, 2) returning id into v_moto;

  insert into public.tarifas (parqueadero_id, tipo_vehiculo_id, nombre, modalidad, valor, es_predeterminada)
  values (v_id, v_carro, 'Por hora (ejemplo, revisar)', 'por_hora', 3000, true),
         (v_id, v_moto, 'Por hora (ejemplo, revisar)', 'por_hora', 1500, true);

  insert into public.metodos_pago (parqueadero_id, nombre, es_efectivo, orden)
  values (v_id, 'Efectivo', true, 1);

  return jsonb_build_object('success', true, 'parqueadero_id', v_id, 'mensaje', 'Parqueadero creado exitosamente');
end;
$$;

drop function if exists public.obtener_parqueaderos_superadmin();

create or replace function public.obtener_parqueaderos_superadmin()
returns table (
  id uuid,
  nombre text,
  nit text,
  direccion text,
  telefono text,
  estado text,
  created_at timestamptz,
  total_usuarios bigint,
  admin_email text,
  admin_nombre text,
  admin_invitacion_pendiente boolean,
  registros_ultimo_mes bigint,
  ultima_actividad timestamptz
)
language sql
stable
security definer
set search_path = public
as $$
  select
    pq.id, pq.nombre, pq.nit, pq.direccion, pq.telefono, pq.estado, pq.created_at,
    (select count(*) from public.profiles pr where pr.parqueadero_id = pq.id),
    adm.email::text, adm.nombre, adm.pendiente,
    (select count(*) from public.registros r where r.parqueadero_id = pq.id and r.entrada_at > now() - interval '30 days'),
    greatest(
      (select max(r.created_at) from public.registros r where r.parqueadero_id = pq.id),
      (select max(u.last_sign_in_at) from public.profiles pr join auth.users u on u.id = pr.id where pr.parqueadero_id = pq.id))
  from public.parqueaderos pq
  left join lateral (
    select u.email, pr.nombre, u.email_confirmed_at is null as pendiente
    from public.profiles pr join auth.users u on u.id = pr.id
    where pr.parqueadero_id = pq.id and pr.rol = 'admin'
    order by pr.created_at limit 1
  ) adm on true
  where public.es_superadmin()
  order by pq.created_at desc;
$$;

-- -----------------------------------------------------------------------------
-- 12. SINCRONIZACIÓN OFFLINE
-- -----------------------------------------------------------------------------
create or replace function public.sincronizar_operaciones(p_operaciones jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_op jsonb;
  v_id uuid;
  v_tipo text;
  v_payload jsonb;
  v_creada timestamptz;
  v_res text;
  v_detalle text;
  v_procesadas integer := 0;
  v_conflictos integer := 0;
  v_ignoradas integer := 0;
  v_resultados jsonb := '[]'::jsonb;
begin
  if jsonb_typeof(p_operaciones) <> 'array' then
    raise exception 'El payload debe ser un array de operaciones';
  end if;

  for v_op in select * from jsonb_array_elements(p_operaciones) loop
    v_res := 'ok';
    v_detalle := null;

    begin
      v_id := (v_op->>'id')::uuid;
      v_creada := coalesce((v_op->>'creada_en_dispositivo_at')::timestamptz, now());
    exception when others then
      v_resultados := v_resultados || jsonb_build_object('id', v_op->>'id', 'resultado', 'error', 'detalle', 'Identificador inválido');
      v_conflictos := v_conflictos + 1;
      continue;
    end;

    v_tipo := v_op->>'tipo';
    v_payload := v_op->'payload';

    if exists (select 1 from public.operaciones_sync where id = v_id) then
      v_ignoradas := v_ignoradas + 1;
      v_resultados := v_resultados || jsonb_build_object('id', v_id, 'resultado', 'ignorada');
      continue;
    end if;

    begin
      if v_tipo = 'entrada' then
        perform public.registrar_entrada(v_id, v_payload->>'placa', (v_payload->>'tipoVehiculoId')::uuid,
          (v_payload->>'tarifaId')::uuid, v_creada);
      elsif v_tipo = 'salida' then
        perform public.registrar_salida((v_payload->>'registroId')::uuid, (v_payload->>'metodoPagoId')::uuid,
          (v_payload->>'tarifaId')::uuid, (v_payload->>'valorCobrado')::integer,
          coalesce((v_payload->>'salidaAt')::timestamptz, v_creada));
      elsif v_tipo = 'pago_mensualidad' then
        perform public.registrar_pago_mensualidad((v_payload->>'mensualidadId')::uuid, (v_payload->>'metodoPagoId')::uuid,
          (v_payload->>'valor')::integer, (v_payload->>'desdeFecha')::date,
          coalesce((v_payload->>'reiniciar')::boolean, false), v_id);
      elsif v_tipo = 'aviso' then
        perform public.registrar_aviso_mensualidad((v_payload->>'mensualidadId')::uuid, v_payload->>'medio',
          v_payload->>'nota', (v_payload->>'periodoHasta')::date);
      else
        v_res := 'error';
        v_detalle := 'Tipo de operación no soportado: ' || coalesce(v_tipo, '(vacío)');
      end if;
    exception when others then
      v_res := 'conflicto';
      v_detalle := SQLERRM;
    end;

    if v_res <> 'ok' then
      v_conflictos := v_conflictos + 1;
    end if;

    insert into public.operaciones_sync (id, parqueadero_id, tipo, payload, dispositivo, usuario_id, creada_en_dispositivo_at, resultado, detalle)
    values (v_id, v_pq, coalesce(v_tipo, 'desconocido'), coalesce(v_payload, '{}'::jsonb), v_op->>'dispositivo', auth.uid(), v_creada, v_res, v_detalle);

    v_procesadas := v_procesadas + 1;
    v_resultados := v_resultados || jsonb_build_object('id', v_id, 'resultado', v_res, 'detalle', v_detalle);
  end loop;

  return jsonb_build_object('success', true, 'procesadas', v_procesadas, 'conflictos', v_conflictos,
    'ignoradas', v_ignoradas, 'resultados', v_resultados, 'ahora', clock_timestamp());
end;
$$;

-- -----------------------------------------------------------------------------
-- 13. REALTIME (ocupación, caja y mensualidades entre dispositivos)
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    foreach t in array array['registros', 'turnos_caja', 'mensualidades', 'pagos_mensualidad', 'avisos_mensualidad'] loop
      begin
        execute format('alter publication supabase_realtime add table public.%I', t);
      exception when duplicate_object then null;
      end;
    end loop;
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 14. PERMISOS: las RPC no se exponen a usuarios anónimos (salvo keep_alive)
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select p.oid::regprocedure as firma
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f' and p.proname <> 'keep_alive'
  loop
    execute format('revoke execute on function %s from public, anon', r.firma);
    execute format('grant execute on function %s to authenticated, service_role', r.firma);
  end loop;
end;
$$;

-- Bucket público de logos (HU-06): cada parqueadero sube su logo (PNG/JPG, máx. 1 MB)
-- a la carpeta logos/<parqueadero_id>/. Lectura pública para el PDF; escritura solo admin.
-- Protegido con "if exists" para que no falle en entornos sin el esquema storage.

do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('logos', 'logos', true, 1048576, array['image/png', 'image/jpeg'])
    on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/png', 'image/jpeg'];

    execute 'drop policy if exists "logos_lectura_publica" on storage.objects';
    execute 'drop policy if exists "logos_escritura_admin" on storage.objects';
    execute 'drop policy if exists "logos_actualizacion_admin" on storage.objects';

    execute $p$
      create policy "logos_lectura_publica" on storage.objects for select
      using (bucket_id = 'logos')
    $p$;

    execute $p$
      create policy "logos_escritura_admin" on storage.objects for insert to authenticated
      with check (
        bucket_id = 'logos'
        and (storage.foldername(name))[1] = public.mi_parqueadero_id()::text
        and public.mi_rol() = 'admin'
      )
    $p$;

    execute $p$
      create policy "logos_actualizacion_admin" on storage.objects for update to authenticated
      using (
        bucket_id = 'logos'
        and (storage.foldername(name))[1] = public.mi_parqueadero_id()::text
        and public.mi_rol() = 'admin'
      )
    $p$;
  end if;
end;
$$;

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

-- Reglas de entrada:
--   1. Toda entrada en línea exige un turno de caja abierto.
--   2. El tipo de vehículo debe tener una tarifa general activa.
--
-- Las entradas sin conexión que se sincronizan después (p_hora_dispositivo con
-- valor) se aceptan aunque ya no haya turno o tarifa: el vehículo ya está dentro
-- y rechazarlas lo dejaría sin registro. La app las bloquea antes de encolarlas
-- con la copia local del turno y de las tarifas.

create or replace function public.registrar_entrada(
  p_id uuid,
  p_placa text,
  p_tipo_vehiculo_id uuid,
  p_tarifa_id uuid default null,
  p_hora_dispositivo timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pq uuid := public.requerir_parqueadero();
  v_zona text := public.zona_parqueadero(v_pq);
  v_placa text;
  v_tipo record;
  v_vehiculo_id uuid;
  v_tarifa_id uuid := p_tarifa_id;
  v_existente record;
  v_registro_id uuid := coalesce(p_id, gen_random_uuid());
  v_turno_id uuid;
  v_hora timestamptz;
  v_origen text;
  v_ocupados integer;
  v_mens jsonb;
  v_es_mensual boolean := false;
  v_sincronizada boolean := p_hora_dispositivo is not null;
begin
  -- Idempotencia: reenviar la misma entrada no crea otra
  select * into v_existente from public.registros where id = v_registro_id;
  if found then
    if v_existente.parqueadero_id <> v_pq then
      raise exception 'Identificador de registro inválido';
    end if;
    return jsonb_build_object('success', true, 'ya_existia', true, 'registro_id', v_existente.id,
      'placa', v_existente.placa, 'entrada_at', v_existente.entrada_at, 'es_mensual', v_existente.es_mensual);
  end if;

  v_placa := upper(regexp_replace(trim(coalesce(p_placa, '')), '[^A-Za-z0-9]', '', 'g'));
  if length(v_placa) < 3 then
    raise exception 'Placa inválida: %', p_placa;
  end if;

  select * into v_tipo from public.tipos_vehiculo
  where id = p_tipo_vehiculo_id and parqueadero_id = v_pq and activo = true;
  if not found then
    raise exception 'Tipo de vehículo no válido o desactivado';
  end if;

  select id into v_turno_id from public.turnos_caja where parqueadero_id = v_pq and estado = 'abierto';
  if v_turno_id is null and not v_sincronizada then
    raise exception 'No hay un turno de caja abierto. Abre el turno en Caja para registrar entradas.';
  end if;

  select * into v_existente from public.registros
  where parqueadero_id = v_pq and placa = v_placa and estado = 'abierto';
  if found then
    raise exception 'Este vehículo ya está dentro desde las %',
      to_char(v_existente.entrada_at at time zone v_zona, 'HH24:MI');
  end if;

  if v_tarifa_id is not null and not exists (
    select 1 from public.tarifas
    where id = v_tarifa_id and parqueadero_id = v_pq and tipo_vehiculo_id = p_tipo_vehiculo_id and activa = true
  ) then
    if v_sincronizada then
      v_tarifa_id := null;
    else
      raise exception 'La tarifa elegida no corresponde al tipo de vehículo';
    end if;
  end if;

  if v_tarifa_id is null then
    select id into v_tarifa_id from public.tarifas
    where parqueadero_id = v_pq and tipo_vehiculo_id = p_tipo_vehiculo_id
      and activa = true and franja_inicio is null
    order by es_predeterminada desc, created_at
    limit 1;
  end if;

  if v_tarifa_id is null and not v_sincronizada then
    raise exception 'El tipo % no tiene una tarifa activa. Un administrador debe configurarla en Ajustes antes de registrar entradas.', v_tipo.nombre;
  end if;

  select id into v_vehiculo_id from public.vehiculos where parqueadero_id = v_pq and placa = v_placa;
  if not found then
    insert into public.vehiculos (parqueadero_id, placa, tipo_vehiculo_id)
    values (v_pq, v_placa, p_tipo_vehiculo_id)
    returning id into v_vehiculo_id;
  end if;

  v_mens := public.mensualidad_de_vehiculo(v_vehiculo_id);
  v_es_mensual := coalesce((v_mens->>'vigente')::boolean, false);

  -- En línea la hora la pone el servidor; solo las entradas sincronizadas traen hora del dispositivo
  if v_sincronizada then
    v_hora := least(p_hora_dispositivo, now());
    v_origen := 'dispositivo';
  else
    v_hora := now();
    v_origen := 'servidor';
  end if;

  select count(*) into v_ocupados from public.registros
  where parqueadero_id = v_pq and tipo_vehiculo_id = p_tipo_vehiculo_id and estado = 'abierto';

  insert into public.registros (
    id, parqueadero_id, placa, tipo_vehiculo_id, tarifa_id, vehiculo_id, entrada_at,
    es_mensual, turno_entrada_id, usuario_entrada, hora_origen, estado
  ) values (
    v_registro_id, v_pq, v_placa, p_tipo_vehiculo_id, v_tarifa_id, v_vehiculo_id, v_hora,
    v_es_mensual, v_turno_id, auth.uid(), v_origen, 'abierto'
  );

  return jsonb_build_object(
    'success', true,
    'registro_id', v_registro_id,
    'placa', v_placa,
    'entrada_at', v_hora,
    'hora_origen', v_origen,
    'tarifa_id', v_tarifa_id,
    'es_mensual', v_es_mensual,
    'mensualidad', v_mens,
    'sobrecupo', v_ocupados + 1 > v_tipo.capacidad,
    'ocupados', v_ocupados + 1,
    'capacidad', v_tipo.capacidad
  );
end;
$$;

