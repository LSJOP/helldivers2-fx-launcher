import importlib.util
import json
from pathlib import Path
import plistlib
import re
import tempfile
import unittest

APP=Path(__file__).resolve().parents[1]
class UpdateResources(unittest.TestCase):
    def test_ten_language_actual_coverage(self):
        source=(APP/'Services/AppUpdateManager.swift').read_text()
        keys=set(re.findall(r'case \.\w+: return "([^"]+)"',source))
        catalogs=json.loads((APP/'Resources/native-locales.json').read_text())
        for code in ['en','zh-CN','ja','ko','ru','es','de','fr','pt-BR','zh-TW']:
            self.assertTrue(keys<=catalogs[code].keys(),(code,keys-catalogs[code].keys()))
            self.assertTrue(all(catalogs[code][key] for key in keys))
            if code!='en':self.assertTrue(all(catalogs[code][key]!=key for key in keys if key!='Stable' or code!='fr'))
    def test_manifest_generation_matches_bundle(self):
        spec=importlib.util.spec_from_file_location('manifest_under_test',APP/'script/make_update_manifest.py')
        module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as directory:
            archive=Path(directory)/'HD2FXLauncher-0.2.0.zip';archive.write_bytes(b'fixture-only')
            info=dict(CFBundleIdentifier=module.BUNDLE,CFBundleShortVersionString='0.2.0',CFBundleVersion='2',LSMinimumSystemVersion='14.0')
            manifest=module.manifest(info,archive,'stable','arm64')
            self.assertEqual(manifest['build'],2);self.assertEqual(manifest['length'],12)
            self.assertEqual(len(manifest['sha256']),64)
            with self.assertRaises(AssertionError):module.manifest(info,archive,'preview','arm64')
            with self.assertRaises(AssertionError):module.manifest(dict(info,CFBundleIdentifier='wrong'),archive,'stable','arm64')
    def test_installation_security_flags(self):
        info=plistlib.loads((APP/'Info.plist').read_bytes())
        self.assertIs(info['SURequireSignedFeed'],True);self.assertIs(info['SUVerifyUpdateBeforeExtraction'],True)
        self.assertEqual(info['SUSignedFeedFailureExpirationInterval'],0)
        self.assertIs(info['SUAllowsAutomaticUpdates'],False)
        config=(APP/'Config/Updates.xcconfig').read_text()
        self.assertIn('HD2_UPDATE_CHANNEL = stable',config)
        self.assertIn('HD2_UPDATE_ENABLED = NO',config)
    def test_inactive_workflow_template_cannot_publish_or_use_secrets(self):
        text=(APP.parent/'docs/ci/native-release-check.yml').read_text()
        self.assertFalse((APP.parent/'.github/workflows/native-release-check.yml').exists())
        self.assertIn('workflow_dispatch:',text);self.assertIn('contents: read',text)
        self.assertNotIn('contents: write',text);self.assertNotIn('${{ secrets.',text)
        self.assertNotIn('gh release',text);self.assertNotIn('git push',text)
    def test_update_module_does_not_depend_on_performance_or_shell(self):
        source=(APP/'Services/AppUpdateManager.swift').read_text()+(APP/'Services/UpdateReleaseService.swift').read_text()
        for token in ['performanceConfiguration','performance_apply','/bin/sh','sudo','runtime_root']:self.assertNotIn(token,source)

if __name__=='__main__':unittest.main(verbosity=2)
