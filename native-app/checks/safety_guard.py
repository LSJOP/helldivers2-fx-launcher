"""OS/Python audit events prove the adapter does not touch protected boundaries."""
import importlib.util
import json
from pathlib import Path
import sys

app = Path(__file__).resolve().parents[1]
blocked = ('subprocess.Popen', 'os.system', 'os.posix_spawn', 'os.exec', 'socket.connect', 'socket.bind',
           'os.mkdir', 'os.remove', 'os.rename', 'os.rmdir', 'os.chmod', 'os.chown')

def audit(event, args):
    if any(event.startswith(value) for value in blocked):
        raise AssertionError('Forbidden side effect: ' + event)
    if event == 'open':
        path, mode, flags = args
        if isinstance(path, (str, bytes)) and any(value in str(path) for value in ('settings.json', 'runtime-paths.json', '/.ssh/', 'Keychains')):
            raise AssertionError('Protected configuration access')
        if (isinstance(mode, str) and any(c in mode for c in 'wax+')) or (isinstance(flags, int) and flags & 3):
            raise AssertionError('Write access forbidden')

sys.addaudithook(audit)
spec = importlib.util.spec_from_file_location('native_safety_adapter', app / 'bridge/core_adapter.py')
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
adapter = module.CoreAdapter(app / 'CoreSnapshot/native-app-core-snapshot', [app / 'checks/nonexistent-apps'])
for method in ('launcher_version', 'system_info', 'environment', 'dependency_info', 'fx_versions'):
    value = getattr(adapter, method)()
    assert isinstance(value, dict)
target = adapter.launch_target(str(app / 'checks/nonexistent-runtime'))
assert target['launch'] == 'unverified' and not target['fx_executable_present']
print(json.dumps({'result': 'PASS', 'guard': 'imports and all five adapter operations',
                  'writes': 'denied', 'process_execution': 'denied', 'network': 'denied',
                  'settings_ssh_keychain_access': 'denied'}))
