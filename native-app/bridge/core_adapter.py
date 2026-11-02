"""Narrow read-only reuse of current Python Core. Never imports entrypoints."""
import importlib.util
import itertools
import os
from pathlib import Path
import platform
import shutil
import stat
import sys

CORE_NAMES = ('launcher_version', 'dependencies', 'dependency_discovery', 'fx_versions')


def load_module(root, name):
    if name not in CORE_NAMES:
        raise ValueError('Core module is not allowlisted')
    spec = importlib.util.spec_from_file_location('native_readonly_' + name,
                                                root / 'launcher-20261026' / (name + '.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class CoreAdapter:
    def __init__(self, root, app_dirs=None):
        self.root = Path(root)
        self.version = load_module(self.root, 'launcher_version')
        self.dependencies = load_module(self.root, 'dependencies')
        self.discovery = load_module(self.root, 'dependency_discovery')
        self.fx = load_module(self.root, 'fx_versions')
        self.app_dirs = list(app_dirs) if app_dirs is not None else [Path('/Applications'), Path.home() / 'Applications']

    def launcher_version(self):
        return {'version': self.version.get_version(), 'source': 'bundled_core_snapshot',
                'ui_version': 'Native Phase 1', 'terminal_ui': '2.1'}

    def system_info(self):
        return {'os': platform.system(), 'os_release': platform.release(),
                'os_version': platform.mac_ver()[0] or 'unknown',
                'arch': platform.machine(), 'python': platform.python_version()}

    def environment(self):
        return {'status': 'unverified', 'scope': 'host_metadata_only',
                'checks': [{'name': key, 'state': 'unverified'} for key in
                           ('FX runtime', 'gvproxy runtime', 'SSH connection', 'Guest', 'Steam', 'FEX', 'Proton-JE', 'EAC', 'Multiplayer')]}

    def dependency_info(self):
        # Never call inspect_runtime or node_state: both can execute Node.
        # Fixed file presence means only file presence, never connection/runtime readiness.
        items = [{'name': 'Python', 'version': platform.python_version(), 'state': 'running_bridge'}]
        for name, executable in [('Node.js', 'node'), ('OpenSSH', 'ssh')]:
            candidate = shutil.which(executable)
            if not candidate and name == 'Node.js':
                candidate = next((p for p in ('/opt/homebrew/bin/node', '/usr/local/bin/node') if Path(p).is_file()), None)
            state = self.dependencies.file_state(candidate, executable=True) if candidate else 'missing'
            items.append({'name': name, 'version': 'unknown', 'state': 'file_present_unverified' if state == 'ready' else state})
        items.append({'name': 'Game components', 'version': 'unknown', 'state': 'unverified'})
        return {'items': items, 'scope': 'file_presence_only_no_binary_execution'}

    def fx_versions(self):
        candidates = []
        seen = set()
        incomplete = False
        issues = []
        for directory in self.app_dirs[:2]:
            try:
                # Bound enumeration itself, not only the number of matching apps.
                with os.scandir(directory) as entries:
                    children = list(itertools.islice(entries, 65))
                incomplete |= len(children) > 64
                for entry in children[:64]:
                    app = Path(entry.path)
                    if app.suffix.casefold() != '.app' or app.is_symlink():
                        continue
                    executable = app / 'Contents/MacOS/steamac-vm'
                    try:
                        info = executable.lstat()
                    except FileNotFoundError:
                        continue
                    if not stat.S_ISREG(info.st_mode) or any(p.is_symlink() for p in (app / 'Contents', app / 'Contents/MacOS')):
                        continue
                    identity = (info.st_dev, info.st_ino)
                    if identity in seen:
                        continue
                    seen.add(identity)
                    details = self.discovery.bundle_details(executable)
                    facts = self.fx.facts(dict(details, exists=True, regular_file=True))
                    candidates.append({'version': facts['version'] or 'unknown',
                                       'structure': 'metadata_valid' if facts['structure'] is True else 'unverified',
                                       'launch': facts['launch'], 'eac': facts['eac'], 'multiplayer': facts['multiplayer'],
                                       'location': '/Applications' if directory == Path('/Applications') else '~/Applications',
                                       'path': str(app),
                                       'name': 'FX candidate ' + str(len(candidates) + 1)})
            except FileNotFoundError:
                continue
            except OSError:
                incomplete = True
                issues.append('DIRECTORY_UNAVAILABLE')
        return {'candidates': candidates, 'scan_incomplete': incomplete, 'issues': issues,
                'scope': 'two_shallow_application_directories_metadata_only',
                'compatibility': 'unverified', 'runtime_selection': 'not_read'}
