"""Isolated bridge/Core contract and side-effect checks. No game/SSH/FX execution."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

APP = Path(__file__).resolve().parents[1]
ROOT = APP / 'CoreSnapshot/native-app-core-snapshot'
SCRIPT = APP / 'bridge/bridge.py'

def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
    return value

bridge = module('bridge_checks_protocol', SCRIPT)
core = module('bridge_checks_adapter', APP / 'bridge/core_adapter.py')


def req(method='handshake', rid='test-1', **extra):
    return dict(protocol=1, request_id=rid, method=method, params={}, **extra)


class ContractChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hd2-bridge-check-')
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)

    def run_protocol(self, frames):
        proc = subprocess.run([sys.executable, '-I', '-B', str(SCRIPT)],
                              input=frames, capture_output=True, timeout=5,
                              env={'HOME': str(self.home), 'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8'})
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(proc.stderr, b'')
        return [json.loads(line) for line in proc.stdout.splitlines()]

    def target_fixture(self):
        archive, selected = self.home / 'archive', self.home / 'selected'
        for relative in ['launcher-20261026/steam-cdp.mjs', 'tools/check_node.cjs', 'goal-fx-multiplayer-20261026/gvproxy-eim-wrapper']:
            for folder in [archive, selected]:
                path = folder / relative
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(b'fixture helper; never execute')
        bundle = selected / 'performance-stutter-20261027/FX HUD隔离诊断.app'
        executable = bundle / 'Contents/MacOS/steamac-vm'
        executable.parent.mkdir(parents=True)
        executable.write_bytes(b'fixture executable; never execute')
        executable.chmod(0o700)
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString': 'fixture'}))
        adapter = object.__new__(core.CoreAdapter)
        adapter.root = archive / 'native-app-core-snapshot'
        return adapter, selected, bundle

    def test_target_inspection_is_metadata_not_health(self):
        adapter, selected, _ = self.target_fixture()
        with patch('subprocess.Popen', side_effect=AssertionError('No process permitted')):
            value = adapter.launch_target(str(selected))
        self.assertTrue(value['archive_files_match'] and value['fx_executable_present'])
        self.assertEqual(value['fx_version'], 'fixture')
        for key in ['guest', 'launch', 'eac', 'multiplayer']:
            self.assertEqual(value[key], 'unverified')

    def test_target_mismatch_never_repairs(self):
        adapter, selected, _ = self.target_fixture()
        path = selected / 'tools/check_node.cjs'
        path.write_bytes(b'user modification')
        self.assertFalse(adapter.launch_target(str(selected))['archive_files_match'])
        self.assertEqual(path.read_bytes(), b'user modification')

    def test_app_bundle_is_not_complete_runtime(self):
        adapter, _, bundle = self.target_fixture()
        value = adapter.launch_target(str(bundle))
        self.assertEqual(value['target_kind'], 'fx_app_bundle')
        self.assertFalse(value['archive_files_match'])

    def test_target_symlink_and_large_files_are_rejected(self):
        adapter, selected, _ = self.target_fixture()
        path = selected / 'tools/check_node.cjs'
        path.unlink()
        path.symlink_to(self.home / 'archive/tools/check_node.cjs')
        self.assertFalse(adapter.launch_target(str(selected))['archive_files_match'])
        path.unlink()
        path.write_bytes(b'x' * (2 * 1024 * 1024 + 1))
        self.assertFalse(adapter.launch_target(str(selected))['archive_files_match'])

    def test_target_invalid_metadata_and_missing_directory(self):
        adapter, _, bundle = self.target_fixture()
        (bundle / 'Contents/Info.plist').write_bytes(b'bad plist')
        self.assertEqual(adapter.launch_target(str(bundle.parent.parent))['fx_version'], 'unknown')
        self.assertFalse(adapter.launch_target(str(self.home / 'absent'))['fx_executable_present'])

    def test_target_protocol_forbids_commands_credentials_and_consent(self):
        for params in [{}, {'runtime_root': ''}, {'runtime_root': '/fixture', 'confirmed': True},
                       {'runtime_root': '/fixture', 'password': 'fixture-not-a-real-password'}, {'runtime_root': '/fixture', 'command': 'id'}]:
            request = dict(req('inspect_launch_target'), params=params)
            row = self.run_protocol((json.dumps(request) + '\n').encode())[0]
            self.assertEqual(row['error']['code'], 'INVALID_ARGUMENT')

    def test_multiple_requests_and_id_correlation(self):
        methods = ['handshake', 'get_launcher_version', 'get_system_info', 'get_environment_status', 'get_dependencies', 'get_logs']
        requests = [req(method, 'r-' + str(i)) for i, method in enumerate(methods)]
        rows = self.run_protocol(('\n'.join(json.dumps(r) for r in requests) + '\n').encode())
        self.assertEqual([r['request_id'] for r in rows], [r['request_id'] for r in requests])
        self.assertTrue(all(r['ok'] and r['protocol'] == 1 for r in rows))
        self.assertEqual(rows[1]['result']['version'], (ROOT / 'VERSION').read_text().strip())
        self.assertTrue(any('get_dependencies: OK' in r['message'] for r in rows[-1]['result']['entries']))
        self.assertEqual(list(self.home.iterdir()), [])

    def test_handshake_capabilities(self):
        row = self.run_protocol((json.dumps(req()) + '\n').encode())[0]['result']
        self.assertTrue(set(row['capabilities']).issuperset(bridge.METHODS))
        self.assertFalse(row['read_only'])
        self.assertTrue(row['read_only_default'])
        self.assertEqual(row['permission_model'],'explicit_actions')

    def test_unknown_write_operations_fail_closed(self):
        for method in ['launch_game', 'set_ssh_settings', 'update_settings', 'switch_fx', 'run_shell', 'check_fx_updates', 'install_update']:
            with self.subTest(method=method):
                row = self.run_protocol((json.dumps(req(method)) + '\n').encode())[0]
                self.assertEqual(row['error']['code'], 'CONFIRMATION_REQUIRED' if method=='launch_game' else 'NOT_IMPLEMENTED')

    def test_invalid_params_and_schema(self):
        invalid = [dict(req(), params={'command': 'touch /tmp/should-never-run'}),
                   dict(req(), request_id=''), dict(req(), request_id=3),
                   dict(req(), request_id='secret\nvalue'), dict(req(), method=[]),
                   dict(req(), timeout_ms=True), dict(req(), timeout_ms=0), dict(req(), unexpected='x')]
        for request in invalid:
            with self.subTest(request=request):
                self.assertEqual(self.run_protocol((json.dumps(request)+'\n').encode())[0]['error']['code'], 'INVALID_ARGUMENT')

    def test_protocol_mismatch(self):
        for value in (2, True, 1.0, '1', None):
            row = self.run_protocol((json.dumps(dict(req(), protocol=value)) + '\n').encode())[0]
            self.assertEqual(row['error']['code'], 'PROTOCOL_MISMATCH')
            self.assertEqual(row['request_id'], 'test-1')

    def test_malformed_frames(self):
        for data in (b'[]\n', b'bad\n', b'{"x":1,"x":2}\n', b'\xff\n', b'{"x":NaN}\n'):
            self.assertEqual(self.run_protocol(data)[0]['error']['code'], 'PROTOCOL_ERROR')

    def test_frame_limit(self):
        self.assertEqual(self.run_protocol(b'x' * 65537 + b'\n')[0]['error']['code'], 'PROTOCOL_ERROR')

    def test_eof_exits(self):
        self.assertEqual(self.run_protocol(b''), [])

    def test_actual_unknown_states(self):
        result = self.run_protocol((json.dumps(req('get_environment_status')) + '\n').encode())[0]['result']
        self.assertEqual(result['status'], 'unverified')
        self.assertTrue(all(r['state'] == 'unverified' for r in result['checks']))

    def test_timeout_and_recovery(self):
        class Slow:
            def system_info(self): time.sleep(0.3); return {}
        server = bridge.Bridge(Slow())
        self.assertEqual(server.reply(req('get_system_info', timeout_ms=10))['error']['code'], 'TIMEOUT')
        self.assertTrue(server.reply(req())['ok'])

    def test_errors_redacted_and_stdout_clean(self):
        class Broken:
            def system_info(self):
                print('legacy diagnostic')
                raise OSError('/private/person password=supersecret')
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            response = bridge.Bridge(Broken()).reply(req('get_system_info'))
        self.assertEqual(out.getvalue(), '')
        self.assertEqual(response['error']['code'], 'CORE_UNAVAILABLE')
        self.assertNotIn('supersecret', json.dumps(response) + err.getvalue())
        self.assertIn('legacy diagnostic', err.getvalue())

    def test_oversized_result(self):
        class Large:
            def system_info(self): return {'value': 'x' * 65536}
        out = io.StringIO()
        bridge.serve(Large(), io.BytesIO((json.dumps(req('get_system_info')) + '\n').encode()), out)
        self.assertEqual(json.loads(out.getvalue())['error']['code'], 'OUTPUT_LIMIT')


class CoreChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hd2-core-check-')
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.adapter = core.CoreAdapter(ROOT, [self.directory, self.directory / 'missing'])

    def fake_app(self, name='renamed.app', version='1.9.6'):
        app = self.directory / name
        (app / 'Contents/MacOS').mkdir(parents=True)
        (app / 'Contents/MacOS/steamac-vm').write_bytes(b'not-executed')
        with (app / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleShortVersionString': version, 'CFBundleExecutable': 'steamac-vm',
                          'CFBundleIdentifier': 'es.fxgam.steamac'}, stream)
        return app

    def test_reuses_core_metadata_for_renamed_app(self):
        self.fake_app()
        result = self.adapter.fx_versions()
        self.assertEqual(len(result['candidates']), 1)
        row = result['candidates'][0]
        self.assertEqual(row['version'], '1.9.6')
        self.assertEqual(row['structure'], 'metadata_valid')
        self.assertTrue(all(row[key] == 'unverified' for key in ('launch', 'eac', 'multiplayer')))
        self.assertEqual(result['candidates'][0]['path'], str(self.directory/'renamed.app'))
        self.assertEqual(result['runtime_selection'], 'not_read')

    def test_incomplete_enumeration_is_explicit(self):
        for i in range(70): (self.directory / str(i)).touch()
        self.assertTrue(self.adapter.fx_versions()['scan_incomplete'])

    def test_symlink_candidate_not_followed(self):
        app = self.fake_app()
        (self.directory / 'alias.app').symlink_to(app)
        self.assertEqual(len(self.adapter.fx_versions()['candidates']), 1)

    def test_dependency_probe_never_executes_node_or_ssh(self):
        with patch.object(subprocess, 'run', side_effect=AssertionError('Execution forbidden')):
            result = self.adapter.dependency_info()
        self.assertEqual(result['scope'], 'file_presence_only_no_binary_execution')

    def test_metadata_no_writes_process_network_keychain(self):
        self.fake_app()
        before = {str(p.relative_to(self.directory)): p.read_bytes() for p in self.directory.rglob('*') if p.is_file()}
        with patch.object(subprocess, 'run', side_effect=AssertionError('Execution forbidden')), \
             patch.object(self.adapter.discovery.runtime_paths, 'load', side_effect=AssertionError('Settings forbidden')), \
             patch('socket.socket', side_effect=AssertionError('Network forbidden')):
            for function in (self.adapter.launcher_version, self.adapter.system_info, self.adapter.environment,
                             self.adapter.dependency_info, self.adapter.fx_versions): function()
        after = {str(p.relative_to(self.directory)): p.read_bytes() for p in self.directory.rglob('*') if p.is_file()}
        self.assertEqual(before, after)

    def test_import_allowlist(self):
        for name in ['menu', 'preferences', 'start-hd2', 'keychain_store', 'runtime_selection', 'update_installer']:
            with self.assertRaises(ValueError): core.load_module(ROOT, name)


if __name__ == '__main__': unittest.main(verbosity=2)
