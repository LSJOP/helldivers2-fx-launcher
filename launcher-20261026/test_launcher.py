import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('launcher_menu', Path(__file__).with_name('menu.py'))
menu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(menu)
h = menu.helper


class LauncherTests(unittest.TestCase):
    def test_performance_summary_fits_all_languages_and_terminal_sizes(self):
        old=menu.LANG
        try:
            for code in menu.i18n.CODES:
                menu.LANG=code
                for columns in (88,80,60,40):
                    output=io.StringIO()
                    with self.subTest(code=code,columns=columns),patch.object(menu.shutil,'get_terminal_size',return_value=os.terminal_size((columns,24))),contextlib.redirect_stdout(output):
                        menu.show_performance_profile()
                    self.assertTrue(all(menu.width(line)<=columns for line in output.getvalue().splitlines()))
        finally:menu.LANG=old

    def test_configuration_menu_applies_performance_profile_and_shows_next_launch_step(self):
        output=io.StringIO()
        with patch.object(menu,'LaunchProgress'),patch.object(menu,'refresh_connection'),patch.object(menu.performance_profile,'apply',return_value={'restart_required':False}) as apply,patch.object(h,'main') as old_setup,contextlib.redirect_stdout(output):
            menu.launch_game(configure=True)
        apply.assert_called_once_with(h);old_setup.assert_not_called()
        self.assertIn(menu.i18n.text('performance.resources',menu.LANG),output.getvalue())
        self.assertIn(menu.i18n.text('performance.applied',menu.LANG),output.getvalue())
        self.assertIsNone(menu.ACTIVE_PROGRESS)

    def test_configuration_menu_reports_busy_without_claiming_success(self):
        output=io.StringIO()
        with patch.object(menu,'LaunchProgress') as progress,patch.object(menu,'refresh_connection'),patch.object(menu.performance_profile,'apply',side_effect=menu.performance_profile.ProfileError('busy')),contextlib.redirect_stdout(output):
            with self.assertRaises(RuntimeError) as caught:menu.launch_game(configure=True)
        self.assertEqual(str(caught.exception),menu.i18n.text('performance.error.busy',menu.LANG))
        self.assertNotIn(menu.i18n.text('performance.applied',menu.LANG),output.getvalue())
        progress.return_value.failed.assert_called_once();progress.return_value.close.assert_called_once()
        self.assertIsNone(menu.ACTIVE_PROGRESS)

    def test_normal_cold_boot_preserves_verified_resources_and_network_without_a_guard(self):
        with tempfile.TemporaryDirectory() as folder:
            binary=Path(folder)/'gvproxy';binary.write_bytes(b'verified-network-fixture')
            wrapper=Path(folder)/'wrapper';wrapper.write_text('fixture')
            def native(args,**kwargs):
                return subprocess.CompletedProcess(args,1 if args[0]=='pgrep' else 0)
            state={'verified_network':True,'game_pids':['123'],'apps':['553850']}
            with patch.object(h,'vm_reachable',side_effect=[False,True]),patch.object(h,'connect'),patch.object(h,'state',return_value=state),patch.object(h,'activate_fx'),patch.object(h,'verify_fx_profile') as verify,patch.object(h,'run_post_launch_checks') as post_checks,patch.object(h,'GVPROXY',binary),patch.object(h,'GVPROXY_WRAPPER',wrapper),patch.object(h,'GVPROXY_SHA256',hashlib.sha256(binary.read_bytes()).hexdigest()),patch.object(h.subprocess,'run',side_effect=native) as run,patch.object(h.subprocess,'Popen') as background,patch.object(h,'say'),patch.object(h,'PROGRESS_HOOK',None):
                h.main()
            verify.assert_called_once()
            post_checks.assert_not_called()  # Existing game needs no fresh probes.
            background.assert_not_called()
            launches=[c.args[0] for c in run.call_args_list if c.args[0][0]=='open']
            self.assertEqual(len(launches),1)
            args=launches[0]
            self.assertEqual(args[1],h.APP)
            self.assertEqual(args[args.index('--mem')+1],'8192')
            self.assertEqual(args[args.index('--cpus')+1],'8')
            self.assertIn('steamac.gpu_mib=6144',args[args.index('--cmdline')+1])
            self.assertEqual(args[args.index('--vulkan-driver')+1],'kosmickrisp')
            self.assertEqual(args[args.index('--gvproxy')+1],str(wrapper))
            self.assertIn('--no-wmtr',args)

    def test_missing_performance_copy_never_launches_a_fallback_app(self):
        with tempfile.TemporaryDirectory() as folder,patch.object(h,'APP',str(Path(folder)/'missing.app')),patch.object(h.subprocess,'run') as run:
            with self.assertRaisesRegex(RuntimeError,'performance copy'):
                h.verify_fx_profile()
            run.assert_not_called()

    def test_terminal_theme_aligns_chinese_and_can_disable_color(self):
        with patch.object(menu.sys.stdout, 'isatty', return_value=True), patch.dict(menu.os.environ, {'TERM': 'xterm-256color'}, clear=True):
            self.assertIn('\033[', menu.paint('测试'))
            self.assertEqual(menu.width(menu.paint('测试')), 4)
            with patch.dict(menu.os.environ, {'NO_COLOR': '1'}):
                self.assertEqual(menu.paint('test'), 'test')
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            menu.panel('中文 TITLE', ['1. 中文', '2. English'])
        self.assertEqual(len(set(menu.width(line) for line in output.getvalue().splitlines())), 1)

    def test_environment_status_uses_colored_icons_and_plain_fallback(self):
        data = {
            'time': '2026-10-27 20:00:00 +0800',
            'fx_installed': True,
            'proxy_available': True,
            'vm_available': True,
            'network_component_valid': True,
            'guest': {
                'vulkan': True, 'verified_network': True, 'ipv4_only': True,
                'steam_proxy': True, 'steam_logged_on': False,
                'tool': 'proton-je-11.0-20261014-3',
                'fex': 'ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf',
                'wine_core': h.WINE_CORE_SHA256,
                'ntdll': 'a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe',
                'launch': h.WORKING_LAUNCH, 'game_pids': [],
            },
        }
        with patch.object(menu, 'color_enabled', return_value=True):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                menu.print_status(data)
        rendered = output.getvalue()
        self.assertIn('● [OK]', menu.ANSI.sub('', rendered))
        self.assertIn('● [!!]', menu.ANSI.sub('', rendered))
        self.assertIn('\x1b[1;38;5;114m', rendered)
        self.assertIn('\x1b[38;5;196m', rendered)

        with patch.object(menu, 'color_enabled', return_value=False):
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                menu.print_status(data)
        self.assertNotIn('\x1b[', output.getvalue())
        self.assertIn('● [OK]', output.getvalue())
        self.assertIn('● [!!]', output.getvalue())

    def test_tun_environment_keeps_game_proxy_but_not_steam_process_proxy(self):
        data = {
            'fx_installed': True, 'proxy_available': True, 'vm_available': True,
            'network_component_valid': True, 'network_mode': 'tun',
            'expected_launch': h.TUN_LAUNCH,
            'guest': {
                'vulkan': True, 'verified_network': True, 'ipv4_only': True,
                'steam_proxy': False, 'steam_proxy_config': False, 'steam_logged_on': True,
                'tool': 'proton-je-11.0-20261014-3',
                'fex': 'ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf',
                'wine_core': h.WINE_CORE_SHA256,
                'ntdll': 'a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe',
                'launch': h.TUN_LAUNCH, 'game_pids': [],
            },
        }
        old_lang = menu.LANG
        menu.LANG = 'zh'
        try:
            output = io.StringIO()
            with patch.object(menu, 'color_enabled', return_value=False), contextlib.redirect_stdout(output):
                    menu.print_status(data)
        finally:
            menu.LANG = old_lang
        rendered = output.getvalue()
        self.assertIn('● [OK] Steam HTTP 代理已关闭（TUN）', rendered)
        self.assertIn('● [OK] 已验证的完整启动项', rendered)
        self.assertIn('● [OK] 已保存游戏 Host HTTPS 代理',rendered)

    def test_language_menu_validation_and_switching(self):
        with tempfile.TemporaryDirectory() as folder, patch.dict(menu.os.environ, {'HD2FX_SETTINGS_FILE':str(Path(folder)/'settings.json')}):
            data=menu.prefs.load();data['ssh_configured']=True;menu.prefs.save(data)
            result = subprocess.run([str(ROOT/'启动绝地潜兵2.command')], input='11\n2\nx\n7\n1\n0\n', text=True, capture_output=True)
        self.assertEqual(result.returncode, 0)
        for text in ['Enter 01–10, or 0 to go back.', 'Helldivers 2 · FX Launcher', 'Enter a number from 0 to 10.', '绝地潜兵 2 · FX 启动助手']:
            self.assertIn(text, result.stdout)

    def test_configuration_never_interrupts_active_game_or_installer(self):
        for pids, apps in [(['123'], ['553850']), ([], ['553850']), ([], ['42'])]:
            with self.subTest(pids=pids, apps=apps), patch.object(h, 'reachable', return_value=True), patch.object(h, 'connect'), patch.object(h, 'state', return_value={'verified_network': True, 'game_pids': pids, 'apps': apps}), patch.object(h, 'activate_fx') as activate, patch.object(h, 'remote') as remote, patch.object(h, 'configure_launch_options') as configure:
                with self.assertRaisesRegex(RuntimeError, '正常退出'):
                    h.main(configure_only=True)
                activate.assert_not_called()
                remote.assert_not_called()
                configure.assert_not_called()

    def test_configuration_backs_up_original_options_before_native_update(self):
        before = {'launch': '%command% --custom-option', 'tool': 'proton-je-11.0-20261014-3'}
        response = {'result': {'result': {'type': 'string', 'value': '{"saved":true}'}}}
        with tempfile.TemporaryDirectory() as folder, patch.object(h, 'ROOT', Path(folder)), patch.object(h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, json.dumps(response))) as native, patch.object(h, 'say'):
            h.configure_launch_options(before)
            backup = next((Path(folder)/'launcher-20261026/backups').glob('*.json'))
            self.assertEqual(json.loads(backup.read_text()), before)
            self.assertEqual(backup.stat().st_mode & 0o777, 0o600)
            self.assertIn('SetAppLaunchOptions(553850,expected)', native.call_args.args[0][2])
            self.assertIn(h.WORKING_LAUNCH, native.call_args.args[0][2])
            self.assertNotIn('shell', native.call_args.kwargs)

    def test_native_javascript_failure_is_not_reported_as_success(self):
        response = {'result': {'exceptionDetails': {'text': 'Uncaught'}, 'result': {}}}
        with tempfile.TemporaryDirectory() as folder, patch.object(h, 'ROOT', Path(folder)), patch.object(h.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, json.dumps(response))), patch.object(h, 'say') as say:
            with self.assertRaisesRegex(RuntimeError, '未确认'):
                h.configure_launch_options({'launch': 'original', 'tool': 'original'})
            say.assert_not_called()
            self.assertEqual(len(list((Path(folder)/'launcher-20261026/backups').glob('*.json'))), 1)

    def test_report_does_not_export_arbitrary_launch_options(self):
        with tempfile.TemporaryDirectory() as folder, patch.object(menu, 'ROOT', Path(folder)), patch.object(menu, 'collect_status', return_value={'guest': {'launch': 'SENSITIVE=value %command% --use-d3d11'}}), contextlib.redirect_stdout(io.StringIO()):
            (Path(folder)/'launcher-20261026').mkdir()
            menu.export_report()
            report = next((Path(folder)/'launcher-20261026/reports').glob('*.json'))
            data = json.loads(report.read_text())
            self.assertNotIn('launch', data['guest'])
            self.assertNotIn('SENSITIVE', report.read_text())
            self.assertTrue(data['guest']['dx11_requested'])
            self.assertEqual(report.stat().st_mode & 0o777, 0o600)


if __name__ == '__main__':
    unittest.main()
