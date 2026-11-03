"""Isolated release history checks; ephemeral file keys, never Keychain."""
import base64
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET

APP = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('history', APP/'script/validate_release_history.py')
history = importlib.util.module_from_spec(spec)
spec.loader.exec_module(history)
TOOL = APP/'build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update'


class HistoryChecks(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.path = Path(self.directory.name)/'appcast.xml'
        self.root = ET.Element('rss', {'version': '2.0'})
        channel = ET.SubElement(self.root, 'channel')
        self.item = ET.SubElement(channel, 'item')
        ET.SubElement(self.item, history.SPARKLE+'version').text = '2'
        ET.SubElement(self.item, history.SPARKLE+'shortVersionString').text = '0.2.0'
        self.enclosure = ET.SubElement(self.item, 'enclosure', {
            'url': history.PREFIX+'0.2.0/HD2FXLauncher-0.2.0.zip',
            'length': '12', history.SPARKLE+'edSignature': base64.b64encode(bytes(64)).decode()})

    def write(self):
        ET.ElementTree(self.root).write(self.path, encoding='utf-8', xml_declaration=True)

    def check_policy(self, channel='stable', build='3'):
        self.write()
        history.validate(self.path, channel, build)

    def test_valid_stable_history(self):
        self.check_policy()

    def test_signed_empty_bootstrap_policy(self):
        self.root.find('channel').remove(self.item)
        self.check_policy()

    def test_duplicate_build_rejected(self):
        import copy
        self.root.find('channel').append(copy.deepcopy(self.item))
        with self.assertRaises(ValueError): self.check_policy()

    def test_overwrite_and_downgrade_rejected(self):
        for build in ['1', '2']:
            with self.subTest(build=build), self.assertRaises(ValueError): self.check_policy(build=build)

    def test_wrong_channel_rejected(self):
        ET.SubElement(self.item, history.SPARKLE+'channel').text = 'preview'
        with self.assertRaises(ValueError): self.check_policy()

    def test_foreign_and_mismatched_asset_rejected(self):
        for url in ['https://example.com/archive.zip', history.PREFIX+'0.3.0/HD2FXLauncher-0.2.0.zip']:
            self.enclosure.set('url', url)
            with self.subTest(url=url), self.assertRaises(ValueError): self.check_policy()

    def test_package_installer_rejected(self):
        self.enclosure.set(history.SPARKLE+'installationType', 'package')
        with self.assertRaises(ValueError): self.check_policy()

    def test_missing_archive_signature_rejected(self):
        del self.enclosure.attrib[history.SPARKLE+'edSignature']
        with self.assertRaises(ValueError): self.check_policy()

    def test_xml_entities_rejected(self):
        self.path.write_text('<!DOCTYPE rss [<!ENTITY x "fixture">]><rss><channel/></rss>')
        with self.assertRaises(ValueError): history.validate(self.path, 'stable', '3')

    def test_real_sparkle_signature_boundary(self):
        self.assertTrue(TOOL.is_file(), 'Resolve pinned Sparkle before release checks')
        self.write()
        keys = []
        for name in ['first', 'other']:
            key = Path(self.directory.name)/name
            descriptor = os.open(key, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(descriptor, 'wb') as stream:
                stream.write(base64.b64encode(os.urandom(32)))
            keys.append(key)
        def run(key, verify=False):
            args = [str(TOOL), '--ed-key-file', str(key)]
            if verify: args.append('--verify')
            return subprocess.run(args+[str(self.path)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20).returncode
        self.assertNotEqual(run(keys[0], verify=True), 0, 'Unsigned feed accepted')
        self.assertEqual(run(keys[0]), 0)
        self.assertEqual(run(keys[0], verify=True), 0)
        self.assertNotEqual(run(keys[1], verify=True), 0, 'Wrong signing identity accepted')
        self.path.write_bytes(self.path.read_bytes().replace(b'0.2.0', b'0.9.0'))
        self.assertNotEqual(run(keys[0], verify=True), 0, 'Tampered signed history accepted')


if __name__ == '__main__': unittest.main(verbosity=2)
