-- Bucket público de logos (HU-06): cada parqueadero sube su logo (PNG/JPG, máx. 1 MB)
-- a la carpeta logos/<parqueadero_id>/. Lectura pública para el PDF; escritura solo admin.
-- Protegido con "if exists" para que no falle en entornos sin el esquema storage.

do $$
begin
  if exists (select 1 from information_schema.schemata where schema_name = 'storage') then
    insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
    values ('logos', 'logos', true, 1048576, array['image/png', 'image/jpeg'])
    on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/png', 'image/jpeg'];

    execute 'drop policy if exists "logos_lectura_publica" on storage.objects';
    execute 'drop policy if exists "logos_escritura_admin" on storage.objects';
    execute 'drop policy if exists "logos_actualizacion_admin" on storage.objects';

    execute $p$
      create policy "logos_lectura_publica" on storage.objects for select
      using (bucket_id = 'logos')
    $p$;

    execute $p$
      create policy "logos_escritura_admin" on storage.objects for insert to authenticated
      with check (
        bucket_id = 'logos'
        and (storage.foldername(name))[1] = public.mi_parqueadero_id()::text
        and public.mi_rol() = 'admin'
      )
    $p$;

    execute $p$
      create policy "logos_actualizacion_admin" on storage.objects for update to authenticated
      using (
        bucket_id = 'logos'
        and (storage.foldername(name))[1] = public.mi_parqueadero_id()::text
        and public.mi_rol() = 'admin'
      )
    $p$;
  end if;
end;
$$;
