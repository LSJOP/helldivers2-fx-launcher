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
  (self.root/'emulator.json').write_text('{}')
  self.ns={};tree=ast.parse(pipeline)
  exec(compile(ast.Module(body=[n for n in tree.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))],type_ignores=[]),'helpers','exec'),self.ns)
 def tearDown(self):self.temp.cleanup()
 def run_probe(self,expected='',status=42):
  output=io.StringIO();ns=dict(self.ns,EXPECTED_TREE=expected,EXPECTED_BOOT=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip() if pathlib.Path('/proc').exists() else 'fixture')
  original_read=pathlib.Path.read_text
  def read(p,*a,**k):return 'fixture' if str(p)=='/proc/sys/kernel/random/boot_id' else original_read(p,*a,**k)
  with patch.object(pathlib.Path,'home',return_value=self.home),patch.object(pathlib.Path,'read_text',read),patch('platform.machine',return_value='aarch64'),patch('subprocess.Popen') as process,contextlib.redirect_stdout(output):
   process.return_value.wait.return_value=status
   exec(probe,ns)
   self.calls=process.call_count
  return json.loads(output.getvalue())
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
 def test_no_execute_permission(self):
  self.exe.chmod(0o600);self.assertEqual(self.run_probe()['reason'],'FEX_NOT_EXECUTABLE')
 def test_wrong_architecture(self):
  self.exe.write_bytes(b'wrong');self.assertEqual(self.run_probe()['reason'],'FEX_ARCHITECTURE')
 def test_missing_integration(self):
  (self.root/'emulator.json').unlink();self.assertEqual(self.run_probe()['reason'],'FEX_INTEGRATION_MISSING')
 def test_unsafe_symlink_never_executes(self):
  (self.root/'escape').symlink_to('/tmp');self.assertEqual(self.run_probe()['reason'],'FEX_INTEGRITY_FAILED');self.assertEqual(self.calls,0)
if __name__=='__main__':unittest.main()
