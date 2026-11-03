"""Parameter-scoped FX 1.9.4 persistence. No launch, SSH, or Guest mutations.

CFPreferences is the authoritative store; its daemon owns plist metadata. Production
writes require a stopped, hash-pinned FX. Injectable stores/probes are test-only.
"""
import contextlib
import ctypes as C
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import time

DOMAIN = 'es.fxgam.steamac'
KEYS = ('cpus', 'memMiB', 'vulkanDriver', 'metalHUD', 'superResolution')
PINNED_EXECUTABLE = '0db013e9766b77e1c40f588c5f02ce1bab5937ec88cc17d6a8ade6c53e00b0cb'

class ConfigurationError(Exception):
    def __init__(self, code):
        self.code = code
        super().__init__(code)

def digest(data):
    return hashlib.sha256(plistlib.dumps(data, fmt=plistlib.FMT_BINARY, sort_keys=True)).hexdigest()

def selected(data):
    return {k: data.get(k) for k in KEYS}

class Preferences:
    """Use one CFPreferencesSetMultiple for the five owned keys, retaining others."""
    def __init__(self, domain=DOMAIN):
        self.cf = C.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
        signatures = {
            'CFStringCreateWithCString': (C.c_void_p, [C.c_void_p,C.c_char_p,C.c_uint32]),
            'CFDataCreate': (C.c_void_p,[C.c_void_p,C.c_void_p,C.c_long]),
            'CFDataGetLength': (C.c_long,[C.c_void_p]),
            'CFDataGetBytePtr': (C.c_void_p,[C.c_void_p]),
            'CFPropertyListCreateWithData': (C.c_void_p,[C.c_void_p,C.c_void_p,C.c_ulong,C.c_void_p,C.c_void_p]),
            'CFPropertyListCreateData': (C.c_void_p,[C.c_void_p,C.c_void_p,C.c_long,C.c_ulong,C.c_void_p]),
            'CFPreferencesCopyMultiple': (C.c_void_p,[C.c_void_p]*4),
            'CFPreferencesSetMultiple': (None,[C.c_void_p]*5),
            'CFPreferencesSynchronize': (C.c_bool,[C.c_void_p]*3),
            'CFRelease': (None,[C.c_void_p]),
        }
        for name,(result,args) in signatures.items():
            fn=getattr(self.cf,name);fn.restype=result;fn.argtypes=args
        self.app=self.cf.CFStringCreateWithCString(None,domain.encode(),0x08000100)
        self.user=C.c_void_p.in_dll(self.cf,'kCFPreferencesCurrentUser').value
        self.host=C.c_void_p.in_dll(self.cf,'kCFPreferencesAnyHost').value

    def object(self, value):
        raw=plistlib.dumps(value)
        data=self.cf.CFDataCreate(None,raw,len(raw))
        try: result=self.cf.CFPropertyListCreateWithData(None,data,0,None,None)
        finally: self.cf.CFRelease(data)
        if not result: raise ConfigurationError('PERF_FORMAT')
        return result

    def read(self):
        if not self.cf.CFPreferencesSynchronize(self.app,self.user,self.host):
            raise ConfigurationError('PERF_STORE')
        obj=self.cf.CFPreferencesCopyMultiple(None,self.app,self.user,self.host)
        if not obj: raise ConfigurationError('PERF_STORE')
        data=None
        try:
            data=self.cf.CFPropertyListCreateData(None,obj,200,0,None)
            if not data: raise ConfigurationError('PERF_FORMAT')
            size=self.cf.CFDataGetLength(data)
            if size>1024*1024: raise ConfigurationError('PERF_FORMAT')
            return plistlib.loads(C.string_at(self.cf.CFDataGetBytePtr(data),size))
        finally:
            if data:self.cf.CFRelease(data)
            self.cf.CFRelease(obj)

    def write(self, values):
        obj=self.object({k:v for k,v in values.items() if v is not None})
        removed=self.object([k for k,v in values.items() if v is None])
        try:
            self.cf.CFPreferencesSetMultiple(obj,removed,self.app,self.user,self.host)
            if not self.cf.CFPreferencesSynchronize(self.app,self.user,self.host):
                raise ConfigurationError('PERF_STORE')
        finally:self.cf.CFRelease(obj);self.cf.CFRelease(removed)


def stopped():
    try:
        p=subprocess.run(['/bin/ps','-axo','comm='],capture_output=True,text=True,timeout=5,check=True)
    except (OSError,subprocess.SubprocessError):raise ConfigurationError('PERF_STATE_UNKNOWN')
    if not p.stdout.strip():raise ConfigurationError('PERF_STATE_UNKNOWN')
    # Any local FX, including foreign copies, blocks domain writes. Guest Steam/game
    # run inside that VM: no SSH or speculative process-to-game inference is needed.
    if any(Path(row.strip()).name in ('steamac-vm','gvproxy','gvproxy-eim','krun') for row in p.stdout.splitlines()):
        raise ConfigurationError('PERF_RUNNING')


def capabilities(app):
    app=Path(app)
    try:
        info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
        exe=app/'Contents/MacOS/steamac-vm'
        if info.get('CFBundleShortVersionString')!='1.9.4' or hashlib.sha256(exe.read_bytes()).hexdigest()!=PINNED_EXECUTABLE:
            raise ConfigurationError('PERF_VERSION')
        memory=int(subprocess.check_output(['/usr/sbin/sysctl','-n','hw.memsize'],timeout=5))//1048576
        cores=int(subprocess.check_output(['/usr/sbin/sysctl','-n','hw.physicalcpu'],timeout=5))
        os_major=int(subprocess.check_output(['/usr/bin/sw_vers','-productVersion'],timeout=5).decode().split('.')[0])
    except (OSError,ValueError,subprocess.SubprocessError,plistlib.InvalidFileException):
        raise ConfigurationError('PERF_VERSION')
    drivers=[]
    for name,lib,min_os in [('moltenvk','libMoltenVK.dylib',15),('kosmickrisp','libvulkan_kosmickrisp.dylib',26)]:
        if os_major>=min_os and (app/'Contents/Frameworks'/lib).is_file():drivers.append(name)
    # Native policy is deliberately narrower than upstream 1..255 / >=1024.
    # Reserve max(3 GiB, 25%) for macOS plus the unchanged 6144 MiB GPU budget.
    maximum=min(16384,(memory-max(3072,memory//4)-6144)//256*256)
    return dict(version='1.9.4',cpu_min=1,cpu_max=min(255,cores),memory_min=4096,
                memory_max=maximum,memory_step=256,drivers=drivers,
                writable=['cpus','memMiB','vulkanDriver','metalHUD'],
                super_resolution_reason='device_support_not_probed',command_line_overrides=True)


class Manager:
    def __init__(self, store, directory, probe, rules):
        self.store,self.directory,self.probe,self.rules=store,Path(directory),probe,rules

    def validate(self, values, restore=False):
        r=self.rules
        if r.get('version')!='1.9.4':raise ConfigurationError('PERF_VERSION')
        if not isinstance(values,dict) or set(values)!=set(KEYS):raise ConfigurationError('PERF_PARAMETER')
        for key,value in values.items():
            if restore and value is None:continue
            if key=='cpus' and (type(value) is not int or not r['cpu_min']<=value<=r['cpu_max']):raise ConfigurationError('PERF_RANGE')
            if key=='memMiB' and (type(value) is not int or not r['memory_min']<=value<=r['memory_max'] or value%r['memory_step']):raise ConfigurationError('PERF_RANGE')
            if key=='vulkanDriver' and value not in r['drivers']:raise ConfigurationError('PERF_PARAMETER')
            if key in ('metalHUD','superResolution') and type(value) is not bool:raise ConfigurationError('PERF_PARAMETER')

    def prepare_directory(self):
        self.directory.mkdir(parents=True,exist_ok=True,mode=0o700)
        for p in [self.directory,*self.directory.parents]:
            if p.is_symlink():raise ConfigurationError('PERF_BACKUP')
        st=self.directory.stat()
        if st.st_uid!=os.getuid() or st.st_mode&0o077:raise ConfigurationError('PERF_BACKUP')

    @contextlib.contextmanager
    def locked(self):
        self.prepare_directory()
        fd=os.open(self.directory/'lock',os.O_CREAT|os.O_RDWR|os.O_NOFOLLOW,0o600)
        try:
            if os.fstat(fd).st_uid!=os.getuid() or os.fstat(fd).st_nlink!=1:raise ConfigurationError('PERF_BACKUP')
            try:fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
            except BlockingIOError:raise ConfigurationError('PERF_CONFLICT')
            yield
        finally:os.close(fd)

    def save(self, path, value):
        raw=json.dumps(value,sort_keys=True).encode()
        fd,name=tempfile.mkstemp(dir=self.directory)
        try:
            with os.fdopen(fd,'wb') as stream:stream.write(raw);stream.flush();os.fsync(stream.fileno())
            os.replace(name,path)
        finally:
            if os.path.exists(name):os.unlink(name)

    def receipt(self):
        path=self.directory/'last.json'
        if path.is_symlink() or not path.is_file() or path.stat().st_size>65536 or path.stat().st_uid!=os.getuid() or path.stat().st_mode&0o077:raise ConfigurationError('PERF_BACKUP')
        try:
            value=json.loads(path.read_text())
            body=value['body']
            if value['sha256']!=hashlib.sha256(json.dumps(body,sort_keys=True).encode()).hexdigest():raise ValueError()
            if body['version']!=self.rules['version'] or body['domain']!=DOMAIN:raise ValueError()
            self.validate(body['before'],restore=True)
            return body
        except (ValueError,KeyError,TypeError):raise ConfigurationError('PERF_BACKUP')

    def snapshot(self):
        data=self.store.read()
        if not isinstance(data,dict) or not data:raise ConfigurationError('PERF_FORMAT')
        current=selected(data)
        if any(v is None for v in current.values()):raise ConfigurationError('PERF_FORMAT')
        self.validate(current)
        backup=None
        try:backup=self.receipt()
        except (OSError,ConfigurationError):pass
        return dict(current=current,revision=digest(data),capabilities=self.rules,effective='unverified',
                    last_applied=backup.get('after') if backup else None,
                    backup=backup.get('before') if backup else None,
                    can_restore=bool(backup and backup.get('status')=='saved' and backup.get('after_revision')==digest(data)))

    def preview(self, values, revision, restore=False):
        self.probe()
        current=self.snapshot()
        if current['revision']!=revision:raise ConfigurationError('PERF_CONFLICT')
        if restore:
            receipt=self.receipt()
            if not current['can_restore']:raise ConfigurationError('PERF_CONFLICT')
            values=receipt['before']
        self.validate(values,restore=restore)
        for k in KEYS:
            if k not in self.rules['writable'] and values[k]!=current['current'][k] and not restore:raise ConfigurationError('PERF_PARAMETER')
        changes={k:{'before':current['current'][k],'after':values[k]} for k in KEYS if values[k]!=current['current'][k]}
        if not changes:raise ConfigurationError('PERF_UNCHANGED')
        plan=dict(before=current['current'],after=values,revision=revision,restore=restore,version=self.rules['version'])
        return dict(plan=plan,token=hashlib.sha256(json.dumps(plan,sort_keys=True).encode()).hexdigest(),changes=changes)

    def commit(self, values, revision, token, restore=False, emit=lambda status:None):
        with self.locked():
            preview=self.preview(values,revision,restore)
            if preview['token']!=token:raise ConfigurationError('PERF_CONFLICT')
            before=self.store.read();after=preview['plan']['after']
            emit('backing_up')
            # Only owned fields are backed up. Unknown fields may contain credentials.
            body=dict(domain=DOMAIN,version=self.rules['version'],created=time.time(),source='native_performance_v2',
                      validation='saved_not_effective',before=selected(before),after=after,status='prepared',before_revision=digest(before))
            envelope=lambda b:dict(body=b,sha256=hashlib.sha256(json.dumps(b,sort_keys=True).encode()).hexdigest())
            backup=self.directory/('backup-'+str(time.time_ns())+'.json')
            self.save(backup,envelope(body))
            if json.loads(backup.read_text())!=envelope(body):raise ConfigurationError('PERF_BACKUP')
            if digest(self.store.read())!=revision:raise ConfigurationError('PERF_CONFLICT')
            self.probe()
            emit('restoring' if restore else 'applying')
            try:
                self.store.write(after)
                observed=self.store.read()
                # Whole-domain comparison also detects unrelated concurrent modifications.
                expected=dict(before)
                for k,v in after.items():
                    if v is None:expected.pop(k,None)
                    else:expected[k]=v
                if digest(observed)!=digest(expected):raise ConfigurationError('PERF_VERIFY')
            except BaseException:
                observed=self.store.read()
                # Roll back only our owned after-values with every unrelated field unchanged.
                expected=dict(before);expected.update(after)
                if digest(observed)==digest(expected):
                    self.probe();self.store.write(selected(before))
                    if digest(self.store.read())!=digest(before):raise ConfigurationError('PERF_ROLLBACK')
                elif digest(observed)!=digest(before):raise ConfigurationError('PERF_CONFLICT')
                raise
            body.update(status='restored' if restore else 'saved',after_revision=digest(observed))
            self.save(backup,envelope(body))
            self.save(self.directory/'last.json',envelope(body))
            result=self.snapshot()
            result.update(status=body['status'],restart_required=True,effective='unverified')
            emit('waiting_restart')
            return result
