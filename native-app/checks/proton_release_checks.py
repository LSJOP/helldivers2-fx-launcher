"""Run the actual production Guest installer on isolated tiny archives; never SSH/VM."""
import base64, hashlib, io, json, os, pathlib, subprocess, sys, tarfile, tempfile, unittest, uuid
ROOT=pathlib.Path(__file__).resolve().parents[1]
SOURCE=(ROOT/'Core/ComponentDeploymentAdapters.swift').read_text().split('    static let python = #"""\n',1)[1].split('"""#',1)[0]
class ProtonReleaseChecks(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=pathlib.Path(self.temp.name).resolve();self.home=self.root/'home';self.home.mkdir();self.bin=self.root/'bin';self.bin.mkdir()
  self.boot=self.root/'boot';self.boot.write_text(str(uuid.uuid4()));self.archive=self.root/'fixture.tar.xz';self.version='proton-je-fixture'
  data=b'fixture-proton\n'
  with tarfile.open(self.archive,'w:xz') as tar:
   d=tarfile.TarInfo(self.version);d.type=tarfile.DIRTYPE;d.mode=0o755;tar.addfile(d)
   f=tarfile.TarInfo(self.version+'/proton');f.mode=0o755;f.size=len(data);tar.addfile(f,io.BytesIO(data))
   link=tarfile.TarInfo(self.version+'/alias');link.type=tarfile.SYMTYPE;link.linkname='proton';tar.addfile(link)
  self.manifest={'version':self.version,'files':{'proton':[hashlib.sha256(data).hexdigest(),0o755]},'links':{'alias':'proton'},'directories':[], 'archiveSHA256':hashlib.sha256(self.archive.read_bytes()).hexdigest(),'archiveBytes':self.archive.stat().st_size,'unpackedBytes':len(data),'url':'https://fixture.invalid/pinned.tar.xz'}
  self.checksum=self.root/'fixture.sha512sum';self.refresh_checksum()
  self.p=self.home/'.local/share/Steam/compatibilitytools.d'/self.version
  scripts={'curl':'#!/bin/sh\nwhile [ "$#" -gt 0 ]; do case "$1" in --output) shift; out="$1";; https://*) url="$1";; esac; shift; done\ncase "$url" in *.sha512sum) cp "$FIXTURE_CHECKSUM" "$out";; *) cp "$FIXTURE_ARCHIVE" "$out";; esac\n','pgrep':'#!/bin/sh\n[ "$2" = steam ] && exit 0\n[ -f "$HOME/game-running" ] && exit 0\nexit 1\n'}
  for name,script in scripts.items():p=self.bin/name;p.write_text(script);p.chmod(0o755)
 def refresh_checksum(self):
  sha=hashlib.sha512(self.archive.read_bytes()).hexdigest();self.manifest['archiveSHA512']=sha;self.checksum.write_text(sha+'  '+self.manifest['version']+'.tar.xz\n')
 def tearDown(self):self.temp.cleanup()
 def run_script(self,mode):
  prefix='MANIFEST='+repr(base64.b64encode(json.dumps(self.manifest).encode()).decode())+'\nMODE='+repr(mode)+'\nBOOT='+repr(self.boot.read_text())+'\nSUFFIX='+repr(str(uuid.uuid4()))+'\n'
  source=SOURCE.replace('/proc/sys/kernel/random/boot_id',str(self.boot))
  env=dict(os.environ,HOME=str(self.home),PATH=str(self.bin)+':/usr/bin:/bin',FIXTURE_ARCHIVE=str(self.archive),FIXTURE_CHECKSUM=str(self.checksum))
  return subprocess.run([sys.executable,'-'],input=prefix+source,env=env,capture_output=True,text=True,timeout=15)
 def test_readonly_probe(self):
  r=self.run_script('probe');self.assertEqual(r.returncode,0,r.stderr);self.assertIn('proton_package=missing',r.stdout);self.assertFalse(self.p.parent.exists())
 def test_install_with_running_steam_verify_and_recover(self):
  r=self.run_script('install');self.assertEqual(r.returncode,0,r.stderr);self.assertEqual(os.readlink(self.p/'alias'),'proton')
  self.assertIn(self.manifest['archiveSHA256'],self.run_script('probe').stdout)
  self.assertNotEqual(self.run_script('install').returncode,0)
  r=self.run_script('recover');self.assertEqual(r.returncode,0,r.stderr);self.assertFalse(self.p.exists());self.assertEqual(len(list(self.p.parent.glob(self.version+'.hd2-recovered-*'))),1)
 def test_corrupt_tree_not_overwritten_or_recovered(self):
  self.assertEqual(self.run_script('install').returncode,0)
  (self.p/'proton').write_text('external-change')
  self.assertIn('unknown',self.run_script('probe').stdout)
  self.assertNotEqual(self.run_script('install').returncode,0);self.assertNotEqual(self.run_script('recover').returncode,0)
  self.assertEqual((self.p/'proton').read_text(),'external-change')
 def test_extra_file_rejected(self):
  self.assertEqual(self.run_script('install').returncode,0);(self.p/'extra').write_text('external')
  self.assertIn('unknown',self.run_script('probe').stdout)
 def test_hash_mismatch_never_installs(self):
  self.manifest['archiveSHA256']='0'*64
  self.assertNotEqual(self.run_script('install').returncode,0);self.assertFalse(self.p.exists())
 def test_game_prevents_install(self):
  (self.home/'game-running').touch();self.assertNotEqual(self.run_script('install').returncode,0);self.assertFalse(self.p.exists())
 def test_symlink_parent_rejected(self):
  outside=self.root/'outside';outside.mkdir();(self.home/'.local').symlink_to(outside,target_is_directory=True)
  self.assertNotEqual(self.run_script('install').returncode,0);self.assertEqual(list(outside.iterdir()),[])
 def test_escaping_archive_link_rejected(self):
  with tarfile.open(self.archive,'w:xz') as tar:
   link=tarfile.TarInfo(self.version+'/alias');link.type=tarfile.SYMTYPE;link.linkname='../../escape';tar.addfile(link)
  self.manifest['archiveSHA256']=hashlib.sha256(self.archive.read_bytes()).hexdigest();self.manifest['archiveBytes']=self.archive.stat().st_size;self.refresh_checksum()
  self.assertNotEqual(self.run_script('install').returncode,0);self.assertFalse(self.p.exists());self.assertFalse((self.root/'escape').exists())
 def test_sha512_pin_mismatch_never_installs(self):
  self.manifest['archiveSHA512']='0'*128
  self.assertNotEqual(self.run_script('install').returncode,0);self.assertFalse(self.p.exists())
 def test_published_checksum_mismatch_never_installs(self):
  self.checksum.write_text('0'*128+'  '+self.version+'.tar.xz\n')
  self.assertNotEqual(self.run_script('install').returncode,0);self.assertFalse(self.p.exists())
 def test_approved_metadata(self):
  m=json.loads((ROOT/'Resources/proton-je-approved.json').read_text())
  self.assertEqual(m['version'],'proton-je-11.0-20261014-3');self.assertEqual(m['archiveSHA256'],'aa5430696ca39451299e2f007ef652bc030e6419242776343d48947e21827485')
  self.assertTrue(all(not x.endswith('/') for x in m['directories']));self.assertEqual(len(m['files']),5609);self.assertEqual(len(m['links']),1896);self.assertIn('LICENSE',m['files'])
if __name__=='__main__':unittest.main(verbosity=2)
