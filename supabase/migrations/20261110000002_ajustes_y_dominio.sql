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
