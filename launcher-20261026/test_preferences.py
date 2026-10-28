import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('test_menu', HERE/'menu.py')
menu = importlib.util.module_from_spec(spec)
spec.loader.exec_module(menu)
prefs = menu.prefs


class PreferencesTests(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory()
        self.settings = Path(self.folder.name)/'user/settings.json'
        self.environment = patch.dict(os.environ, {'HD2FX_SETTINGS_FILE': str(self.settings)})
        self.environment.start()

    def tearDown(self):
        self.environment.stop()
        self.folder.cleanup()

    def test_first_run_setup_then_skip_on_second_launch(self):
        command = [str(HERE.parent/'启动绝地潜兵2.command'), '--lang', 'en']
        result = subprocess.run(command, input='\n\n\n\n2\n\n0\n', capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
        self.assertIn('First run: set up', result.stdout)
        self.assertTrue(prefs.load()['ssh_configured'])
        self.assertFalse(prefs.load()['ssh']['remember_password'])
        again = subprocess.run(command, input='0\n', capture_output=True, text=True, timeout=10)
        self.assertNotIn('First run: set up', again.stdout)
        self.assertIn('[8] SSH settings', again.stdout)
        self.assertIn('[9] Emblem & appearance', again.stdout)

    def test_all_four_emblems_persist_without_changing_ssh(self):
        data = prefs.load()
        data['ssh'].update(port=2244, username='tester', remember_password=True)
        data['ssh_configured'] = True
        prefs.save(data)
        for choice in ['1', '2', '3', '4']:
            with patch.object(menu, 'select_option', return_value=choice), patch.object(menu, 'banner'), contextlib.redirect_stdout(io.StringIO()):
                menu.select_emblem()
            restored = prefs.load()
            self.assertEqual(restored['appearance']['emblem'], choice)
            self.assertEqual(restored['ssh'], data['ssh'])
            self.assertTrue((HERE/'assets'/('emblem-'+choice+'.txt')).is_file())

    def test_settings_file_contains_no_password_even_if_supplied(self):
        data = prefs.load()
        data['ssh'].update(password='synthetic-secret', remember_password=True)
        prefs.save(data)
        self.assertNotIn('synthetic-secret', self.settings.read_text())
        self.assertNotIn('"password":', self.settings.read_text())
        self.assertTrue(prefs.load()['ssh']['remember_password'])
        self.assertEqual(self.settings.stat().st_mode & 0o777, 0o600)

    def test_each_emblem_fits_narrow_terminal_and_banner_is_visible(self):
        for choice in ['1', '2', '3', '4']:
            data = prefs.load()
            data['appearance']['emblem'] = choice
            prefs.save(data)
            original = (HERE/'assets'/('emblem-'+choice+'.txt')).read_text().splitlines()
            scaled = menu.fit_emblem(original, 45)
            self.assertLessEqual(max(map(len, scaled)), 45)
            output = io.StringIO()
            with patch.object(menu.shutil, 'get_terminal_size', return_value=os.terminal_size((47, 40))), contextlib.redirect_stdout(output):
                menu.banner()
            self.assertIn('H E L L D I V E R S', output.getvalue())
            self.assertIn('█', output.getvalue())

    def test_old_settings_migrate_save_password_default_to_false(self):
        data = copy.deepcopy(prefs.DEFAULTS)
        del data['ssh']['remember_password']
        self.settings.parent.mkdir()
        self.settings.write_text(json.dumps(data))
        self.assertFalse(prefs.load()['ssh']['remember_password'])

    def test_unsafe_hosts_users_and_invalid_ports_rejected(self):
        for key, value in [('host', '-oProxyCommand=bad'), ('host', 'host; command'), ('username', '-root'), ('port', 0), ('port', True), ('cdp_local_port', 2222)]:
            with self.subTest(key=key, value=value):
                data = prefs.load()
                data['ssh'][key] = value
                with self.assertRaises(ValueError):prefs.save(data)
                self.assertFalse(self.settings.exists())

    def test_custom_endpoint_and_key_are_used_without_shell(self):
        key = Path(self.folder.name)/'private key'
        key.touch()
        data = prefs.load()
        data['ssh'].update(host='192.0.2.10', port=2244, username='tester', auth='key', identity_file=str(key))
        client = prefs.SSHClient(data, test=True)
        args = client.command()
        self.assertEqual(args[args.index('-p')+1], '2244')
        self.assertEqual(args[args.index('-l')+1], 'tester')
        self.assertEqual(args[args.index('-i')+1], str(key))
        self.assertEqual(args[-1], '192.0.2.10')
        self.assertNotEqual(client.socket, '/tmp/steamos-hd2-ntsync.sock')

    def test_password_opt_out_never_reads_or_writes_keychain(self):
        client = prefs.SSHClient(prefs.load(), test=True)
        client.password = 'synthetic-secret'
        with patch.object(prefs, 'VAULT') as vault:
            self.assertIsNone(client._saved_password())
            client._remember_authenticated_password()
            vault.get.assert_not_called()
            vault.put.assert_not_called()

    def test_saved_password_is_scoped_to_endpoint_and_used(self):
        data = prefs.load()
        data['ssh']['remember_password'] = True
        client = prefs.SSHClient(data, test=True)
        with patch.object(prefs, 'VAULT') as vault:
            vault.get.return_value = 'synthetic-secret'
            self.assertEqual(client._saved_password(), 'synthetic-secret')
            client.password = 'synthetic-secret'
            client._remember_authenticated_password()
            vault.put.assert_called_once_with(client.settings, 'synthetic-secret')
        different = dict(client.settings, username='another_user')
        self.assertNotEqual(prefs.keychain.account(client.settings), prefs.keychain.account(different))

    def test_remove_password_disables_storage_and_drops_memory_copy(self):
        data = prefs.load()
        data['ssh']['remember_password'] = True
        prefs.save(data)
        with patch.object(prefs, 'VAULT') as vault, patch.object(menu, 'refresh_connection'), contextlib.redirect_stdout(io.StringIO()):
            menu.manage_saved_password(clear=True)
            vault.delete.assert_called_once()
        self.assertFalse(prefs.load()['ssh']['remember_password'])
        self.assertIsNone(menu.helper.CLIENT.password)

    def test_save_password_menu_uses_keychain_and_never_prints_secret(self):
        prefs.save(prefs.load())
        output = io.StringIO()
        with patch.object(prefs, 'VAULT') as vault, patch.object(menu, 'refresh_connection'), patch.object(menu, 'secret_prompt', return_value='synthetic-secret'), contextlib.redirect_stdout(output):
            menu.manage_saved_password()
            vault.put.assert_called_once()
            self.assertEqual(vault.put.call_args.args[1], 'synthetic-secret')
        self.assertTrue(prefs.load()['ssh']['remember_password'])
        self.assertNotIn('synthetic-secret', self.settings.read_text())
        self.assertNotIn('synthetic-secret', output.getvalue())

    def test_disabling_storage_in_setup_removes_saved_password(self):
        data = prefs.load()
        data['ssh']['remember_password'] = True
        data['appearance']['emblem'] = '4'
        prefs.save(data)
        with patch.object(prefs, 'VAULT') as vault, patch.object(menu, 'prompt', side_effect=['','','','','']), patch.object(menu, 'select_option', return_value='2'), patch.object(menu, 'refresh_connection'), contextlib.redirect_stdout(io.StringIO()):
            menu.edit_ssh()
            vault.delete.assert_called_once()
        self.assertFalse(prefs.load()['ssh']['remember_password'])
        self.assertEqual(prefs.load()['appearance']['emblem'], '4')

    def test_fake_ssh_password_prompt_and_auth_failure(self):
        fake = Path(self.folder.name)/'ssh'
        fake.write_text('''#!/usr/bin/python3
import os,sys,termios
if '-O' in sys.argv:sys.exit(1 if 'check' in sys.argv else 0)
if '-M' not in sys.argv:
 print('HD2FX_SSH_OK');sys.exit(0)
attributes=termios.tcgetattr(0);attributes[3] &= ~termios.ECHO;termios.tcsetattr(0,termios.TCSANOW,attributes)
sys.stderr.write('SSH password: ');sys.stderr.flush()
value=sys.stdin.readline().strip()
if value=='synthetic-secret' and os.environ.get('HD2FX_FAKE_DENY')!='1':sys.exit(0)
sys.stderr.write('Permission denied.');sys.stderr.flush();sys.exit(255)
''')
        fake.chmod(0o700)
        with patch.dict(os.environ, {'PATH': self.folder.name+os.pathsep+os.environ['PATH']}), patch.object(prefs, 'VAULT') as vault:
            data = prefs.load();data['ssh']['remember_password'] = True
            vault.get.return_value = None
            client = prefs.SSHClient(data, test=True)
            client.prompt_secret = Mock(return_value='synthetic-secret')
            client.connect_once()
            client.prompt_secret.assert_called_once()
            vault.put.assert_called_once_with(client.settings, 'synthetic-secret')
            self.assertNotIn('synthetic-secret', client.command())
            vault.put.reset_mock()
            with patch.dict(os.environ, {'HD2FX_FAKE_DENY': '1'}):
                other = prefs.SSHClient(data, test=True)
                other.prompt_secret = Mock(return_value='wrong')
                with self.assertRaises(prefs.AuthenticationError):other.connect_once()
                vault.put.assert_not_called()

    def test_real_terminal_arrow_return_and_escape_restore_terminal(self):
        program = """import importlib.util
from pathlib import Path
p=Path('launcher-20261026/menu.py');s=importlib.util.spec_from_file_location('m',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);m.LANG='en'
choice=m.select_option('TEST MENU',[('1','1. First'),('2','2. Second'),('0','0. Back')])
print('SELECTED='+choice,flush=True)
"""
        for sequence, expected in [(b'\x1b[B\r', '2'), (b'\x1b', '0'), (b'0\r', '0')]:
            master, slave = pty.openpty()
            process = subprocess.Popen([sys.executable, '-c', program], cwd=HERE.parent, stdin=slave, stdout=slave, stderr=slave, env=dict(os.environ, TERM='xterm-256color'), start_new_session=True)
            os.close(slave)
            output = b''
            try:
                end = time.monotonic()+5
                while b'Numbers supported' not in output and time.monotonic()<end:
                    if select.select([master],[],[],.2)[0]:output += os.read(master,65536)
                self.assertIn(b'Numbers supported', output)
                os.write(master,sequence)
                while process.poll() is None and time.monotonic()<end:
                    if select.select([master],[],[],.2)[0]:
                        try:output += os.read(master,65536)
                        except OSError:break
                process.wait(timeout=2)
                try:
                    while select.select([master],[],[],0)[0]:
                        chunk=os.read(master,65536)
                        if not chunk:break
                        output+=chunk
                except OSError:pass
                self.assertIn(('SELECTED='+expected).encode(), output)
                self.assertIn(b'\x1b[?25h', output)
            finally:
                if process.poll() is None:process.terminate();process.wait(timeout=2)
                os.close(master)


if __name__ == '__main__':
    unittest.main()
