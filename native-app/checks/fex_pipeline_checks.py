"""Real filesystem transaction tests; identity/idle are fixture-only substitutions."""
import ast,contextlib,hashlib,io,json,pathlib,tempfile,unittest,uuid
from unittest.mock import patch
source=(pathlib.Path(__file__).resolve().parents[1]/'Core/ComponentDeploymentAdapters.swift').read_text().split('    static let pipeline = #"""\n',1)[1].rsplit('\n"""#',1)[0]
class PipelineChecks(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.home=pathlib.Path(self.tmp.name).resolve()
  self.work=self.home/'.local/share/HD2FXLauncher/fex-rf-v1';self.stage=self.work/'runtime'
  self.installed=self.home/'.local/share/Steam/steamapps/common/FEX-Emu'
  (self.stage/'usr/bin').mkdir(parents=True);(self.installed/'usr/bin').mkdir(parents=True)
  (self.stage/'usr/bin/FEX').write_bytes((b'\x7fELF\x02\x01'+bytes(12)+b'\xb7\x00'+bytes(44)));(self.stage/'usr/bin/FEX').chmod(0o700)
  (self.installed/'usr/bin/FEX').write_bytes(b'original');(self.installed/'compatibilitytool.vdf').write_text('original metadata')
  self.expected=hashlib.sha256((b'\x7fELF\x02\x01'+bytes(12)+b'\xb7\x00'+bytes(44))).hexdigest();self.ticket=str(uuid.uuid4())
  tree=ast.parse(source)
  functions=[n for n in tree.body if isinstance(n,(ast.Import,ast.ImportFrom,ast.FunctionDef))]
  ns={};exec(compile(ast.Module(body=functions,type_ignores=[]),'helpers','exec'),ns);self.helpers=ns
  self.inventory=ns['inventory'];self.fingerprint=ns['fingerprint']
  self.original=self.inventory(self.installed)
  self.provenance()
 def tearDown(self):self.tmp.cleanup()
 def provenance(self):
  self.work.mkdir(parents=True,exist_ok=True)
  (self.work/'provenance.json').write_text(json.dumps({'source':'87c57f0a5f2a0e87c6b994e9d91f72ac6d512ab8','patch':'85999c4f3a82063c66095d5315a661f0eed8369ed7b4b03191ed5dc8521d7926','runtime':self.inventory(self.stage)}))
 def run_pipeline(self,mode,audit=None):
  tree=ast.parse(source)
  for n in tree.body:
   if isinstance(n,ast.FunctionDef) and n.name in ['identity','idle']:n.body=[ast.Return(value=None)]
  ast.fix_missing_locations(tree)
  request={'mode':mode,'boot':'fixture-boot','ticket':self.ticket,'audit':audit}
  out=io.StringIO()
  with patch.object(pathlib.Path,'home',return_value=self.home),contextlib.redirect_stdout(out):
   try:exec(compile(tree,'fixture-pipeline','exec'),{'REQUEST':request})
   except SystemExit as e:
    if e.code:raise
  return json.loads(out.getvalue())
 def test_build_proxy_helper_is_in_bundled_pipeline(self):
  self.helpers['REQUEST']={'source_proxy':'http://192.168.127.254:7890'}
  self.assertEqual(self.helpers['guest_proxy'](),'http://192.168.127.254:7890')
 def test_proxy_credentials_are_not_forwarded(self):
  self.helpers['REQUEST']={'source_proxy':'http://user:password@192.168.127.254:7890'}
  self.assertIsNone(self.helpers['guest_proxy']())
 def test_build_timeout_terminates_only_owned_process(self):
  import os,subprocess,sys
  tree=ast.parse(source)
  functions=[n for n in ast.walk(tree) if isinstance(n,ast.FunctionDef) and n.name=='run']
  ns={'identity':lambda:None,'guest_proxy':lambda:None,'log':self.work/'timeout.log','env':dict(os.environ),'active':None,'subprocess':subprocess,'os':os,'signal':__import__('signal')}
  exec(compile(ast.Module(body=functions,type_ignores=[]),'run-helper','exec'),ns)
  created=[];original=subprocess.Popen
  def owned(*args,**kwargs):
   p=original(*args,**kwargs);created.append(p);return p
  with patch.object(subprocess,'Popen',owned):
   with self.assertRaises(subprocess.TimeoutExpired):ns['run']([sys.executable,'-c','import time;time.sleep(60)'],seconds=0.05)
  self.assertEqual(len(created),1);self.assertIsNotNone(created[0].poll());self.assertIsNone(ns['active'])
 def test_missing_provenance_blocks(self):
  (self.work/'provenance.json').unlink();self.assertFalse(self.run_pipeline('audit')['ready'])
 def test_modified_runtime_blocks(self):
  (self.stage/'usr/bin/FEX').write_bytes(b'changed');self.assertFalse(self.run_pipeline('audit')['ready'])
 def test_install_preserves_metadata_and_recovers(self):
  a=self.run_pipeline('audit');self.assertTrue(a['ready'])
  self.assertTrue(self.run_pipeline('install',a)['verified'])
  self.assertIn(self.ticket,self.run_pipeline('audit')['recoverable'])
  self.assertEqual((self.installed/'compatibilitytool.vdf').read_text(),'original metadata')
  self.assertTrue(self.run_pipeline('recover')['recovered']);self.assertEqual(self.inventory(self.installed),self.original)
  self.assertNotIn(self.ticket,self.run_pipeline('audit')['recoverable'])
 def test_stale_review_rejected(self):
  a=self.run_pipeline('audit');(self.installed/'extra').write_text('external edit')
  with self.assertRaisesRegex(RuntimeError,'ARTIFACT_UNAPPROVED'):self.run_pipeline('install',a)
  self.assertEqual((self.installed/'usr/bin/FEX').read_bytes(),b'original')
 def test_restore_external_drift_rejected(self):
  self.run_pipeline('install',self.run_pipeline('audit'));(self.installed/'usr/bin/FEX').write_bytes(b'external')
  with self.assertRaisesRegex(RuntimeError,'EXTERNAL_DRIFT'):self.run_pipeline('recover')
 def test_escape_link_rejected(self):
  (self.stage/'escape').symlink_to('/tmp')
  with self.assertRaisesRegex(RuntimeError,'UNSAFE_PATH'):self.run_pipeline('audit')
 def test_original_symlink_parent_rejected(self):
  # The original tree's internal link must never redirect an overlay write.
  (self.installed/'usr/bin/FEX').unlink();(self.installed/'usr/bin').rmdir();(self.installed/'other').mkdir()
  (self.installed/'usr/bin').symlink_to('../other',target_is_directory=True)
  a=self.run_pipeline('audit')
  with self.assertRaisesRegex(RuntimeError,'UNSAFE_PATH'):self.run_pipeline('install',a)
 def test_automatic_recovery_after_backup_swap_gap(self):
  a=self.run_pipeline('audit');rename=pathlib.Path.rename
  def interrupted(p,d):
   if '.hd2-stage-' in p.name:raise OSError('fixture interruption')
   return rename(p,d)
  with patch.object(pathlib.Path,'rename',interrupted):
   with self.assertRaises(OSError):self.run_pipeline('install',a)
  self.assertNotIn(self.ticket,self.run_pipeline('audit')['recoverable'])
  self.assertEqual(self.inventory(self.installed),self.original)
 def test_recovery_resumes_after_retaining_new_tree(self):
  self.run_pipeline('install',self.run_pipeline('audit'));rename=pathlib.Path.rename
  def interrupted(p,d):
   if '.hd2-backup-' in p.name:raise OSError('fixture recovery interruption')
   return rename(p,d)
  with patch.object(pathlib.Path,'rename',interrupted):
   with self.assertRaises(OSError):self.run_pipeline('recover')
  self.assertTrue(self.run_pipeline('recover')['recovered'])
  self.assertEqual(self.inventory(self.installed),self.original)
 def test_shared_work_directory_rejected(self):
  self.work.chmod(0o777)
  with self.assertRaisesRegex(RuntimeError,'UNSAFE_PATH'):self.run_pipeline('audit')
if __name__=='__main__':unittest.main()
