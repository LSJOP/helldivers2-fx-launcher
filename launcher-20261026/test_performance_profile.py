import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock,patch

spec=importlib.util.spec_from_file_location('performance_profile_test',Path(__file__).with_name('performance_profile.py'))
profile=importlib.util.module_from_spec(spec);spec.loader.exec_module(profile)


class PerformanceProfileTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory();self.root=Path(self.folder.name)
        app=self.root/'FX.app';exe=app/'Contents/MacOS/steamac-vm';exe.parent.mkdir(parents=True);exe.write_bytes(b'verified-executable')
        self.helper=SimpleNamespace(ROOT=self.root,APP=str(app),APP_EXECUTABLE_SHA256=hashlib.sha256(exe.read_bytes()).hexdigest(),WORKING_LAUNCH='verified launch',SETTINGS={'ssh':{'host':'127.0.0.1'}},prefs=SimpleNamespace(local_host=lambda host:host=='127.0.0.1'),refresh_settings=Mock(),vm_reachable=Mock(return_value=True),connect=Mock(),state=Mock(side_effect=[{'game_pids':[],'apps':[]},{'launch':'verified launch'}]),verify_fx_profile=Mock(),main=Mock(),remote=Mock(return_value=json.dumps({'memory_kib':8108356,'online':'0-7','cmdline':'steamac.gpu_mib=6144'})))
        self.values={'cpus':0,'memMiB':0,'vulkanDriver':'moltenvk','metalHUD':False,'superResolution':False}
        self.before=dict(self.values)

    def tearDown(self):self.folder.cleanup()

    def write(self,key,value):
        if value is None:self.values.pop(key,None)
        else:self.values[key]=value

    def apply(self,driver=True):
        with patch.object(profile,'processes',return_value={'running':True,'foreign':False}),patch.object(profile,'read_setting',side_effect=lambda key:self.values.get(key)),patch.object(profile,'write_setting',side_effect=self.write),patch.object(profile,'runtime_driver_ready',return_value=driver):
            return profile.apply(self.helper)

    def test_success_backs_up_only_profile_keys_before_configuring_steam(self):
        self.helper.main.side_effect=lambda **kwargs:self.assertEqual(self.values,profile.SETTINGS)
        result=self.apply()
        self.assertFalse(result['restart_required'])
        self.assertEqual(self.values,profile.SETTINGS)
        self.helper.main.assert_called_once_with(configure_only=True)
        receipt=json.loads(result['backup'].read_text())
        self.assertEqual(receipt['before'],self.before)
        self.assertEqual(set(receipt['before']),set(profile.SETTINGS))
        self.assertEqual(result['backup'].stat().st_mode&0o777,0o600)
        self.assertFalse(receipt['vm_stopped']);self.assertFalse(receipt['runtime_monitor_enabled'])
        self.assertEqual(receipt['status'],'applied')

    def test_busy_game_or_installation_is_rejected_before_any_preferences_or_backup(self):
        for games,apps in [(['123'],['553850']),([],['553850']),([],['42'])]:
            self.helper.state=Mock(return_value={'game_pids':games,'apps':apps})
            with self.subTest(games=games,apps=apps),patch.object(profile,'processes',return_value={'running':True,'foreign':False}),patch.object(profile,'read_setting') as read,patch.object(profile,'write_setting') as write:
                with self.assertRaises(profile.ProfileError) as caught:profile.apply(self.helper)
                self.assertEqual(caught.exception.code,'busy');read.assert_not_called();write.assert_not_called()
                self.assertFalse((self.root/'launcher-20261026/backups').exists())
        self.helper.main.assert_not_called()

    def test_foreign_fx_is_not_changed_or_restarted(self):
        with patch.object(profile,'processes',return_value={'running':False,'foreign':True}),patch.object(profile,'write_setting') as write:
            with self.assertRaises(profile.ProfileError) as caught:profile.apply(self.helper)
            self.assertEqual(caught.exception.code,'foreign_fx');write.assert_not_called()
        self.helper.connect.assert_not_called();self.helper.main.assert_not_called()

    def test_unreachable_running_fx_is_not_treated_as_idle(self):
        self.helper.vm_reachable.return_value=False
        with patch.object(profile,'processes',return_value={'running':True,'foreign':False}),patch.object(profile,'write_setting') as write:
            with self.assertRaises(profile.ProfileError) as caught:profile.apply(self.helper)
            self.assertEqual(caught.exception.code,'not_ready');write.assert_not_called()

    def test_changed_executable_is_rejected_before_preferences(self):
        self.helper.APP_EXECUTABLE_SHA256='0'*64
        with patch.object(profile,'processes',return_value={'running':True,'foreign':False}),patch.object(profile,'write_setting') as write:
            with self.assertRaises(profile.ProfileError) as caught:profile.apply(self.helper)
            self.assertEqual(caught.exception.code,'app_changed');write.assert_not_called()

    def test_preference_failure_restores_already_attempted_keys_and_never_configures_steam(self):
        self.values['metalHUD']=True;self.before=dict(self.values)
        def fail_once(key,value):
            if key=='metalHUD' and value is False:raise profile.ProfileError('preferences')
            self.write(key,value)
        with patch.object(profile,'processes',return_value={'running':True,'foreign':False}),patch.object(profile,'read_setting',side_effect=lambda key:self.values.get(key)),patch.object(profile,'write_setting',side_effect=fail_once):
            with self.assertRaises(profile.ProfileError):profile.apply(self.helper)
        self.assertEqual(self.values,self.before);self.helper.main.assert_not_called()
        receipt=json.loads(next((self.root/'launcher-20261026/backups').glob('*.json')).read_text())
        self.assertEqual(receipt['status'],'preferences_failed');self.assertEqual(receipt['rollback_failed_keys'],[])

    def test_different_live_memory_cpu_or_driver_reports_restart_without_signalling(self):
        for memory,online,driver in [(12000000,'0-7',True),(8108356,'0-4',True),(8108356,'0-7',False)]:
            self.helper.state=Mock(side_effect=[{'game_pids':[],'apps':[]},{'launch':'verified launch'}])
            self.helper.remote.return_value=json.dumps({'memory_kib':memory,'online':online,'cmdline':'steamac.gpu_mib=6144'})
            with self.subTest(memory=memory,online=online,driver=driver),patch.object(profile.os,'kill') as kill:
                result=self.apply(driver);self.assertTrue(result['restart_required']);kill.assert_not_called()

    def test_unconfirmed_steam_options_never_report_applied(self):
        self.helper.state=Mock(side_effect=[{'game_pids':[],'apps':[]},{'launch':'different'}])
        with self.assertRaises(profile.ProfileError) as caught:self.apply()
        self.assertEqual(caught.exception.code,'launch_unverified')
        receipt=json.loads(next((self.root/'launcher-20261026/backups').glob('*.json')).read_text())
        self.assertEqual(receipt['status'],'preferences_saved')

    def test_changed_live_graphics_settings_require_normal_restart(self):
        self.values['superResolution']=True
        result=self.apply()
        self.assertTrue(result['restart_required'])

    def test_defaults_preserve_types_and_missing_keys(self):
        import subprocess
        for key,raw,expected in [('cpus','8\n',8),('metalHUD','0\n',False),('superResolution','true\n',True),('vulkanDriver','kosmickrisp\n','kosmickrisp')]:
            with self.subTest(key=key),patch.object(profile.subprocess,'run',return_value=subprocess.CompletedProcess([],0,raw,'')):
                self.assertEqual(profile.read_setting(key),expected)
        for error in ['The domain/default pair does not exist',"Error: Could not find key 'cpus' in domain 'es.fxgam.steamac'.","Error: Domain 'es.fxgam.profile-test' not found.\n"]:
            with self.subTest(error=error),patch.object(profile.subprocess,'run',return_value=subprocess.CompletedProcess([],1,'',error)):
                self.assertIsNone(profile.read_setting('cpus'))


if __name__=='__main__':unittest.main()
