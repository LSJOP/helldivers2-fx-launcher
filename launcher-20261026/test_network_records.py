"""Privacy, outage attribution and menu tests; no real network or authentication."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import sqlite3
import subprocess
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock,patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('network_record_menu_test',HERE/'menu.py')
menu=importlib.util.module_from_spec(spec);spec.loader.exec_module(menu)
n=menu.network_records


def sample_guest():
    return {'steam_running':True,'log_available':True,'log_truncated':False,'timezone_offset':'+0800',
            'events':[['2026-10-27 22:18:01','Logged On'],['2026-10-28 03:00:19','Logged Off'],
                      ['2026-10-28 03:00:26','Connecting'],['2026-10-28 03:00:26','Logged Off'],
                      ['2026-10-28 03:02:14','Logged Off'],['2026-10-28 03:02:37','Connected'],
                      ['2026-10-28 03:02:37','Logging On'],['2026-10-28 03:02:37','Logged On']],
            'saved_launch_raw':menu.helper.WORKING_LAUNCH,'games':[]}


def helper_fixture():
    client=SimpleNamespace(settings={'host':'127.0.0.1'},base=Mock(return_value=['ssh','-S','fixture.sock']),
                           command=Mock(return_value=['ssh','-S','fixture.sock','-o','BatchMode=yes','127.0.0.1']),
                           connect_once=Mock(),_saved_password=Mock())
    return SimpleNamespace(CLIENT=client,refresh_settings=Mock(),connect=Mock())


class NetworkRecordTests(unittest.TestCase):
    def test_retries_remain_one_outage_and_recovery_uses_correct_cycle(self):
        data=sample_guest();s=n.summarize_steam(data)
        self.assertEqual(s['last_disconnect_at'],'2026-10-28 03:00:19')
        self.assertEqual(s['last_recovery_at'],'2026-10-28 03:02:37')
        self.assertEqual(s['outage_seconds'],138)
        self.assertEqual(s['state'],'Logged On');self.assertFalse(s['outage_open'])
        data['events'] += [['bad-date','Logged Off'],['2026-10-28 03:30:00','Logged Off'],['2026-10-28 03:30:10','Connecting']]
        s=n.summarize_steam(data)
        self.assertEqual(s['last_disconnect_at'],'2026-10-28 03:30:00')
        self.assertIsNone(s['last_recovery_at']);self.assertIsNone(s['outage_seconds']);self.assertTrue(s['outage_open'])

    def test_stale_log_cannot_claim_stopped_steam_is_online(self):
        data=sample_guest();data['steam_running']=False
        self.assertEqual(n.summarize_steam(data)['state'],'stopped')
        data.update(steam_running=True,events=[],log_available=False)
        self.assertIsNone(n.summarize_steam(data)['state'])

    def test_launch_snapshot_omits_credentials_custom_tokens_and_subscription_urls(self):
        secret='DO_NOT_PERSIST'
        text=menu.helper.WORKING_LAUNCH.replace('http://192.168.127.254:7890',f'http://user:{secret}@192.168.127.254:7890/?subscription={secret}')
        text+=' API_TOKEN='+secret+' --password '+secret+' https://subscribe.example/'+secret
        with patch.object(n.subprocess,'run') as run:result=n.safe_launch(text)
        self.assertTrue(result['omitted']);self.assertNotIn(secret,json.dumps(result))
        self.assertIn('https_proxy=http://192.168.127.254:7890',result['text'])
        self.assertIn(n.CPU_PREFIX,result['text']);self.assertIn('%command%',result['text'])
        run.assert_not_called()
        self.assertEqual(n.safe_launch(menu.helper.WORKING_LAUNCH),{'text':menu.helper.WORKING_LAUNCH,'omitted':False})
        self.assertIsNone(n.safe_proxy('not-a-proxy'))
        self.assertEqual(n.safe_environment({'TOKEN':secret,'https_proxy':'http://u:'+secret+'@[::1]:7890','FEX_DISKCACHE':'0'}),{'https_proxy':'http://[::1]:7890','FEX_DISKCACHE':'0'})

    def test_missing_or_dying_master_never_authenticates_or_reconnects(self):
        h=helper_fixture()
        with patch.object(n.subprocess,'run',return_value=subprocess.CompletedProcess([],1)) as run:
            result=n.guest_snapshot(h)
        self.assertEqual(result['reason'],'no_existing_session');self.assertEqual(run.call_count,1)
        h.CLIENT.command.assert_not_called();h.connect.assert_not_called();h.CLIENT.connect_once.assert_not_called();h.CLIENT._saved_password.assert_not_called()
        with patch.object(n.subprocess,'run',side_effect=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],1)]) as run:
            result=n.guest_snapshot(h)
        self.assertEqual(result['reason'],'existing_session_read_failed')
        command=run.call_args.args[0]
        self.assertIn('ProxyCommand=false',command);self.assertIn('ControlMaster=no',command);self.assertIn('BatchMode=yes',command)
        h.connect.assert_not_called();h.CLIENT._saved_password.assert_not_called()

    def test_guest_raw_custom_options_are_filtered_before_return(self):
        h=helper_fixture();raw=sample_guest();raw['saved_launch_raw']+=' TOKEN=SECRET_VALUE'
        raw['games']=[{'pid':42,'environment':{'https_proxy':'http://u:SECRET_VALUE@localhost:7890','TOKEN':'SECRET_VALUE','VKD3D_CONFIG':'single_queue'}}]
        with patch.object(n.subprocess,'run',side_effect=[subprocess.CompletedProcess([],0),subprocess.CompletedProcess([],0,json.dumps(raw))]):
            result=n.guest_snapshot(h)
        self.assertEqual(result['status'],'available');self.assertNotIn('SECRET_VALUE',json.dumps(result))
        self.assertNotIn('saved_launch_raw',result);self.assertNotIn('events',result)

    def test_flclash_node_is_scoped_to_active_profile_and_never_copies_credentials(self):
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);p=home/'Library/Preferences/com.follow.clash.plist';p.parent.mkdir(parents=True)
            config={'currentProfileId':'2','networkProps':{'systemProxy':False,'authentication':'SECRET'},
                    'vpnProps':{'enable':True},'patchClashConfig':{'mode':'global','allow-lan':True,'mixed-port':7890,'secret':'SECRET'}}
            p.write_bytes(plistlib.dumps({'flutter.config':json.dumps(config)}))
            db=home/'Library/Application Support/com.follow.clash/database.sqlite';db.parent.mkdir(parents=True)
            with sqlite3.connect(db) as c:
                c.execute('CREATE TABLE profiles(id TEXT,selected_map TEXT,current_group_name TEXT,url TEXT)')
                c.executemany('INSERT INTO profiles VALUES(?,?,?,?)',[('1','{"GLOBAL":"Wrong node"}','GLOBAL','SECRET'),('2','{"GLOBAL":"示例节点"}','GLOBAL','SECRET')])
            result=n.flclash_selection(home)
            self.assertEqual(result['node_name'],'示例节点');self.assertEqual(result['source'],'flclash_saved_GLOBAL');self.assertFalse(result['runtime_verified'])
            self.assertNotIn('SECRET',json.dumps(result));self.assertNotIn('currentProfileId',result)
        self.assertIsNone(n.flclash_selection('/nonexistent-fixture')['node_name'])
        self.assertIsNone(n.clean_label('https://subscription.example/secret'))
        self.assertEqual(n.clean_label('\033[31mName\n'),'[31mName')

    def test_snapshot_is_partial_when_guest_unavailable_and_saved_files_are_private_unique(self):
        network=SimpleNamespace(inspect=Mock(return_value={'default_interface':'en0','wired_default':True,'wifi':[{'device':'en1','on':False}],'proxy_available':True,'password':'SECRET'}),success_conditions=Mock(return_value={'tun_route':True,'system_proxy':False}))
        with patch.object(n,'guest_snapshot',return_value={'status':'unavailable'}),patch.object(n,'flclash_selection',return_value={'node_name':None,'source':'unavailable','runtime_verified':False}):
            captured=n.capture(helper_fixture(),network)
        self.assertEqual(captured['guest']['status'],'unavailable');self.assertNotIn('SECRET',json.dumps(captured))
        with tempfile.TemporaryDirectory() as folder:
            path=Path(folder)/'settings.json';first=n.save(captured,path);before=first.read_bytes();second=n.save(captured,path)
            self.assertNotEqual(first,second);self.assertEqual(first.read_bytes(),before)
            self.assertEqual(first.stat().st_mode&0o777,0o600);self.assertFalse(path.exists())

    def test_menu_dispatch_keeps_existing_numbers_and_waits_for_return(self):
        with tempfile.TemporaryDirectory() as folder,patch.dict(os.environ,{'HD2FX_SETTINGS_FILE':str(Path(folder)/'settings.json')}),patch.object(menu,'select_option',side_effect=['5','6','0']) as choose,patch.object(menu,'save_successful_network') as save,patch.object(menu,'check_steam_connection') as check,patch('builtins.input',return_value='') as pause,contextlib.redirect_stdout(io.StringIO()):
            menu.network_menu()
        save.assert_called_once();check.assert_called_once();self.assertEqual(pause.call_count,2)
        self.assertEqual([key for key,_ in choose.call_args_list[0].args[1]],['1','2','3','4','5','6','0'])

    def test_steam_panel_fits_languages_and_does_not_treat_log_as_game_login(self):
        result={'status':'available','steam':n.summarize_steam(sample_guest())}
        old=menu.LANG
        try:
            for language in menu.i18n.CODES:
                menu.LANG=language
                for columns in [101,88,60,40]:
                    output=io.StringIO()
                    with self.subTest(language=language,columns=columns),patch.object(n,'guest_snapshot',return_value=result),patch.object(menu.shutil,'get_terminal_size',return_value=os.terminal_size((columns,30))),contextlib.redirect_stdout(output):
                        menu.check_steam_connection()
                    self.assertTrue(all(menu.width(line)<=columns for line in output.getvalue().splitlines()))
        finally:menu.LANG=old

    def test_terminal_size_request_is_only_for_interactive_apple_terminal(self):
        output=io.StringIO()
        with patch.object(menu.sys,'platform','darwin'),patch.dict(os.environ,{'TERM_PROGRAM':'Apple_Terminal'}),patch.object(menu.sys,'stdout',output),patch.object(output,'isatty',return_value=True):
            self.assertTrue(menu.configure_terminal_window())
        self.assertEqual(output.getvalue(),'\033[8;30;101t')
        for program,tty in [('Apple_Terminal',False),('iTerm.app',True),('',True)]:
            output=io.StringIO()
            with patch.object(menu.sys,'platform','darwin'),patch.dict(os.environ,{'TERM_PROGRAM':program}),patch.object(menu.sys,'stdout',output),patch.object(output,'isatty',return_value=tty):
                self.assertFalse(menu.configure_terminal_window())
            self.assertEqual(output.getvalue(),'')

    def test_requested_geometry_keeps_home_and_new_network_actions_visible(self):
        old=menu.LANG
        try:
            for code in menu.i18n.CODES:
                menu.LANG=code
                frame=menu.ui2.build_home(101,30,code,{'layout':'immersive','emblem':'2'},menu.home_labels(),{})
                self.assertEqual(len(frame.cells),30)
                self.assertTrue(all(menu.ui2.text_width(line)<=101 for line in frame.plain().splitlines()))
                options=[(str(i),str(i)+'. '+menu.i18n.text('network.'+key,code,state='ON')) for i,key in enumerate(['apply','inspect','restore','toggle','save_success','steam_check'],1)]
                options.append(('0',menu.i18n.text('language.back',code)))
                frame=menu.ui2.build_list(101,30,menu.i18n.text('network.title',code),options,5,language=code)
                self.assertEqual(set(frame.positions),set('1234560'))
                self.assertTrue(all(menu.ui2.text_width(line)<=101 for line in frame.plain().splitlines()))
        finally:menu.LANG=old


if __name__=='__main__':unittest.main()
