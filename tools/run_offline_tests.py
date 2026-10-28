"""Run bundled tests with temporary HOME and macOS network/process restrictions."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent


def main():
    sandbox = Path('/usr/bin/sandbox-exec')
    if sys.platform != 'darwin' or not sandbox.is_file():
        print('This runner requires macOS sandbox-exec for offline isolation.', file=sys.stderr)
        return 2
    with tempfile.TemporaryDirectory(prefix='hd2fx-offline-') as folder:
        temp = Path(folder).resolve()
        home = temp/'home'
        home.mkdir()
        env = dict(os.environ, HOME=str(home), TMPDIR=str(temp)+'/',
                   HD2FX_SETTINGS_FILE=str(home/'settings.json'),
                   PYTHONDONTWRITEBYTECODE='1', PYTHONNOUSERSITE='1', NO_COLOR='1')
        # Tests mock native operations. Restrict the entire process tree too.
        policy = '''(version 1)
(allow default)
(deny network*)
(deny process-exec (literal "/usr/bin/ssh") (literal "/usr/bin/open")
 (literal "/usr/bin/defaults") (literal "/usr/sbin/networksetup")
 (literal "/usr/bin/security") (literal "/usr/bin/sudo")
 (literal "/usr/bin/curl"))
'''
        result = subprocess.run([str(sandbox), '-p', policy, sys.executable,
                                 '-m', 'unittest', 'discover', '-s',
                                 'launcher-20261026', '-p', 'test_*.py', '-v'],
                                cwd=ROOT, env=env)
        return result.returncode


if __name__ == '__main__':
    sys.exit(main())
