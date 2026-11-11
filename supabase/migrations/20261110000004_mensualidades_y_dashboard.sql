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
