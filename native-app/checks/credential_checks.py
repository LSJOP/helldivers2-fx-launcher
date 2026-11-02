"""Fictional credentials only. Never connects SSH or reads a real Keychain."""
from pathlib import Path
import importlib.util
import json
import tempfile
import os
import subprocess
import unittest
import types
from unittest.mock import patch
import zipfile

APP=Path(__file__).resolve().parents[1]
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
ops=load('security_ops',APP/'bridge/legacy_operations.py')
security=load('credential_redaction',APP/'bridge/credential_security.py')
scanner=load('release_secret_scan',APP/'script/check_release_secrets.py')

class CredentialChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.directory=Path(self.temp.name)
        self.ops=ops.Operations(APP/'CoreSnapshot',settings_file=self.directory/'settings.json',data_dir=self.directory/'data')
        self.fake='unit-'+'m'*24
    def test_keychain_hooks_disabled_even_with_legacy_remember_flag(self):
        prefs=self.ops.module('preferences')
        config=prefs.DEFAULTS.copy();config['ssh']=dict(config['ssh'],remember_password=True)
        client=prefs.SSHClient(config);client.password=self.fake
        with patch.object(prefs.keychain.Keychain,'get',side_effect=AssertionError('Keychain forbidden')),patch.object(prefs.keychain.Keychain,'put',side_effect=AssertionError('Keychain forbidden')),patch.object(prefs.keychain.Keychain,'delete',side_effect=AssertionError('delete forbidden')):
            self.assertIsNone(client._saved_password());self.assertIsNone(client._remember_authenticated_password())
            self.assertIsNone(prefs.VAULT.get(config))
            with self.assertRaises(RuntimeError):prefs.VAULT.delete(config)
        self.assertFalse((self.directory/'settings.json').exists())
    def test_redaction_all_secret_kinds_and_private_key(self):
        fake_key='-----BEGIN '+'PRIVATE KEY-----\n'+'A'*80+'\n-----END PRIVATE KEY-----'
        redactor=security.Redactor([self.fake])
        value=redactor.text(self.fake+'\nAuthorization: Bearer '+self.fake+'\n'+fake_key)
        self.assertNotIn(self.fake,value);self.assertNotIn('BEGIN PRIVATE',value)
        self.assertNotIn(self.fake,security.Redactor().text(json.dumps({'Authorization':'Bearer '+self.fake})))
    def test_credentials_rejected_before_runtime_if_revision_missing_or_stale(self):
        for revision in [None,'stale']:
            with patch.object(self.ops,'runtime',side_effect=AssertionError('must not connect')):
                with self.assertRaises(ops.OperationError) as error:self.ops.run('launch_game',{'confirmed':True,'password':self.fake,'credential_revision':revision})
            self.assertEqual(error.exception.code,'CREDENTIAL_SCOPE_CHANGED')
    def test_stdin_credentials_reach_only_prompt_callback_and_do_not_write_files(self):
        root=self.directory/'runtime'
        for relative in ['launcher-20261026/steam-cdp.mjs','tools/check_node.cjs','goal-fx-multiplayer-20261026/gvproxy-eim-wrapper']:
            target=root/relative;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((APP/'CoreSnapshot'/relative).read_bytes())
        revision=self.ops.read_config()[2]
        params=json.loads(json.dumps({'password':self.fake,'sudo_password':self.fake,'runtime_root':str(root),'credential_revision':revision}))
        self.ops.secret_values=[self.fake]
        with patch('subprocess.run',side_effect=AssertionError('no commands allowed')):helper=self.ops.runtime(params)
        self.assertEqual(helper.CLIENT.prompt_secret('SSH password: '),self.fake)
        self.assertEqual(helper.CLIENT.prompt_secret('Guest sudo password: '),self.fake)
        self.assertFalse((self.directory/'settings.json').exists());self.assertFalse((self.directory/'data').exists())
        (self.directory/'settings.json').write_text(json.dumps(self.ops.module('preferences').DEFAULTS))
        with self.assertRaises(ops.OperationError) as error:helper.refresh_settings()
        self.assertEqual(error.exception.code,'CREDENTIAL_SCOPE_CHANGED')
    def test_secret_configuration_is_not_backed_up_or_rewritten(self):
        config=self.ops.read_config()[0];config['custom']={'token':self.fake}
        path=self.directory/'settings.json';path.write_text(json.dumps(config));before=path.read_bytes()
        with self.assertRaises(ops.OperationError) as error:self.ops.run('save_configuration',{'confirmed':True,'expected_revision':self.ops.read_config()[2],'configuration':{}})
        self.assertEqual(error.exception.code,'SENSITIVE_CONFIGURATION');self.assertEqual(path.read_bytes(),before)
        self.assertEqual(list(self.directory.glob('settings.native-backup-*')),[])
    def test_release_scan_fake_secrets_and_safe_public_key(self):
        path=self.directory/'config.json';path.write_text(json.dumps({'password':self.fake}))
        scan=scanner.Scan();scan.path(path)
        self.assertEqual(scan.report()['status'],'SUSPECTED');self.assertNotIn(self.fake,json.dumps(scan.report()))
        path.write_text(json.dumps({'SUPublicEDKey':'A'*43+'='}));scan=scanner.Scan();scan.path(path)
        self.assertEqual(scan.report()['status'],'PASS')
    def test_release_archive_and_missing_input_statuses(self):
        path=self.directory/'fixture.zip'
        fake_key='-----BEGIN '+'OPENSSH PRIVATE KEY-----\n'+'A'*80+'\n-----END OPENSSH PRIVATE KEY-----'
        with zipfile.ZipFile(path,'w') as archive:archive.writestr('App/private.txt',fake_key)
        scan=scanner.Scan();scan.archive(path)
        self.assertEqual(scan.report()['status'],'SUSPECTED');self.assertNotIn('A'*80,json.dumps(scan.report()))
        scan=scanner.Scan();scan.path(self.directory/'missing')
        self.assertEqual(scan.report()['status'],'UNABLE')
    def test_manager_source_has_no_persistence_or_keychain_calls(self):
        source=(APP/'Services/SessionCredentialManager.swift').read_text()
        for forbidden in ['UserDefaults','AppStorage','SecItem','FileManager','KeychainAccess','Process(']:self.assertNotIn(forbidden,source)
    def test_source_prompt_labels_are_not_literal_password_assignments(self):
        self.assertEqual(scanner.rules(b"prompt('SSH password: ')",'prompts.py'),[])
        data=b'password = '+repr(self.fake).encode()
        self.assertIn('credential_assignment',scanner.rules(data,'settings.py'))
    def test_staged_scan_reads_index_not_cleaned_working_copy(self):
        directory=self.directory/'git';directory.mkdir()
        subprocess.run(['git','init','-q',str(directory)],check=True,stderr=subprocess.DEVNULL)
        path=directory/'config.json';path.write_text(json.dumps({'password':self.fake}))
        subprocess.run(['git','-C',str(directory),'add','config.json'],check=True)
        path.write_text('{}')
        previous=Path.cwd()
        try:
            os.chdir(directory);scan=scanner.Scan();scan.git(staged=True)
        finally:os.chdir(previous)
        self.assertEqual(scan.report()['status'],'SUSPECTED');self.assertNotIn(self.fake,json.dumps(scan.report()))
    def test_sudo_credentials_are_separate_from_ssh_password_and_restored_after_request(self):
        seen=[]
        helper=types.SimpleNamespace(CLIENT=types.SimpleNamespace(password=self.fake))
        helper.safety=types.SimpleNamespace(request=lambda h,data,sudo=False:seen.append(h.CLIENT.password))
        sudo=self.fake+'-sudo';security.bind_session_sudo(helper,{'sudo_password':sudo})
        helper.safety.request(helper,{},sudo=True)
        self.assertEqual(seen,[sudo]);self.assertEqual(helper.CLIENT.password,self.fake)

if __name__=='__main__':unittest.main(verbosity=2)
