"""Temporary plist/domain tests only; never access the real FX preference domain."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import plistlib
import tempfile
import unittest
from unittest.mock import patch
import uuid

APP=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('performance_under_test',APP/'bridge/performance_configuration.py')
p=importlib.util.module_from_spec(spec);spec.loader.exec_module(p)

class Store:
    def __init__(self, path, values):
        self.path=path;self.path.write_bytes(plistlib.dumps(values));self.fail=False;self.fail_after=False;self.corrupt=False;self.external=False;self.calls=0
    def read(self):return plistlib.loads(self.path.read_bytes())
    def write(self, values):
        self.calls+=1
        if self.fail:raise OSError('fixture write failure')
        data=self.read()
        for k,v in values.items():
            if v is None:data.pop(k,None)
            else:data[k]=v
        if self.external:data['unrelated']='external'
        self.path.write_bytes(plistlib.dumps(data))
        if self.fail_after:
            self.fail_after=False
            raise OSError('fixture response failure after write')

class Checks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name).resolve()
        self.values=dict(cpus=8,memMiB=8192,vulkanDriver='kosmickrisp',metalHUD=False,superResolution=False)
        self.rules=dict(version='1.9.4',cpu_min=1,cpu_max=12,memory_min=4096,memory_max=12288,memory_step=256,drivers=['moltenvk','kosmickrisp'],writable=['cpus','memMiB','vulkanDriver','metalHUD'])
        self.store=Store(self.root/'preferences.plist',dict(self.values,unrelated='keep',password='fixture-only-do-not-back-up'))
        self.manager=p.Manager(self.store,self.root/'backups',lambda:None,self.rules)
        self.edited=dict(self.values,cpus=6,memMiB=8448,vulkanDriver='moltenvk',metalHUD=True)
    def tearDown(self):self.temp.cleanup()
    def preview(self):return self.manager.preview(self.edited,self.manager.snapshot()['revision'])
    def apply(self):
        v=self.preview();return self.manager.commit(self.edited,v['plan']['revision'],v['token'])
    def test_read_and_parse(self):self.assertEqual(self.manager.snapshot()['current'],self.values)
    def test_invalid_type_and_ranges(self):
        for key,value in [('cpus',True),('cpus',0),('cpus',256),('memMiB',256),('memMiB',9000),('memMiB',32768),('metalHUD','true')]:
            with self.subTest(key=key,value=value),self.assertRaises(p.ConfigurationError):self.manager.validate(dict(self.values,**{key:value}))
    def test_unknown_parameter(self):
        with self.assertRaises(p.ConfigurationError):self.manager.validate(dict(self.values,unknown=1))
    def test_unknown_driver(self):
        with self.assertRaises(p.ConfigurationError):self.manager.validate(dict(self.values,vulkanDriver='fiction'))
    def test_super_resolution_read_only(self):
        with self.assertRaises(p.ConfigurationError):self.manager.preview(dict(self.values,superResolution=True),self.manager.snapshot()['revision'])
    def test_diff_and_no_write_on_preview_cancel(self):
        before=self.store.path.read_bytes();v=self.preview()
        self.assertEqual(set(v['changes']),{'cpus','memMiB','vulkanDriver','metalHUD'});self.assertEqual(self.store.path.read_bytes(),before)
        self.assertFalse((self.root/'backups').exists())
    def test_apply_backup_preserve_unknown_verify(self):
        r=self.apply();self.assertEqual(r['current'],self.edited);self.assertEqual(self.store.read()['unrelated'],'keep')
        self.assertTrue(r['can_restore']);self.assertEqual(r['effective'],'unverified')
        backup=self.manager.receipt();self.assertEqual(backup['before'],self.values)
        for file in (self.root/'backups').glob('*.json'):
            self.assertNotIn('fixture-only-do-not-back-up',file.read_text());self.assertEqual(file.stat().st_mode&0o777,0o600)
    def test_preview_conflict(self):
        v=self.preview();data=self.store.read();data['unrelated']='changed';self.store.path.write_bytes(plistlib.dumps(data))
        with self.assertRaises(p.ConfigurationError):self.manager.commit(self.edited,v['plan']['revision'],v['token'])
        self.assertEqual(self.store.calls,0)
    def test_token_conflict(self):
        v=self.preview()
        with self.assertRaises(p.ConfigurationError):self.manager.commit(self.edited,v['plan']['revision'],'invalid')
        self.assertEqual(self.store.calls,0)
    def test_backup_failure_prevents_write(self):
        v=self.preview()
        with patch.object(self.manager,'save',side_effect=OSError('backup')),self.assertRaises(OSError):self.manager.commit(self.edited,v['plan']['revision'],v['token'])
        self.assertEqual(self.store.calls,0)
    def test_write_failure(self):
        self.store.fail=True
        with self.assertRaises(OSError):self.apply()
        self.assertEqual(self.store.read()['cpus'],8)
    def test_owned_failure_rolls_back(self):
        self.store.fail_after=True
        with self.assertRaises(OSError):self.apply()
        self.assertEqual(p.selected(self.store.read()),self.values);self.assertEqual(self.store.calls,2)
    def test_external_modification_never_rolled_back(self):
        self.store.external=True
        with self.assertRaises(p.ConfigurationError):self.apply()
        self.assertEqual(self.store.read()['unrelated'],'external');self.assertEqual(self.store.calls,1)
    def test_restore_real_backup(self):
        r=self.apply();v=self.manager.preview(None,r['revision'],True)
        restored=self.manager.commit(None,r['revision'],v['token'],True)
        self.assertEqual(restored['current'],self.values);self.assertFalse(restored['can_restore'])
    def test_restore_external_conflict(self):
        r=self.apply();data=self.store.read();data['unrelated']='external';self.store.path.write_bytes(plistlib.dumps(data))
        with self.assertRaises(p.ConfigurationError):self.manager.preview(None,r['revision'],True)
    def test_corrupt_backup(self):
        self.apply();path=self.root/'backups/last.json';data=json.loads(path.read_text());data['body']['before']['cpus']=1;path.write_text(json.dumps(data))
        with self.assertRaises(p.ConfigurationError):self.manager.receipt()
        self.assertFalse(self.manager.snapshot()['can_restore'])
    def test_restore_failure(self):
        r=self.apply();v=self.manager.preview(None,r['revision'],True);self.store.fail=True
        with self.assertRaises(OSError):self.manager.commit(None,r['revision'],v['token'],True)
        self.assertEqual(p.selected(self.store.read()),self.edited)
    def test_unknown_version(self):
        self.rules['version']='9.0'
        with self.assertRaises(p.ConfigurationError):self.preview()
    def test_running_or_unknown_state(self):
        for code in ['PERF_RUNNING','PERF_STATE_UNKNOWN']:
            self.manager.probe=lambda:(_ for _ in ()).throw(p.ConfigurationError(code))
            with self.assertRaises(p.ConfigurationError):self.preview()
        self.assertEqual(self.store.calls,0)
    def test_process_detection(self):
        import types
        for text in ['/Applications/Other.app/Contents/MacOS/steamac-vm\n','/usr/bin/gvproxy\n','']:
            with patch.object(p.subprocess,'run',return_value=types.SimpleNamespace(stdout=text)),self.assertRaises(p.ConfigurationError):p.stopped()
    def test_missing_or_malformed_configuration(self):
        self.store.path.write_bytes(b'invalid')
        with self.assertRaises(plistlib.InvalidFileException):self.manager.snapshot()
        self.store.path.unlink()
        with self.assertRaises(FileNotFoundError):self.manager.snapshot()
    def test_lock_conflict(self):
        with self.manager.locked(),self.assertRaises(p.ConfigurationError):self.apply()
    def test_events_follow_actual_writes(self):
        v=self.preview();events=[];self.manager.commit(self.edited,v['plan']['revision'],v['token'],emit=events.append)
        self.assertEqual(events,['backing_up','applying','waiting_restart'])
    def test_locale_coverage(self):
        import re
        locales=json.loads((APP/'bridge/native-locales.json').read_text())
        keys=set(re.findall(r'\bl\("([^"\n]+)"\)',(APP/'Views/GamePerformanceView.swift').read_text()))
        for code in ['zh-CN','en','ja','ko','ru','es','de','fr','pt-BR','zh-TW']:
            self.assertTrue(keys<=set(locales[code]),(code,keys-set(locales[code])))
            if code!='en':self.assertTrue(all(locales[code][k]!=k for k in keys))
    def test_bridge_operation_fixture_roundtrip_and_consent(self):
        import types
        spec=importlib.util.spec_from_file_location('performance_operations_under_test',APP/'bridge/legacy_operations.py')
        legacy=importlib.util.module_from_spec(spec);spec.loader.exec_module(legacy)
        ops=legacy.Operations(APP/'CoreSnapshot',data_dir=self.root/'native')
        with patch.object(ops,'runtime',return_value=types.SimpleNamespace(APP='/fixture/FX.app')), \
             patch.object(legacy.performance_configuration,'capabilities',return_value=self.rules), \
             patch.object(legacy.performance_configuration,'Preferences',return_value=self.store), \
             patch.object(legacy.performance_configuration,'stopped',return_value=None):
            current=ops.run('performance_read',{})
            params={'values':self.edited,'expected_revision':current['revision']}
            preview=ops.run('performance_preview',params)
            params['preview_token']=preview['token']
            with self.assertRaises(legacy.OperationError):ops.run('performance_apply',params)
            self.assertEqual(self.store.calls,0)
            params['confirmed']=True
            applied=ops.run('performance_apply',params)
            self.assertEqual(applied['current'],self.edited)
            params={'expected_revision':applied['revision']}
            preview=ops.run('performance_restore_preview',params)
            params.update(confirmed=True,preview_token=preview['token'])
            self.assertEqual(ops.run('performance_restore',params)['current'],self.values)
    def test_rollback_failure_never_succeeds(self):
        original=self.store.write
        def fail(values):
            if self.store.calls==0:
                original(values)
                raise OSError('write response lost')
            raise p.ConfigurationError('PERF_ROLLBACK')
        self.store.write=fail
        with self.assertRaises(p.ConfigurationError):self.apply()
        self.assertEqual(p.selected(self.store.read()),self.edited)
    def test_private_directory_permissions_required(self):
        self.manager.directory.mkdir(mode=0o755)
        os.chmod(self.manager.directory,0o755)
        with self.assertRaises(p.ConfigurationError):self.apply()
        self.assertEqual(self.store.calls,0)
    def test_capability_version_hash_os_and_host_policy(self):
        app=self.root/'FX.app';(app/'Contents/MacOS').mkdir(parents=True);(app/'Contents/Frameworks').mkdir()
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':'1.9.4'}))
        (app/'Contents/MacOS/steamac-vm').write_bytes(b'fixture')
        for lib in ['libMoltenVK.dylib','libvulkan_kosmickrisp.dylib']:(app/'Contents/Frameworks'/lib).write_bytes(b'fixture')
        with self.assertRaises(p.ConfigurationError):p.capabilities(app)
        def output(args,**kwargs):return b'25769803776' if args[-1]=='hw.memsize' else b'12' if args[-1]=='hw.physicalcpu' else b'26.1'
        import hashlib
        with patch.object(p,'PINNED_EXECUTABLE',hashlib.sha256(b'fixture').hexdigest()),patch.object(p.subprocess,'check_output',side_effect=output):
            rules=p.capabilities(app)
            self.assertEqual(rules['cpu_max'],12);self.assertEqual(rules['memory_max'],12288)
            self.assertEqual(rules['drivers'],['moltenvk','kosmickrisp'])
            (app/'Contents/Frameworks/libvulkan_kosmickrisp.dylib').unlink()
            self.assertEqual(p.capabilities(app)['drivers'],['moltenvk'])
    def test_real_cfpreferences_isolated_domain(self):
        domain='com.lsjop.performance-fixture.'+uuid.uuid4().hex
        preferences=p.Preferences(domain)
        try:
            self.assertEqual(preferences.read(),{})
            preferences.write(self.values);self.assertEqual(preferences.read(),self.values)
            preferences.write(dict(cpus=4));self.assertEqual(preferences.read()['cpus'],4);self.assertEqual(preferences.read()['memMiB'],8192)
        finally:preferences.write({k:None for k in p.KEYS})

if __name__=='__main__':unittest.main(verbosity=2)
