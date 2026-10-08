import hashlib
import json
import shutil
import sys

from publish_android_release import BUCKET, PROJECT, ROOT, command, configuration, request


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    cli = shutil.which('supabase')
    keys = json.loads(command([cli, 'projects', 'api-keys', '--project-ref', PROJECT, '--output', 'json']))
    key = next(item['api_key'] for item in keys if item['name'] == 'service_role')
    bucket = json.loads(request(key, f'bucket/{BUCKET}'))
    if bucket['public'] or bucket['file_size_limit'] != 52428800:
        raise RuntimeError('Configuración del bucket incorrecta.')
    for user in configuration():
        release = json.loads(request(key, f'object/{BUCKET}/{user}/android/latest.json'))
        for artifact in release['artifacts'].values():
            data = request(key, f'object/{BUCKET}/{user}/{artifact["path"]}')
            if len(data) != artifact['bytes'] or hashlib.sha256(data).hexdigest() != artifact['sha256']:
                raise RuntimeError('Un APK publicado no coincide con el manifiesto.')
        claims = json.dumps({'sub': user, 'role': 'authenticated'})
        sql = f"""
begin;
set local role authenticated;
select set_config('request.jwt.claims', '{claims}', true);
do $$
declare affected integer;
begin
  if (select count(*) from storage.objects where bucket_id = '{BUCKET}' and name like '{user}/%') < 5 then
    raise exception 'El usuario no puede leer sus actualizaciones';
  end if;
  if exists (select 1 from storage.objects where bucket_id = '{BUCKET}' and name not like '{user}/%') then
    raise exception 'El usuario puede leer otro directorio';
  end if;
  begin
    insert into storage.objects (bucket_id, name) values ('{BUCKET}', '{user}/forbidden-test');
    raise exception 'El usuario puede publicar archivos';
  exception when insufficient_privilege then null;
  end;
  update storage.objects set name = name where bucket_id = '{BUCKET}';
  get diagnostics affected = row_count;
  if affected <> 0 then raise exception 'El usuario puede modificar archivos'; end if;
  begin
    delete from storage.objects where bucket_id = '{BUCKET}';
    get diagnostics affected = row_count;
    if affected <> 0 then raise exception 'El usuario puede eliminar archivos'; end if;
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}}', true);
do $$ begin
  if exists (select 1 from storage.objects where bucket_id = '{BUCKET}') then
    raise exception 'Otra cuenta puede leer archivos privados';
  end if;
end $$;
reset role;
set local role anon;
do $$ begin
  if exists (select 1 from storage.objects where bucket_id = '{BUCKET}') then
    raise exception 'Una sesión anónima puede leer archivos privados';
  end if;
end $$;
rollback;
"""
        sql_path = ROOT / 'build/verify_android_updates.sql'
        sql_path.write_text(sql, encoding='utf-8')
        try:
            command([cli, 'db', 'query', '--linked', '--project-ref', PROJECT, '--file', str(sql_path)])
        finally:
            sql_path.unlink(missing_ok=True)
        print(f'Rucio {release["version"]}: APK descargados y verificados; acceso privado y escritura bloqueada comprobados.')


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'La verificación falló: {error}', file=sys.stderr)
        raise SystemExit(1)
