#!/usr/bin/env python3
import unittest
from unittest.mock import patch
from check_changed import select, changed


class SelectionTests(unittest.TestCase):
    def test_isolated_fixture_and_dependencies(self):
        focused = ('bash', 'script/check_performance_fixture.sh')
        full = ('bash', 'native-app/script/run_checks.sh')
        self.assertIn(focused, select({'native-app/checks/PerformanceChecks.swift'})[0])
        for dependency in ('native-app/Services/GamePerformanceInferenceService.swift',
                           'native-app/Models/BridgeModels.swift',
                           'native-app/Stores/AppState.swift',
                           'native-app/Views/DashboardView.swift',
                           'native-app/Core/GuestService.swift',
                           'native-app/HD2FXNative.xcodeproj/project.pbxproj',
                           'native-app/Resources/environment-profile-v1.json',
                           'native-app/unknown.swift'):
            with self.subTest(dependency=dependency):
                self.assertIn(full, select({dependency})[0])
        self.assertIn(full, select(set(), release=True)[0])

    def test_staged_and_unstaged_paths_are_independent(self):
        with patch('check_changed.git', side_effect=[b'committed\0', b'staged\0', b'unstaged\0', b'untracked\0']):
            self.assertEqual(changed('base'), {'committed', 'staged', 'unstaged', 'untracked'})

    def test_localization_and_documentation(self):
        checks, _ = select({'native-app/Resources/native-locales.json', 'README.md'})
        self.assertIn(('python3', 'native-app/script/check_localization.py'), checks)
        self.assertIn(('python3', 'native-app/checks/localization_checks.py'), checks)
        self.assertIn(('python3', 'script/check_docs.py'), checks)


if __name__ == '__main__':
    unittest.main()
