"""UI-only regression tests. All settings and terminal sessions are isolated."""
import ast
import contextlib
import fcntl
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import pty
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import time
import unittest
from unittest.mock import call, patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('ui2_menu_test',HERE/'menu.py')
menu=importlib.util.module_from_spec(spec);spec.loader.exec_module(menu)
ui=menu.ui2


class UI2Tests(unittest.TestCase):
    def setUp(self):
        self.folder=tempfile.TemporaryDirectory()
        self.environment=patch.dict(os.environ,{'HD2FX_SETTINGS_FILE':str(Path(self.folder.name)/'settings.json')})
        self.environment.start();menu.LANG='zh'

    def tearDown(self):
        self.environment.stop();self.folder.cleanup()

    def frame(self,columns=91,rows=27,lang='zh',layout='immersive',emblem='2',selected='1'):
        menu.LANG=lang
        return ui.build_home(columns,rows,lang,{'layout':layout,'emblem':emblem},menu.home_labels(),{},selected)

    def test_bilingual_layouts_keep_all_controls_visible(self):
        for columns,rows in [(91,27),(120,35),(85,26),(80,25),(80,24),(72,20),(60,20)]:
            for lang in ['zh','en']:
                for layout in ['immersive','compact']:
                    with self.subTest(columns=columns,rows=rows,lang=lang,layout=layout):
                        frame=self.frame(columns,rows,lang,layout)
                        self.assertEqual(set(frame.positions),set(ui.ORDER))
                        for key in ui.ORDER[:-1]:
                            row,x,width=frame.positions[key]
                            self.assertLess(row,rows-6)
                            self.assertIn('['+key+']',''.join(cell[0] for cell in frame.cells[row]))
                        self.assertEqual(len(frame.cells),rows)
                        self.assertTrue(all(ui.text_width(line)<=columns for line in frame.plain().splitlines()))
                        self.assertNotIn('…',frame.plain())

    def test_short_terminal_scrolls_focused_option_into_view(self):
        for key in ui.ORDER[:-1]:
            frame=self.frame(40,12,selected=key)
            row,x,width=frame.positions[key]
            self.assertGreaterEqual(row,2);self.assertLess(row,6)
            self.assertIn('['+key+']',''.join(cell[0] for cell in frame.cells[row]))
        frame=self.frame(40,12)
        key='1'
        for expected in ui.ORDER[1:]:
            key=ui.move_selection(key,'down',frame.positions)
            self.assertEqual(key,expected)

    def test_status_bar_shows_playfab_and_udp_probe_summary(self):
        status={
            'latency_vm_ms':53.2,'latency_vm_state':'ready',
            'latency_steam_ms':739.4,'latency_steam_state':'ready',
            'playfab_checked_routes':2,'playfab_reachable':2,'playfab_ms':221.1,
            'udp_samples':4,'udp_successes':4,'udp_ms':128.9,'udp_jitter_ms':48.6,
            'probe_age_seconds':120,
        }
        for columns,rows in [(105,32),(80,25),(60,20)]:
            frame=ui.build_home(columns,rows,'zh',{'layout':'immersive','emblem':'2'},
                                menu.home_labels(),status)
            line=frame.plain().splitlines()[rows-3]
            self.assertIn(('PlayFab 2/2 221 ms' if columns>=80 else 'PF 2/2 221 ms'),line)
            self.assertIn('UDP 4/4 129 ms',line)
            self.assertTrue(all(ui.text_width(value)<=columns for value in frame.plain().splitlines()))
        frame=ui.build_home(105,32,'zh',{'layout':'immersive','emblem':'2'},
                            menu.home_labels(),status)
        self.assertIn('PF/UDP 2m',frame.plain())
        self.assertIn('38;2;85;214;138',frame.ansi())
        partial=dict(status,udp_successes=3)
        self.assertIn('38;2;255;214;0',ui.build_home(
            105,32,'zh',{'layout':'immersive','emblem':'2'},menu.home_labels(),partial).ansi())
        failed=dict(status,playfab_reachable=0,udp_successes=0)
        self.assertIn('38;2;255;87;87',ui.build_home(
            105,32,'zh',{'layout':'immersive','emblem':'2'},menu.home_labels(),failed).ansi())

    def test_two_column_navigation_and_exit(self):
        positions=self.frame().positions
        for current,direction,expected in [('1','down','2'),('1','right','8'),('8','left','1'),('9','left','2'),('5','down','0'),('0','down','1')]:
            self.assertEqual(ui.move_selection(current,direction,positions),expected)

    def test_mode_switch_changes_actual_85_by_26_layout(self):
        compact=self.frame(85,26,layout='compact')
        immersive=self.frame(85,26,layout='immersive')
        self.assertNotEqual(compact.positions['1'][0],immersive.positions['1'][0])
        self.assertIn('设置与工具',immersive.plain())
        self.assertIn('沉浸模式',immersive.plain())
        self.assertIn('已切换：沉浸',ui.layout_notice({'layout':'immersive'},85,26,'zh'))
        small=self.frame(70,24,layout='immersive')
        self.assertIn('自动',small.plain())
        self.assertIn('80×25',ui.layout_notice({'layout':'immersive'},70,24,'zh'))

    def test_four_original_assets_preserved_and_cached(self):
        outputs=[]
        for selection in ['1','2','3','4']:
            art=ui.emblem(selection,25,7)
            self.assertTrue(art);self.assertLessEqual(len(art),7)
            self.assertLessEqual(max(map(len,art)),25)
            outputs.append('\n'.join(art))
        self.assertEqual(len(set(outputs)),4)
        self.frame()
        with patch.object(Path,'read_text',side_effect=AssertionError('redraw read a file')):
            self.frame(selected='2');self.frame(selected='8')

    def test_palette_focus_marker_and_no_color(self):
        self.assertEqual([ui.COLORS[key] for key in ['yellow','background','muted','green','red']],['#FFD600','#101114','#737780','#55D68A','#FF5757'])
        frame=self.frame()
        self.assertIn('☠ [1]',frame.plain())
        self.assertIn('38;2;255;214;0',frame.ansi())
        self.assertIn('38;5;220',frame.ansi(truecolor=False))
        self.assertNotIn('38;2;',frame.ansi(colors=False))
        self.assertIn('☠ [1]',frame.ansi(colors=False))

    def test_old_appearance_migrates_and_switches_without_changing_ssh(self):
        data=menu.prefs.load()
        data['appearance']={'emblem':'4','intro_animation':False}
        menu.prefs.save(data)
        self.assertEqual(menu.prefs.load()['appearance'],{'emblem':'4','intro_animation':False,'layout':'immersive','language':None})
        before=menu.prefs.load()['ssh']
        menu.toggle_layout()
        self.assertEqual(menu.prefs.load()['appearance']['layout'],'compact')
        with patch.object(menu,'select_option',return_value='2'),patch.object(menu,'banner'):
            menu.choose_language()
        self.assertEqual(menu.prefs.load()['appearance']['language'],'en')
        self.assertEqual(menu.prefs.load()['ssh'],before)
        self.assertFalse(menu.prefs.load()['appearance']['intro_animation'])

    def test_second_launch_uses_saved_language_without_prompting(self):
        data=menu.prefs.load();data['ssh_configured']=True;data['appearance']['language']='en';menu.prefs.save(data)
        with patch.object(sys,'argv',['menu.py']),patch.object(menu,'startup_animation'),patch.object(menu,'menu') as home,patch.object(menu,'choose_language') as choose,patch.object(menu,'edit_ssh') as edit:
            self.assertEqual(menu.main(),0)
            self.assertEqual(menu.LANG,'en')
            home.assert_called_once();choose.assert_not_called();edit.assert_not_called()

    def test_launch_dispatch_preserves_existing_arguments(self):
        with patch.object(ui,'choose_home',side_effect=['1','2','0']),patch.object(menu,'dashboard_data',return_value={}) as status,patch.object(menu,'launch_game') as launch,patch('builtins.input',return_value=''),contextlib.redirect_stdout(io.StringIO()):
            menu.menu()
        self.assertEqual(launch.call_args_list,[call(),call(configure=True)])
        self.assertEqual(status.call_count,3)  # Once per home entry, never per key press.


    def terminal(self,keys,auto=False,columns=91,rows=27):
        program='''import importlib.util,json,termios,sys,time
from pathlib import Path
p=Path('launcher-20261026/ui2.py');s=importlib.util.spec_from_file_location('ui',p);ui=importlib.util.module_from_spec(s);s.loader.exec_module(ui)
appearance={'emblem':'2','layout':'immersive'};toggles=[]
def toggle():
 appearance['layout']='compact' if appearance['layout']=='immersive' else 'immersive';toggles.append(appearance['layout']);return appearance
before=termios.tcgetattr(sys.stdin.fileno())
def refresh():
 time.sleep(2);return {'note':'REFRESHED'}
options={'refresh_status':refresh,'refresh_interval':10} if AUTO_REFRESH else {}
try:result=ui.choose_home('en',appearance,{key:'Action '+key for key in ui.ORDER[:-1]}, {},toggle,**options)
except KeyboardInterrupt:result='interrupted'
after=termios.tcgetattr(sys.stdin.fileno())
# Darwin may set PENDIN while restoring canonical mode. It is a kernel retype
# request, not a changed input setting; compare all other flags and controls.
for attrs in [before,after]:attrs[3]&=~getattr(termios,'PENDIN',0)
print('RESULT_JSON='+json.dumps({'result':result,'toggles':toggles,'restored':before==after}),flush=True)
'''
        program=program.replace('AUTO_REFRESH',repr(auto))
        master,slave=pty.openpty()
        fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',rows,columns,0,0))
        process=subprocess.Popen([sys.executable,'-c',program],cwd=HERE.parent,stdin=slave,stdout=slave,stderr=slave,env=dict(os.environ,TERM='xterm-256color'),start_new_session=True)
        os.close(slave);output=b''
        try:
            deadline=time.monotonic()+5
            while b'Snapshot' not in output and time.monotonic()<deadline:
                if select.select([master],[],[],.1)[0]:output+=os.read(master,65536)
            self.assertIn(b'Snapshot',output)
            # Verify idling performs no full redraw before providing input.
            while select.select([master],[],[],.02)[0]:output+=os.read(master,65536)
            self.assertFalse(select.select([master],[],[],.2)[0])
            # This isolated PTY has no controlling foreground process group.
            # Deliver the SIGINT a normal terminal sends for Ctrl-C explicitly.
            if keys==b'\x03':os.kill(process.pid,signal.SIGINT)
            else:os.write(master,keys)
            while b'RESULT_JSON=' not in output and time.monotonic()<deadline:
                if select.select([master],[],[],.1)[0]:
                    try:output+=os.read(master,65536)
                    except OSError:break
            process.wait(timeout=2)
            self.assertEqual(process.returncode,0,output.decode(errors='replace'))
            self.assertIn(b'\x1b[?1049l',output);self.assertIn(b'\x1b[?25h',output);self.assertIn(b'\x1b[?7h',output)
            result=json.loads(output.split(b'RESULT_JSON=')[-1].splitlines()[0])
            self.assertTrue(result['restored'])
            return result
        finally:
            if process.poll() is None:process.terminate();process.wait(timeout=1)
            os.close(master)

    def test_real_pty_default_arrows_digits_refresh_and_escape(self):
        for keys,result in [(b'\r','1'),(b'\x1b[B\r','2'),(b'\x1b[C\r','8'),(b'9\r','9'),(b'10\r','10'),(b'0\r','0'),(b'10\x7f\r','1'),(b'R','3'),(b'\x1b','0'),(b'9\x1b[H\r','1'),(b'\x1b[F\r','0')]:
            with self.subTest(keys=keys):self.assertEqual(self.terminal(keys)['result'],result)

    def test_real_pty_layout_toggle_and_interrupt_restore_terminal(self):
        result=self.terminal(b'm\r')
        self.assertEqual(result['result'],'1');self.assertEqual(result['toggles'],['compact'])
        self.assertEqual(self.terminal(b'\x03')['result'],'interrupted')

    def test_real_pty_slow_refresh_does_not_block_keys_or_manual_refresh(self):
        started=time.monotonic()
        result=self.terminal(b'R\x1b[C\r',auto=True,columns=85,rows=26)
        self.assertEqual(result['result'],'8')
        self.assertLess(time.monotonic()-started,1.5)
        result=self.terminal(b'M\r',columns=85,rows=26)
        self.assertEqual(result['toggles'],['compact'])

    def test_non_tty_mode_key_is_handled(self):
        with patch.object(ui.sys.stdin,'isatty',return_value=False),patch('builtins.input',side_effect=['M','0']),contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(ui.choose_home('zh',{'emblem':'2','layout':'compact'},menu.home_labels(),{},lambda:{'emblem':'2','layout':'immersive'}),'0')
        self.assertIn('已切换',output.getvalue())


if __name__=='__main__':unittest.main()
