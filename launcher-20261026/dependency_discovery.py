"""Bounded, session-only dependency discovery. Never adopts runtime paths.

FX/network files and wrappers are read, never executed. Only a native Node binary
may run the reviewed offline capability probe. No shells, managers or installers.
Private paths stay inside Session; public_summary emits no paths or raw errors.
"""
import ast
import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shlex
import shutil
import stat
import struct
import subprocess
import sys
import time

COMPONENTS = ('node','fx','gvproxy')
STATES = ('ready','found_unverified','path_missing','version_mismatch','hash_mismatch','unusable','probe_failed')
SOURCES = ('runtime','manifest','path','homebrew','official','manager','applications','related_project','manual')
REASONS = ('local_match','runtime_differs','not_found','executable_missing','permission','not_regular',
           'symlink_loop','hash_mismatch','hash_unknown','version_mismatch','probe_failed',
           'shim_unverified','native_unverified','options_unverified','probe_source_unverified',
           'changed_during_check','limit_reached','metadata_unverified','wrapper_unverified')
PROBE_SHA256 = '91a16ba36afab8681b2a95d8504b0ebfafc82421b79c5dea9808334c1fa8d915'
WRAPPER_SHA256 = '80dca2b7d0b04dae44f46b4b6dc9e2735434fdeaa241925f8061613498911d3d'
MAX_CANDIDATES = 24
MAX_FILE_BYTES = 256*1024*1024


def version_number(value):
    return value if isinstance(value,str) and len(value)<=32 and re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?',value) else None


def manual_path(value,root,home=None):
    """Finder escapes/quotes are parsed as data, never expanded/executed as Shell."""
    if not isinstance(value,str) or not value.strip():return None
    if len(value)>4096 or any(ord(c)<32 or ord(c)==127 for c in value):raise ValueError('Invalid path input')
    value=value.strip();home=Path(home) if home is not None else Path.home()
    def expand(text):
        if text=='~':return home
        if text.startswith('~/'):return home/text[2:]
        path=Path(text)
        return path if path.is_absolute() else Path(root)/path
    raw=expand(value)
    try:
        if raw.exists() or raw.is_symlink():return raw
    except (OSError,ValueError):pass
    try:
        words=shlex.split(value,posix=True)
        if len(words)==1:return expand(words[0])
    except ValueError:pass
    return raw


def _expression(node,names,home,env):
    """Restricted AST path reader. No eval, imports or backend execution."""
    if isinstance(node,ast.Constant) and isinstance(node.value,str):return node.value
    if isinstance(node,ast.Name) and node.id in names:return names[node.id]
    if isinstance(node,ast.BinOp) and isinstance(node.op,ast.Div):
        return Path(_expression(node.left,names,home,env))/_expression(node.right,names,home,env)
    if isinstance(node,ast.Call) and not node.keywords:
        if isinstance(node.func,ast.Name) and node.func.id=='str' and len(node.args)==1:
            return str(_expression(node.args[0],names,home,env))
        if isinstance(node.func,ast.Attribute) and node.func.attr=='home' and not node.args:
            if ast.unparse(node.func.value) in ('Path','pathlib.Path'):return home
        if isinstance(node.func,ast.Attribute) and node.func.attr=='which' and len(node.args)==1:
            if ast.unparse(node.func.value)=='shutil' and isinstance(node.args[0],ast.Constant) and node.args[0].value=='node':
                return shutil.which('node',path=env['PATH'] if 'PATH' in env else os.defpath)
    raise ValueError('Unrecognized runtime path expression')


def runtime_rules(root,home,env):
    paths={key:None for key in ('fx','gvproxy','wrapper')};hashes={};nodes=[]
    try:
        tree=ast.parse((Path(root)/'goal-dxmt-20261026/start-hd2.py').read_text(encoding='utf-8'))
        names={'ROOT':Path(root)}
        for entry in tree.body:
            if isinstance(entry,ast.Assign) and len(entry.targets)==1 and isinstance(entry.targets[0],ast.Name):
                key=entry.targets[0].id
                if key in ('APP','NETWORK_DIR','GVPROXY','GVPROXY_WRAPPER'):
                    try:names[key]=_expression(entry.value,names,home,env)
                    except (ValueError,TypeError):pass
                elif key in ('APP_EXECUTABLE_SHA256','GVPROXY_SHA256') and isinstance(entry.value,ast.Constant):hashes[key]=entry.value.value
            elif isinstance(entry,ast.FunctionDef) and entry.name=='find_node':
                assignment=next((n for n in entry.body if isinstance(n,ast.Assign) and any(isinstance(t,ast.Name) and t.id=='candidates' for t in n.targets)),None)
                reference=ast.parse('for candidate in candidates:\n if candidate and pathlib.Path(candidate).is_file():return str(candidate)').body[0]
                conventional=(len(entry.body)==3 and isinstance(entry.body[1],ast.For) and ast.dump(entry.body[1])==ast.dump(reference))
                if conventional and assignment and isinstance(assignment.value,ast.List):
                    try:nodes=[_expression(n,names,home,env) for n in assignment.value.elts]
                    except (ValueError,TypeError):nodes=[]
        if 'APP' in names:paths['fx']=Path(names['APP'])/'Contents/MacOS/steamac-vm'
        paths['gvproxy']=Path(names['GVPROXY']) if 'GVPROXY' in names else None
        paths['wrapper']=Path(names['GVPROXY_WRAPPER']) if 'GVPROXY_WRAPPER' in names else None
    except (OSError,ValueError,SyntaxError,TypeError,UnicodeError):pass
    return paths,{'fx':hashes.get('APP_EXECUTABLE_SHA256'),'gvproxy':hashes.get('GVPROXY_SHA256')},nodes


def _resolve(path):
    return Path(path).resolve() if path is not None else None


def same_path(a,b):
    try:return a is not None and b is not None and _resolve(a)==_resolve(b)
    except (OSError,RuntimeError,ValueError):return False


def _identity(info):
    return info.st_dev,info.st_ino,info.st_size,info.st_mtime_ns,info.st_ctime_ns


def digest(path):
    """Bounded regular-file read with concurrent-change detection."""
    flags=os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0)
    fd=os.open(path,flags)
    try:
        before=os.fstat(fd)
        if not stat.S_ISREG(before.st_mode):raise ValueError('not_regular')
        if before.st_size>MAX_FILE_BYTES:raise ValueError('limit_reached')
        value=hashlib.sha256();count=0;deadline=time.monotonic()+5
        while True:
            data=os.read(fd,1024*1024)
            if not data:break
            count+=len(data)
            if count>MAX_FILE_BYTES or time.monotonic()>deadline:raise ValueError('limit_reached')
            value.update(data)
        if _identity(before)!=_identity(os.fstat(fd)) or _identity(before)!=_identity(Path(path).stat()):raise ValueError('changed_during_check')
        return value.hexdigest()
    finally:os.close(fd)


def _children(parent,pattern,limit=16):
    # One directory only; never recursive glob/rglob or a whole-disk search.
    try:return list(itertools.islice(Path(parent).glob(pattern),limit))
    except (OSError,ValueError):return []


def related_projects(root):
    result=[]
    for path in _children(Path(root).parent,'HD2-*'):
        try:
            if path!=root and (path/'goal-dxmt-20261026/start-hd2.py').is_file():result.append(path)
        except OSError:pass
    return result


def native_node(path):
    """Avoid shell/manager shims and Rosetta install prompts during discovery."""
    text=str(path)
    if Path(path).name!='node':return False
    if any(marker in text for marker in ('/shims/','/.volta/bin/','/volta/bin/')):return False
    with Path(path).open('rb') as stream:head=stream.read(1024)
    if sys.platform!='darwin':return head.startswith(b'\x7fELF')
    machine=platform.machine();cpu=0x0100000c if machine=='arm64' else 0x01000007 if machine=='x86_64' else None
    if len(head)>=8 and head[:4] in (b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf'):
        endian='<' if head[:4]==b'\xcf\xfa\xed\xfe' else '>'
        return struct.unpack(endian+'I',head[4:8])[0]==cpu
    fat={b'\xca\xfe\xba\xbe':('>',20),b'\xbe\xba\xfe\xca':('<',20),b'\xca\xfe\xba\xbf':('>',32),b'\xbf\xba\xfe\xca':('<',32)}
    if len(head)>=8 and head[:4] in fat:
        endian,step=fat[head[:4]];count=struct.unpack(endian+'I',head[4:8])[0]
        return 0<count<=16 and len(head)>=8+count*step and any(struct.unpack(endian+'I',head[8+i*step:12+i*step])[0]==cpu for i in range(count))
    return False


def manifest_rules(root):
    paths={};hashes={}
    try:
        data=json.loads((Path(root)/'runtime-requirements.json').read_text(encoding='utf-8'))
        for key,name in (('fx','FX steamac-vm'),('gvproxy','gvproxy-eim')):
            row=next(c for c in data['components'] if c['name']==name)
            paths[key]=Path(root)/row['path'];hashes[key]=row.get('sha256')
    except (OSError,ValueError,KeyError,TypeError,StopIteration,UnicodeError):pass
    return paths,hashes


class Session:
    def __init__(self,root,home=None,env=None):
        self.root=Path(root);self.home=Path(home) if home is not None else Path.home()
        self.env=dict(os.environ if env is None else env);self.manual={key:[] for key in COMPONENTS};self.results={};self.cache={};self.scope_limited={}
        self.runtime,self.runtime_hash,self.node_runtime_candidates=runtime_rules(self.root,self.home,self.env)
        self.manifest,self.expected_hash=manifest_rules(self.root)
        # Mirrors the current backend's first-existing-file rule, not best version.
        self.runtime['node']=next((Path(p) for p in self.node_runtime_candidates if p and self._is_file(p)),None)

    @staticmethod
    def _is_file(path):
        try:return Path(path).is_file()
        except (OSError,ValueError):return False

    def candidates(self,key):
        result=[]
        def add(path,source):
            if path is not None:result.append((Path(path),source))
        add(self.runtime.get(key),'runtime');add(self.manifest.get(key),'manifest')
        if key=='node':
            for p in self.node_runtime_candidates:add(p,'runtime')
            for directory in itertools.islice(self.env.get('PATH','').split(os.pathsep),32):
                if directory:add(Path(directory)/'node','path')
            for prefix in ('/opt/homebrew','/usr/local'):
                add(Path(prefix)/'bin/node','homebrew')
                for p in _children(Path(prefix)/'opt','node*',8):
                    if re.fullmatch(r'node(?:@\d+)?',p.name):add(p/'bin/node','homebrew')
            add(Path('/usr/local/bin/node'),'official')
            if self.env.get('NVM_BIN'):add(Path(self.env['NVM_BIN'])/'node','manager')
            add(Path(self.env.get('NVM_DIR',str(self.home/'.nvm')))/'current/bin/node','manager')
            if self.env.get('FNM_MULTISHELL_PATH'):add(Path(self.env['FNM_MULTISHELL_PATH'])/'bin/node','manager')
            add(Path(self.env.get('VOLTA_HOME',str(self.home/'.volta')))/'bin/node','manager')
        else:
            relative=self.manifest.get(key)
            if relative:
                try:
                    relative=relative.relative_to(self.root)
                    for project in related_projects(self.root):add(project/relative,'related_project')
                except ValueError:pass
            if key=='fx':
                for directory in (Path('/Applications'),self.home/'Applications'):
                    for app in _children(directory,'*.app',64):
                        if app.name.casefold().startswith('fx') or 'steamac' in app.name.casefold():add(app,'applications')
        # Manual entries always get examined even if the automatic scope is full.
        unique=[];seen={}
        for path,source in result:
            try:alias=str(_resolve(self.executable(key,path)))
            except (OSError,ValueError,RuntimeError):alias=str(path)
            if alias in seen:
                if source not in seen[alias]['sources']:seen[alias]['sources'].append(source)
                continue
            row={'path':path,'sources':[source]};seen[alias]=row;unique.append(row)
        def priority(row):
            if any(v in row['sources'] for v in ('runtime','manifest')):return 0
            try:return 1 if row['path'].exists() else 2
            except (OSError,ValueError,RuntimeError):return 2
        unique.sort(key=priority)
        self.scope_limited[key]=len(unique)>MAX_CANDIDATES
        unique=unique[:MAX_CANDIDATES]
        seen={}
        for row in unique:
            try:alias=str(_resolve(self.executable(key,row['path'])))
            except (OSError,ValueError,RuntimeError):alias=str(row['path'])
            seen[alias]=row
        for path in self.manual[key]:
            try:alias=str(_resolve(self.executable(key,path)))
            except (OSError,ValueError,RuntimeError):alias=str(path)
            if alias in seen:
                if 'manual' not in seen[alias]['sources']:seen[alias]['sources'].append('manual')
            else:
                row={'path':path,'sources':['manual']};seen[alias]=row;unique.append(row)
        return unique

    @staticmethod
    def executable(key,path):
        path=Path(path)
        return path/'Contents/MacOS/steamac-vm' if key=='fx' and path.suffix.casefold()=='.app' else path

    def add_manual(self,key,value):
        if key not in COMPONENTS:raise ValueError('Unknown component')
        path=manual_path(value,self.root,self.home)
        if path is None:return False
        if path not in self.manual[key]:
            if len(self.manual[key])>=8:raise ValueError('Manual candidate limit')
            self.manual[key].append(path)
        self.results.pop(key,None)
        return True

    def _probe_node(self,path,identity):
        if any(self.env.get(key) for key in ('NODE_OPTIONS','NODE_PATH','NODE_V8_COVERAGE','NODE_COMPILE_CACHE','DYLD_INSERT_LIBRARIES','DYLD_LIBRARY_PATH','LD_PRELOAD','LD_LIBRARY_PATH')):
            return dict(state='found_unverified',reason='options_unverified')
        volta_bin=Path(self.env.get('VOLTA_HOME',str(self.home/'.volta')))/'bin'
        if same_path(path.parent,volta_bin):return dict(state='found_unverified',reason='shim_unverified')
        if not native_node(path):return dict(state='found_unverified',reason='native_unverified')
        probe=self.root/'tools/check_node.cjs'
        with probe.open('rb') as stream:payload=stream.read(8193)
        if len(payload)>8192 or hashlib.sha256(payload).hexdigest()!=PROBE_SHA256:
            return dict(state='probe_failed',reason='probe_source_unverified')
        key=('node',str(path),identity)
        if key in self.cache:return dict(self.cache[key])
        result=subprocess.run([str(path),'-e',payload.decode('utf-8')],capture_output=True,text=True,timeout=5,env=self.env,shell=False)
        data=json.loads(result.stdout);observed=version_number(data.get('version'))
        flags=('ok','version_ok','fetch','WebSocket')
        if observed is None or result.returncode not in (0,1) or any(type(data.get(k)) is not bool for k in flags):raise ValueError('probe_failed')
        numbers=tuple(int(n) for n in observed.split('.'));version_ok=numbers>=(22,0,0)
        if data['version_ok']!=version_ok or data['ok']!=(version_ok and data['fetch'] and data['WebSocket']) or (result.returncode==0)!=data['ok']:raise ValueError('probe_failed')
        if _identity(path.stat())!=identity:raise ValueError('changed_during_check')
        value=dict(state='ready' if result.returncode==0 and data['ok'] else 'version_mismatch',
                   reason='local_match' if result.returncode==0 and data['ok'] else 'version_mismatch',
                   version=observed,version_match=version_ok,fetch=data['fetch'],websocket=data['WebSocket'])
        self.cache[key]=value;return value

    def assess(self,key,entry):
        path=self.executable(key,entry['path'])
        row=dict(path=path,candidate_path=entry['path'],sources=entry['sources'],state='path_missing',reason='not_found',version=None,exists=False,
                 executable=False,manifest_match=None,runtime_hash_match=None,runtime_match=None,
                 wrapper_verified=None,wrapper_runtime_match=None,version_match=None,fetch=None,websocket=None,symlink=False)
        row['runtime_match']=same_path(path,self.runtime.get(key)) if self.runtime.get(key) is not None else None
        try:
            row['symlink']=path.is_symlink() or entry['path'].is_symlink()
            path=_resolve(path);row['resolved']=path
            try:info=path.stat()
            except FileNotFoundError:
                if key=='fx' and entry['path'].is_dir():row.update(exists=True,state='found_unverified',reason='executable_missing')
                return row
            row['exists']=True
            if not stat.S_ISREG(info.st_mode):row.update(state='unusable',reason='not_regular');return row
            row['executable']=os.access(path,os.X_OK)
            if not row['executable']:row.update(state='unusable',reason='permission');return row
            if key=='node':
                row.update(self._probe_node(path,_identity(info)))
            else:
                value=digest(path)
                expected=self.expected_hash.get(key);runtime=self.runtime_hash.get(key)
                row['manifest_match']=value==expected if isinstance(expected,str) and re.fullmatch('[a-f0-9]{64}',expected) else None
                row['runtime_hash_match']=value==runtime if isinstance(runtime,str) and re.fullmatch('[a-f0-9]{64}',runtime) else None
                row.update(state='found_unverified',reason='hash_unknown')
                if False in (row['manifest_match'],row['runtime_hash_match']):row.update(state='hash_mismatch',reason='hash_mismatch')
                elif row['manifest_match'] is True and row['runtime_hash_match'] is True:row.update(state='ready',reason='local_match')
                if key=='fx':
                    try:
                        with (path.parent.parent/'Info.plist').open('rb') as stream:info=plistlib.load(stream)
                        row['version']=version_number(info.get('CFBundleShortVersionString') or info.get('CFBundleVersion'))
                    except (OSError,ValueError,TypeError,AttributeError,plistlib.InvalidFileException):pass
                else:
                    wrapper=path.parent/'gvproxy-eim-wrapper'
                    row['wrapper_runtime_match']=same_path(wrapper,self.runtime.get('wrapper')) if self.runtime.get('wrapper') is not None else None
                    row['wrapper_verified']=wrapper.is_file() and os.access(wrapper,os.X_OK) and digest(_resolve(wrapper))==WRAPPER_SHA256
                    if row['state']=='ready' and (not row['wrapper_verified'] or (row['runtime_match'] is True and row['wrapper_runtime_match'] is not True)):row.update(state='found_unverified',reason='wrapper_unverified')
            if row['state']=='ready' and row['runtime_match'] is not True:row.update(state='found_unverified',reason='runtime_differs')
        except RuntimeError:row.update(state='unusable',reason='symlink_loop')
        except (OSError,ValueError,TypeError,AttributeError,subprocess.SubprocessError,UnicodeError) as error:
            reason=str(error) if isinstance(error,ValueError) and str(error) in REASONS else 'probe_failed'
            row.update(state='probe_failed',reason=reason)
        return row

    def scan(self,key):
        if key not in COMPONENTS:raise ValueError('Unknown component')
        self.runtime,self.runtime_hash,self.node_runtime_candidates=runtime_rules(self.root,self.home,self.env)
        self.runtime['node']=next((Path(p) for p in self.node_runtime_candidates if p and self._is_file(p)),None)
        self.manifest,self.expected_hash=manifest_rules(self.root)
        rows=[];deadline=time.monotonic()+10;incomplete=False
        for entry in self.candidates(key):
            if time.monotonic()>deadline:
                incomplete=True
                rows.append(dict(path=entry['path'],sources=entry['sources'],state='probe_failed',reason='limit_reached',exists=None))
            else:rows.append(self.assess(key,entry))
        def rank(row):
            locally_good=(row['state']=='ready' or (row['reason']=='runtime_differs'))
            return (0 if locally_good and row.get('runtime_match') else 1 if locally_good else 2 if row.get('exists') or row['state']=='unusable' else 3 if row['state']=='probe_failed' else 4)
        chosen=min(rows,key=rank) if rows else dict(state='path_missing',reason='not_found',version=None)
        if incomplete and chosen['state']=='path_missing':
            chosen=next(row for row in rows if row['reason']=='limit_reached')
        self.results[key]=dict(items=rows,selected=chosen,scan_incomplete=incomplete,scope_limited=self.scope_limited.get(key,False))
        return self.results[key]

    def summary(self):
        for key in COMPONENTS:
            if key not in self.results:self.scan(key)
        return public_summary(self.results)

    def display_path(self,path):
        if path is None:return '<unknown>'
        path=Path(path)
        try:
            relative=path.relative_to(self.root)
            # Only fixed project locations are shown; user-defined names stay hidden.
            if str(path) in {str(p) for p in self.runtime.values() if p is not None}|{str(p) for p in self.manifest.values()}:return '<project>/'+relative.as_posix()
        except ValueError:pass
        safe=('/opt/homebrew/bin/node','/usr/local/bin/node','/Applications/FX.app')
        if str(path) in safe:return str(path)
        name=path.name if path.name in ('node','steamac-vm','gvproxy-eim','FX.app') else '<file>'
        return '<external>/…/'+name


def public_summary(results):
    """Idempotent report projection. Never exports path strings, digests or errors."""
    output={}
    for key in COMPONENTS:
        result=results.get(key,{})
        rows=result.get('items',[])
        clean=[]
        for row in rows[:MAX_CANDIDATES+8]:
            if not isinstance(row,dict):continue
            clean.append(dict(state=row.get('state') if row.get('state') in STATES else 'probe_failed',
                reason=row.get('reason') if row.get('reason') in REASONS else 'probe_failed',
                sources=[v for v in row.get('sources',[]) if v in SOURCES],version=version_number(row.get('version')),
                **{k:row.get(k) if type(row.get(k)) is bool else None for k in ('exists','executable','manifest_match','runtime_hash_match','runtime_match','wrapper_verified','wrapper_runtime_match','symlink','version_match','fetch','websocket')}))
        selected=result.get('selected',{})
        output[key]=dict(candidate_count=len(clean),found_count=sum(r['exists'] is True for r in clean),items=clean,
                         state=selected.get('state') if selected.get('state') in STATES else result.get('state') if result.get('state') in STATES else 'probe_failed',
                         runtime_path_known=result.get('runtime_path_known') is True or any(r['runtime_match'] is not None for r in clean),
                         scan_incomplete=result.get('scan_incomplete') is True,scope_limited=result.get('scope_limited') is True)
    return output
