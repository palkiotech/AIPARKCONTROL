-- Snapshot de tarifa compacto en registros.tarifa_snapshot.
--
-- Antes se guardaba la fila completa de cada tarifa (id, created_at,
-- parqueadero_id, tipo_vehiculo_id, es_predeterminada, activa, nulos...): unos
-- 600 B por salida, el 70 % de la fila. Ahora se guardan solo los parámetros que
-- definen el cobro, más el desglose:
--
--   { "general":  { nombre, modalidad, valor, minutos_gracia, minutos_fraccion, tope_por_24h },
--     "nocturna": { id, nombre, modalidad, valor, ..., franja_inicio, franja_fin },
--     "desglose": [ { tipo, minutos, valor } ] }
--
-- No se pierde información de auditoría:
--   - el id de la tarifa general ya está en registros.tarifa_id;
--   - la nocturna conserva su id;
--   - las claves nulas se omiten.
-- El único lector del snapshot es obtener_detalle_comprobante, y solo lee 'desglose'.

create or replace function public.tarifa_compacta(p_tarifa jsonb, p_con_id boolean default false)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case
    when p_tarifa is null or jsonb_typeof(p_tarifa) <> 'object' then null
    else jsonb_strip_nulls(jsonb_build_object(
      'id', case when p_con_id then p_tarifa->'id' end,
      'nombre', p_tarifa->'nombre',
      'modalidad', p_tarifa->'modalidad',
      'valor', p_tarifa->'valor',
      'minutos_gracia', p_tarifa->'minutos_gracia',
      'minutos_fraccion', p_tarifa->'minutos_fraccion',
      'tope_por_24h', p_tarifa->'tope_por_24h',
      'franja_inicio', p_tarifa->'franja_inicio',
      'franja_fin', p_tarifa->'franja_fin'))
  end
$$;

create or replace function public.compactar_snapshot_tarifa(p_snapshot jsonb)
returns jsonb
language sql
immutable
set search_path = public
as $$
  select case
    when p_snapshot is null or jsonb_typeof(p_snapshot) <> 'object' then p_snapshot
    else jsonb_strip_nulls(jsonb_build_object(
      'general', public.tarifa_compacta(p_snapshot->'general'),
      'nocturna', public.tarifa_compacta(p_snapshot->'nocturna', true),
      'desglose', p_snapshot->'desglose'))
  end
$$;

revoke execute on function public.tarifa_compacta(jsonb, boolean) from public, anon;
revoke execute on function public.compactar_snapshot_tarifa(jsonb) from public, anon;

-- registrar_salida: igual que en 20261111000000_saneamiento.sql, salvo el
-- snapshot, que ahora se guarda compacto.
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
    tarifa_snapshot = public.compactar_snapshot_tarifa(
      (v_cobro->'snapshot') || jsonb_build_object('desglose', v_cobro->'desglose')),
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

-- Compactar los registros ya cerrados (no cambia valores, desglose ni fechas)
update public.registros
set tarifa_snapshot = public.compactar_snapshot_tarifa(tarifa_snapshot)
where tarifa_snapshot is not null
  and tarifa_snapshot is distinct from public.compactar_snapshot_tarifa(tarifa_snapshot);
