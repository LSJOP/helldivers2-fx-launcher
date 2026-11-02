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
    def gui_fixture(self, running=True):
        from unittest.mock import Mock
        from contextlib import nullcontext
        session=Mock()
        session.bind.return_value={'service':'stopped'}
        session.verify.return_value={'service':'running'}
        session.steam.return_value={'ok':True,'started':True}
        helper=types.SimpleNamespace(APP='/fixture/FX.app',GVPROXY_WRAPPER='/fixture/wrapper',
            SETTINGS={'ssh':{'host':'127.0.0.1','port':2222}},
            prefs=types.SimpleNamespace(local_host=lambda host:True),
            connect=Mock(),remote=Mock(),network_ready=lambda:True,verify_fx_profile=Mock(),
            subprocess=types.SimpleNamespace(run=Mock()),
            dependencies=types.SimpleNamespace(inspect_runtime=lambda h:{'ready':True}),
            safety=types.SimpleNamespace(Session=Mock(return_value=session),target_lock=lambda settings:nullcontext()))
        host={'fx_host_running':running,'ssh_connected':False}
        return helper,session,host
    def test_gui_connect_refuses_stopped_fx_before_ssh(self):
        helper,session,host=self.gui_fixture(False)
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(self.ops,'fx_host_state',return_value=host):
            with self.assertRaises(m.OperationError) as error:self.ops.run('connect_fx',{'confirmed':True})
        self.assertEqual(error.exception.code,'FX_NOT_RUNNING');helper.connect.assert_not_called()
        helper.subprocess.run.assert_not_called()
    def test_gui_connect_requires_identity_and_never_starts_apps(self):
        helper,session,host=self.gui_fixture()
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(self.ops,'fx_host_state',return_value=host),patch.object(self.ops,'check_fx_entry'):
            result=self.ops.run('connect_fx',{'confirmed':True})
            self.assertTrue(result['ssh_connected']);self.assertTrue(result['guest_ready'])
            session.bind.side_effect=RuntimeError('Guest identity changed')
            with self.assertRaises(m.OperationError):self.ops.run('connect_fx',{'confirmed':True})
        helper.connect.assert_called();helper.subprocess.run.assert_not_called();session.steam.assert_not_called()
    def test_gui_guest_read_preserves_negative_evidence_and_rechecks_identity(self):
        helper,session,host=self.gui_fixture()
        helper.remote.return_value=json.dumps({'components':{'game_executable':False},'steam_process_count':0})
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(self.ops,'fx_host_state',return_value=host),patch.object(self.ops,'check_fx_entry'):
            result=self.ops.run('inspect_guest_environment',{'confirmed':True})
            self.assertFalse(result['components']['game_executable']);self.assertEqual(result['steam_process_count'],0)
            session.verify.assert_called_once()
            session.verify.side_effect=RuntimeError('Guest replaced')
            with self.assertRaises(m.OperationError):self.ops.run('inspect_guest_environment',{'confirmed':True})
        helper.remote.assert_called_with(m.GUEST_ENVIRONMENT_READ,timeout=25)
        self.assertNotIn('sudo',m.GUEST_ENVIRONMENT_READ);self.assertNotIn('write_text',m.GUEST_ENVIRONMENT_READ)
        session.steam.assert_not_called()
    def test_gui_steam_reuses_controlled_core_and_does_not_launch_game(self):
        helper,session,host=self.gui_fixture()
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(self.ops,'fx_host_state',return_value=host),patch.object(self.ops,'check_fx_entry'):
            result=self.ops.run('start_steam',{'confirmed':True})
            self.assertTrue(result['steam_running']);session.steam.assert_called_once()
            session.verify.return_value={'service':'stopped'}
            with self.assertRaises(m.OperationError) as error:self.ops.run('start_steam',{'confirmed':True})
        self.assertEqual(error.exception.code,'STEAM_START_FAILED');helper.subprocess.run.assert_not_called()
    def test_gui_start_fx_preserves_original_entry_and_never_uses_ssh(self):
        helper,session,host=self.gui_fixture(False)
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(self.ops,'fx_host_state',side_effect=[host,host,dict(host,fx_host_running=True)]),patch.object(self.ops,'check_fx_entry'):
            result=self.ops.run('start_fx',{'confirmed':True})
        self.assertTrue(result['fx_host_running']);helper.connect.assert_not_called()
        helper.subprocess.run.assert_called_once_with(['open','/fixture/FX.app','--args','--no-wmtr','--vulkan-driver','kosmickrisp','--gvproxy','/fixture/wrapper','--ssh-port','2222','--cpus','8','--mem','8192','--cmdline','console=hvc0 loglevel=4 rootwait steamac.gpu_mib=6144','--perf-stats'],check=True,timeout=15)
    def test_gui_existing_fx_never_duplicate_starts_and_unavailable_actions_rejected(self):
        helper,session,host=self.gui_fixture()
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(self.ops,'fx_host_state',return_value=host),patch.object(self.ops,'check_fx_entry'):
            result=self.ops.run('start_fx',{'confirmed':True})
        self.assertTrue(result['already_running']);helper.subprocess.run.assert_not_called()
        for method,params in [('stop_fx',{}),('restart_fx',{}),('connect_fx',{'confirmed':True,'command':'id'})]:
            with self.assertRaises(m.OperationError):self.ops.run(method,params)
    def test_guest_sudo_refusal_is_not_component_incompatibility(self):
        from types import SimpleNamespace
        class NotWrittenError(RuntimeError): pass
        helper=SimpleNamespace(APP=str(self.directory/'FX.app'),safety=SimpleNamespace(NotWrittenError=NotWrittenError))
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(self.ops,'check_fx_entry',side_effect=NotWrittenError('Guest sudo authorization failed; no configuration was written')):
            with self.assertRaises(m.OperationError) as failure:self.ops.run('launch_game',{'confirmed':True})
        self.assertEqual(failure.exception.code,'SUDO_AUTH_FAILED')
        self.assertIn('no configuration was written',failure.exception.details['summary'])
        self.assertFalse(self.config.exists())
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
    def fake_launch_helper(self, fail=None, game=True, invalid_fx=False):
        rows=[{'id':'fx','state':'invalid' if invalid_fx else 'ready'}]
        helper=types.SimpleNamespace(APP=str(self.directory/'FX.app'))
        helper.dependencies=types.SimpleNamespace(inspect_runtime=lambda h:{'items':rows,'ready':not invalid_fx},launcher_problems=lambda:[])
        helper.verify_fx_profile=lambda:None
        helper.wait_for_game=lambda:None
        helper.state=lambda:{'game_pids':[123] if game else [],'steam_pids':[456],'verified_network':True}
        helper.network_ready=lambda:True
        helper.safety=types.SimpleNamespace(Session=lambda h:types.SimpleNamespace(bind=lambda:None),output=lambda args:'fixture',process_table=lambda text:{10:(1,'fixture',str(Path(helper.APP)/'Contents/MacOS/steamac-vm'))})
        def main():
            helper.PROGRESS_HOOK('fx','done');helper.PROGRESS_HOOK('ssh','running')
            if fail:raise fail
            helper.PROGRESS_HOOK('ssh','done');helper.PROGRESS_HOOK('steam','done')
            helper.PROGRESS_HOOK('game','running');helper.wait_for_game();helper.PROGRESS_HOOK('game','done')
            helper.PROGRESS_HOOK('eac','unverified');helper.run_post_launch_checks()
        helper.main=main
        return helper
    def test_launch_reuses_main_and_streams_real_callback_states_without_gameplay_inference(self):
        helper=self.fake_launch_helper()
        with patch.object(self.ops,'runtime',return_value=helper):result=self.ops.run('launch_game',{'confirmed':True})
        self.assertTrue(result['game_process_detected']);self.assertEqual(result['main_menu'],'unverified');self.assertEqual(result['single_player'],'unverified')
        stages=[x.get('stage') for x in self.events]
        self.assertIn('WaitingForGame',stages);self.assertIn('GameProcessDetected',stages)
        self.assertEqual(result['multiplayer'],'not_requested')
    def test_launch_classifies_ssh_failure_and_redacts_detail(self):
        helper=self.fake_launch_helper(fail=RuntimeError('password=fixture-secret'))
        with patch.object(self.ops,'runtime',return_value=helper),self.assertRaises(m.OperationError) as error:self.ops.run('launch_game',{'confirmed':True})
        self.assertEqual(error.exception.code,'SSH_CONNECTION_FAILED');self.assertEqual(error.exception.details['stage'],'WaitingForGuest')
        self.assertNotIn('fixture-secret',json.dumps(error.exception.details))
    def test_launch_preflight_rejects_changed_fx_without_starting(self):
        helper=self.fake_launch_helper(invalid_fx=True)
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(helper,'main',side_effect=AssertionError('must not launch')):
            with self.assertRaises(m.OperationError) as error:self.ops.run('launch_game',{'confirmed':True})
        self.assertEqual(error.exception.code,'FX_UNAVAILABLE')
    def test_preflight_never_starts_guest_or_claims_guest_ready(self):
        helper=self.fake_launch_helper()
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(helper,'main',side_effect=AssertionError('must not launch')):
            result=self.ops.run('preflight_launch',{})
        self.assertTrue(result['host_ready']);self.assertEqual(result['guest'],'unverified')
    def test_game_exit_at_final_observation_is_not_success(self):
        helper=self.fake_launch_helper(game=False)
        with patch.object(self.ops,'runtime',return_value=helper),self.assertRaises(m.OperationError) as error:self.ops.run('launch_game',{'confirmed':True})
        self.assertEqual(error.exception.code,'GAME_EXITED')
    def test_configuration_confirmation_preserved(self):
        helper=self.fake_launch_helper(fail=m.OperationError('CHANGE_CONFIRMATION_REQUIRED',{'change':{'kind':'fixture'}}))
        with patch.object(self.ops,'runtime',return_value=helper),self.assertRaises(m.OperationError) as error:self.ops.run('launch_game',{'confirmed':True})
        self.assertEqual(error.exception.details['change'],{'kind':'fixture'})
    def test_observation_requires_target_identity_and_never_invokes_launcher(self):
        helper=self.fake_launch_helper()
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(helper,'main',side_effect=AssertionError('must not launch')):
            value=self.ops.run('observe_launch',{'confirmed':True})
        self.assertTrue(value['game_process_detected']);self.assertEqual(value['main_menu'],'unverified')
    def test_supervisor_vm_topology_retains_raw_child_identity(self):
        app='/fixture/FX.app/Contents/MacOS/steamac-vm'
        rows={10:(1,'start',app),11:(10,'start',app),12:(10,'start','/bin/sh'),13:(12,'start','/fixture/gvproxy')}
        view,proof=m.fx_process_view(rows,app)
        self.assertEqual([pid for pid,row in view.items() if row[2]==app],[10])
        self.assertEqual(view[12],rows[12]);self.assertEqual(proof,[(11,rows[11])]);self.assertEqual(rows[11][2],app)
        replaced=dict(rows);replaced[11]=(10,'new-start',app)
        self.assertNotEqual(m.fx_process_view(replaced,app)[1],proof)
    def test_ambiguous_or_multiple_vm_topology_fails_closed(self):
        app='/fixture/fx'
        for rows in [{},{1:(0,'s',app),2:(0,'s',app)}, {1:(2,'s',app),2:(1,'s',app)}, {1:(0,'s',app),2:(1,'s',app),3:(1,'s',app)}]:
            with self.assertRaises(m.OperationError):m.fx_process_view(rows,app)
    def test_foreign_fx_is_rejected_before_ssh_or_vm_start(self):
        helper=self.fake_launch_helper()
        helper.safety.process_table=lambda text:{20:(1,'fixture','/Applications/Other FX.app/Contents/MacOS/steamac-vm')}
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(helper,'main',side_effect=AssertionError('must not start')):
            with self.assertRaises(m.OperationError) as error:self.ops.run('launch_game',{'confirmed':True})
        self.assertEqual(error.exception.code,'FX_INSTANCE_MISMATCH');self.assertEqual(error.exception.details['stage'],'CheckingFXEntry')
        self.assertEqual(error.exception.details['running_apps'],['Other FX.app'])
    def test_host_fx_done_requires_selected_process_and_expected_transport(self):
        helper=self.fake_launch_helper();helper.network_ready=lambda:False
        with patch.object(self.ops,'runtime',return_value=helper),self.assertRaises(m.OperationError) as error:self.ops.run('launch_game',{'confirmed':True})
        self.assertEqual(error.exception.code,'FX_ENTRY_MISMATCH')
        self.assertFalse(any(x.get('stage')=='StartingFX' and x.get('status')=='done' for x in self.events))
    def test_legacy_negative_transport_result_is_not_overridden_by_a_later_positive_probe(self):
        helper=self.fake_launch_helper();helper.state=lambda:{'game_pids':[123],'verified_network':False}
        with patch.object(self.ops,'runtime',return_value=helper),self.assertRaises(m.OperationError) as error:self.ops.run('launch_game',{'confirmed':True})
        self.assertEqual(error.exception.code,'FX_ENTRY_MISMATCH')
        self.assertEqual(error.exception.details['source'],'legacy state().verified_network')

if __name__=='__main__':unittest.main(verbosity=2)
