"""Negative fixtures prove the localization gate rejects incomplete edits."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('localization_gate', ROOT / 'native-app/script/check_localization.py')
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class LocalizationChecks(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for folder in ['App', 'Views', 'Stores', 'Services', 'Models', 'Support']:
            shutil.copytree(ROOT / 'native-app' / folder, self.root / 'native-app' / folder)
        self.path = self.root / 'native-app/bridge/native-locales.json'
        self.path.parent.mkdir()
        shutil.copyfile(ROOT / 'native-app/bridge/native-locales.json', self.path)
        shutil.copytree(ROOT / 'native-app/Localization', self.root / 'native-app/Localization')
        for name in ['README.md', 'README.zh-CN.md']:
            shutil.copyfile(ROOT / name, self.root / name)

    def mutate(self, change):
        data = json.loads(self.path.read_text())
        change(data)
        self.path.write_text(json.dumps(data))

    def errors(self):
        return '\n'.join(gate.validate(self.root)[0])

    def test_complete(self):
        self.assertEqual(self.errors(), '')

    def test_missing_translation(self):
        self.mutate(lambda d: d['ja'].pop('ui.053'))
        self.assertIn('missing=', self.errors())

    def test_duplicate(self):
        self.path.write_text('{"en":{},"en":{}}')
        self.assertIn('duplicate key', self.errors())

    def test_format_mismatch(self):
        self.mutate(lambda d: d['ru'].__setitem__('ui.053', 'Проверка %@'))
        self.assertIn('format parameters differ', self.errors())

    def test_placeholder(self):
        self.mutate(lambda d: d['de'].__setitem__('ui.053', 'TODO'))
        self.assertIn('placeholder', self.errors())

    def test_orphan(self):
        self.mutate(lambda d: [v.__setitem__('ui.999', 'unused') for v in d.values()])
        self.assertIn('unused translation keys', self.errors())

    def test_hardcoded_ui(self):
        (self.root / 'native-app/Views/Bad.swift').write_text('Text("New untranslated action")')
        self.assertIn('unlocalized UI literal', self.errors())

    def test_missing_readme(self):
        (self.root / 'README.zh-CN.md').unlink()
        self.assertIn('missing README.zh-CN.md', self.errors())


if __name__ == '__main__':
    unittest.main()
