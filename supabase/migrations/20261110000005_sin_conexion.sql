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
