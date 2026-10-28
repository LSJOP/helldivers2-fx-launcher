"""Restore the verified local FX profile without stopping a game or VM."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

DOMAIN = 'es.fxgam.steamac'
SETTINGS = {'cpus':8, 'memMiB':8192, 'vulkanDriver':'kosmickrisp',
            'metalHUD':False, 'superResolution':False}


class ProfileError(RuntimeError):
    def __init__(self,code):
        self.code=code
        super().__init__(code)


def missing_key(message):
    text=message.strip().lower()
    return (any(part in text for part in ('does not exist','could not find key','could not find domain'))
            or (text.startswith("error: domain '") and text.endswith("' not found.")))


def processes(helper):
    result=subprocess.run(['ps','-axo','comm='],capture_output=True,text=True,check=True,timeout=5)
    executable=str(Path(helper.APP)/'Contents/MacOS/steamac-vm')
    paths=[line.strip() for line in result.stdout.splitlines() if Path(line.strip()).name=='steamac-vm']
    return {'running':executable in paths,'foreign':any(path!=executable for path in paths)}


def read_setting(key):
    result=subprocess.run(['defaults','read',DOMAIN,key],capture_output=True,text=True,timeout=5)
    if result.returncode:
        if missing_key(result.stderr):return None
        raise ProfileError('preferences')
    value=result.stdout.strip()
    target=SETTINGS[key]
    try:
        if type(target) is bool:
            if value.lower() not in ('0','1','true','false','yes','no'):raise ValueError()
            return value.lower() in ('1','true','yes')
        if type(target) is int:return int(value)
        return value
    except ValueError:
        raise ProfileError('preferences')


def runtime_driver_ready(helper):
    result=subprocess.run(['ps','-axo','command='],capture_output=True,text=True,check=True,timeout=5)
    prefix=str(Path(helper.APP)/'Contents/MacOS/steamac-vm')+' '
    rows=[line.strip() for line in result.stdout.splitlines() if line.strip().startswith(prefix)]
    return bool(rows) and all('--vulkan-driver kosmickrisp' in row and '--no-wmtr' in row for row in rows)


def write_setting(key,value):
    if value is None:
        args=['defaults','delete',DOMAIN,key]
    else:
        kind='-bool' if type(value) is bool else ('-int' if type(value) is int else '-string')
        encoded=('true' if value else 'false') if type(value) is bool else str(value)
        args=['defaults','write',DOMAIN,key,kind,encoded]
    result=subprocess.run(args,capture_output=True,text=True,timeout=5)
    if result.returncode and not (value is None and missing_key(result.stderr)):
        raise ProfileError('preferences')


def write_receipt(path,data):
    fd=os.open(path,os.O_WRONLY|os.O_CREAT|os.O_TRUNC,0o600)
    with os.fdopen(fd,'w') as stream:
        json.dump(data,stream,ensure_ascii=False,indent=2)
        stream.write('\n')


def apply(helper):
    helper.refresh_settings()
    if not helper.prefs.local_host(helper.SETTINGS['ssh']['host']):
        raise ProfileError('local_only')
    status=processes(helper)
    if status['foreign']:raise ProfileError('foreign_fx')
    if status['running'] and not helper.vm_reachable():raise ProfileError('not_ready')
    if helper.vm_reachable():
        if not status['running']:raise ProfileError('foreign_fx')
        helper.connect()
        before=helper.state()
        if before['game_pids'] or before['apps']:raise ProfileError('busy')
    executable=Path(helper.APP)/'Contents/MacOS/steamac-vm'
    if not executable.is_file() or hashlib.sha256(executable.read_bytes()).hexdigest()!=helper.APP_EXECUTABLE_SHA256:
        raise ProfileError('app_changed')
    original={key:read_setting(key) for key in SETTINGS}
    directory=helper.ROOT/'launcher-20261026/backups'
    directory.mkdir(parents=True,exist_ok=True)
    backup=directory/('verified-performance-'+str(time.time_ns())+'.json')
    receipt={'created':time.time(),'status':'prepared','before':original,'profile':SETTINGS,
             'vm_stopped':False,'runtime_monitor_enabled':False}
    write_receipt(backup,receipt)
    attempted=[]
    try:
        for key,value in SETTINGS.items():
            attempted.append(key)
            write_setting(key,value)
            if read_setting(key)!=value:raise ProfileError('preferences')
    except (OSError,ProfileError,subprocess.SubprocessError):
        failed=[]
        for key in reversed(attempted):
            try:write_setting(key,original[key])
            except (OSError,ProfileError,subprocess.SubprocessError):failed.append(key)
        receipt.update(status='preferences_failed',rollback_failed_keys=failed)
        write_receipt(backup,receipt)
        raise ProfileError('preferences')
    receipt['status']='preferences_saved';write_receipt(backup,receipt)
    # UserDefaults and the on-disk plist used by the existing launch preflight
    # may briefly differ. Wait for persistence before invoking that preflight.
    until=time.monotonic()+3
    while True:
        try:
            helper.verify_fx_profile()
            break
        except RuntimeError:
            if time.monotonic()>=until:raise ProfileError('preferences')
            time.sleep(.1)
    helper.main(configure_only=True)
    observed=helper.state()
    if observed['launch']!=helper.WORKING_LAUNCH:raise ProfileError('launch_unverified')
    guest=json.loads(helper.remote(r'''
from pathlib import Path
import json
p=Path('/proc')
print(json.dumps({'memory_kib':int(next(x for x in (p/'meminfo').read_text().splitlines() if x.startswith('MemTotal:')).split()[1]),'online':Path('/sys/devices/system/cpu/online').read_text().strip(),'cmdline':(p/'cmdline').read_text()}))
''',timeout=12))
    restart_required=not (7_900_000<=guest['memory_kib']<=8_300_000 and guest['online']=='0-7'
                          and 'steamac.gpu_mib=6144' in guest['cmdline'] and runtime_driver_ready(helper))
    if status['running'] and any(original[key]!=SETTINGS[key] for key in ('metalHUD','superResolution')):
        restart_required=True
    receipt.update(status='applied',restart_required=restart_required,guest=guest)
    write_receipt(backup,receipt)
    return {'restart_required':restart_required,'backup':backup}
