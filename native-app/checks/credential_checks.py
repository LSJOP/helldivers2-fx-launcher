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
    def test_manager_has_no_plaintext_storage_and_keychain_is_opt_in(self):
        source=(APP/'Services/SessionCredentialManager.swift').read_text()
        for forbidden in ['AppStorage','FileManager','Process(']:self.assertNotIn(forbidden,source)
        self.assertIn('kSecUseAuthenticationUIFail',source)
        self.assertIn('guard remembers(kind) else { return }',source)
        self.assertNotIn('preferences.set(password',source)
        self.assertNotIn('preferences.set(sudoPassword',source)
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

    def sudo_fixture(self, mutation_exit=0):
        safety=load('fixture_archived_safety',APP/'CoreSnapshot/launcher-20261026/launch_safety.py')
        safety.guest_code=lambda data:'print("fixture transaction")'
        calls=[]
        def run(args,**kwargs):
            calls.append((args,kwargs))
            command=args[-1]
            if command=='sudo -n -v':return subprocess.CompletedProcess(args,1,'','sudo: a password is required')
            if command=='sudo -S -p "" -v':
                self.assertEqual(kwargs['input'],self.fake+'\n')
                return subprocess.CompletedProcess(args,0,'','')
            # Model the Guest policy: an independent SSH exec has no cached sudo.
            if command.startswith('sudo -n python3 -c '):return subprocess.CompletedProcess(args,1,'','sudo: a password is required')
            self.assertTrue(command.startswith('sudo -S -p "" python3 -c '))
            self.assertEqual(kwargs['input'],self.fake+'\n')
            return subprocess.CompletedProcess(args,mutation_exit,'{"ok":true}',('fixture transaction failure '+self.fake) if mutation_exit else '')
        h=types.SimpleNamespace(CLIENT=types.SimpleNamespace(password='fixture-ssh-only'),SSH=['fixture-ssh','fixture-host'],subprocess=types.SimpleNamespace(run=run),safety=safety)
        return h,calls
    def test_sudo_credential_reaches_exactly_one_mutation_without_argv_or_environment(self):
        h,calls=self.sudo_fixture()
        security.bind_session_sudo(h,{'sudo_password':self.fake})
        self.assertEqual(h.safety.request(h,{'action':'ipv6'},sudo=True),{'ok':True})
        self.assertEqual(len(calls),3)
        self.assertEqual(sum('python3 -c' in args[-1] for args,kwargs in calls),1)
        for args,kwargs in calls:
            self.assertNotIn(self.fake,repr(args));self.assertNotIn('env',kwargs)
        self.assertEqual(h.CLIENT.password,'fixture-ssh-only')
    def test_sudo_failed_mutation_is_not_retried_or_reported_as_unwritten(self):
        h,calls=self.sudo_fixture(mutation_exit=1)
        security.bind_session_sudo(h,{'sudo_password':self.fake})
        with self.assertRaises(security.GuestTransactionFailure) as error:h.safety.request(h,{'action':'ipv6'},sudo=True)
        self.assertEqual(len(calls),3)
        self.assertIn('outcome unverified',str(error.exception))
        self.assertNotIn(self.fake,str(error.exception));self.assertEqual(h.CLIENT.password,'fixture-ssh-only')

    def test_sudo_mutation_timeout_is_never_retried_and_clears_temporary_role(self):
        h,calls=self.sudo_fixture()
        original_run=h.subprocess.run
        def run(args,**kwargs):
            value=original_run(args,**kwargs)
            if 'python3 -c' in args[-1]:raise subprocess.TimeoutExpired(args,45)
            return value
        h.subprocess.run=run
        security.bind_session_sudo(h,{'sudo_password':self.fake})
        with self.assertRaises(subprocess.TimeoutExpired):h.safety.request(h,{'action':'ipv6'},sudo=True)
        self.assertEqual(len(calls),3);self.assertEqual(h.CLIENT.password,'fixture-ssh-only')

    def test_sudo_auth_proof_requires_password_prompt_not_just_success(self):
        for prompted in (False,True):
            h,calls=self.sudo_fixture()
            original_run=h.subprocess.run
            def run(args,**kwargs):
                # Use the preserved validation barrier; both successes are real
                # outcomes in the fixture, but only a prompt proves password use.
                command=args[-1]
                if command=='sudo -n -v':return subprocess.CompletedProcess(args,1,'','')
                stderr='[HD2_NATIVE_SUDO_AUTH]' if prompted else ''
                return subprocess.CompletedProcess(args,0,'{"ok":true}',stderr)
            h.subprocess.run=run
            proof=[];security.bind_session_sudo(h,{'sudo_password':self.fake},proof.append)
            self.assertEqual(h.safety.request(h,{'action':'ipv6'},sudo=True),{'ok':True})
            self.assertEqual(bool(proof),prompted)

    def test_passwordless_sudo_check_never_prompts_or_mutates(self):
        calls=[];events=[];self.ops.emit=events.append
        helper=types.SimpleNamespace(CLIENT=types.SimpleNamespace(connect_once=lambda:None),SSH=['fixture-ssh'],safety=types.SimpleNamespace(Session=lambda h:types.SimpleNamespace(bind=lambda:{})),subprocess=types.SimpleNamespace(run=lambda args,**kwargs:(calls.append((args,kwargs)) or subprocess.CompletedProcess(args,0,'',''))))
        with patch.object(self.ops,'runtime',return_value=helper),patch.object(self.ops,'check_fx_entry'):
            result=self.ops.run('test_guest_sudo',{'confirmed':True})
        self.assertEqual(result['configuration_changed'],False);self.assertEqual(result['password_verified'],False)
        self.assertEqual(len(calls),1);self.assertEqual(calls[0][0][-1],'sudo -n -v');self.assertNotIn('input',calls[0][1])
        self.assertFalse(any(row.get('kind')=='credential_status' for row in events))
    def test_cached_ssh_master_is_not_password_verification_proof(self):
        prefs=self.ops.module('preferences');proof=[]
        security.session_only(prefs,proof.append)
        client=prefs.SSHClient(prefs.DEFAULTS)
        client.password=self.fake
        with patch.object(prefs.subprocess,'run',return_value=subprocess.CompletedProcess([],0,b'',b'')):
            client.connect_once()
        self.assertEqual(proof,[])
        client._remember_authenticated_password()
        self.assertEqual(proof,['ssh'])

if __name__=='__main__':unittest.main(verbosity=2)
