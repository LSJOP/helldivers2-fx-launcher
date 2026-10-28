import contextlib
import copy
import fcntl
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import select
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('i18n_menu_test',HERE/'menu.py')
menu=importlib.util.module_from_spec(spec);spec.loader.exec_module(menu)
loc=menu.i18n;ui=menu.ui2


class LocalizationTests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.environment=patch.dict(os.environ,{'HD2FX_SETTINGS_FILE':str(Path(self.folder.name)/'settings.json')})
        self.environment.start();menu.LANG='en'

    def tearDown(self):
        self.environment.stop();self.folder.cleanup();loc.catalog.cache_clear()

    def test_ten_independent_catalogs_have_complete_core_and_matching_fields(self):
        self.assertEqual(len(loc.CODES),10)
        english=loc.catalog('en')['strings']
        for code in loc.CODES:
            self.assertTrue((loc.LOCALES/(code+'.json')).is_file())
            strings=loc.catalog(code)['strings']
            self.assertEqual(set(strings),set(english),code)
            for key,value in strings.items():
                self.assertTrue(value.strip(),(code,key))
                self.assertEqual(loc.fields(value),loc.fields(english[key]),(code,key))
                self.assertNotIn('\x1b',value)
            if code!='en':self.assertNotEqual(strings['home.start'],english['home.start'])

    def test_missing_entry_invalid_template_and_unknown_language_fall_back_to_english(self):
        english=loc.catalog('en');foreign=copy.deepcopy(loc.catalog('de'))
        foreign['strings'].pop('home.start');foreign['strings']['ui.small_window']='Kaputt {missing}'
        with patch.object(loc,'catalog',side_effect=lambda code:foreign if code=='de' else english):
            self.assertEqual(loc.text('home.start','de'),'Start game')
            self.assertIn('80x25',loc.text('ui.small_window','de',columns=85,rows=26))
        self.assertEqual(loc.text('home.start','../../bad'),'Start game')
        self.assertEqual(loc.message('A new untranslated diagnostic.','ja'),'A new untranslated diagnostic.')

    def test_missing_or_malformed_language_file_is_not_fatal(self):
        temporary=Path(self.folder.name)/'locales';temporary.mkdir()
        (temporary/'en.json').write_text(json.dumps(loc.catalog('en')))
        (temporary/'fr.json').write_text('{not json')
        with patch.object(loc,'LOCALES',temporary):
            loc.catalog.cache_clear()
            self.assertEqual(loc.text('home.start','fr'),'Start game')
            self.assertEqual(loc.text('home.start','ko'),'Start game')

    def test_legacy_language_alias_migration_and_new_codes(self):
        for raw,expected in [('zh','zh-CN'),('ZH_cn','zh-CN'),('zh-Hant','zh-TW'),('pt_br','pt-BR')]:
            data=menu.prefs.load();data['appearance']['language']=raw
            menu.prefs.save(data)
            self.assertEqual(menu.prefs.load()['appearance']['language'],expected)
        data=menu.prefs.load();data['appearance']['language']='../../bad'
        with self.assertRaises(ValueError):menu.prefs.save(data)

    def test_switching_all_languages_only_changes_launcher_appearance(self):
        before=menu.prefs.load();menu.prefs.save(before)
        with patch.object(menu.helper,'remote') as remote,patch.object(menu.helper,'configure_launch_options') as configure,patch.object(menu.prefs,'VAULT') as vault:
            for index,code in enumerate(loc.CODES,1):
                with patch.object(menu,'select_option',return_value=str(index).zfill(2)):
                    self.assertTrue(menu.choose_language())
                after=menu.prefs.load()
                self.assertEqual(after['ssh'],before['ssh'])
                self.assertEqual(after['appearance']['language'],code)
                self.assertEqual(after['appearance']['emblem'],before['appearance']['emblem'])
            remote.assert_not_called();configure.assert_not_called()
            vault.get.assert_not_called();vault.put.assert_not_called()

    def test_cancel_keeps_language_and_numbered_technical_messages_translate(self):
        menu.LANG='ja'
        with patch.object(menu,'select_option',return_value='0'):
            self.assertFalse(menu.choose_language())
        self.assertEqual(menu.LANG,'ja')
        self.assertEqual(menu.tr('unused','2. Test SSH connection'),'2. SSH 接続テスト')
        self.assertIn('認証',menu.localize('SSH authentication failed. Check the username, password or key in SSH settings.'))
        self.assertIn('Starting Helldivers 2',menu.localize('正在启动绝地潜兵 2……'))

    def test_width_for_cjk_hangul_cyrillic_and_combining_text(self):
        for text,width in [('日本語',6),('한국어',6),('Русский',7),('e\u0301',1),('한',2),('中文',4)]:
            self.assertEqual(ui.text_width(text),width,text)
        self.assertLessEqual(ui.text_width(ui.truncate('環境とネットワーク確認',12)),12)
        self.assertLessEqual(ui.text_width(ui.truncate('Umgebungsüberprüfung',12)),12)

    def test_all_languages_fit_supported_grids_and_keep_latency_visible(self):
        for code in loc.CODES:
            menu.LANG=code
            for columns,rows in [(88,27),(85,26),(80,25),(60,20)]:
                for layout in ['immersive','compact']:
                    status={'latency_vm_ms':8.1,'latency_vm_state':'ready','latency_steam_ms':141.2,'latency_steam_state':'ready'}
                    frame=ui.build_home(columns,rows,code,{'emblem':'2','layout':layout},menu.home_labels(),status)
                    self.assertTrue(all(ui.text_width(line)<=columns for line in frame.plain().splitlines()),(code,columns,layout))
                    for key in ui.ORDER[:-1]:
                        row=frame.positions[key][0]
                        line=''.join(cell[0] for cell in frame.cells[row])
                        self.assertIn('['+key+']',line)
                        self.assertNotIn('…',line,(code,columns,key))
                    readout=''.join(cell[0] for cell in frame.cells[rows-3])
                    self.assertIn('141 ms',readout,(code,columns))
                    self.assertIn('Steam TLS' if columns>=80 else 'TLS',readout)

    def test_language_list_scrolls_and_never_splits_wide_labels(self):
        options=[(str(index).zfill(2),str(index).zfill(2)+'  '+name) for index,(_,name) in enumerate(loc.LANGUAGES,1)]+[('0','0. Back')]
        for index in range(len(options)):
            frame=ui.build_list(40,14,'LANGUAGE',options,index,language='en')
            key=options[index][0]
            self.assertIn(key,frame.positions)
            self.assertLess(frame.positions[key][0],10)
            self.assertTrue(all(ui.text_width(line)<=40 for line in frame.plain().splitlines()))
        self.assertNotIn('01',ui.build_list(40,14,'LANGUAGE',options,9,language='en').positions)

    def test_saved_language_opens_directly_for_each_locale(self):
        data=menu.prefs.load();data['ssh_configured']=True;data['appearance']['intro_animation']=False
        for code in loc.CODES:
            data['appearance']['language']=code;menu.prefs.save(data)
            result=subprocess.run([str(HERE.parent/'启动绝地潜兵2.command')],input='0\n',text=True,capture_output=True,timeout=5)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertIn(loc.text('home.start',code),result.stdout)
            self.assertNotIn('01  简体中文',result.stdout)
        alias=subprocess.run([str(HERE.parent/'启动绝地潜兵2.command'),'--lang','zh'],input='0\n',text=True,capture_output=True,timeout=5)
        self.assertEqual(alias.returncode,0)
        self.assertIn('启动游戏',alias.stdout)

    def test_real_pty_two_digit_selection_scrolling_and_cancel(self):
        program='''import importlib.util
from pathlib import Path
p=Path('launcher-20261026/menu.py');s=importlib.util.spec_from_file_location('m',p);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
options=[(str(i).zfill(2),str(i).zfill(2)+'  '+name) for i,(_,name) in enumerate(m.i18n.LANGUAGES,1)]+[('0','0. Back')]
r=m.ui2.choose_list('LANGUAGE',options,'01','en');print('SELECTED='+r,flush=True)
'''
        for keys,expected in [(b'10\r','10'),(b'09\r','09'),(b'1\r','01'),(b'10\x7f\r','01'),(b'\x1b[6~\r','07'),(b'\x1b','0')]:
            master,slave=pty.openpty();fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',14,48,0,0))
            child=subprocess.Popen([sys.executable,'-c',program],cwd=HERE.parent,stdin=slave,stdout=slave,stderr=slave,env=dict(os.environ,TERM='xterm-256color',NO_COLOR='1'),start_new_session=True)
            os.close(slave);output=b''
            try:
                deadline=time.monotonic()+4
                while b'Enter a number' not in output and time.monotonic()<deadline:
                    if select.select([master],[],[],.1)[0]:output+=os.read(master,65536)
                self.assertIn(b'Enter a number',output)
                os.write(master,keys)
                while b'SELECTED=' not in output and time.monotonic()<deadline:
                    if select.select([master],[],[],.1)[0]:
                        try:output+=os.read(master,65536)
                        except OSError:break
                child.wait(timeout=1)
                self.assertIn(('SELECTED='+expected).encode(),output,(keys,output))
                self.assertIn(b'\x1b[?25h',output);self.assertIn(b'\x1b[?1049l',output)
            finally:
                if child.poll() is None:child.terminate();child.wait(timeout=1)
                os.close(master)


if __name__=='__main__':unittest.main()
