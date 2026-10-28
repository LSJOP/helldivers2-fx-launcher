"""Offline diagnostics tests: no game, SSH, DNS or external HTTP calls."""
import contextlib
import fcntl
import pty
import re
import select
import struct
import termios
import importlib.util
import io
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import MagicMock, patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('diagnostic_menu_test', HERE/'menu.py')
menu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(menu)
d = menu.network_diagnostics


def fake_snapshot():
    return {'kind': 'snapshot', 'id': 'snapshot1', 'time': '2026-10-27T15:00:00+08:00',
            'fx': True, 'gvproxy': True, 'steam': None, 'proxy_open': True,
            'eim': {'runtime_mapping': 'unverified'}, 'interface': 'en0',
            'ipv4': True, 'ipv6': False, 'udp_configuration': 'unverified',
            'udp_connectivity': 'unverified', 'nat': 'unknown'}


class SnapshotTests(unittest.TestCase):
    def process_output(self, args, processes):
        if args[-1] == 'pid=,ppid=,comm=':
            return '\n'.join(f'{pid} {ppid} {exe}' for pid, ppid, exe, argv in processes)
        if args[-1] == 'pid=,args=':
            return '\n'.join(f'{pid} {argv}' for pid, ppid, exe, argv in processes)
        raise AssertionError('Unexpected ps format')

    def take(self, ps=(), port_open=True):
        def commands(args):
            if args[0] == '/bin/ps': return self.process_output(args, ps)
            if args[0] == '/sbin/route': return 'interface: en0\n'
            return 'inet 192.168.1.2\ninet6 fe80::abcd\n'
        connection = MagicMock()
        if not port_open: connection.side_effect = socket.timeout()
        with patch.object(d, 'optional_command', side_effect=commands), patch.object(d.socket, 'create_connection', connection):
            return d.snapshot('/Applications/FX App.app', '/test/gvproxy-eim', '/missing-wrapper', 'hash')

    def test_fx_gvproxy_absent_and_proxy_closed(self):
        row = self.take(port_open=False)
        self.assertIs(row['fx'], False);self.assertIs(row['gvproxy'], False)
        self.assertIs(row['proxy_open'], False)
        self.assertIsNone(row['steam'])
        self.assertEqual(row['udp_connectivity'], 'unverified')
        self.assertEqual(row['nat'], 'unknown')

    def test_process_path_arguments_and_missing_components_are_separate(self):
        row = self.take([(10,1,'/Applications/FX App.app/Contents/MacOS/fx', '/Applications/FX App.app/Contents/MacOS/fx --gvproxy /missing-wrapper'),
                         (11,10,'/test/gvproxy-eim','/test/gvproxy-eim -listen-vfkit unix:///socket')])
        self.assertTrue(row['fx']);self.assertTrue(row['gvproxy'])
        self.assertTrue(row['eim']['expected_executable']);self.assertTrue(row['eim']['listen_vfkit'])
        self.assertEqual(row['udp_configuration'], 'unverified')
        self.assertNotIn('/test/', json.dumps(row))
        self.assertNotIn('192.168', json.dumps(row))

    def test_ps_failure_unknown_and_false_positive_mentions_ignored(self):
        row = self.take([(99,1,'/bin/sh','sh -c /test/gvproxy-eim -listen-vfkit a /Applications/FX App.app/Contents/MacOS/fx')])
        self.assertFalse(row['fx']);self.assertFalse(row['gvproxy'])
        with patch.object(d, 'optional_command', return_value=None), patch.object(d.socket, 'create_connection', side_effect=OSError):
            row = d.snapshot('app', 'binary', 'wrapper', 'hash')
        self.assertIsNone(row['fx']);self.assertIsNone(row['gvproxy']);self.assertIsNone(row['ipv4'])

    def test_verified_disk_and_arguments_still_do_not_verify_runtime_udp(self):
        with tempfile.TemporaryDirectory() as folder:
            binary = Path(folder)/'gvproxy-eim';binary.write_bytes(b'binary')
            wrapper = Path(folder)/'wrapper'
            wrapper.write_text('#!/bin/sh\nexport GVPROXY_UDP_PORT_MAPPING=endpoint-independent\n'
                'steamac_network_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1\n'
                'exec "$steamac_network_dir/gvproxy-eim" "$@"\n')
            ps = [(10,1,'/app/Contents/MacOS/fx',f'/app/Contents/MacOS/fx --gvproxy {wrapper}'),
                  (11,10,str(binary),f'{binary} -listen-vfkit unix:///socket')]
            with patch.object(d, 'optional_command', side_effect=lambda args: self.process_output(args, ps) if args[0]=='/bin/ps' else None), patch.object(d.socket, 'create_connection'):
                row = d.snapshot('/app', binary, wrapper, d.hashlib.sha256(b'binary').hexdigest())
            self.assertEqual(row['udp_configuration'], 'detected')
            self.assertEqual(row['eim']['runtime_mapping'], 'unverified')
            self.assertEqual(row['udp_connectivity'], 'unverified')
            self.assertEqual(row['nat'], 'unknown')

    def test_long_executable_with_spaces_is_not_read_from_truncated_comm_column(self):
        root = '/Volumes/Long Drive/very-long-folder/'
        binary = root + 'gvproxy-eim'
        processes = [(10,1,root+'FX App.app/Contents/MacOS/steamac-vm',
                      root+'FX App.app/Contents/MacOS/steamac-vm --gvproxy /wrapper'),
                     (11,10,binary,binary+' -listen-vfkit unix:///socket')]
        seen = []
        def commands(args):
            if args[0] != '/bin/ps': return None
            seen.append(args[-1])
            return self.process_output(args, processes)
        with patch.object(d,'optional_command',side_effect=commands), patch.object(d.socket,'create_connection'):
            row = d.snapshot(root+'FX App.app',binary,'/wrapper','hash')
        self.assertTrue(row['fx']);self.assertTrue(row['gvproxy'])
        self.assertTrue(row['eim']['expected_executable']);self.assertTrue(row['eim']['listen_vfkit'])
        self.assertTrue(row['eim']['wrapper_selected'])
        self.assertNotIn('pid=,ppid=,comm=,args=',seen)
        self.assertNotIn(root,json.dumps(row))



class ProbeTests(unittest.TestCase):
    def test_dns_tcp_https_failures_and_success(self):
        for code, raw, failure in [(6, '000 0 0.1', 'dns'), (28, '000 0 1.5', 'timeout'),
                                   (60, '000 0.02 0.03', 'https'), (0, '503 0.02 0.03', 'https'),
                                   (0, '200 0.02 0.03', None)]:
            runner = MagicMock(return_value=(code, raw))
            row = d.probe('www.apple.com', 'direct', threading.Event(), runner=runner)
            self.assertEqual(row['failure'], failure)
            self.assertEqual(row['https'], failure is None)
            self.assertIn('--disable', runner.call_args.args[0])
            self.assertGreater(runner.call_args.kwargs['timeout'], 0)
        self.assertEqual(d.probe('www.apple.com', 'direct', threading.Event(),
            runner=MagicMock(side_effect=subprocess.TimeoutExpired('curl', 1)))['failure'], 'timeout_or_unavailable')

    def test_test_is_bounded_and_cancelled(self):
        cancel = threading.Event();cancel.set()
        result = d.network_test('s', cancel, runner=MagicMock(side_effect=d.Cancelled))
        self.assertTrue(result['cancelled']);self.assertEqual(result['samples'], [])
        def runner(args, **kwargs):
            if args[0].endswith('dscacheutil'): return 1, ''
            return 6, '000 0 0.1'
        with patch.object(d.time, 'monotonic', side_effect=[0, 0, 14, 14]):
            result = d.network_test('s', runner=runner)
        self.assertEqual(result['host_dns'], 'failed')
        self.assertLessEqual(len(result['samples']), 1)

    def test_actual_child_timeout_and_cancellation_are_reaped(self):
        # A local Python sleep is the only real subprocess used by this suite.
        started = time.monotonic()
        with self.assertRaises(subprocess.TimeoutExpired):
            d.command([os.sys.executable, '-c', 'import time; time.sleep(10)'], timeout=.15)
        self.assertLess(time.monotonic()-started, 1.5)
        cancel = threading.Event()
        timer = threading.Timer(.1, cancel.set);timer.start()
        try:
            with self.assertRaises(d.Cancelled):
                d.command([os.sys.executable, '-c', 'import time; time.sleep(10)'], timeout=2, cancel=cancel)
        finally: timer.join()


class StorageTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory();self.store = d.Store(self.tmp.name)
    def tearDown(self): self.tmp.cleanup()

    def test_success_timeout_persistence_time_filter_and_corrupt_tail(self):
        # Match submission uses the current clock; pin it to the fixture day so
        # the date-range expectation remains valid after midnight and tomorrow.
        with patch.object(d,'stamp',return_value='2026-10-27T15:01:00+08:00'):
            for result in ('success', 'timeout', 'disconnect'):
                self.store.record_match(result, fake_snapshot(), '正常备注')
        rows = self.store.read()
        self.assertEqual([r['result'] for r in rows if r['kind']=='match'], ['success', 'timeout', 'disconnect'])
        self.assertTrue(all(r['snapshot_id']=='snapshot1' for r in rows if r['kind']=='match'))
        with (Path(self.tmp.name)/'history.jsonl').open('a') as f:f.write('{interrupted\n')
        self.assertEqual(len(self.store.read()), 6)
        self.assertEqual(self.store.read('2026-10-28', '2026-10-29'), [])
        self.assertTrue(self.store.read('2026-10-27', '2026-10-28'))
        self.assertEqual((Path(self.tmp.name)/'history.jsonl').stat().st_mode & 0o777, 0o600)

    def test_append_after_partial_tail_preserves_next_record(self):
        self.store.append(fake_snapshot())
        path = Path(self.tmp.name)/'history.jsonl'
        with path.open('ab') as stream:
            stream.write(b'{"kind":"match","time":')
        self.store.record_match('timeout', fake_snapshot())
        rows = self.store.read()
        self.assertEqual([r['result'] for r in rows if r['kind']=='match'], ['timeout'])
        self.assertEqual(len(rows), 3)

    def test_date_query_preserves_only_required_snapshot_dependencies(self):
        snap = fake_snapshot();snap['time'] = '2026-10-26T23:59:59+08:00'
        self.store.append(snap)
        other = dict(snap, id='unrelated')
        self.store.append(other)
        self.store.append({'kind':'match', 'snapshot_id':snap['id'], 'result':'timeout',
                           'time':'2026-10-27T00:00:01+08:00'})
        rows = self.store.read('2026-10-27', '2026-10-28')
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]['id'], snap['id'])
        stats = d.summarize(rows, [('night', 0, 1)])
        self.assertEqual(stats[0]['failures_with_gvproxy_observed'], 1)
        self.assertEqual(self.store.read('2026-10-28'), [])

    def test_non_list_time_window_settings_are_rejected(self):
        path = Path(self.tmp.name)/'diagnostic-settings.json'
        for value in (1, None, {}, 'invalid'):
            path.write_text(json.dumps({'windows':value}))
            with self.assertRaises(ValueError):
                self.store.windows()

    def test_nested_unknown_eim_fields_are_not_exported(self):
        snap = fake_snapshot()
        snap['eim'].update(password='HIDDEN_CREDENTIAL', nested={'API_KEY':'HIDDEN_KEY'},
                           expected_executable={'password':'NESTED_SECRET'}, runtime_mapping='RUNTIME_SECRET')
        text = self.store.export([snap], d.WINDOWS).read_text()
        self.assertNotIn('HIDDEN_CREDENTIAL', text)
        self.assertNotIn('HIDDEN_KEY', text)
        self.assertNotIn('NESTED_SECRET', text)
        self.assertNotIn('RUNTIME_SECRET', text)
        self.assertNotIn('password', text)
        self.assertIn('runtime_mapping', text)

    def test_known_bad_process_reading_is_invalidated_without_rewriting_history(self):
        snap = fake_snapshot();snap['fx'] = False
        self.store.append(snap)
        self.store.append({'kind':'snapshot_invalidation','time':'2026-10-28T00:00:00+08:00',
                           'snapshot_id':snap['id'],'fields':['fx','gvproxy']})
        rows = self.store.read('2026-10-27','2026-10-28')
        self.assertIsNone(rows[0]['fx']);self.assertIsNone(rows[0]['gvproxy'])
        self.assertTrue(rows[0]['process_evidence_invalidated'])
        original = json.loads((Path(self.tmp.name)/'history.jsonl').read_text().splitlines()[0])
        self.assertIs(original['fx'], False)
        self.assertIn('process_evidence_invalidated', self.store.export(rows,d.WINDOWS).read_text())

    def test_afternoon_evening_real_record_aggregation_and_empty(self):
        rows = [fake_snapshot()]
        for hour, results in [(15, ['success']*8+['timeout']*2), (20, ['success']*3+['timeout']*7)]:
            rows.extend({'kind':'match', 'time':f'2026-10-27T{hour}:00:00+08:00', 'result':r, 'snapshot_id':'snapshot1'} for r in results)
            rows.append({'kind':'test', 'time':f'2026-10-27T{hour}:00:00+08:00', 'samples':[
                {'route':'direct','tcp_ms':10,'failure':None}, {'route':'direct','tcp_ms':30,'failure':'https'}]})
        stats = d.summarize(rows)
        self.assertEqual([r['success_rate'] for r in stats], [80,30])
        self.assertEqual(stats[1]['failures_with_gvproxy_observed'], 7)
        self.assertEqual(stats[0]['quality']['direct']['tcp_mean_ms'], 20)
        self.assertEqual(stats[0]['quality']['direct']['tcp_stdev_ms'], 10)
        self.assertFalse(stats[0]['small_sample'])
        self.assertIsNone(d.summarize([])[0]['success_rate'])
        self.assertTrue(d.summarize([])[0]['small_sample'])

    def test_configurable_windows_and_invalid_config(self):
        path=Path(self.tmp.name)/'diagnostic-settings.json'
        path.write_text(json.dumps({'windows':[['custom',0,12]]}))
        self.assertEqual(self.store.windows(), [['custom',0,12]])
        path.write_text(json.dumps({'windows':[['custom',24,1]]}))
        with self.assertRaises(ValueError):self.store.windows()

    def test_reports_redact_ips_username_paths_notes_and_unknown_fields(self):
        row = fake_snapshot();row.update(interface='192.168.1.1', process='/Users/example_user/private', env={'API_KEY':'secret'})
        with patch.object(d, 'stamp', return_value=row['time']):
            self.store.record_match('timeout', row, 'https://subscription/secret token=abc')
        rows = self.store.read();rows[-1]['note']='arbitrary-private-note'
        rows.append({'kind':'test','time':row['time'],'snapshot_id':'snapshot1','samples':[
            {'target':'fe80::1234','route':'direct','failure':'/Volumes/private','raw':'SECRET'}]})
        path = self.store.export(rows, d.WINDOWS);text=path.read_text()
        for value in ('192.168.1.1','example_user','/Users/','/Volumes/','subscription','arbitrary-private-note','API_KEY','SECRET','fe80::1234'):
            self.assertNotIn(value, text)
        self.assertEqual(path.stat().st_mode & 0o777, 0o600)
        self.assertIn('[REDACTED]', json.dumps(self.store.read()))
        self.assertIn('runtime_mapping', text)
        self.assertEqual(json.loads(text)['statistics'][0]['attempts'], 1)

    def test_launch_probe_is_allowlisted_and_exported_without_network_addresses(self):
        result = {
            'playfab': {'routes': {
                'direct': {'state': 'reachable', 'ms': 12.34, 'address': '203.0.113.9'},
                'proxy': {'state': 'failed', 'ms': None, 'error': 'SECRET_PATH'},
            }},
            'udp': {
                'samples': [
                    {'ok': True, 'ms': 41.2, 'target': 'stun.cloudflare.com'},
                    {'ok': True, 'ms': 47.8, 'target': 'stun.l.google.com'},
                    {'ok': False, 'ms': None, 'address': '198.51.100.8'},
                ],
                'game_sockets': 2, 'connected_sockets': 1,
                'in_datagrams_delta': 17, 'out_datagrams_delta': 21,
                'raw': 'not exported',
            },
            'password': 'HIDDEN',
        }
        row = d.record_launch_probe(result, self.store)
        self.assertEqual(row['playfab_direct'], 'reachable')
        self.assertEqual(row['playfab_proxy'], 'failed')
        self.assertEqual(row['udp_samples'], 3)
        self.assertEqual(row['udp_successes'], 2)
        self.assertEqual(row['game_udp_sockets'], 2)
        self.assertNotIn('203.0.113.9', json.dumps(row))
        self.assertNotIn('SECRET_PATH', json.dumps(row))
        exported = self.store.export(self.store.read(), d.WINDOWS).read_text()
        self.assertIn('launch_probe', exported)
        self.assertIn('udp_rtt_ms', exported)
        for value in ('203.0.113.9', '198.51.100.8', 'SECRET_PATH', 'HIDDEN', 'not exported'):
            self.assertNotIn(value, exported)


class UITests(unittest.TestCase):
    def test_bilingual_88x27_and_small_window_layout(self):
        for language in ('zh-CN','en'):
            for columns, rows in ((88,27),(80,24),(40,12),(20,10)):
                frame=d.build_frame(menu.ui2,columns,rows,fake_snapshot(),language)
                self.assertEqual(set(frame.positions), set('0123456'))
                positions=[v[0] for v in frame.positions.values()]
                self.assertEqual(len(positions),len(set(positions)))
                self.assertTrue(all(0<y<rows-1 for y in positions))
                self.assertTrue(all(menu.ui2.text_width(line)<=columns for line in frame.plain().splitlines()))
                if columns==88:
                    self.assertIn('UNVERIFIED',frame.plain());self.assertIn('UNKNOWN',frame.plain())
                    self.assertIn('联机诊断' if language=='zh-CN' else 'NETWORK DIAGNOSTICS',frame.plain())

    def test_cancel_record_and_exit_never_start_game_or_ssh(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(d,'Store',return_value=d.Store(folder)), patch.object(d,'snapshot',return_value=fake_snapshot()), patch.object(d,'choose',side_effect=['2','0']), patch.object(menu,'select_option',return_value='0'), patch.object(menu.helper,'main') as launch, patch.object(menu.helper,'remote') as remote:
            d.run(menu._diagnostic_menu_context())
            self.assertFalse(any(r['kind']=='match' for r in d.Store(folder).read()))
            launch.assert_not_called();remote.assert_not_called()

    def test_menu_record_success_and_timeout(self):
        for answer, expected in [('1','success'),('2','timeout')]:
            with tempfile.TemporaryDirectory() as folder, patch.object(d,'Store',return_value=d.Store(folder)), patch.object(d,'snapshot',return_value=fake_snapshot()), patch.object(d,'choose',side_effect=['2','0']), patch.object(menu,'select_option',return_value=answer), patch('builtins.input',return_value='note'):
                d.run(menu._diagnostic_menu_context())
                matches=[r for r in d.Store(folder).read() if r['kind']=='match']
                self.assertEqual(matches[0]['result'], expected)

    def test_network_ui_interrupt_saves_partial_cancel(self):
        def test(sid, cancel):
            cancel.wait(1)
            return {'cancelled':cancel.is_set(),'samples':[]}
        with patch.object(d,'network_test',side_effect=test), patch.object(d.sys.stdin,'isatty',return_value=False), patch.object(d.threading.Thread,'is_alive',side_effect=KeyboardInterrupt), contextlib.redirect_stdout(io.StringIO()):
            result = d.run_test_ui(menu, 's')
        self.assertTrue(result['cancelled'])

    def test_real_pty_navigation_cancel_and_terminal_restoration(self):
        snapshot_json = repr(fake_snapshot())
        for keys, expected, network in [(b'\x1b[B\r', '2', False), (b'6\r', '6', False),
                                         (b'\x1b', '0', False), (b'q', True, True)]:
            program = """import importlib.util,sys,termios,json
from types import SimpleNamespace
from pathlib import Path
s=importlib.util.spec_from_file_location('d','network_diagnostics.py');d=importlib.util.module_from_spec(s);s.loader.exec_module(d)
s=importlib.util.spec_from_file_location('u','ui2.py');u=importlib.util.module_from_spec(s);s.loader.exec_module(u)
before=termios.tcgetattr(0)
if NETWORK:
 def fake(sid,cancel):
  cancel.wait(3)
  return {'cancelled':cancel.is_set()}
 d.network_test=fake
 result=d.run_test_ui(SimpleNamespace(LANG='en'),'s')['cancelled']
else:
 result=d.choose(u,SNAPSHOT,'en')
after=termios.tcgetattr(0)
for attrs in (before,after):attrs[3]&=~getattr(termios,'PENDIN',0)
print('RESULT='+json.dumps([result,before==after]),flush=True)
""".replace('NETWORK', repr(network)).replace('SNAPSHOT', snapshot_json)
            master, slave = pty.openpty()
            fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH',27,88,0,0))
            process = subprocess.Popen([os.sys.executable,'-c',program],cwd=HERE,
                stdin=slave,stdout=slave,stderr=slave,env=dict(os.environ,TERM='xterm-256color'))
            os.close(slave);output=b''
            try:
                deadline=time.monotonic()+5
                marker=b'cancels.' if network else b'\x1b[27;1H'
                while marker not in output and time.monotonic()<deadline:
                    if select.select([master],[],[],.1)[0]:output+=os.read(master,65536)
                self.assertIn(marker, output)
                os.write(master,keys)
                while b'RESULT=' not in output and time.monotonic()<deadline:
                    if select.select([master],[],[],.1)[0]:
                        try:output+=os.read(master,65536)
                        except OSError:break
                self.assertIn(b'RESULT=',output)
                value=json.loads(output.split(b'RESULT=')[-1].splitlines()[0])
                self.assertEqual(value,[expected,True])
                process.wait(timeout=1)
                self.assertEqual(process.returncode,0)
            finally:
                if process.poll() is None:process.kill();process.wait()
                os.close(master)

    def test_old_network_profile_remains_explicit_action(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(d,'Store',return_value=d.Store(folder)), patch.object(d,'snapshot',return_value=fake_snapshot()), patch.object(d,'choose',side_effect=['5','0']), patch.object(menu,'network_menu') as profile:
            d.run(menu._diagnostic_menu_context())
            profile.assert_called_once()


if __name__ == '__main__':unittest.main()
