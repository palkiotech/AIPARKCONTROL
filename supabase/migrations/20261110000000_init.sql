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
