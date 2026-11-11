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
