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
