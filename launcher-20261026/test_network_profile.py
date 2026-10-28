"""Network mutations are mocked; no real Wi-Fi, credentials or game changes."""
import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import call, patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('network_menu_test', HERE/'menu.py')
menu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(menu)
network = menu.network_profile


def snapshot(wifi=True, wired=True, proxy=True):
    return {'default_interface': 'en5' if wired else 'en6', 'wired_default': wired,
            'wifi': [{'device':'en6','on':wifi}], 'proxy_available':proxy,
            'ready':wired and wifi is False}


class NetworkProfileTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.settings = Path(self.folder.name)/'settings.json'
        self.path = network.settings_path(self.settings)
        self.environment = patch.dict(os.environ, {'HD2FX_SETTINGS_FILE':str(self.settings)})
        self.environment.start()
        menu.LANG = 'en'

    def tearDown(self):
        self.environment.stop()
        self.folder.cleanup()

    def test_discovery_uses_hardware_mapping_not_fixed_interface_numbers(self):
        def command(args, **kwargs):
            if '-listallhardwareports' in args:
                return 'Hardware Port: USB 10/100/1000 LAN\nDevice: en5\n\nHardware Port: Wi-Fi\nDevice: en6\n'
            if args[0] == '/sbin/route':return '    interface: en5\n'
            if 'getifaddr' in args:return '192.0.2.2\n'
            if '-getairportpower' in args:return 'Wi-Fi Power (en6): Off\n'
            self.fail(str(args))
        with patch.object(network, '_command', side_effect=command), patch.object(network.socket, 'create_connection'):
            result = network.inspect()
        self.assertTrue(result['ready'])
        self.assertEqual(result['wifi'], [{'device':'en6','on':False}])
        self.assertEqual(result['default_interface'], 'en5')
        self.assertNotIn('192.0.2', json.dumps(result))

    def test_wifi_only_proxy_missing_and_unknown_wifi_never_mutate(self):
        for status, code in [(snapshot(wired=False),'need_wired'),
                             (snapshot(proxy=False),'need_proxy'),
                             (snapshot(wifi=None),'wifi_unknown')]:
            with self.subTest(code=code), patch.object(network,'inspect',return_value=status), patch.object(network,'_set_wifi') as change:
                with self.assertRaises(network.ProfileError) as caught:network.apply(self.path)
                self.assertEqual(caught.exception.code,code)
                change.assert_not_called()
                self.assertFalse(self.path.exists())

    def test_backup_precedes_change_and_repeated_apply_preserves_original_wifi(self):
        state = {'wifi':True}
        def inspect():return snapshot(state['wifi'])
        def change(device, on):
            self.assertEqual(device,'en6')
            backup=network.load(self.path)
            self.assertIn('en6',backup['restore_wifi'])
            self.assertEqual(self.path.stat().st_mode & 0o777,0o600)
            state['wifi']=on
        with patch.object(network,'inspect',side_effect=inspect), patch.object(network,'_set_wifi',side_effect=change) as mutation:
            self.assertTrue(network.apply(self.path)['ready'])
            self.assertTrue(network.apply(self.path)['ready'])
        self.assertEqual(mutation.call_args_list,[call('en6',False)])
        data=network.load(self.path)
        self.assertEqual(data['restore_wifi'],['en6'])
        self.assertTrue(data['check_before_launch'])
        self.assertFalse(self.settings.exists())

    def test_originally_off_wifi_is_never_claimed_or_enabled_by_restore(self):
        with patch.object(network,'inspect',return_value=snapshot(False)), patch.object(network,'_set_wifi') as change:
            network.apply(self.path)
            self.assertFalse(network.restore(self.path))
        change.assert_not_called()
        self.assertFalse(network.load(self.path)['check_before_launch'])

    def test_failed_post_change_check_rolls_back_wifi_and_settings(self):
        original=copy.deepcopy(network.DEFAULTS)
        original['check_before_launch']=True
        network.save(self.path,original)
        with patch.object(network,'inspect',side_effect=[snapshot(),snapshot(False,wired=False)]), patch.object(network,'_set_wifi') as change:
            with self.assertRaises(network.ProfileError) as caught:network.apply(self.path)
        self.assertEqual(caught.exception.code,'apply_failed_restored')
        self.assertEqual(change.call_args_list,[call('en6',False),call('en6',True)])
        self.assertEqual(network.load(self.path),original)

    def test_failed_rollback_keeps_recovery_record(self):
        with patch.object(network,'inspect',side_effect=[snapshot(),snapshot(False,wired=False)]), patch.object(network,'_set_wifi',side_effect=[None,network.ProfileError('wifi_change_failed')]):
            with self.assertRaises(network.ProfileError) as caught:network.apply(self.path)
        self.assertEqual(caught.exception.code,'rollback_failed')
        data=network.load(self.path)
        self.assertEqual(data['restore_wifi'],['en6'])
        self.assertEqual(data['phase'],'rollback_failed')

    def test_cannot_write_backup_means_no_network_changes(self):
        with patch.object(network,'inspect',return_value=snapshot()), patch.object(network,'save',side_effect=OSError('disk full')), patch.object(network,'_set_wifi') as change:
            with self.assertRaises(OSError):network.apply(self.path)
        change.assert_not_called()

    def test_restore_is_scoped_to_saved_wifi_and_disables_preflight(self):
        data=copy.deepcopy(network.DEFAULTS)
        data.update(restore_wifi=['en6'],check_before_launch=True,phase='applied')
        network.save(self.path,data)
        with patch.object(network,'hardware_ports',return_value={'en5':'Ethernet','en6':'Wi-Fi'}), patch.object(network,'_set_wifi') as change:
            self.assertTrue(network.restore(self.path))
        change.assert_called_once_with('en6',True)
        self.assertEqual(network.load(self.path)['restore_wifi'],[])
        self.assertFalse(network.load(self.path)['check_before_launch'])

    def test_restore_refuses_reassigned_device_and_keeps_backup(self):
        data=copy.deepcopy(network.DEFAULTS);data['restore_wifi']=['en6'];network.save(self.path,data)
        with patch.object(network,'hardware_ports',return_value={'en6':'Ethernet','en7':'Wi-Fi'}), patch.object(network,'_set_wifi') as change:
            with self.assertRaises(network.ProfileError) as caught:network.restore(self.path)
        self.assertEqual(caught.exception.code,'wifi_changed')
        change.assert_not_called()
        self.assertEqual(network.load(self.path)['restore_wifi'],['en6'])

    def test_restore_failure_keeps_pending_devices(self):
        data=copy.deepcopy(network.DEFAULTS);data['restore_wifi']=['en6'];network.save(self.path,data)
        with patch.object(network,'hardware_ports',return_value={'en6':'Wi-Fi'}), patch.object(network,'_set_wifi',side_effect=network.ProfileError('wifi_change_failed')):
            with self.assertRaises(network.ProfileError):network.restore(self.path)
        self.assertEqual(network.load(self.path)['restore_wifi'],['en6'])

    def test_invalid_device_in_backup_never_becomes_a_command_argument(self):
        data=copy.deepcopy(network.DEFAULTS);data['restore_wifi']=['en6; command']
        self.path.write_text(json.dumps(data))
        with patch.object(network,'_set_wifi') as change:
            with self.assertRaises(network.ProfileError):network.restore(self.path)
        change.assert_not_called()

    def test_preflight_is_opt_in_and_never_changes_network_or_blocks_launch(self):
        with patch.object(network,'inspect') as inspect:
            menu.network_launch_notice()
            inspect.assert_not_called()
        network.toggle_check(self.path)
        with patch.object(network,'inspect',return_value=snapshot(wired=False)), patch.object(network,'_set_wifi') as change, patch.object(menu,'refresh_connection'), patch.object(menu.helper,'main') as launch, contextlib.redirect_stdout(io.StringIO()) as output:
            menu.launch_game()
        self.assertIn('Startup continues',output.getvalue())
        change.assert_not_called()
        launch.assert_called_once_with(configure_only=False)

    def test_menu_10_dispatch_and_status_do_not_start_games_or_authenticate(self):
        with patch.object(menu.ui2,'choose_home',side_effect=['10','0']), patch.object(menu,'dashboard_data',return_value={}), patch.object(menu.network_diagnostics,'run') as settings, patch.object(menu.helper,'main') as game, patch('builtins.input',return_value=''):
            menu.menu()
        settings.assert_called_once();game.assert_not_called()
        with patch.object(network,'inspect',return_value=snapshot(False)), patch.object(network,'success_conditions',return_value={'tun_route':True,'system_proxy':False,'flclash_mode':'global','allow_lan':True}), patch.object(menu.helper,'remote') as remote, patch.object(menu.helper,'connect') as connect, contextlib.redirect_stdout(io.StringIO()):
            self.assertTrue(menu.network_status()['ready'])
        remote.assert_not_called();connect.assert_not_called()

    def test_network_status_result_waits_for_return_before_redrawing(self):
        with patch.object(menu,'select_option',side_effect=['2','0']), patch.object(menu,'network_status') as status, patch('builtins.input',return_value='') as pause, contextlib.redirect_stdout(io.StringIO()):
            menu.network_menu()
        status.assert_called_once()
        pause.assert_called_once()


if __name__ == '__main__':unittest.main()
