import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
PROJECT = 'dmxkbaezodourxuspnyq'
PACKAGE = 'com.rucio.rucio_flutter'
BUCKET = 'rucio-updates'
ABIS = {'arm64-v8a': 'arm64-v8a', 'armeabi-v7a': 'armeabi-v7a', 'x86_64': 'x86_64'}


def command(args):
    environment = os.environ.copy()
    jdk = Path(environment['LOCALAPPDATA']) / 'Android/jdk17/jdk-17.0.20.1+1'
    if jdk.exists():
        environment['JAVA_HOME'] = str(jdk)
    completed = subprocess.run(args, cwd=ROOT, env=environment, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if completed.returncode:
        raise RuntimeError(f'Falló {Path(args[0]).name}. Código {completed.returncode}.')
    return completed.stdout


def configuration():
    path = Path.home() / '.rucio' / 'updates.json'
    if path.exists():
        config = json.loads(path.read_text(encoding='utf-8'))
    else:
        preferences = Path(os.environ.get('APPDATA', '')) / 'com.rucio/rucio_flutter/shared_preferences.json'
        values = json.loads(preferences.read_text(encoding='utf-8'))
        session = json.loads(values[f'flutter.sb-{PROJECT}-auth-token'])
        config = {'userIds': [session['user']['id']]}
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(config, indent=2), encoding='utf-8')
    users = config['userIds']
    if not users or any(not re.fullmatch(r'[0-9a-f-]{36}', user) for user in users):
        raise RuntimeError('Configura los usuarios autorizados en ~/.rucio/updates.json.')
    return users


def request(key, endpoint, data=None, content_type='application/json', upsert=False):
    headers = {'apikey': key, 'Authorization': f'Bearer {key}'}
    if data is not None:
        headers.update({'Content-Type': content_type, 'x-upsert': str(upsert).lower(), 'Cache-Control': 'max-age=0'})
    req = Request(f'https://{PROJECT}.supabase.co/storage/v1/{endpoint}', data=data, headers=headers)
    try:
        with urlopen(req, timeout=300) as response:
            return response.read()
    except HTTPError as error:
        raise RuntimeError(f'Supabase devolvió HTTP {error.code} en la operación de publicación.') from None


def immutable_upload(key, path, data, content_type='application/json'):
    parent, name = path.rsplit('/', 1)
    listing = json.loads(request(key, f'object/list/{BUCKET}', json.dumps({'prefix': parent, 'search': name}).encode()))
    if any(item['name'] == name for item in listing):
        existing = request(key, f'object/{BUCKET}/{path}')
        if hashlib.sha256(existing).digest() != hashlib.sha256(data).digest():
            raise RuntimeError('Ya existe un archivo diferente para esta versión. Incrementa la versión.')
        return
    request(key, f'object/{BUCKET}/{path}', data, content_type)


def manifest(version, build, notes, certificate, artifacts):
    return {
        'schema': 1, 'packageId': PACKAGE, 'version': version, 'buildNumber': build,
        'notes': notes, 'certificateSha256': certificate,
        'publishedAt': datetime.now(timezone.utc).isoformat(), 'artifacts': artifacts,
    }


def inspect_apk(path, abi, version, build, certificate, tools):
    badging = command([str(tools / 'aapt2.exe'), 'dump', 'badging', str(path)])
    match = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
    if not match or match.groups() != (PACKAGE, str(build), version):
        raise RuntimeError(f'El APK {abi} no tiene el identificador o la versión esperados.')
    signature = command([str(tools / 'apksigner.bat'), 'verify', '--print-certs', str(path)])
    if f'certificate SHA-256 digest: {certificate}' not in signature:
        raise RuntimeError(f'La firma de {abi} no coincide con la app instalada.')
    with ZipFile(path) as archive:
        native_abis = {name.split('/')[1] for name in archive.namelist() if name.startswith('lib/') and name.endswith('.so')}
    if native_abis != {abi} or path.stat().st_size > 50 * 1024 * 1024:
        raise RuntimeError(f'El APK {abi} no está dividido correctamente o supera 50 MB.')
    return {'path': f'android/{build}/rucio-{abi}.apk', 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--notes-file', type=Path, required=True)
    parser.add_argument('--publish', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    text = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    version, build_text = re.search(r'^version: (\d+\.\d+\.\d+)\+(\d+)$', text, re.M).groups()
    build = int(build_text)
    notes = args.notes_file.read_text(encoding='utf-8').strip()
    if not notes or len(notes) > 10000:
        raise RuntimeError('Las notas de versión no son válidas.')
    command(['powershell.exe', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(ROOT / 'tool/prepare_android_signing.ps1')])
    certificate = (ROOT / 'android/release-certificate.sha256').read_text(encoding='utf-8-sig').strip()
    if not args.skip_build:
        print(f'Compilando Rucio {version} ({build})…', flush=True)
        flutter = shutil.which('flutter')
        result = subprocess.run([flutter, 'build', 'apk', '--release', '--split-per-abi', '--target-platform',
                                 'android-arm,android-arm64,android-x64', '--dart-define-from-file=.env'], cwd=ROOT)
        if result.returncode:
            raise RuntimeError('La compilación de Android ha fallado.')
    tools = Path(os.environ['LOCALAPPDATA']) / 'Android/sdk/build-tools/36.0.0'
    artifacts = {}
    apks = {}
    for abi in ABIS:
        apk = ROOT / f'build/app/outputs/flutter-apk/app-{abi}-release.apk'
        artifacts[abi] = inspect_apk(apk, abi, version, build, certificate, tools)
        apks[abi] = apk
    release = manifest(version, build, notes, certificate, artifacts)
    output = ROOT / f'build/releases/{build}'
    output.mkdir(parents=True, exist_ok=True)
    for abi, apk in apks.items():
        destination = output / f'rucio-{version}-{abi}.apk'
        shutil.copy2(apk, destination)
        apks[abi] = destination
    payload = json.dumps(release, ensure_ascii=False, indent=2).encode('utf-8')
    (output / 'release.json').write_bytes(payload)
    print(f'APK verificados: {", ".join(artifacts)}', flush=True)
    if not args.publish:
        print('Preparado para publicar. Añade --publish para distribuir esta versión.')
        return
    users = configuration()
    cli = shutil.which('supabase')
    command([cli, 'db', 'query', '--linked', '--project-ref', PROJECT, '--file', str(ROOT / 'tool/android_updates_storage.sql')])
    keys = json.loads(command([cli, 'projects', 'api-keys', '--project-ref', PROJECT, '--output', 'json']))
    key = next(item['api_key'] for item in keys if item['name'] == 'service_role')
    bucket = json.loads(request(key, f'bucket/{BUCKET}'))
    if bucket['public']:
        raise RuntimeError('El bucket de actualizaciones debe ser privado.')
    for user in users:
        current = request(key, f'object/list/{BUCKET}', json.dumps({'prefix': f'{user}/android/'}).encode())
        if any(item['name'] == 'latest.json' for item in json.loads(current)):
            latest = json.loads(request(key, f'object/{BUCKET}/{user}/android/latest.json'))
            if latest['buildNumber'] >= build:
                raise RuntimeError('La versión publicada ya es igual o posterior. Incrementa la versión antes de publicar.')
        for abi, artifact in artifacts.items():
            immutable_upload(key, f'{user}/{artifact["path"]}', apks[abi].read_bytes(), 'application/vnd.android.package-archive')
        request(key, f'object/{BUCKET}/{user}/android/{build}/release.json', payload, upsert=True)
        request(key, f'object/{BUCKET}/{user}/android/latest.json', payload, upsert=True)
    print(f'Rucio {version} publicado para {len(users)} usuario(s).', flush=True)


if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print(f'No se pudo publicar: {error}', file=sys.stderr)
        raise SystemExit(1)
