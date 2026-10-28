import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('status_menu',HERE/'menu.py')
menu=importlib.util.module_from_spec(spec);spec.loader.exec_module(menu)
h=menu.helper


class StatusProgressTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.env=patch.dict(os.environ,{'HD2FX_SETTINGS_FILE':str(Path(self.folder.name)/'settings.json')})
        self.env.start()
        menu.LANG='en'
        menu.reset_observation()

    def tearDown(self):
        self.env.stop();self.folder.cleanup()

    def test_home_status_never_authenticates_or_reads_keychain(self):
        stream=io.StringIO()
        with patch.object(menu.subprocess,'run',return_value=subprocess.CompletedProcess([],1)),patch.object(h,'reachable',return_value=True),patch.object(h,'connect') as connect,patch.object(menu.prefs,'VAULT') as vault,contextlib.redirect_stdout(stream):
            menu.render_dashboard()
        self.assertIn('SSH: unchecked',stream.getvalue())
        self.assertIn('Steam: unchecked',stream.getvalue())
        self.assertIn('port open',stream.getvalue())
        connect.assert_not_called();vault.get.assert_not_called()

    def test_cached_remote_status_expires_and_endpoint_changes_invalidate(self):
        menu.observe_ssh({'steam_logged_on':True,'game_pids':['42']})
        with patch.object(menu.subprocess,'run',return_value=subprocess.CompletedProcess([],0)),patch.object(h,'reachable',return_value=True):
            output=io.StringIO()
            with contextlib.redirect_stdout(output):menu.render_dashboard()
            self.assertIn('SSH: verified',output.getvalue())
            self.assertIn('signed in',output.getvalue())
            menu.OBSERVATION['ssh_at']-=60;menu.OBSERVATION['guest_at']-=60
            output=io.StringIO()
            with contextlib.redirect_stdout(output):menu.render_dashboard()
            self.assertIn('SSH: unchecked',output.getvalue())
            data=menu.prefs.load();data['ssh']['port']=2244;menu.prefs.save(data)
            with contextlib.redirect_stdout(io.StringIO()):menu.render_dashboard()
            self.assertIsNone(menu.OBSERVATION['guest'])

    def test_post_save_retry_and_edit_choices(self):
        with patch.object(menu.sys.stdin,'isatty',return_value=True),patch.object(menu,'test_ssh_connection',side_effect=[RuntimeError('not ready'),None]) as test,patch.object(menu,'select_option',return_value='1'),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(menu.verify_saved_ssh(),'verified')
            self.assertEqual(test.call_count,2)
        with patch.object(menu.sys.stdin,'isatty',return_value=True),patch.object(menu,'test_ssh_connection',side_effect=RuntimeError('denied')),patch.object(menu,'select_option',return_value='2'),contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(menu.verify_saved_ssh(),'edit')

    def test_post_save_test_later_never_claims_verification(self):
        with patch.object(menu.sys.stdin,'isatty',return_value=False),patch.object(menu,'test_ssh_connection') as test,contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(menu.verify_saved_ssh(),'saved')
            self.assertIn('connection untested',output.getvalue())
            test.assert_not_called()
        self.assertIsNone(menu.OBSERVATION['ssh_at'])

    def test_ssh_test_only_observes_success_after_python_check(self):
        client=Mock(password='synthetic')
        client.reachable.return_value=True
        client.test_connection.side_effect=RuntimeError('Python failed')
        with patch.object(menu.prefs,'SSHClient',return_value=client):
            with self.assertRaises(RuntimeError):menu.test_ssh_connection()
        self.assertIsNone(menu.OBSERVATION['ssh_at'])
        client.test_connection.side_effect=None
        with patch.object(menu.prefs,'SSHClient',return_value=client),patch.object(menu,'refresh_connection'),contextlib.redirect_stdout(io.StringIO()):menu.test_ssh_connection()
        self.assertIsNotNone(menu.OBSERVATION['ssh_at'])

    def test_progress_failure_identifies_stage_and_restores_hook(self):
        def fail(**kwargs):
            h.report_progress('ssh')
            raise RuntimeError('synthetic connection error')
        previous=h.PROGRESS_HOOK
        with patch.object(menu,'refresh_connection'),patch.object(h,'main',side_effect=fail),contextlib.redirect_stdout(io.StringIO()) as output:
            with self.assertRaises(RuntimeError):menu.launch_game()
        self.assertIn('Stopped at: Connect to VM',output.getvalue())
        self.assertIs(h.PROGRESS_HOOK,previous)
        self.assertIsNone(menu.ACTIVE_PROGRESS)

    def test_progress_pauses_during_secret_input(self):
        progress=Mock()
        def password(prompt):
            progress.pause.assert_called_once()
            progress.resume.assert_not_called()
            return 'synthetic'
        with patch.object(menu,'ACTIVE_PROGRESS',progress),patch.object(menu.prefs,'secret',side_effect=password):
            self.assertEqual(menu.secret_prompt('SSH password: '),'synthetic')
        progress.resume.assert_called_once()

    def test_spinner_renders_and_stops(self):
        stream=io.StringIO()
        with contextlib.redirect_stdout(stream):
            progress=menu.LaunchProgress()
            progress.dynamic=True
            try:
                progress.update('ssh')
                time.sleep(.35)
                progress.pause()
                snapshot=stream.getvalue()
                time.sleep(.2)
                self.assertEqual(stream.getvalue(),snapshot)
                progress.resume()
                progress.update('ssh','done')
            finally:progress.close()
        self.assertIn('⠋',stream.getvalue())
        self.assertIn('passed',stream.getvalue())
        self.assertFalse(progress.thread.is_alive())

    def test_eac_parser_requires_fresh_success_log(self):
        root=Path(self.folder.name)
        log=root/'.local/share/Steam/steamapps/compatdata/553850/pfx/drive_c/users/steamuser/AppData/Roaming/EasyAntiCheat/product/deployment/anticheatlauncher.log'
        log.parent.mkdir(parents=True)
        log.write_text('Launcher finished with: 301\nSuccessfully initialized the Easy Anti-Cheat module\nTerminating with: 0.\n')
        def parse():
            output=io.StringIO()
            with patch.object(Path,'home',return_value=root),contextlib.redirect_stdout(output):exec(h.EAC_STATUS.replace('SINCE','20'),{})
            return json.loads(output.getvalue())
        os.utime(log,(10,10));self.assertEqual(parse()['result'],'pending')
        os.utime(log,(30,30));self.assertEqual(parse()['result'],'passed')
        log.write_text('Terminating with: 505.\n');os.utime(log,(30,30))
        self.assertEqual(parse(),{'result':'failed','exit_code':505})

    def test_eac_missing_result_is_unverified_and_failure_is_reported(self):
        with patch.object(h,'remote',return_value='{"result":"pending"}'),patch.object(h.time,'sleep'),patch.object(h,'report_progress') as report:
            h.check_eac(20,attempts=1)
            self.assertEqual(report.call_args.args,('eac','unverified'))
        with patch.object(h,'remote',return_value='{"result":"failed","exit_code":505}'):
            with self.assertRaisesRegex(RuntimeError,'EAC initialization failed'):h.check_eac(20,attempts=1)

    def test_playfab_monitor_reports_tls_route_without_claiming_login(self):
        response = json.dumps({'target': 'title.playfabapi.com', 'routes': {
            'direct': {'state': 'reachable', 'ms': 120.0},
            'proxy': {'state': 'failed', 'ms': None},
        }})
        output = io.StringIO()
        with patch.object(h, 'remote', return_value=response) as remote, patch.object(
                h, 'report_progress') as report, contextlib.redirect_stdout(output):
            result = h.monitor_playfab()
        self.assertEqual(result['routes']['direct']['state'], 'reachable')
        self.assertIn('CONNECT', h.PLAYFAB_PROBE)
        self.assertIn("server_hostname=host", h.PLAYFAB_PROBE)
        self.assertIn('不等于账号已登录', output.getvalue())
        report.assert_called_with('playfab', 'done')
        self.assertEqual(remote.call_args.kwargs['timeout'], 15)

    def test_udp_monitor_is_bounded_and_never_blocks_launch(self):
        response = json.dumps({
            'samples': [{'ok': True, 'ms': 42.0}, {'ok': False, 'ms': None},
                        {'ok': True, 'ms': 48.0}, {'ok': True, 'ms': 45.0}],
            'rtt_mean_ms': 45.0, 'jitter_ms': 2.4, 'game_sockets': 1,
        })
        output = io.StringIO()
        with patch.object(h, 'remote', return_value=response), patch.object(
                h, 'report_progress') as report, contextlib.redirect_stdout(output):
            result = h.monitor_udp()
        self.assertEqual(len(result['samples']), 4)
        self.assertIn('成功 3/4', output.getvalue())
        self.assertIn('不代表 NAT', output.getvalue())
        self.assertIn('stun.cloudflare.com', h.UDP_MONITOR)
        self.assertIn('0x2112A442', h.UDP_MONITOR)
        report.assert_called_with('udp', 'done')

    def test_post_launch_monitor_persists_once_and_survives_probe_errors(self):
        with patch.object(h, 'monitor_playfab', return_value={'routes': {}}), patch.object(
                h, 'monitor_udp', return_value={'samples': []}), patch.object(
                h.diagnostics, 'record_launch_probe') as record:
            h.run_post_launch_checks()
        record.assert_called_once()
        output = io.StringIO()
        with patch.object(h, 'monitor_playfab', side_effect=RuntimeError('synthetic')), patch.object(
                h, 'monitor_udp', return_value={'samples': []}), patch.object(
                h.diagnostics, 'record_launch_probe') as record, contextlib.redirect_stdout(output):
            h.run_post_launch_checks()
        self.assertIn('游戏启动未受影响', output.getvalue())
        self.assertEqual(record.call_count, 1)

    def test_tun_detection_selects_launch_mode_and_rejects_http_proxy_overlap(self):
        normal=subprocess.CompletedProcess([],0,'default 192.168.1.1 UGScg en0\n')
        tunnel=subprocess.CompletedProcess([],0,
            'default 192.168.1.1 UGScg en0\n0/1 198.18.0.1 UGScg utun4\n128.0/1 198.18.0.1 UGScg utun4\n')
        with patch.object(h.subprocess,'run',return_value=normal):
            self.assertFalse(h.tun_active())
        with patch.object(h.subprocess,'run',return_value=tunnel),patch.object(h,'tun_active',return_value=True):
            self.assertTrue(h.tun_active())
            self.assertEqual(h.required_launch(),h.TUN_LAUNCH)
            self.assertIn('https_proxy=http://192.168.127.254:7890',h.required_launch())
        proxy=subprocess.CompletedProcess([],0,'<dictionary> {\n HTTPEnable : 1\n HTTPSEnable : 1\n}\n')
        with patch.object(h.subprocess,'run',return_value=proxy):
            self.assertTrue(h.system_http_proxy_enabled())
        disabled=subprocess.CompletedProcess([],0,'<dictionary> {\n HTTPEnable : 0\n HTTPSEnable : 0\n}\n')
        with patch.object(h.subprocess,'run',return_value=disabled):
            self.assertFalse(h.system_http_proxy_enabled())

    def test_steam_proxy_helper_targets_only_launcher_owned_dropin(self):
        with patch.object(h,'remote',return_value='ok') as remote,patch.object(h,'say'):
            h.configure_steam_proxy(True)
            enabled=remote.call_args.args[0]
            h.configure_steam_proxy(False)
            disabled=remote.call_args.args[0]
        self.assertIn('ENABLED = True',enabled)
        self.assertIn('ENABLED = False',disabled)
        self.assertIn('90-hd2-proxy.conf',disabled)
        self.assertIn('p.unlink()',disabled)
        self.assertIn("p.read_text() in [text,legacy]",disabled)

    def test_animation_setting_does_not_change_ssh(self):
        before=menu.prefs.load()['ssh']
        with patch.object(menu,'select_option',side_effect=['6','0']),contextlib.redirect_stdout(io.StringIO()):menu.select_emblem()
        self.assertFalse(menu.prefs.load()['appearance']['intro_animation'])
        self.assertEqual(menu.prefs.load()['ssh'],before)

    def test_real_terminal_startup_animation_can_be_skipped(self):
        program="""import importlib.util
from pathlib import Path
p=Path('launcher-20261026/menu.py');s=importlib.util.spec_from_file_location('m',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
m.LANG='en';m.startup_animation(duration=10);print('INTRO_FINISHED',flush=True)
"""
        master,slave=pty.openpty()
        process=subprocess.Popen([sys.executable,'-c',program],cwd=HERE.parent,stdin=slave,stdout=slave,stderr=slave,env=dict(os.environ,TERM='xterm-256color'),start_new_session=True)
        os.close(slave);output=b''
        try:
            deadline=time.monotonic()+3
            while b'STARTING INTERFACE' not in output and time.monotonic()<deadline:
                if select.select([master],[],[],.1)[0]:output+=os.read(master,65536)
            self.assertIn(b'STARTING INTERFACE',output)
            os.write(master,b'x')
            while process.poll() is None and time.monotonic()<deadline:
                if select.select([master],[],[],.1)[0]:
                    try:output+=os.read(master,65536)
                    except OSError:break
            process.wait(timeout=1)
            try:
                while select.select([master],[],[],0)[0]:
                    chunk=os.read(master,65536)
                    if not chunk:break
                    output+=chunk
            except OSError:pass
            self.assertIn(b'INTRO_FINISHED',output)
            self.assertIn(b'\x1b[?25h',output)
        finally:
            if process.poll() is None:process.terminate();process.wait(timeout=1)
            os.close(master)


if __name__=='__main__':unittest.main()
