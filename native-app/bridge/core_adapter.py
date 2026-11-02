"""Narrow read-only reuse of current Python Core. Never imports entrypoints."""
import importlib.util
import hashlib
import itertools
import os
from pathlib import Path
import platform
import plistlib
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

    def launch_target(self, selected, selected_fx=None):
        """Bounded file metadata only; never imports a launcher or runs a binary."""
        if not isinstance(selected, str) or not selected or len(selected) > 4096 or '\x00' in selected:
            raise ValueError('Invalid selected target')
        root = Path(selected).expanduser().resolve()
        archive = self.root.parent / 'legacy'
        if not archive.is_dir():
            archive = self.root.parent
        required = ['launcher-20261026/steam-cdp.mjs', 'tools/check_node.cjs',
                    'goal-fx-multiplayer-20261026/gvproxy-eim-wrapper']

        def regular(base, relative, limit):
            path = base
            for part in Path(relative).parts:
                path = path / part
                if path.is_symlink():
                    return None
            try:
                info = path.stat()
                return path if stat.S_ISREG(info.st_mode) and info.st_size <= limit else None
            except OSError:
                return None

        matches = []
        for relative in required:
            actual = regular(root, relative, 2 * 1024 * 1024)
            expected = regular(archive, relative, 2 * 1024 * 1024)
            matches.append(bool(actual and expected and
                                hashlib.sha256(actual.read_bytes()).digest() == hashlib.sha256(expected.read_bytes()).digest()))
        bundle = 'performance-stutter-20261027/FX HUD隔离诊断.app'
        fx = self.validated_fx(selected_fx) if selected_fx else None
        fx_base = Path(fx['path']) if fx and fx['identity_valid'] else root / bundle
        if selected_fx and not (fx and fx['identity_valid']):
            fx_base = root / 'invalid-fx-target'
        executable = regular(fx_base, 'Contents/MacOS/steamac-vm', 512 * 1024 * 1024)
        metadata = regular(fx_base, 'Contents/Info.plist', 65536)
        version = None
        if metadata:
            try:
                info = plistlib.loads(metadata.read_bytes())
                version = info.get('CFBundleShortVersionString') if isinstance(info, dict) else None
            except (ValueError, plistlib.InvalidFileException):
                pass
        return {'target_root': str(root), 'target_kind': 'fx_app_bundle' if root.suffix.casefold() == '.app' else 'runtime_directory',
                'archive_files_match': all(matches), 'fx_executable_present': bool(executable and os.access(executable, os.X_OK)),
                'fx_path': str(fx_base), 'fx_version': version if isinstance(version, str) else 'unknown',
                'scope': 'selected_target_file_metadata_only', 'guest': 'unverified', 'eac': 'unverified',
                'multiplayer': 'unverified', 'launch': 'unverified'}

    def validated_fx(self, selected):
        """Identity and path evidence only; never execute the candidate."""
        app = Path(selected).expanduser()
        if not app.is_absolute() or app.suffix.casefold() != '.app':
            return None
        if app.is_symlink():
            return None
        executable = app / 'Contents/MacOS/steamac-vm'
        try:
            if any(p.is_symlink() for p in (app / 'Contents', executable.parent, executable)):
                return None
            info = executable.stat()
            if not stat.S_ISREG(info.st_mode) or not os.access(executable, os.X_OK):
                return None
            details = self.discovery.bundle_details(executable)
            valid = details['structure_valid'] is True
            return {'path': str(app.resolve()), 'version': details['bundle_version'] or 'unknown',
                    'structure': 'metadata_valid' if valid else 'unverified',
                    'identity_valid': valid, 'launch': 'unverified', 'eac': 'unverified', 'multiplayer': 'unverified',
                    'location': str(app.parent), 'name': app.name}
        except OSError:
            return None

    def fx_versions(self, selected_paths=None, runtime_root=None):
        candidates = []
        seen = set()
        incomplete = False
        issues = []
        for directory in self.app_dirs[:2]:
            try:
                # Bound enumeration itself, not only the number of matching apps.
                with os.scandir(directory) as entries:
                    children = list(itertools.islice(entries, 2049))
                incomplete |= len(children) > 2048
                for entry in children[:2048]:
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
        # Revalidate remembered/manual paths and the dedicated runtime copy on every scan.
        hints = list(selected_paths or [])
        if runtime_root:
            hints.append(str(Path(runtime_root) / 'performance-stutter-20261027/FX HUD隔离诊断.app'))
        paths = [row['path'] for row in candidates] + hints
        candidates = []
        seen_paths = set()
        for path in paths:
            row = self.validated_fx(path)
            if not row or row['path'] in seen_paths:
                continue
            seen_paths.add(row['path'])
            # Resolve only bounded ancestors or an explicitly supplied independent resource directory.
            roots = ([Path(runtime_root)] if runtime_root else []) + list(Path(row['path']).parents)[:4]
            for root in roots:
                target = self.launch_target(str(root))
                if target['archive_files_match']:
                    row['runtime_root'] = target['target_root']
                    break
            candidates.append(row)
        return {'candidates': candidates, 'scan_incomplete': incomplete, 'issues': issues,
                'scope': 'two_shallow_application_directories_metadata_only',
                'compatibility': 'unverified', 'runtime_selection': 'not_read'}
