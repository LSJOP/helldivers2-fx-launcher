"""No real FX, Node, SSH, Guest or game execution. All launch targets are fixtures."""
import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest.mock import patch

APP = Path(__file__).resolve().parents[1]
def load(name, path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
ops_module=load('resource_checks_ops',APP/'bridge/legacy_operations.py')
core=load('resource_checks_core',APP/'bridge/core_adapter.py')
r=ops_module.launch_resources

class LaunchResourceChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='hd2-resource-check-');self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name).resolve();self.root=self.home/'runtime'
        self.ops=ops_module.Operations(APP/'CoreSnapshot',settings_file=self.home/'settings.json',data_dir=self.home/'data')
        for relative in r.REQUIRED:
            target=self.root/relative;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(APP/'CoreSnapshot'/relative,target)
        self.apps=[]
        for version in ('1.9.4','1.9.8'):
            app=self.home/('FX '+version+'.app');exe=app/'Contents/MacOS/steamac-vm';exe.parent.mkdir(parents=True)
            exe.write_bytes(('NEVER EXECUTE '+version).encode());exe.chmod(0o700)
            (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':version,'CFBundleExecutable':'steamac-vm','CFBundleIdentifier':'es.fxgam.steamac'}))
            self.apps.append(app)
    def signed(self):
        return patch.object(r.subprocess,'run',return_value=types.SimpleNamespace(returncode=0))
    def test_both_versions_and_switch_bind_exact_path(self):
        with self.signed() as signature:
            for app in [*self.apps,self.apps[0]]:
                helper=self.ops.runtime({'runtime_root':str(self.root),'fx_path':str(app)})
                self.assertEqual(helper.APP,str(app));self.assertEqual(helper.ROOT,self.root)
                self.assertEqual(helper.APP_EXECUTABLE_SHA256,hashlib.sha256((app/'Contents/MacOS/steamac-vm').read_bytes()).hexdigest())
                self.assertEqual(helper.NATIVE_FX_INTEGRITY['trust'],'fx_publisher_signature')
            self.assertTrue(all(call.args[0][0]=='/usr/bin/codesign' and call.args[0][-1] in list(map(str,self.apps)) for call in signature.call_args_list))
    def test_matching_resources_are_shared_with_inspection(self):
        adapter=core.CoreAdapter(APP/'CoreSnapshot/native-app-core-snapshot',app_dirs=[])
        value=adapter.launch_target(str(self.root),str(self.apps[0]))
        self.assertTrue(value['archive_files_match']);self.assertEqual(value['fx_path'],str(self.apps[0]))
        self.assertEqual(value['resource_files'],r.inspect_resources(self.root,self.ops.root)['resource_files'])
        self.assertEqual(value['launch'],'unverified')
    def test_explicit_empty_selection_never_uses_legacy_default(self):
        with patch.object(r.subprocess,'run',side_effect=AssertionError('Nothing may execute')):
            with self.assertRaises(ops_module.OperationError) as error:self.ops.runtime({'runtime_root':str(self.root),'fx_path':''})
        self.assertEqual(error.exception.code,'FX_UNAVAILABLE')
    def test_applications_is_not_a_runtime(self):
        folder=self.home/'Applications';folder.mkdir()
        with patch.object(r.subprocess,'run',side_effect=AssertionError('Nothing may execute')):
            with self.assertRaises(ops_module.OperationError) as error:self.ops.runtime({'runtime_root':str(folder),'fx_path':str(self.apps[0])})
        self.assertEqual(error.exception.code,'SOURCE_MISMATCH')
        self.assertTrue(all(row['state']=='missing' and str(folder) in row['actual_path'] for row in error.exception.details['resource_files']))
    def test_missing_resource_reports_exact_path_and_expected_hash(self):
        relative=r.REQUIRED[0];(self.root/relative).unlink()
        with self.assertRaises(ops_module.OperationError) as error:self.ops.runtime({'runtime_root':str(self.root)})
        row=error.exception.details['resource_files'][0]
        self.assertEqual(row['actual_path'],str(self.root/relative));self.assertIsNone(row['actual_sha256']);self.assertEqual(len(row['expected_sha256']),64)
    def test_hash_mismatch_refuses_before_import_or_process(self):
        target=self.root/r.REQUIRED[1];target.write_bytes(b'changed resource')
        with patch.object(r.subprocess,'run',side_effect=AssertionError('Nothing may execute')):
            with self.assertRaises(ops_module.OperationError) as error:self.ops.runtime({'runtime_root':str(self.root)})
        row=error.exception.details['resource_files'][1]
        self.assertEqual(row['state'],'hash_mismatch');self.assertNotEqual(row['actual_sha256'],row['expected_sha256']);self.assertEqual(target.read_bytes(),b'changed resource')
    def test_layout_change_has_explicit_missing_path(self):
        target=self.root/r.REQUIRED[0];target.rename(target.with_name('new-layout.mjs'))
        self.assertEqual(r.inspect_resources(self.root,self.ops.root)['resource_files'][0]['state'],'missing')
    def test_symlink_and_oversize_and_directory_are_refused(self):
        target=self.root/r.REQUIRED[0];target.unlink();target.symlink_to(self.ops.root/r.REQUIRED[0])
        self.assertEqual(r.inspect_resources(self.root,self.ops.root)['resource_files'][0]['state'],'unsafe_path')
        target.unlink();target.write_bytes(b'x'*(2*1024*1024+1))
        self.assertEqual(r.inspect_resources(self.root,self.ops.root)['resource_files'][0]['state'],'invalid_file')
        target.unlink();target.mkdir()
        self.assertEqual(r.inspect_resources(self.root,self.ops.root)['resource_files'][0]['state'],'invalid_file')
    def test_missing_archive_never_trusts_actual(self):
        value=r.inspect_resources(self.root,self.home/'no-archive')
        self.assertFalse(value['archive_files_match']);self.assertTrue(all(row['state']=='archive_missing' for row in value['resource_files']))
    def test_unsigned_or_wrong_publisher_refused(self):
        with patch.object(r.subprocess,'run',return_value=types.SimpleNamespace(returncode=1)):
            with self.assertRaises(ops_module.OperationError) as error:self.ops.runtime({'runtime_root':str(self.root),'fx_path':str(self.apps[0])})
        self.assertEqual(error.exception.code,'FX_PROFILE_MISMATCH');self.assertEqual(error.exception.details['state'],'signature_invalid')
    def test_signature_timeout_refused(self):
        with patch.object(r.subprocess,'run',side_effect=subprocess.TimeoutExpired('codesign',15)):
            self.assertEqual(r.fx_integrity(self.apps[0],'0'*64)['state'],'signature_unavailable')
    def test_signature_requirement_is_publisher_bound(self):
        with self.signed() as signature:r.fx_integrity(self.apps[0],'0'*64)
        command=signature.call_args.args[0]
        self.assertIn('-R='+r.FX_REQUIREMENT,command);self.assertIn('anchor apple generic',r.FX_REQUIREMENT);self.assertIn('V25VKGTW55',r.FX_REQUIREMENT);self.assertIn('es.fxgam.steamac',r.FX_REQUIREMENT)
    def test_historical_digest_remains_supported_without_signature_fallback(self):
        digest=hashlib.sha256((self.apps[0]/'Contents/MacOS/steamac-vm').read_bytes()).hexdigest()
        with patch.object(r.subprocess,'run',side_effect=AssertionError('Signature not needed for exact archive hash')):
            self.assertEqual(r.fx_integrity(self.apps[0],digest)['trust'],'pinned_archive')
    def test_modified_fx_after_validation_is_refused(self):
        with self.signed():helper=self.ops.runtime({'runtime_root':str(self.root),'fx_path':str(self.apps[0])})
        (self.apps[0]/'Contents/MacOS/steamac-vm').write_bytes(b'tampered')
        with self.signed(),self.assertRaises(ops_module.OperationError) as error:helper.verify_fx_profile()
        self.assertEqual(error.exception.code,'FX_PROFILE_MISMATCH')
    def test_profile_options_still_enforced_for_signed_fx(self):
        with self.signed():helper=self.ops.runtime({'runtime_root':str(self.root),'fx_path':str(self.apps[0])})
        home=self.home/'preferences';prefs=home/'Library/Preferences/es.fxgam.steamac.plist';prefs.parent.mkdir(parents=True);prefs.write_bytes(plistlib.dumps({'metalHUD':True,'superResolution':False}))
        with self.signed(),patch.object(Path,'home',return_value=home),self.assertRaisesRegex(RuntimeError,'Metal HUD'):helper.verify_fx_profile()
    def test_signature_validation_detects_concurrent_binary_change(self):
        def signature(*args,**kwargs):
            (self.apps[0]/'Contents/MacOS/steamac-vm').write_bytes(b'changed during signature check')
            return types.SimpleNamespace(returncode=0)
        with patch.object(r.subprocess,'run',side_effect=signature):self.assertEqual(r.fx_integrity(self.apps[0],'0'*64)['state'],'signature_invalid')

if __name__=='__main__':unittest.main(verbosity=2)
