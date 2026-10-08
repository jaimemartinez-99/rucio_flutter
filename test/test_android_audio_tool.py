import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


tool_path = Path(__file__).resolve().parents[1] / 'tool' / 'test_android_audio.py'
spec = importlib.util.spec_from_file_location('android_audio_tool', tool_path)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)


class AndroidAudioToolTest(unittest.TestCase):
    def test_only_the_isolated_test_package_is_removed(self):
        markers = [
            'AUDIORUCIO_TEST_READY', 'AUDIORUCIO_AUTO_ADVANCED',
            'AUDIORUCIO_PAUSED', 'AUDIORUCIO_REWOUND',
            'AUDIORUCIO_FORWARDED', 'AUDIORUCIO_RESUMED',
            'AUDIORUCIO_STOPPED',
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            commands = []
            poll_results = iter([None, 0, 0])

            class Process:
                returncode = 0

                def poll(self):
                    return next(poll_results)

                def terminate(self):
                    raise AssertionError('A completed test should not be terminated.')

            def start(command, **kwargs):
                commands.append(command)
                kwargs['stdout'].write('\n'.join(markers))
                kwargs['stdout'].flush()
                return Process()

            def run(command, **kwargs):
                commands.append(command)
                output = 'package:fixture/base.apk' if 'path' in command else ''
                return subprocess.CompletedProcess(command, 0, output, '')

            with (
                patch.object(tool, '__file__', str(root / 'tool' / 'test_android_audio.py')),
                patch.object(tool.sys, 'argv', ['test', '--device', 'fixture', '--adb', 'adb']),
                patch.object(tool.shutil, 'which', return_value='flutter'),
                patch.object(tool.subprocess, 'Popen', side_effect=start),
                patch.object(tool.subprocess, 'run', side_effect=run),
                patch.object(tool.time, 'sleep'),
                patch('builtins.print'),
            ):
                tool.main()

            flutter_command = commands[0]
            self.assertIn('--keep-app-running', flutter_command)
            self.assertIn('--android-project-arg=audiorucioIntegrationTest=true', flutter_command)
            removed = [command[-1] for command in commands if 'uninstall' in command]
            self.assertEqual(removed, ['com.rucio.rucio_flutter.audio_test'])
            stopped = [command[-1] for command in commands if 'force-stop' in command]
            self.assertEqual(stopped, ['com.rucio.rucio_flutter.audio_test'])
            activity = [command[-1] for command in commands if 'start' in command]
            self.assertEqual(activity, ['com.rucio.rucio_flutter.audio_test/com.rucio.rucio_flutter.MainActivity'])


if __name__ == '__main__':
    unittest.main()
