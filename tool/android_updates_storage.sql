insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('rucio-updates', 'rucio-updates', false, 52428800,
        array['application/vnd.android.package-archive', 'application/json'])
on conflict (id) do nothing;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects' and policyname = 'rucio_updates_read') then
    create policy rucio_updates_read on storage.objects for select to authenticated
      using (bucket_id = 'rucio-updates' and (storage.foldername(name))[1] = (select auth.uid())::text);
    create policy rucio_updates_read_scope on storage.objects as restrictive for select to authenticated
      using (bucket_id <> 'rucio-updates' or (storage.foldername(name))[1] = (select auth.uid())::text);
    create policy rucio_updates_no_anon on storage.objects as restrictive for select to anon
      using (bucket_id <> 'rucio-updates');
    create policy rucio_updates_no_insert on storage.objects as restrictive for insert to authenticated, anon
      with check (bucket_id <> 'rucio-updates');
    create policy rucio_updates_no_update on storage.objects as restrictive for update to authenticated, anon
      using (bucket_id <> 'rucio-updates') with check (bucket_id <> 'rucio-updates');
    create policy rucio_updates_no_delete on storage.objects as restrictive for delete to authenticated, anon
      using (bucket_id <> 'rucio-updates');
  end if;
end $$;
