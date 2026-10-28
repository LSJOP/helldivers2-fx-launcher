import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import threading
import time
import unittest
from unittest.mock import Mock,patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('status_monitor_menu_test',HERE/'menu.py')
menu=importlib.util.module_from_spec(spec);spec.loader.exec_module(menu)
monitor=menu.status_monitor


class StatusMonitorTests(unittest.TestCase):
    def setUp(self):
        self.settings=json.loads(json.dumps(menu.prefs.DEFAULTS));self.settings['ssh_configured']=True
        self.prefs=Mock();self.prefs.load.return_value=self.settings
        self.prefs.SSHClient.return_value.socket='/tmp/hd2fx-synthetic-status.sock'
        self.helper=Mock(APP='/Applications/FX.app');self.helper.reachable.return_value=True
        latency=patch.object(monitor,'steam_latency',return_value=(12.3,'ready'))
        latency.start();self.addCleanup(latency.stop)

    def test_readonly_session_reports_real_remote_state(self):
        replies=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0,json.dumps({'steam_logged_on':True,'game_running':False}))]
        with patch.object(Path,'exists',return_value=True),patch.object(monitor.subprocess,'run',side_effect=replies) as run:
            result=monitor.snapshot(self.prefs,self.helper,'en')
        self.assertEqual(result['ssh'],('connected','green'))
        self.assertEqual(result['steam'],('signed in','green'))
        self.assertEqual(result['game'],('stopped','muted'))
        self.assertIn('10s auto',result['note'])
        args=run.call_args.args[0]
        for option in ['BatchMode=yes','ProxyCommand=false','StrictHostKeyChecking=yes','/dev/null']:
            self.assertIn(option,args)
        for option in ['-M','-L','exit']:self.assertNotIn(option,args)
        self.assertEqual(run.call_args.kwargs['timeout'],4)
        self.prefs.VAULT.get.assert_not_called();self.helper.connect.assert_not_called()

    def test_no_master_never_authenticates_or_uses_cached_green_state(self):
        with patch.object(Path,'exists',return_value=False),patch.object(monitor.subprocess,'run',return_value=subprocess.CompletedProcess([],0)) as run:
            result=monitor.snapshot(self.prefs,self.helper,'zh')
        self.assertEqual(run.call_count,1)
        self.assertEqual(result['ssh'],('待连接','muted'))
        self.assertEqual(result['steam'],('未检查','muted'))
        self.prefs.SSHClient.return_value.connect_once.assert_not_called()
        self.prefs.VAULT.get.assert_not_called()

    def test_timeout_leaves_remote_unknown_and_reports_failure(self):
        replies=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0),subprocess.TimeoutExpired('ssh',4)]
        with patch.object(Path,'exists',return_value=True),patch.object(monitor.subprocess,'run',side_effect=replies):
            result=monitor.snapshot(self.prefs,self.helper,'en')
        self.assertEqual(result['ssh'],('check failed','red'))
        self.assertEqual(result['steam'],('unchecked','muted'))
        self.assertEqual(result['game'],('unchecked','muted'))

    def test_guest_missing_login_state_is_not_reported_as_signed_in(self):
        replies=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0,'{"steam_logged_on":null,"game_running":true}')]
        with patch.object(Path,'exists',return_value=True),patch.object(monitor.subprocess,'run',side_effect=replies),patch.object(monitor,'latest_launch_probe',return_value={}):
            result=monitor.snapshot(self.prefs,self.helper,'en')
        self.assertEqual(result['steam'],('unchecked','muted'))
        self.assertEqual(result['game'],('running','green'))

    def test_gameplay_or_unknown_state_skips_external_tls_without_zero_latency(self):
        for running in [True,None,False]:
            replies=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0,json.dumps({'steam_logged_on':True,'game_running':running}))]
            with patch.object(Path,'exists',return_value=True),patch.object(monitor.subprocess,'run',side_effect=replies),patch.object(monitor,'latest_launch_probe',return_value={}),patch.object(monitor,'steam_latency',return_value=(123.0,'ready')) as tls:
                result=monitor.snapshot(self.prefs,self.helper,'en')
            if running is False:
                tls.assert_called_once();self.assertEqual(result['latency_steam_ms'],123.0)
            else:
                tls.assert_not_called();self.assertIsNone(result['latency_steam_ms']);self.assertEqual(result['latency_steam_state'],'paused')

    def test_full_environment_check_does_not_reuse_historical_login_after_steam_stops(self):
        h=menu.helper
        for pids,expected in [([],False),(['123'],True)]:
            with patch.object(h,'remote',return_value=json.dumps({'steam_pids':pids,'steam_logged_on':True})),patch.object(h,'network_ready',return_value=True):
                self.assertEqual(h.state()['steam_logged_on'],expected)

    def test_latest_launch_probe_is_allowlisted_and_ages_without_network_calls(self):
        import tempfile
        from datetime import datetime
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'history.jsonl'
            row={
                'kind':'launch_probe','time':datetime.now().astimezone().isoformat(timespec='seconds'),
                'playfab_direct':'reachable','playfab_direct_ms':210.4,
                'playfab_proxy':'failed','playfab_proxy_ms':None,
                'udp_samples':4,'udp_successes':3,'udp_rtt_ms':[120.0,126.0,130.0],
                'udp_jitter_ms':5.0,'password':'HIDDEN','ip':'203.0.113.9',
            }
            path.write_text(json.dumps(row)+'\n')
            result=monitor.latest_launch_probe(path)
        self.assertEqual(result['playfab_checked_routes'],2)
        self.assertEqual(result['playfab_reachable'],1)
        self.assertEqual(result['playfab_ms'],210.4)
        self.assertEqual(result['udp_samples'],4)
        self.assertEqual(result['udp_successes'],3)
        self.assertEqual(result['udp_ms'],125.3)
        self.assertEqual(result['udp_jitter_ms'],5.0)
        self.assertIn('probe_age_seconds',result)
        self.assertNotIn('HIDDEN',json.dumps(result))
        self.assertNotIn('203.0.113.9',json.dumps(result))

    def test_snapshot_attaches_latest_probe_only_while_game_runs(self):
        probe={'playfab_checked_routes':2,'playfab_reachable':2,'playfab_ms':220.0,
               'udp_samples':4,'udp_successes':4,'udp_ms':128.0,'udp_jitter_ms':4.0,
               'probe_age_seconds':30}
        for running in (True,False):
            replies=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0),
                     subprocess.CompletedProcess([],0,json.dumps({'steam_logged_on':True,'game_running':running}))]
            with patch.object(Path,'exists',return_value=True),patch.object(monitor.subprocess,'run',side_effect=replies),patch.object(monitor,'latest_launch_probe',return_value=probe) as latest:
                result=monitor.snapshot(self.prefs,self.helper,'en')
            self.assertEqual(latest.call_count,1 if running else 0)
            self.assertEqual(result['playfab_reachable'],2 if running else 0)
            self.assertEqual(result['udp_successes'],4 if running else 0)

    def test_ten_second_schedule_never_overlaps_and_stops_after_close(self):
        clock=[0];done=threading.Event();entered=threading.Event();calls=[]
        def refresh():
            calls.append(clock[0]);entered.set();done.wait(1);return {'note':'updated'}
        worker=menu.ui2.StatusRefresher(refresh,{},now=lambda:clock[0])
        try:
            self.assertEqual(worker.interval,10)
            worker.poll();self.assertTrue(entered.wait(.5))
            self.assertFalse(worker.request())
            clock[0]=9;worker.poll();self.assertEqual(calls,[0])
            done.set()
            deadline=time.monotonic()+1
            while worker.running and time.monotonic()<deadline:
                worker.poll();time.sleep(.005)
            self.assertEqual(worker.snapshot['note'],'updated')
            clock[0]=10;worker.poll()
            deadline=time.monotonic()+1
            while len(calls)<2 and time.monotonic()<deadline:time.sleep(.005)
            self.assertEqual(calls,[0,10])
            worker.close();clock[0]=30;self.assertFalse(worker.poll())
            self.assertEqual(len(calls),2)
        finally:done.set();worker.close()

    def test_refresh_exception_does_not_escape_or_leave_remote_green(self):
        worker=menu.ui2.StatusRefresher(Mock(side_effect=RuntimeError('synthetic')),{'ssh':('connected','green')})
        try:
            worker.poll();deadline=time.monotonic()+1
            while worker.running and time.monotonic()<deadline:
                worker.poll();time.sleep(.005)
            self.assertEqual(worker.snapshot['ssh'][1],'muted')
            self.assertIn('Refresh failed',worker.snapshot['note'])
        finally:worker.close()


if __name__=='__main__':unittest.main()
