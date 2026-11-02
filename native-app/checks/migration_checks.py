"""Targeted Core migration tests. All writes are temporary; no real network/game/Keychain."""
from pathlib import Path
import copy
import importlib.util
import json
import os
import tempfile
import types
import unittest
from unittest.mock import patch

APP=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('migration',APP/'bridge/legacy_operations.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class MigrationChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='hd2-migration-');self.addCleanup(self.temp.cleanup)
        self.directory=Path(self.temp.name)
        self.config=self.directory/'settings.json'
        self.events=[]
        self.ops=m.Operations(APP/'CoreSnapshot',settings_file=self.config,data_dir=self.directory/'data',emit=self.events.append)
    def test_catalog_and_ten_exact_languages_no_effects(self):
        with patch('subprocess.run',side_effect=AssertionError('process forbidden')),patch('socket.create_connection',side_effect=AssertionError('network forbidden')):
            value=self.ops.run('get_legacy_catalog',{})
        self.assertEqual([x['code'] for x in value['languages']],['zh-CN','en','ja','ko','ru','es','de','fr','pt-BR','zh-TW'])
        self.assertEqual(set(x['method'] for x in value['operations']),set(m.OPERATIONS))
        self.assertFalse(value['automatic_install'])
        self.assertEqual(list(self.directory.iterdir()),[])
    def test_writes_reject_missing_or_nonboolean_consent(self):
        for method,(_,writes,_) in m.OPERATIONS.items():
            if not writes:continue
            for params in [{},{'confirmed':1}]:
                with self.subTest(method=method,params=params),self.assertRaises(m.OperationError) as error:self.ops.run(method,params)
                self.assertEqual(error.exception.code,'CONFIRMATION_REQUIRED')
        self.assertEqual(list(self.directory.iterdir()),[])
    def test_configuration_backup_unknown_fields_and_mode(self):
        original=copy.deepcopy(self.ops.module('preferences').DEFAULTS)
        original['custom']={'retained':True};original['ssh']['future_field']='keep'
        self.config.write_text(json.dumps(original));before=self.config.read_bytes()
        read=self.ops.run('read_configuration',{})
        result=self.ops.run('save_configuration',{'confirmed':True,'expected_revision':read['revision'],'configuration':{'ssh':{'port':2223}}})
        saved=json.loads(self.config.read_text())
        self.assertEqual(saved['custom'],original['custom']);self.assertEqual(saved['ssh']['future_field'],'keep')
        self.assertEqual(saved['ssh']['port'],2223)
        self.assertEqual(Path(result['backup']).read_bytes(),before)
        self.assertEqual(self.config.stat().st_mode & 0o777,0o600)
    def test_stale_revision_does_not_overwrite(self):
        read=self.ops.run('read_configuration',{})
        current=copy.deepcopy(read['configuration']);current['ssh']['port']=2224
        self.config.write_text(json.dumps(current));before=self.config.read_bytes()
        with self.assertRaises(m.OperationError) as error:self.ops.run('save_configuration',{'confirmed':True,'expected_revision':read['revision'],'configuration':read['configuration']})
        self.assertEqual(error.exception.code,'CONFIG_CHANGED');self.assertEqual(self.config.read_bytes(),before)
    def test_replace_failure_preserves_original_and_backup(self):
        self.config.write_text(json.dumps(self.ops.module('preferences').DEFAULTS));before=self.config.read_bytes()
        read=self.ops.run('read_configuration',{})
        with patch.object(m.os,'replace',side_effect=OSError('fixture replace failure')):
            with self.assertRaises(OSError):self.ops.run('save_configuration',{'confirmed':True,'expected_revision':read['revision'],'configuration':read['configuration']})
        self.assertEqual(self.config.read_bytes(),before)
        self.assertEqual(len(list(self.directory.glob('settings.native-backup-*'))),1)
        self.assertEqual(list(self.directory.glob('.native-settings-*')),[])
    def test_unknown_new_fields_and_secrets_rejected(self):
        read=self.ops.run('read_configuration',{})
        for config in [{'ssh':{'password':'fixture-secret'}},{'shell':'touch unsafe'},{'version':True}]:
            with self.assertRaises((ValueError,m.OperationError)):
                self.ops.run('save_configuration',{'confirmed':True,'expected_revision':read['revision'],'configuration':config})
        self.assertFalse(self.config.exists())
    def test_symlink_configuration_rejected(self):
        target=self.directory/'other';target.write_text('{}');self.config.symlink_to(target)
        with self.assertRaises(m.OperationError) as error:self.ops.run('read_configuration',{})
        self.assertEqual(error.exception.code,'UNSAFE_PATH');self.assertEqual(target.read_text(),'{}')
    def test_launch_needs_explicit_runtime_and_cannot_execute_selected_python(self):
        with patch('subprocess.run',side_effect=AssertionError('unexpected process')):
            with self.assertRaises(m.OperationError) as error:self.ops.run('launch_game',{'confirmed':True})
        self.assertEqual(error.exception.code,'RUNTIME_ROOT_REQUIRED')
        root=self.directory/'runtime';root.mkdir()
        with self.assertRaises(m.OperationError) as error:self.ops.run('launch_game',{'confirmed':True,'runtime_root':str(root)})
        self.assertEqual(error.exception.code,'SOURCE_MISMATCH')
    def test_network_preserves_unknown_profile(self):
        profile=self.directory/'network-profile.json';profile.write_text('{"future_key":true}')
        for method in ['apply_network_profile','restore_network_profile','toggle_network_check']:
            with self.assertRaises(m.OperationError) as error:self.ops.run(method,{'confirmed':True})
            self.assertEqual(error.exception.code,'UNSUPPORTED_CONFIGURATION')
        self.assertEqual(profile.read_text(),'{"future_key":true}')
    def test_real_user_match_record_and_bounded_history(self):
        result=self.ops.run('record_match',{'confirmed':True,'match_result':'timeout','note':'password=fixture-secret'})
        self.assertEqual(result['source'],'user_reported')
        history=self.ops.run('read_network_history',{})
        self.assertNotIn('fixture-secret',json.dumps(history))
        self.assertEqual(history['records'][-1]['result'],'timeout')
    def test_safe_report_exports_only_local_evidence(self):
        result=self.ops.run('export_environment_report',{'confirmed':True})
        data=json.loads(Path(result['export']).read_text())
        self.assertEqual(data['runtime'],'unverified');self.assertEqual(data['scope'],'host_metadata_only')
        self.assertEqual(Path(result['export']).stat().st_mode & 0o777,0o600)
    def test_redaction_and_unknown_methods(self):
        self.ops.secret_values=['fixture-secret']
        self.assertNotIn('fixture-secret',self.ops.scrub('password=fixture-secret'))
        self.assertEqual(self.ops.scrub({'password':'fixture-secret','ok':True}),{'ok':True})
        with self.assertRaises(m.OperationError):self.ops.run('run_shell',{'confirmed':True})
    def test_performance_cancellation_restores_only_owned_values(self):
        values={'owned':1,'foreign':2};before=dict(values)
        def write(key,value):values[key]=value
        def apply(helper):
            profile.write_setting('owned',8);profile.write_setting('foreign',8)
            values['foreign']=99
            raise m.OperationError('CANCELLED')
        profile=types.SimpleNamespace(SETTINGS={'owned':8,'foreign':8},write_setting=write,read_setting=values.get,apply=apply)
        with self.assertRaises(m.OperationError):self.ops.apply_performance(profile,None,before)
        self.assertEqual(values,{'owned':1,'foreign':99})
        self.assertIs(profile.write_setting,write)
        self.assertTrue(any('concurrently' in x['message'] for x in self.events))
    def test_runtime_adapter_imports_bundled_core_and_native_diagnostics(self):
        root=self.directory/'runtime'
        for relative in ['launcher-20261026/steam-cdp.mjs','tools/check_node.cjs','goal-fx-multiplayer-20261026/gvproxy-eim-wrapper']:
            target=root/relative;target.parent.mkdir(parents=True,exist_ok=True)
            target.write_bytes((APP/'CoreSnapshot'/relative).read_bytes())
        with patch('subprocess.run',side_effect=AssertionError('process forbidden')):
            helper=self.ops.runtime({'runtime_root':str(root)})
        self.assertEqual(helper.ROOT,root.resolve())
        self.assertEqual(helper.diagnostics.Store().directory,self.directory/'data/diagnostics')
        self.assertFalse(self.config.exists())

if __name__=='__main__':unittest.main(verbosity=2)
