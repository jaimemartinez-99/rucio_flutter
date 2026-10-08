import argparse
from pathlib import Path
import shutil
import subprocess
import sys
import time


def main():
    sys.stdout.reconfigure(encoding='utf-8')
    parser = argparse.ArgumentParser()
    parser.add_argument('--device', required=True)
    parser.add_argument('--adb', required=True)
    parser.add_argument('--screen-off', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    build = root / 'build'
    build.mkdir(exist_ok=True)
    driver = build / 'android_audio_driver.dart'
    driver.write_text("import 'package:integration_test/integration_test_driver.dart';\nFuture<void> main() => integrationDriver();\n", encoding='utf-8')
    log = build / 'android_audio_integration.log'
    flutter = shutil.which('flutter')
    if not flutter:
        raise RuntimeError('Flutter no está en PATH.')

    def adb(*command):
        result = subprocess.run([args.adb, '-s', args.device, *command], capture_output=True, text=True, encoding='utf-8', errors='replace')
        if result.returncode:
            raise RuntimeError(result.stderr or result.stdout)
        return result.stdout

    package = 'com.rucio.rucio_flutter.audio_test'

    def media(key):
        adb('shell', 'cmd', 'media_session', 'dispatch', key)

    def foreground():
        if args.screen_off:
            adb('shell', 'input', 'keyevent', '224')
            adb('shell', 'wm', 'dismiss-keyguard')
        adb('shell', 'am', 'start', '-n', f'{package}/com.rucio.rucio_flutter.MainActivity')

    actions = [
        ('AUDIORUCIO_TEST_READY', lambda: (adb('shell', 'input', 'keyevent', '3'), adb('shell', 'input', 'keyevent', '223') if args.screen_off else None)),
        ('AUDIORUCIO_AUTO_ADVANCED', lambda: media('pause')),
        ('AUDIORUCIO_PAUSED', lambda: media('rewind')),
        ('AUDIORUCIO_REWOUND', lambda: media('fast-forward')),
        ('AUDIORUCIO_FORWARDED', lambda: media('play')),
        ('AUDIORUCIO_RESUMED', lambda: media('stop')),
        ('AUDIORUCIO_STOPPED', foreground),
    ]
    with log.open('w', encoding='utf-8') as output:
        process = subprocess.Popen([flutter, 'drive', '--profile', '-d', args.device, '--target', 'integration_test/android_audio_test.dart', '--driver', str(driver), '--dart-define-from-file=.env', '--android-project-arg=audiorucioIntegrationTest=true', '--keep-app-running'], cwd=root, stdout=output, stderr=subprocess.STDOUT)
        next_action = 0
        deadline = time.monotonic() + 1200
        try:
            while process.poll() is None:
                contents = log.read_text(encoding='utf-8', errors='replace')
                while next_action < len(actions) and actions[next_action][0] in contents:
                    marker, action = actions[next_action]
                    print(marker, flush=True)
                    action()
                    next_action += 1
                if time.monotonic() > deadline:
                    process.terminate()
                    raise TimeoutError(f'La prueba no terminó. Revisa {log}')
                time.sleep(0.25)
        finally:
            if process.poll() is None:
                process.terminate()
            adb('shell', 'am', 'force-stop', package)
            if adb('shell', 'pm', 'path', package).strip():
                adb('uninstall', package)
            if args.screen_off:
                adb('shell', 'input', 'keyevent', '224')
    result = log.read_text(encoding='utf-8', errors='replace')
    print('\n'.join(result.splitlines()[-25:]))
    if process.returncode or next_action != len(actions):
        raise SystemExit(process.returncode or 1)


if __name__ == '__main__':
    main()
