"""Separate launcher prerequisites from locally observable game requirements.

No SSH, VM, Steam, installation or network operations are performed here.
Guest components remain unknown until the existing backend checks them.
"""
import ast
from functools import lru_cache
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from types import SimpleNamespace

ROOT=Path(__file__).resolve().parent.parent
_paths_spec=importlib.util.spec_from_file_location('hd2_dependency_paths',Path(__file__).with_name('runtime_paths.py'))
runtime_paths=importlib.util.module_from_spec(_paths_spec);_paths_spec.loader.exec_module(runtime_paths)
BASE_MODULES=('menu','ui2','i18n','preferences','keychain_store','launcher_instance',
              'status_monitor','network_profile','network_diagnostics','network_records',
              'performance_profile','apple_silicon','performance_catalog','performance_browser','update_checker','update_ui','update_installer','help_center','update_protection','runtime_paths','runtime_selection','fx_versions','fx_updates','fx_version_ui','dependency_discovery','setup_guide','dependencies','launcher_version','launch_safety','guest_safety')


def launcher_problems(root=None):
    root=Path(root) if root is not None else ROOT
    problems=[]
    if sys.version_info<(3,9):problems.append('Python 3.9+')
    paths=['launcher-20261026/'+name+'.py' for name in BASE_MODULES]
    paths+=['goal-dxmt-20261026/start-hd2.py','runtime-requirements.json','tools/runtime_paths.sh',
            'launcher-20261026/locales/en.json','tools/update_worker.py','tools/release_trust.json']
    paths+=['launcher-20261026/assets/emblem-'+name+'.txt' for name in ['wide','compact','1','2','3','4']]
    for name in paths:
        path=root/name
        try:
            text=path.read_text(encoding='utf-8')
            if path.suffix=='.py':ast.parse(text)
            elif path.suffix=='.json':
                data=json.loads(text)
                if not isinstance(data,dict):raise ValueError('Invalid object')
                if name=='runtime-requirements.json' and not isinstance(data.get('components'),list):
                    raise ValueError('Invalid component list')
        except (OSError,ValueError,SyntaxError,UnicodeError):problems.append(name)
    return problems


@lru_cache(maxsize=32)
def _digest(path,size,mtime,ctime):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def file_state(path,expected=None,executable=False):
    path=Path(path)
    try:
        if not path.is_file():return 'missing'
        if executable and not os.access(path,os.X_OK):return 'invalid'
        stat=path.stat()
        if expected and _digest(str(path),stat.st_size,stat.st_mtime_ns,stat.st_ctime_ns)!=expected:
            return 'invalid'
        return 'ready'
    except OSError:return 'unknown'


def node_state():
    candidates=[shutil.which('node'),'/opt/homebrew/bin/node','/usr/local/bin/node',
                str(Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node')]
    for candidate in candidates:
        if not candidate or not Path(candidate).is_file():continue
        try:
            result=subprocess.run([str(candidate),str(ROOT/'tools/check_node.cjs')],
                capture_output=True,timeout=5)
            return 'ready' if result.returncode==0 else 'invalid'
        except subprocess.TimeoutExpired:return 'unknown'
        except OSError:return 'invalid'
    return 'missing'


def _manifest_helper(root):
    data=json.loads((root/'runtime-requirements.json').read_text(encoding='utf-8'))
    components={row['name']:row for row in data['components']}
    fx=components['FX steamac-vm'];network=components['gvproxy-eim']
    paths=runtime_paths.load(root)
    return SimpleNamespace(APP=str(paths.fx_app),RUNTIME_PATHS=paths,
        APP_EXECUTABLE_SHA256=fx['sha256'],GVPROXY=paths.gvproxy_binary,
        GVPROXY_SHA256=network['sha256'],GVPROXY_WRAPPER=paths.gvproxy_wrapper,ROOT=root)


def inspect_runtime(helper=None,root=None):
    root=Path(root) if root is not None else (Path(helper.ROOT) if helper is not None else ROOT)
    rows=[]
    path_error=None
    def add(name,state):rows.append({'id':name,'state':state})
    try:
        helper=helper or _manifest_helper(root)
        path_error=runtime_paths.check_current(getattr(helper,'RUNTIME_PATHS',None))
        add('fx',file_state(Path(helper.APP)/'Contents/MacOS/steamac-vm',helper.APP_EXECUTABLE_SHA256,True))
        states=[file_state(helper.GVPROXY,helper.GVPROXY_SHA256,True),
                file_state(helper.GVPROXY_WRAPPER,executable=True)]
        add('gvproxy',next((value for value in ['missing','invalid','unknown'] if value in states),'ready'))
    except (OSError,ValueError,KeyError,TypeError,AttributeError):
        rows=[];add('fx','unknown');add('gvproxy','unknown')
    if path_error:
        for row in rows:
            if row['id'] in ('fx','gvproxy'):row['state']='unknown'
    add('node',node_state())
    add('ssh','ready' if shutil.which('ssh') else 'missing')
    add('bridge',file_state(root/'launcher-20261026/steam-cdp.mjs'))
    # Unknown is deliberately separate from missing; do not invent Guest results.
    for name in ['steam','fex','proton']:add(name,'unverified')
    local=[row for row in rows if row['state']!='unverified']
    return {'items':rows,'missing_count':sum(row['state']=='missing' for row in local),
            'attention_count':sum(row['state'] in ['invalid','unknown'] for row in local),
            'ready':all(row['state']=='ready' for row in local),'runtime_path_error':path_error}
