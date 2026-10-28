"""Replay startup decisions against the successful record without live writes."""
import contextlib
import importlib.util
import io
import itertools
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import Mock, patch

HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('success_network_menu',HERE/'menu.py')
menu=importlib.util.module_from_spec(spec);spec.loader.exec_module(menu)
h=menu.helper


class SuccessfulNetworkTests(unittest.TestCase):
    def run_setup(self, *, tun=True, port=True, steam_proxy=False, saved_proxy=False, launch=None, apps=None):
        state={'verified_network':True,'game_pids':[], 'apps':apps or [],'vulkan':True,'ipv4_only':True,
               'fex':'ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf',
               'ntdll':'a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe',
               'tool':'proton-je-11.0-20261014-3','wine_core':h.WINE_CORE_SHA256,
               'launch':launch or h.PROXY_LAUNCH,'steam_proxy':steam_proxy,
               'steam_proxy_config':saved_proxy,'steam_pids':['123'],'steam_logged_on':True}
        with contextlib.ExitStack() as stack:
            for name,value in [('refresh_settings',None),('vm_reachable',True),('connect',None),('state',state),('activate_fx',None),('tun_active',tun),('system_http_proxy_enabled',False),('start_proxy',None),('reachable',port),('say',None),('report_progress',None)]:
                stack.enter_context(patch.object(h,name,return_value=value))
            proxy=stack.enter_context(patch.object(h,'configure_steam_proxy'))
            options=stack.enter_context(patch.object(h,'configure_launch_options'))
            remote=stack.enter_context(patch.object(h,'remote'))
            stack.enter_context(patch.object(h.time,'sleep'))
            stack.enter_context(patch.object(h.time,'monotonic',side_effect=itertools.count(0,10)))
            opener=Mock();opener.open.side_effect=lambda *a,**kw:io.StringIO('[{"title":"SharedJSContext"}]')
            stack.enter_context(patch.object(h.urllib.request,'build_opener',return_value=opener))
            stack.enter_context(patch.object(h.sys,'argv',['test']))
            h.main(configure_only=True)
        return proxy,options,remote

    def test_tun_reproduces_successful_saved_launch_and_does_not_enable_steam_proxy(self):
        baseline=json.loads((HERE/'fixtures/launch-options.json').read_text())
        self.assertEqual(h.required_launch(),baseline['helper_state']['launch'])
        proxy,options,remote=self.run_setup()
        proxy.assert_not_called();remote.assert_not_called()
        options.assert_not_called()  # Already matches: no duplicate backup/write.

    def test_tun_repairs_proxy_free_saved_options_and_removes_only_steam_proxy(self):
        proxy,options,remote=self.run_setup(steam_proxy=True,saved_proxy=True,launch=h.BASE_LAUNCH)
        proxy.assert_called_once_with(False)
        options.assert_called_once()
        self.assertEqual(options.call_args.args[1],h.PROXY_LAUNCH)
        remote.assert_not_called()

    def test_tun_still_requires_host_proxy_listener(self):
        with self.assertRaisesRegex(RuntimeError,'7890'):self.run_setup(port=False)

    def test_no_tun_retains_existing_http_proxy_fallback(self):
        proxy,options,remote=self.run_setup(tun=False,steam_proxy=True,saved_proxy=True)
        proxy.assert_not_called();remote.assert_not_called()
        options.assert_not_called()

    def test_launch_options_wait_until_steam_api_and_login_are_ready(self):
        ticks=[]
        # No API write may happen during the readiness wait. A prior mismatch
        # used to trigger one here before the SharedJSContext existed.
        def waiting(*args):
            ticks.append('wait')
            self.assertFalse(configure.called)
        state={'verified_network':True,'game_pids':[],'apps':[],'vulkan':True,'ipv4_only':True,
               'fex':'ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf',
               'ntdll':'a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe',
               'tool':'proton-je-11.0-20261014-3','wine_core':h.WINE_CORE_SHA256,'launch':h.BASE_LAUNCH,
               'steam_proxy':False,'steam_proxy_config':False,'steam_pids':['123'],'steam_logged_on':True}
        with contextlib.ExitStack() as stack:
            for name,value in [('refresh_settings',None),('vm_reachable',True),('connect',None),('state',state),('activate_fx',None),('tun_active',True),('system_http_proxy_enabled',False),('start_proxy',None),('reachable',True),('say',None),('report_progress',None)]:
                stack.enter_context(patch.object(h,name,return_value=value))
            configure=stack.enter_context(patch.object(h,'configure_launch_options'))
            stack.enter_context(patch.object(h.time,'sleep',side_effect=waiting))
            stack.enter_context(patch.object(h.time,'monotonic',side_effect=itertools.count(0,10)))
            opener=Mock();opener.open.side_effect=[io.StringIO('[]'),io.StringIO('[{"title":"SharedJSContext"}]')]
            stack.enter_context(patch.object(h.urllib.request,'build_opener',return_value=opener))
            stack.enter_context(patch.object(h.sys,'argv',['test']))
            h.main(configure_only=True)
        self.assertTrue(ticks);configure.assert_called_once()

    def test_active_app_refuses_before_any_proxy_or_launch_change(self):
        with self.assertRaisesRegex(RuntimeError,'正常退出'):self.run_setup(apps=['553850'])

    def test_local_conditions_distinguish_generated_mode_from_live_route_without_secrets(self):
        network=menu.network_profile
        with tempfile.TemporaryDirectory() as folder:
            home=Path(folder);p=home/'Library/Application Support/com.follow.clash/config.yaml';p.parent.mkdir(parents=True)
            p.write_text('mode: "global"\nallow-lan: true\nproxies:\n  - password: DO_NOT_COPY\n')
            with patch.object(network.Path,'home',return_value=home),patch.object(network,'_command',side_effect=[' interface: utun4\n','HTTPEnable : 0\nHTTPSEnable : 0\nSOCKSEnable : 0\n']):
                result=network.success_conditions()
            self.assertEqual(result,{'tun_route':True,'system_proxy':False,'flclash_mode':'global','allow_lan':True})
            self.assertNotIn('DO_NOT_COPY',json.dumps(result))
            self.assertEqual(p.read_text(),'mode: "global"\nallow-lan: true\nproxies:\n  - password: DO_NOT_COPY\n')
        with patch.object(network.Path,'home',return_value=Path('/nonexistent-fixture')),patch.object(network,'_command',return_value=''):
            self.assertTrue(all(v is None for v in network.success_conditions().values()))

    def test_network_panel_fits_ten_languages_without_authentication(self):
        status={'default_interface':'en0','wired_default':True,'wifi':[{'device':'en1','on':False}],'proxy_available':True,'ready':True}
        conditions={'tun_route':True,'system_proxy':False,'flclash_mode':'global','allow_lan':True}
        old=menu.LANG
        try:
            for language in menu.i18n.CODES:
                menu.LANG=language
                for columns in [88,80,60,40]:
                    output=io.StringIO()
                    with self.subTest(language=language,columns=columns),patch.object(menu.network_profile,'inspect',return_value=status),patch.object(menu.network_profile,'success_conditions',return_value=conditions),patch.object(menu.shutil,'get_terminal_size',return_value=__import__('os').terminal_size((columns,24))),patch.object(h,'remote') as remote,contextlib.redirect_stdout(output):
                        menu.network_status()
                    self.assertTrue(all(menu.width(line)<=columns for line in output.getvalue().splitlines()))
                    remote.assert_not_called()
        finally:menu.LANG=old


if __name__=='__main__':unittest.main()
