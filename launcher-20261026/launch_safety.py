"""Launch-boundary checks, target lock, consent and recovery journal.

Unknown target identity fails closed, including for noninteractive callers.
This does not discover/download replacement FX builds or change launch arguments.
"""
from contextlib import contextmanager
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import shlex
import stat
import subprocess
import time

HERE = Path(__file__).resolve().parent
LOCK_ROOT = Path('/tmp')/('hd2fx-targets-'+str(os.getuid()))
_spec = importlib.util.spec_from_file_location('hd2_guest_safety', HERE/'guest_safety.py')
guest = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(guest)


@contextmanager
def target_lock(settings):
    # Serialize FX launches per macOS user, across all ports/settings/checkouts.
    # Port aliases may reach the same Guest; a port-only lock is insufficient.
    # Never unlink the file or kill a stale owner.
    directory = LOCK_ROOT
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise RuntimeError('Unsafe target lock directory')
    path = directory/'fx-launch.lock'
    fd = os.open(path,os.O_RDWR|os.O_CREAT|getattr(os,'O_NOFOLLOW',0),0o600)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid():
            raise RuntimeError('Unsafe target lock file')
        os.fchmod(fd,0o600)
        try: fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:
            raise RuntimeError('另一个启动器正在操作此 Guest / Another launcher is operating on this Guest') from None
        yield
    finally: os.close(fd)


def output(args):
    result = subprocess.run(args,capture_output=True,text=True,timeout=8)
    if result.returncode: raise RuntimeError('Target identity probe failed: '+args[0])
    return result.stdout


def process_table(text):
    rows = {}
    for line in text.splitlines():
        fields = line.split(None,7)
        if len(fields) == 8 and fields[0].isdigit() and fields[1].isdigit():
            rows[int(fields[0])] = (int(fields[1]),' '.join(fields[2:7]),fields[7])
    return rows


def process_fds(text):
    result = {}; pid = None
    for line in text.splitlines():
        if line.startswith('p') and line[1:].isdigit():
            pid = int(line[1:]); result.setdefault(pid,[])
        elif line.startswith('n') and pid is not None: result[pid].append(line[1:])
    return result


def host_identity(helper):
    rows = process_table(output(['ps','-ww','-axo','pid=,ppid=,lstart=,comm=']))
    app = str(Path(helper.APP)/'Contents/MacOS/steamac-vm')
    fx = [pid for pid, row in rows.items() if row[2] == app]
    if len(fx) != 1: raise RuntimeError('FX instance identity is unverified (requires one exact FX process)')
    fx = fx[0]
    def belongs(pid):
        seen = set()
        while pid in rows and pid not in seen:
            if pid == fx: return True
            seen.add(pid); pid = rows[pid][0]
        return False
    network = [pid for pid,row in rows.items() if row[2] == str(helper.GVPROXY) and belongs(pid)]
    if not network: raise RuntimeError('FX/gvproxy parent relationship is unverified')
    port = str(helper.SETTINGS['ssh']['port'])
    listeners = process_fds(output(['lsof','-nP','-iTCP:'+port,'-sTCP:LISTEN','-Fpn']))
    owners = [pid for pid, names in listeners.items() if any(n.endswith(':'+port) for n in names)]
    if not owners or any(not belongs(pid) for pid in owners):
        raise RuntimeError('SSH listener does not belong to the target FX instance')
    result = subprocess.run(helper.CLIENT.base()+['-O','check',helper.SETTINGS['ssh']['host']],
                            capture_output=True,text=True,timeout=8)
    match = re.search(r'Master running \(pid=(\d+)\)',result.stderr+result.stdout)
    if result.returncode or not match: raise RuntimeError('SSH master identity is unverified')
    master = int(match[1])
    if master not in rows or Path(rows[master][2]).name != 'ssh':
        raise RuntimeError('SSH master process identity is unverified')
    cdp_port = str(helper.SETTINGS['ssh']['cdp_local_port'])
    command = shlex.split(output(['ps','-ww','-p',str(master),'-o','command=']).strip())
    forwards = []
    for i, arg in enumerate(command):
        if arg == '-L' and i+1 < len(command): forwards.append(command[i+1])
        elif arg.startswith('-L'): forwards.append(arg[2:])
    expected_forward = '127.0.0.1:'+cdp_port+':127.0.0.1:8080'
    if expected_forward not in forwards:
        raise RuntimeError('SSH CDP forwarding destination is unverified')
    cdp = process_fds(output(['lsof','-nP','-iTCP:'+cdp_port,'-sTCP:LISTEN','-Fpn']))
    if set(cdp) != {master}:
        raise RuntimeError('Steam CDP forwarding is not owned by the verified SSH master')
    peers = process_fds(output(['lsof','-nP','-a','-p',str(master),'-iTCP','-sTCP:ESTABLISHED','-Fpn']))
    allowed = {'127.0.0.1:'+port,'[::1]:'+port}
    actual = [name.split('->',1)[1] for name in peers.get(master,[]) if '->' in name]
    if len(actual) != 1 or actual[0] not in allowed:
        raise RuntimeError('Actual SSH peer is not the configured local FX port')
    helper.verify_fx_profile()
    if not helper.network_ready(): raise RuntimeError('Verified network binary/process is unavailable')
    return {'fx':(fx,rows[fx]), 'network':[(p,rows[p]) for p in network],
            'listeners':[(p,rows[p]) for p in owners], 'master':master,
            'master_process':rows[master], 'forward':expected_forward, 'peer':actual[0]}


def guest_code(request):
    return (HERE/'guest_safety.py').read_text(encoding='utf-8')+'\nprint(json.dumps(dispatch(json.loads('+repr(json.dumps(request))+'))))\n'


class NotWrittenError(RuntimeError):
    """The operation failed before the mutation command was submitted."""


def request(helper, data, sudo=False):
    code = guest_code(data)
    if not sudo:
        timeout = 180 if data['action'] in ('proxy','restore_proxy') else 60
        return json.loads(helper.remote(code,timeout=timeout))
    # Authorize separately; never rerun a partially executed mutation with sudo -S.
    import shlex
    probe = helper.subprocess.run(helper.SSH+['sudo -n -v'],capture_output=True,text=True,timeout=15)
    if probe.returncode:
        password = helper.CLIENT.password
        if password is None: password = helper.CLIENT.prompt_secret('Guest sudo password (not macOS): ')
        auth = helper.subprocess.run(helper.SSH+['sudo -S -p "" -v'],input=password+'\n',capture_output=True,text=True,timeout=20)
        if auth.returncode: raise NotWrittenError('Guest sudo authorization failed; no configuration was written')
    result = helper.subprocess.run(helper.SSH+['sudo -n python3 -c '+shlex.quote(code)],
                                   capture_output=True,text=True,timeout=45)
    if result.returncode: raise RuntimeError('Guest transaction did not return; inspect the recovery backup before retrying')
    return json.loads(result.stdout)


def backup(helper, name, data):
    folder = helper.ROOT/'launcher-20261026/backups'
    folder.mkdir(mode=0o700,parents=True,exist_ok=True)
    path = folder/(name+'-'+str(time.time_ns())+'.json')
    fd = os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
    with os.fdopen(fd,'w') as stream:
        json.dump(data,stream,ensure_ascii=False,indent=2)
    return path


class Session:
    def __init__(self, helper):
        self.h = helper; self.identity = None; self.boot = None
        settings = getattr(helper,'SETTINGS',None)
        self.endpoint = dict(settings['ssh']) if settings else None
        self.undo = []; self.events = []; self.uncertain = []

    def bind(self):
        first = host_identity(self.h)
        plan = request(self.h,{'action':'inspect'})
        second = host_identity(self.h)
        if first != second or not plan.get('marker') or not plan.get('boot'):
            raise RuntimeError('Guest/FX identity is unverified; Guest writes are blocked')
        self.identity, self.boot = first, plan['boot']
        return plan

    def verify(self):
        if self.identity is None or host_identity(self.h) != self.identity:
            raise RuntimeError('FX/SSH instance changed; Guest writes are blocked')
        plan = request(self.h,{'action':'inspect'})
        if plan.get('boot') != self.boot or not plan.get('marker'):
            raise RuntimeError('Guest identity changed; Guest writes are blocked')
        return plan

    def confirm(self, kind, before, after):
        hook = getattr(self.h,'CONFIRM_HOOK',None)
        if hook is None or hook(kind,before,after) is not True:
            raise RuntimeError('用户取消，本项未写入 / Cancelled; this change was not written')

    def transaction(self, kind, plan, **args):
        current = self.verify()
        keys = ('ipv6',) if kind == 'ipv6' else ('proxy','service')
        if any(current[k] != plan[k] for k in keys):
            raise RuntimeError('Configuration changed since consent; launch cancelled')
        path = backup(self.h,kind,dict(plan=plan,operation=args))
        self.uncertain.append(str(path))
        try:
            result = request(self.h,dict(action=kind,plan=plan,**args),sudo=kind=='ipv6')
        except NotWrittenError:
            self.uncertain.remove(str(path))
            self.events.append(kind+': not written / 未写入')
            raise
        if not result.get('ok'):
            self.events.append(kind+': '+result.get('recovery','manual inspection required'))
            if result.get('recovery') == 'restored': self.uncertain.remove(str(path))
            raise RuntimeError(result.get('reason','Transaction failed')+'; '+result.get('recovery','unknown'))
        self.uncertain.remove(str(path))
        if result.get('changed'):
            receipt = {'action':'restore_'+kind,'boot':self.boot,'before':result['before'],'after':result['after']}
            if kind == 'proxy': receipt['original_service'] = result['original_service']
            self.undo.append((receipt,path))
            self.events.append(kind+': changed / 已修改')
        return result

    def ipv4(self):
        plan = self.verify()
        if all(plan['ipv6'][k] == '1' for k in guest.IPV6_KEYS): return
        self.confirm('ipv6',plan['ipv6'],guest.ipv6_expected(plan['ipv6']))
        self.transaction('ipv6',plan)

    def proxy(self, enabled):
        plan = self.verify()
        if plan['proxy'] not in (None,guest.PROXY_TEXT,guest.LEGACY_PROXY_TEXT):
            raise RuntimeError('Unknown Steam proxy drop-in; no changes made')
        target = guest.PROXY_TEXT if enabled else None
        if plan['proxy'] == target and plan['service'] == 'stopped':
            return  # No file change and no running Steam to restart.
        self.confirm('proxy',{'drop-in':plan['proxy'],'Steam':plan['service']},
                     {'drop-in':target,'Steam':'restart once' if plan['service']=='running' else 'remain stopped until launch'})
        self.transaction('proxy',plan,enabled=enabled)

    def steam(self):
        plan = self.verify()
        path = backup(self.h,'steam-service',{'boot':self.boot,'original_service':plan['service']})
        self.uncertain.append(str(path))
        result = request(self.h,{'action':'steam','boot':self.boot})
        self.uncertain.remove(str(path))
        if not result.get('ok'):
            self.events.append('Steam check/start failed / Steam 检查或启动失败')
            raise RuntimeError(result.get('reason','Steam controlled start failed'))
        if result.get('started'):
            self.events.append('Steam started once; not stopped by rollback / 本次启动了 Steam；回滚不强制停止')
        return result

    def rollback(self):
        if self.uncertain:
            # A timed-out/disconnected remote transaction may still be running.
            # Do not race it with a second transaction or guess its outcome.
            self.uncertain.extend(str(path) for _,path in self.undo)
            self.events.append('Recovery paused: remote outcome unknown / 远端结果未知，停止后续写入')
            self.undo.clear()
            return
        for receipt,path in reversed(self.undo):
            try:
                self.verify()
                if receipt['action'] == 'options':
                    # Do not change launch options while a game is starting.
                    current = self.h.state()
                    if current['game_pids'] or current['apps']:
                        raise RuntimeError('Game active; manual recovery required')
                    self.h.set_launch_options(receipt['after'],receipt['before'])
                else:
                    result = request(self.h,receipt,sudo=receipt['action']=='restore_ipv6')
                    if not result.get('ok'): raise RuntimeError('Recovery unconfirmed')
                self.events.append(receipt['action']+': restored / 已恢复')
            except Exception:
                self.uncertain.append(str(path))
                self.events.append(receipt['action']+': manual recovery required / 需要手动检查')
        self.undo.clear()

    def failure_summary(self):
        self.h.say('配置与恢复 / Configuration and recovery:')
        if not self.events and not self.uncertain:
            self.h.say('  未执行配置写入 / No configuration writes were attempted')
        for event in self.events: self.h.say('  '+event)
        for path in self.uncertain:
            self.h.say('  需要手动检查 / Manual inspection required; private backup: '+path)
