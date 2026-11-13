import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('readme_screenshots_under_test',Path(__file__).resolve().parents[1]/'script/check_readme_screenshots.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class ScreenshotChecks(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        records=[]
        for readme,lang in [('README.md','en'),('README.zh-CN.md','zh-CN')]:
            image='docs/images/'+lang+'/dashboard.png';path=self.root/image;path.parent.mkdir(parents=True);path.write_bytes(b'path-check-fixture-not-a-screenshot')
            (self.root/readme).write_text('[English](README.md) | [Chinese](README.zh-CN.md)\n![Dashboard]('+image+')\n')
            records.append(dict(path=image,language=lang,visual_review='PASS',app_version='0.1.0',app_build='2026110602',capture_bundle_identifier='test.capture',source_base_commit='1234567',captured_at='2026-11-13T09:23:49Z',sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        (self.root/'docs/images/manifest.json').write_text(json.dumps(dict(screenshots=records)))
    def tearDown(self):self.temp.cleanup()
    def test_matching_language_paths(self):self.assertEqual(module.check(self.root),([],2))
    def replace(self,name,old,new):
        p=self.root/name;p.write_text(p.read_text().replace(old,new))
    def test_english_cannot_use_chinese(self):
        self.replace('README.md','docs/images/en/','docs/images/zh-CN/');self.assertTrue(module.check(self.root)[0])
    def test_chinese_cannot_use_english(self):
        self.replace('README.zh-CN.md','docs/images/zh-CN/','docs/images/en/');self.assertTrue(module.check(self.root)[0])
    def test_missing_image(self):
        (self.root/'docs/images/en/dashboard.png').unlink();self.assertTrue(module.check(self.root)[0])
    def test_changed_bytes_require_review(self):
        (self.root/'docs/images/en/dashboard.png').write_bytes(b'changed');self.assertTrue(module.check(self.root)[0])
    def test_language_switch_links_preserved(self):
        self.replace('README.md','[Chinese](README.zh-CN.md)','');self.assertTrue(module.check(self.root)[0])
    def test_ui_source_drift_requires_review(self):
        view=self.root/'native-app/Views/Example.swift';view.parent.mkdir(parents=True);view.write_text('old visible text')
        p=self.root/'docs/images/manifest.json';data=json.loads(p.read_text());data['ui_source_sha256']=module.ui_fingerprint(self.root);p.write_text(json.dumps(data))
        self.assertEqual(module.check(self.root)[0],[])
        view.write_text('new visible text');self.assertTrue(module.check(self.root)[0])
    def test_missing_build_provenance_rejected(self):
        p = self.root/'docs/images/manifest.json'
        data = json.loads(p.read_text())
        del data['screenshots'][0]['app_build']
        p.write_text(json.dumps(data))
        self.assertTrue(module.check(self.root)[0])

    def test_missing_source_provenance_rejected(self):
        p = self.root/'docs/images/manifest.json'
        data = json.loads(p.read_text())
        del data['screenshots'][0]['source_base_commit']
        p.write_text(json.dumps(data))
        self.assertTrue(module.check(self.root)[0])

    def test_invalid_capture_timestamp_rejected(self):
        p = self.root/'docs/images/manifest.json'
        data = json.loads(p.read_text())
        data['screenshots'][0]['captured_at'] = 'unknown'
        p.write_text(json.dumps(data))
        self.assertTrue(module.check(self.root)[0])

    def test_unreviewed_image_rejected(self):
        p=self.root/'docs/images/manifest.json';data=json.loads(p.read_text());data['screenshots'][0]['visual_review']='PENDING';p.write_text(json.dumps(data));self.assertTrue(module.check(self.root)[0])
if __name__=='__main__':unittest.main(verbosity=2)
