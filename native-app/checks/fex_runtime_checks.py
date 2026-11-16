"""Exercise the bundled read-only probe with isolated files and a fake process."""
import ast,json,pathlib,tempfile,unittest,io,contextlib,struct,os,subprocess
from unittest.mock import patch
source=(pathlib.Path(__file__).resolve().parents[1]/'Core/ComponentDeploymentAdapters.swift').read_text()
pipeline=source.split('static let pipeline = #"""\n',1)[1].rsplit('\n"""#',1)[0]
probe=source.split('static let runtimeProbe = #"""\n',1)[1].split('\n"""#',1)[0]
class RuntimeChecks(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.home=pathlib.Path(self.temp.name).resolve()
  self.root=self.home/'.local/share/Steam/steamapps/common/FEX-Emu';self.exe=self.root/'usr/bin/FEX'
  self.exe.parent.mkdir(parents=True);self.exe.write_bytes(b'\x7fELF\x02\x01'+bytes(12)+b'\xb7\x00'+bytes(44));self.exe.chmod(0o700)
  (self.root/'emulator.json').write_text(json.dumps({'emulator_v0':{'argv':'./usr/bin/FEX'}}))
  self.provider=self.home/'fex-mesa'
  (self.provider/'usr/lib').mkdir(parents=True)
  (self.provider/'graphics_provider.json').write_text('{}')
  (self.provider/'usr/lib/ld-linux-x86-64.so.2').touch()
  self.ns={};tree=ast.parse(pipeline)
  exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))],type_ignores=[]),'helpers','exec'),self.ns)
 def tearDown(self):self.temp.cleanup()
 def run_probe(self,expected='',status=42,container_status=0,loaded=True):
  output=io.StringIO();ns=dict(self.ns,EXPECTED_TREE=expected,EXPECTED_BOOT=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip() if pathlib.Path('/proc').exists() else 'fixture')
  ns.update(RUNTIME_VALVE=(0,'',self.ns['fingerprint'](None)),RUNTIME_LOCAL=(0,'','unused'),observed_managed_executable=lambda *_:loaded)
  original_read=pathlib.Path.read_text
  def read(p,*a,**k):return 'fixture' if str(p)=='/proc/sys/kernel/random/boot_id' else original_read(p,*a,**k)
  with patch.object(pathlib.Path,'home',return_value=self.home),patch.object(pathlib.Path,'read_text',read),patch('platform.machine',return_value='aarch64'),patch('subprocess.Popen') as process,contextlib.redirect_stdout(output):
   process.return_value.wait.return_value=status
   process.return_value.communicate.return_value=(b'HD2_ROOTFS_OK:empty\n',b'')
   process.return_value.returncode=container_status
   exec(probe.replace("/usr/share/guestos/fex-mesa",str(self.provider)),ns)
   self.calls=process.call_count
   self.container_call=process.call_args
  return json.loads(output.getvalue())
 def test_installer_probe_prefix_has_no_pipeline_import_dependency(self):
  with patch.object(pathlib.Path,'home',return_value=self.home):
   exec('import pathlib\n'+probe.split('try:print(json.dumps(check()))')[0],{})
 def test_unknown_hash_preflight_does_not_execute(self):
  self.assertTrue(self.run_probe()['preflight']);self.assertEqual(self.calls,0)
 def test_compatible_custom_build(self):
  tree=self.run_probe()['tree'];self.assertTrue(self.run_probe(tree)['runtime']);self.assertEqual(self.calls,1)
 def test_changed_build_invalidates_consent(self):
  tree=self.run_probe()['tree'];(self.root/'new-component').write_bytes(b'changed')
  self.assertEqual(self.run_probe(tree)['reason'],'FEX_CHANGED');self.assertEqual(self.calls,0)
 def test_execution_failure(self):
  tree=self.run_probe()['tree'];self.assertEqual(self.run_probe(tree,status=1)['reason'],'FEX_RUNTIME_FAILED')
 def test_missing(self):
  self.exe.unlink();self.assertEqual(self.run_probe()['reason'],'FEX_MISSING')
 def test_proton_integrated_layout_is_unverified_without_execution(self):
  elf=self.exe.read_bytes();self.exe.unlink()
  root=self.home/'.local/share/Steam/steamapps/common/Proton 11.0 (ARM64)/files/lib/wine/aarch64-unix'
  root.mkdir(parents=True)
  for name in ['libarm64ecfex.so','libwow64fex.so']:(root/name).write_bytes(elf)
  proton=self.home/'.local/share/Steam/steamapps/common/Proton 11.0 (ARM64)'
  (proton/'version').write_text('fixture-arm64-proton')
  result=self.run_probe()
  self.assertEqual(result['reason'],'FEX_PROTON_INTEGRATED_UNVERIFIED')
  self.assertEqual(result['layout'],'proton-integrated');self.assertEqual(self.calls,0)
  self.assertEqual(result['version'],'fixture-arm64-proton')
 def test_managed_emulator_requires_real_container_rootfs_probe(self):
  import shutil
  managed=self.home/'.local/share/HD2FXLauncher/compatibility/FEX-RF'
  managed.parent.mkdir(parents=True)
  shutil.move(self.root,managed)
  metadata=managed/'emulator.json'
  for registered in ['', '/', '/custom-provider']:
   metadata.write_text(json.dumps({'emulator_v0':{'argv':'./usr/bin/FEX','container_environment':{'FEX_ROOTFS':registered}}}))
   static=self.run_probe()
   self.assertEqual(static['registered_rootfs'],registered)
   result=self.run_probe(static['tree'])
   self.assertTrue(result['runtime']);self.assertEqual(result['probe_rootfs'],'empty')
   self.assertEqual(result['loaded_executable'],str(managed/'usr/bin/FEX'))
   self.assertEqual(self.container_call.kwargs['env']['PRESSURE_VESSEL_EMULATOR'],str(metadata))
   self.assertEqual(self.run_probe(static['tree'],container_status=1)['reason'],'FEX_RUNTIME_FAILED')
   self.assertEqual(self.run_probe(static['tree'],loaded=False)['reason'],'FEX_RUNTIME_FAILED')
 def test_no_execute_permission(self):
  self.exe.chmod(0o600);self.assertEqual(self.run_probe()['reason'],'FEX_NOT_EXECUTABLE')
 def test_wrong_architecture(self):
  self.exe.write_bytes(b'wrong');self.assertEqual(self.run_probe()['reason'],'FEX_ARCHITECTURE')
 def test_missing_rootfs_loader(self):
  (self.provider/'usr/lib/ld-linux-x86-64.so.2').unlink()
  self.assertEqual(self.run_probe()['reason'],'FEX_ROOTFS_UNAVAILABLE')
  self.assertEqual(self.calls,0)
 def test_missing_integration(self):
  (self.root/'emulator.json').unlink();self.assertEqual(self.run_probe()['reason'],'FEX_INTEGRATION_MISSING')
 def test_unsafe_symlink_never_executes(self):
  (self.root/'escape').symlink_to('/tmp');self.assertEqual(self.run_probe()['reason'],'FEX_INTEGRITY_FAILED');self.assertEqual(self.calls,0)
if __name__=='__main__':unittest.main()
