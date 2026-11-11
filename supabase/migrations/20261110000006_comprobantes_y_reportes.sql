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
