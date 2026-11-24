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
