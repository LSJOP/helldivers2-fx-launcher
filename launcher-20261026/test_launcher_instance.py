"""Real process-lock checks isolated from the user's running launchers."""
import contextlib
import importlib.util
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('instance_menu_test',HERE/'menu.py')
menu=importlib.util.module_from_spec(spec);spec.loader.exec_module(menu)


class LauncherInstanceTests(unittest.TestCase):
    def test_second_process_refused_and_stale_file_does_not_block_restart(self):
        with tempfile.TemporaryDirectory() as folder:
            settings=Path(folder)/'settings.json'
            code='''import importlib.util,sys,os
s=importlib.util.spec_from_file_location('lock',sys.argv[1]);m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
with m.claim(sys.argv[2]) as acquired:
 print(acquired,flush=True)
 if len(sys.argv)>3:os._exit(0)
'''
            args=[sys.executable,'-c',code,str(HERE/'launcher_instance.py'),str(settings)]
            with menu.launcher_instance.claim(settings) as acquired:
                self.assertTrue(acquired)
                result=subprocess.run(args,capture_output=True,text=True,timeout=5)
                self.assertEqual(result.stdout.strip(),'False')
                self.assertEqual(settings.with_name('launcher.lock').stat().st_mode&0o777,0o600)
            result=subprocess.run(args+['simulate_crash'],capture_output=True,text=True,timeout=5)
            self.assertEqual(result.stdout.strip(),'True')
            with menu.launcher_instance.claim(settings) as acquired:self.assertTrue(acquired)

    def test_duplicate_menu_never_starts_game_or_prompts_for_credentials(self):
        with patch.object(menu.sys,'argv',['launcher','--lang','en']),patch.object(menu.launcher_instance,'claim',return_value=contextlib.nullcontext(False)),patch.object(menu,'run_cli') as run,contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(menu.main(),1)
        run.assert_not_called();self.assertIn('already running',output.getvalue())

    def test_read_only_cli_bypasses_menu_lock_but_launch_and_configure_do_not(self):
        for flag in ['--check','--report','--status','--launch','--configure']:
            with self.subTest(flag=flag),patch.object(menu.sys,'argv',['launcher',flag]),patch.object(menu.launcher_instance,'claim',return_value=contextlib.nullcontext(True)) as lock,patch.object(menu,'run_cli',return_value=0) as run:
                self.assertEqual(menu.main(),0)
            run.assert_called_once()
            self.assertEqual(lock.call_count,0 if flag in ['--check','--report','--status'] else 1)


if __name__=='__main__':unittest.main()
