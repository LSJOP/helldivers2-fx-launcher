"""Immutable runtime snapshot from defaults or a verified private selection.

Default references deliberately retain the historical paths. This is separate
from tools/runtime_paths.sh, which finds Python/Node for the Shell entry only.
"""
import ast
from dataclasses import dataclass,replace
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import stat
import struct
import time

FX_RELATIVE = 'performance-stutter-20261027/FX HUD隔离诊断.app'
NETWORK_RELATIVE = 'goal-fx-multiplayer-20261026'
WRAPPER_SHA256='80dca2b7d0b04dae44f46b4b6dc9e2735434fdeaa241925f8061613498911d3d'
POLICY='historical-pinned-build-v1'


class PathError(RuntimeError):
    def __init__(self,code):self.code=code;self.recovery='not_needed';super().__init__(code)


@dataclass(frozen=True)
class RuntimePaths:
    root: Path
    fx_app: Path
    fx_executable: Path
    gvproxy_binary: Path
    gvproxy_wrapper: Path
    source: str = 'bundled-defaults'
    validation_state: str = 'unverified'
    config_file: Path = None
    config_token: str = None
    selection_json: str = None
    error_code: str = None
    generation: int = 0

    @property
    def wrapper_target(self):
        # Reviewed wrapper uses dirname($0), not the resolved wrapper file.
        return self.gvproxy_wrapper.parent/'gvproxy-eim'


def defaults(root):
    """A pure snapshot, stable for the lifetime of its owning operation/module.

    Do not resolve the app/wrapper themselves: exact lexical process references
    and wrapper invocation paths must remain identical to the original backend.
    No argument accepts a discovered or persisted candidate.
    """
    root=Path(root).resolve()
    app=root/FX_RELATIVE;network=root/NETWORK_RELATIVE
    return RuntimePaths(root,app,app/'Contents/MacOS/steamac-vm',
                        network/'gvproxy-eim',network/'gvproxy-eim-wrapper')


def config_path(settings_file=None):
    if settings_file is None:
        value=os.environ.get('HD2FX_SETTINGS_FILE')
        settings_file=Path(value).expanduser() if value else Path.home()/'Library/Application Support/Helldivers2FXLauncher/settings.json'
    return Path(settings_file).parent/'runtime-paths.json'


def stamp(info):
    return [info.st_dev,info.st_ino,info.st_size,info.st_mtime_ns,info.st_ctime_ns,stat.S_IMODE(info.st_mode)]


def fingerprint(path,executable=False,limit=256*1024*1024):
    try:
        fd=os.open(path,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0))
        with os.fdopen(fd,'rb') as stream:
            before=os.fstat(stream.fileno())
            if not stat.S_ISREG(before.st_mode):raise PathError('file_type')
            if executable and (not before.st_mode&0o111 or not os.access(path,os.X_OK)):raise PathError('permission')
            if before.st_size>limit:raise PathError('resource_limit')
            value=hashlib.sha256();deadline=time.monotonic()+10;head=b'';count=0
            while True:
                chunk=stream.read(1024*1024)
                if not chunk:break
                if not head:head=chunk[:1024]
                value.update(chunk);count+=len(chunk)
                if count>limit or time.monotonic()>deadline:raise PathError('resource_limit')
            if stamp(before)!=stamp(os.fstat(stream.fileno())) or stamp(before)!=stamp(Path(path).stat()):raise PathError('file_changed')
        return {'sha256':value.hexdigest(),'stamp':stamp(before),'architectures':architectures(head)}
    except PermissionError:raise PathError('permission') from None
    except (OSError,ValueError):raise PathError('file_missing') from None


def architectures(head):
    cpus={0x0100000c:'arm64',0x01000007:'x86_64'}
    if len(head)>=8 and head[:4] in (b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf'):
        return [cpus.get(struct.unpack(('<' if head[:4]==b'\xcf\xfa\xed\xfe' else '>')+'I',head[4:8])[0],'unknown')]
    fat={b'\xca\xfe\xba\xbe':('>',20),b'\xbe\xba\xfe\xca':('<',20),b'\xca\xfe\xba\xbf':('>',32),b'\xbf\xba\xfe\xca':('<',32)}
    if len(head)>=8 and head[:4] in fat:
        endian,step=fat[head[:4]];count=struct.unpack(endian+'I',head[4:8])[0]
        if 0<count<=16 and len(head)>=8+count*step:
            return sorted(set(cpus.get(struct.unpack(endian+'I',head[8+i*step:12+i*step])[0],'unknown') for i in range(count)))
    return ['unknown']


def expected_hashes(root):
    try:
        data=json.loads((Path(root)/'runtime-requirements.json').read_text())
        components={r['name']:r for r in data['components']}
        expected={'fx':components['FX steamac-vm']['sha256'],'gvproxy':components['gvproxy-eim']['sha256'],'wrapper':WRAPPER_SHA256}
        tree=ast.parse((Path(root)/'goal-dxmt-20261026/start-hd2.py').read_text())
        literal={n.targets[0].id:n.value.value for n in tree.body if isinstance(n,ast.Assign) and len(n.targets)==1 and isinstance(n.targets[0],ast.Name) and isinstance(n.value,ast.Constant)}
        if expected['fx']!=literal.get('APP_EXECUTABLE_SHA256') or expected['gvproxy']!=literal.get('GVPROXY_SHA256'):raise PathError('baseline_mismatch')
        if not all(isinstance(v,str) and re.fullmatch('[a-f0-9]{64}',v) for v in expected.values()):raise PathError('baseline_mismatch')
        return expected
    except (OSError,ValueError,KeyError,TypeError,SyntaxError):raise PathError('baseline_mismatch') from None


def bundle_manifest(app):
    """Bounded complete Contents evidence, including internal link relationships."""
    app=Path(app).resolve();content=app/'Contents';rows=[];total=0;deadline=time.monotonic()+30
    if not content.is_dir():raise PathError('invalid_app')
    try:
        for directory,dirs,files in os.walk(content,followlinks=False,onerror=lambda error:(_ for _ in ()).throw(error)):
            if len(Path(directory).relative_to(app).parts)>16:raise PathError('resource_limit')
            for name in sorted(dirs+files):
                p=Path(directory)/name;relative=p.relative_to(app).as_posix()
                if p.is_symlink():
                    target=p.resolve(strict=True)
                    try:target=target.relative_to(app).as_posix()
                    except ValueError:raise PathError('resource_escape') from None
                    rows.append((relative,'link',target))
                elif p.is_file():
                    proof=fingerprint(p);total+=proof['stamp'][2]
                    rows.append((relative,proof['sha256'],proof['stamp'][-1]))
                elif not p.is_dir():raise PathError('file_type')
                if len(rows)>2048 or total>512*1024*1024 or time.monotonic()>deadline:raise PathError('resource_limit')
    except (OSError,ValueError,RuntimeError) as error:
        if isinstance(error,PathError):raise
        raise PathError('resource_unverified') from None
    if not rows:raise PathError('resource_unverified')
    return hashlib.sha256(json.dumps(sorted(rows),ensure_ascii=True,separators=(',',':')).encode()).hexdigest()


def build_record(root,app,binary,wrapper):
    """Never admits a new build merely because it exists or is an official release."""
    try:
        root=Path(root).resolve();app=Path(app).resolve();binary=Path(binary);wrapper=Path(wrapper)
    except (OSError,RuntimeError,ValueError):raise PathError('invalid_app') from None
    if app.suffix.casefold()!='.app' or not app.is_dir():raise PathError('invalid_app')
    exe=app/'Contents/MacOS/steamac-vm';info=app/'Contents/Info.plist'
    expected=expected_hashes(root)
    fx=fingerprint(exe,True)
    if 'arm64' not in fx['architectures']:raise PathError('architecture')
    meta=fingerprint(info,limit=1024*1024)
    try:
        fd=os.open(info,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0))
        with os.fdopen(fd,'rb') as stream:
            if stamp(os.fstat(stream.fileno()))!=meta['stamp']:raise PathError('file_changed')
            payload=stream.read(1024*1024+1)
            if len(payload)>1024*1024 or stamp(os.fstat(stream.fileno()))!=meta['stamp']:raise PathError('file_changed')
        data=plistlib.loads(payload)
        if data.get('CFBundleExecutable')!='steamac-vm' or data.get('CFBundleIdentifier')!='es.fxgam.steamac':raise PathError('invalid_app')
    except (OSError,ValueError,TypeError,AttributeError):raise PathError('invalid_app') from None
    if fx['sha256']!=expected['fx']:raise PathError('unsupported_build')
    gv=fingerprint(binary,True);wr=fingerprint(wrapper,True)
    if gv['sha256']!=expected['gvproxy'] or wr['sha256']!=expected['wrapper']:raise PathError('network_build')
    # Invocation path, canonical process path and sibling exec target must agree.
    if not binary.is_absolute() or not wrapper.is_absolute() or binary.resolve()!=binary or wrapper.resolve()!=wrapper or wrapper.parent/'gvproxy-eim'!=binary:raise PathError('wrapper_target')
    baseline=defaults(root).fx_app
    if not baseline.is_dir():raise PathError('baseline_missing')
    if fingerprint(baseline/'Contents/MacOS/steamac-vm',True)['sha256']!=expected['fx']:raise PathError('baseline_mismatch')
    resources=bundle_manifest(app)
    if resources!=bundle_manifest(baseline):raise PathError('resource_mismatch')
    return {'policy':POLICY,'fx_app':str(app),'fx_executable':str(exe),'gvproxy_binary':str(binary),'gvproxy_wrapper':str(wrapper),
            'fx_version':data.get('CFBundleShortVersionString') if isinstance(data.get('CFBundleShortVersionString'),str) else None,
            'files':{'fx':fx,'gvproxy':gv,'wrapper':wr,'info':meta},'bundle_manifest':resources,
            'compatibility':'historical-files-only; launch/EAC/multiplayer unverified',
            'evidence_ref':'runtime-requirements.json + unchanged historical Contents reference'}


def verify_record(root,record,full=True):
    try:
        if not isinstance(record,dict) or record.get('policy')!=POLICY:raise PathError('unsupported_build')
        expected=expected_hashes(root)
        p={key:Path(record[key]) for key in ('fx_app','fx_executable','gvproxy_binary','gvproxy_wrapper')}
        if p['fx_executable']!=p['fx_app']/'Contents/MacOS/steamac-vm':raise PathError('invalid_app')
        if p['gvproxy_wrapper'].parent/'gvproxy-eim'!=p['gvproxy_binary']:raise PathError('wrapper_target')
        for name,path in [('fx',p['fx_executable']),('gvproxy',p['gvproxy_binary']),('wrapper',p['gvproxy_wrapper']),('info',p['fx_app']/'Contents/Info.plist')]:
            if not path.is_absolute() or path.resolve()!=path:raise PathError('wrapper_target')
            current=fingerprint(path,name!='info',1024*1024 if name=='info' else 256*1024*1024)
            if any(current[key]!=record['files'][name].get(key) for key in ('sha256','stamp','architectures')):raise PathError('file_changed')
            if name in expected and current['sha256']!=expected[name]:raise PathError('unsupported_build')
        if full:
            fresh=build_record(root,p['fx_app'],p['gvproxy_binary'],p['gvproxy_wrapper'])
            if fresh['bundle_manifest']!=record['bundle_manifest']:raise PathError('file_changed')
        return p
    except (KeyError,ValueError,TypeError,AttributeError,OSError,RuntimeError) as error:
        if isinstance(error,PathError):raise
        raise PathError('config_invalid') from None


def read_config(path):
    """Returns raw bytes and an optimistic identity token; never writes/migrates."""
    path=Path(path)
    try:fd=os.open(path,os.O_RDONLY|getattr(os,'O_NOFOLLOW',0)|getattr(os,'O_NONBLOCK',0))
    except FileNotFoundError:return None,None,None
    except OSError:raise PathError('config_permissions') from None
    try:
        with os.fdopen(fd,'rb') as stream:
            info=os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid!=os.getuid() or stat.S_IMODE(info.st_mode)&0o077 or info.st_size>1024*1024:raise PathError('config_permissions')
            raw=stream.read(1024*1024+1)
            if len(raw)>1024*1024 or stamp(info)!=stamp(os.fstat(stream.fileno())) or stamp(info)!=stamp(path.stat()):raise PathError('config_conflict')
        def pairs(items):
            result={}
            for k,v in items:
                if k in result:raise ValueError('duplicate key')
                result[k]=v
            return result
        data=json.loads(raw.decode('utf-8'),object_pairs_hook=pairs)
        if not isinstance(data,dict):raise ValueError('not object')
        token=hashlib.sha256(raw+json.dumps(stamp(info)).encode()).hexdigest()
        return data,raw,token
    except (OSError,ValueError,UnicodeError,RecursionError):raise PathError('config_invalid') from None


def load(root,settings_file=None):
    base=defaults(root);file=config_path(settings_file)
    try:
        data,raw,token=read_config(file)
        if data is None:return replace(base,config_file=file)
        if data.get('schema')==0:raise PathError('migration_required')
        if type(data.get('schema')) is not int or data['schema']!=1 or data.get('launcher_root')!=str(base.root) or type(data.get('generation')) is not int or not 1<=data['generation']<2**63:raise PathError('config_invalid')
        paths=verify_record(base.root,data['active'])
        return RuntimePaths(base.root,paths['fx_app'],paths['fx_executable'],paths['gvproxy_binary'],paths['gvproxy_wrapper'],
                            'rollback' if data.get('operation')=='rollback' else 'user-selection','historical-files-only',
                            file,token,json.dumps(data['active'],sort_keys=True),None,data['generation'])
    except (PathError,KeyError,TypeError) as error:
        return replace(base,source='blocked',config_file=file,error_code=error.code if isinstance(error,PathError) else 'config_invalid')


def check_current(snapshot,full=False):
    if snapshot is None:return None
    if snapshot.error_code:return snapshot.error_code
    try:
        if snapshot.config_file is not None:
            data,raw,token=read_config(snapshot.config_file)
            if token!=snapshot.config_token:raise PathError('restart_required')
        if snapshot.selection_json:verify_record(snapshot.root,json.loads(snapshot.selection_json),full)
    except PathError as error:return error.code
    return None


def assert_current(snapshot):
    error=check_current(snapshot,True)
    if error:raise PathError(error)
