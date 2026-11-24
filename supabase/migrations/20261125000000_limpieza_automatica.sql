-- Limpieza automática para ahorrar espacio en el plan gratuito.
--
-- keep_alive ya lo llama el cron del Worker de Cloudflare cada 3 días. Ahora
-- además borra de operaciones_sync las operaciones sincronizadas sin problema
-- con más de 90 días: solo sirven de bitácora de idempotencia, y una operación
-- tan vieja no se reenvía. Los conflictos y errores se conservan para revisarlos
-- en Reportes.

create or replace function public.keep_alive()
returns int
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.operaciones_sync
  where resultado = 'ok' and procesada_at < now() - interval '90 days';
  return 1;
end;
$$;

grant execute on function public.keep_alive() to anon, authenticated, service_role;

create index if not exists operaciones_sync_limpieza_idx
  on public.operaciones_sync (procesada_at)
  where resultado = 'ok';
