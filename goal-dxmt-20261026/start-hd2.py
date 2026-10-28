"""Repeat the verified HD2 launch without changing the launcher's global graphics setting."""
import hashlib, json, os, pathlib, plistlib, re, shlex, shutil, socket, subprocess, sys, time, urllib.request, importlib.util

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
APP = str(ROOT / 'performance-stutter-20261027/FX HUD隔离诊断.app')
APP_EXECUTABLE_SHA256 = '0db013e9766b77e1c40f588c5f02ce1bab5937ec88cc17d6a8ade6c53e00b0cb'
NETWORK_DIR = ROOT / 'goal-fx-multiplayer-20261026'
GVPROXY = NETWORK_DIR / 'gvproxy-eim'
GVPROXY_WRAPPER = NETWORK_DIR / 'gvproxy-eim-wrapper'
GVPROXY_SHA256 = '27136dd87a6e8c35c2607077a6303082e577751a9e31ebcaa1bd81c93cc58444'
WINE_CORE_SHA256 = {'x86_64-windows/user32.dll': 'e51cd4a5e451b5bf6c2f89582bd1b341bfec9309c468bed5ed5f49d3dd5c7e09', 'x86_64-windows/win32u.dll': '1bfc85f5aacb14b405794bbe82cbf733eb7f09701697aa2300dbb9e22a123a92', 'x86_64-windows/kernelbase.dll': '1c4eb48f08594541605e31391835b5d150a4bf46691236df7896cda51001b5b8', 'x86_64-unix/win32u.so': '05a159f75fb302bfe3c67386a6d17b53f4db521e0726281a8dad7121006e627c'}
_prefs_spec = importlib.util.spec_from_file_location('hd2_preferences', ROOT/'launcher-20261026/preferences.py')
prefs = importlib.util.module_from_spec(_prefs_spec)
_prefs_spec.loader.exec_module(prefs)
_diagnostic_spec = importlib.util.spec_from_file_location('hd2_network_diagnostics', ROOT/'launcher-20261026/network_diagnostics.py')
diagnostics = importlib.util.module_from_spec(_diagnostic_spec)
_diagnostic_spec.loader.exec_module(diagnostics)
CLIENT = prefs.SSHClient(prefs.DEFAULTS)
SSH = CLIENT.command()
SOCK = CLIENT.socket
SETTINGS = prefs.DEFAULTS
PROGRESS_HOOK = None

def report_progress(stage, status='running', detail=None):
    if PROGRESS_HOOK is not None:
        PROGRESS_HOOK(stage, status, detail)

def refresh_settings():
    global CLIENT, SSH, SOCK, SETTINGS
    settings = prefs.load()
    if settings['ssh'] != CLIENT.settings:
        CLIENT = prefs.SSHClient(settings)
    SETTINGS = settings
    SSH = CLIENT.command()
    SOCK = CLIENT.socket

def vm_reachable():
    refresh_settings()
    return reachable(SETTINGS['ssh']['port'], SETTINGS['ssh']['host'])

# SteamOS may restrict the Steam user session to CPUs 0-4. Restore the guest's
# online CPU mask before Proton starts so its children inherit the full mask.
BASE_LAUNCH = 'VKD3D_CONFIG=single_queue FEX_NEEDSSECCOMP=1 FEX_DISKCACHE=0 WINEDEBUG=-all PROTON_USE_XALIA=0 PROTON_LOG=1 PROTON_LOG_DIR=/tmp taskset -c $(cat /sys/devices/system/cpu/online) %command%'
PROXY_LAUNCH = BASE_LAUNCH.replace('VKD3D_CONFIG=single_queue ', 'VKD3D_CONFIG=single_queue https_proxy=http://192.168.127.254:7890 ')
# 2026-10-28: the three-hour successful session used TUN plus this per-game
# Host HTTPS proxy. Steam itself had no proxy drop-in. Keep those separate.
TUN_LAUNCH = PROXY_LAUNCH
WORKING_LAUNCH = PROXY_LAUNCH


def verify_fx_profile():
    executable = pathlib.Path(APP) / 'Contents/MacOS/steamac-vm'
    if not executable.is_file() or hashlib.sha256(executable.read_bytes()).hexdigest() != APP_EXECUTABLE_SHA256:
        raise RuntimeError('The verified FX performance copy is missing or has changed. Keep the project folder intact; no fallback FX was started.')
    prefs_file = pathlib.Path.home() / 'Library/Preferences/es.fxgam.steamac.plist'
    values = plistlib.loads(prefs_file.read_bytes()) if prefs_file.is_file() else {}
    if values.get('metalHUD') is not False or values.get('superResolution') is not False:
        raise RuntimeError('This performance profile requires Metal HUD and MetalFX super resolution to stay off in FX Display settings.')

def say(s): print(s, flush=True)
def reachable(port, host='127.0.0.1'):
    try:
        with socket.create_connection((host,port),timeout=.5): return True
    except OSError: return False

def remote(code, timeout=45):
    r = subprocess.run(SSH+['python3 -'],input=code,text=True,capture_output=True,timeout=timeout)
    if r.returncode: raise RuntimeError('虚拟机检查未通过：'+r.stderr.strip()[-700:])
    return r.stdout

def connect():
    refresh_settings()
    deadline = time.monotonic() + 90
    announced = False
    while True:
        try:
            _connect_once()
            return
        except prefs.AuthenticationError:
            raise
        except RuntimeError:
            if time.monotonic() >= deadline:
                raise RuntimeError('虚拟机连接尚未就绪。请保留 FX 窗口，稍后重新双击启动入口。')
            if not announced:
                say('正在等待虚拟机连接就绪，请保持 FX 窗口开启……')
                announced = True
            time.sleep(2)

def _connect_once():
    CLIENT.connect_once()


def activate_fx():
    # LaunchServices activation can fail even while the VM is healthy.
    try:
        result = subprocess.run(['open',APP],capture_output=True,text=True,timeout=8)
        activated = result.returncode == 0
    except (OSError,subprocess.TimeoutExpired):
        activated = False
    if not activated:
        say('FX 已运行，但未能自动切换窗口。请手动切换到 FX；游戏启动将继续。')

def wait_for_game():
    say('正在确认游戏进程启动；若出现驱动版本提示，请在 FX 窗口选择“继续”。')
    for _ in range(90):
        running=remote("import subprocess\nprint(subprocess.run(['pgrep','-x','helldivers2.exe'],capture_output=True,text=True).stdout.strip())\n").strip()
        if running:
            say('已确认绝地潜兵 2 进程启动，请切换到 FX 窗口等待游戏载入。')
            return
        time.sleep(2)
    raise RuntimeError('Steam 已收到请求，但尚未检测到游戏进程。请查看 FX 中是否有登录、更新或启动错误提示，保留此窗口回到聊天检查。')

EAC_STATUS = r'''
import pathlib,re,json
base=pathlib.Path.home()/'.local/share/Steam/steamapps/compatdata/553850/pfx/drive_c/users'
logs=[p for p in base.glob('*/AppData/Roaming/EasyAntiCheat/**/anticheatlauncher.log') if p.stat().st_mtime>=SINCE]
result={'result':'pending'}
if logs:
 p=max(logs,key=lambda p:p.stat().st_mtime)
 text=p.read_text(errors='replace')[-32768:]
 exits=re.findall(r'Terminating with:\s*(\d+)',text)
 if exits and int(exits[-1])!=0:result={'result':'failed','exit_code':int(exits[-1])}
 elif exits and int(exits[-1])==0 and 'Launcher finished with: 301' in text and 'Successfully initialized the Easy Anti-Cheat module' in text:result={'result':'passed'}
print(json.dumps(result))
'''

def check_eac(since, attempts=15):
    if since is None:
        report_progress('eac','unverified')
        return
    report_progress('eac')
    for _ in range(attempts):
        try:
            result=json.loads(remote(EAC_STATUS.replace('SINCE',repr(float(since)))))
        except (RuntimeError,ValueError,OSError,subprocess.TimeoutExpired):
            report_progress('eac','unverified')
            return
        if result['result']=='passed':
            report_progress('eac','done')
            return
        if result['result']=='failed':
            raise RuntimeError('EAC initialization failed (exit '+str(result['exit_code'])+'). The game was left running; inspect its error message.')
        time.sleep(2)
    report_progress('eac','unverified')

PLAYFAB_PROBE = r'''
import json,socket,ssl,time
host='title.playfabapi.com';port=443
context=ssl.create_default_context()
result={'target':host,'routes':{}}

def probe(route):
    started=time.monotonic()
    stream=None
    try:
        if route=='direct':
            stream=socket.create_connection((host,port),timeout=2.5)
        else:
            stream=socket.create_connection(('192.168.127.254',7890),timeout=2.5)
            target=host+':'+str(port)
            stream.sendall(('CONNECT '+target+' HTTP/1.1\r\nHost: '+target+'\r\n\r\n').encode('ascii'))
            response=b''
            while b'\r\n\r\n' not in response and len(response)<4096:
                chunk=stream.recv(1024)
                if not chunk:break
                response+=chunk
            first=response.split(b'\r\n',1)[0].split()
            if len(first)<2 or first[1]!=b'200':
                return {'state':'failed','ms':None}
        with context.wrap_socket(stream,server_hostname=host) as secure:
            return {'state':'reachable','ms':round((time.monotonic()-started)*1000,1),'tls':secure.version()}
    except (OSError,ValueError):
        return {'state':'failed','ms':None}
    finally:
        if stream is not None:
            try:stream.close()
            except OSError:pass

for name in ('direct','proxy'):
    result['routes'][name]=probe(name)
print(json.dumps(result))
'''

UDP_MONITOR = r'''
import json,os,re,socket,statistics,struct,subprocess,time

def udp_counters():
    try:
        rows=[line.split()[1:] for line in (__import__('pathlib').Path('/proc/net/snmp')).read_text().splitlines()
              if line.startswith('Udp: ')]
        header,row=rows[:2]
        pairs=dict(zip(header,row))
        return int(pairs.get('InDatagrams',0)),int(pairs.get('OutDatagrams',0))
    except (OSError,ValueError):
        return None,None

def game_sockets():
    try:
        output=subprocess.run(['ss','-uanp'],capture_output=True,text=True,timeout=3).stdout
    except (OSError,subprocess.SubprocessError):
        return None,None
    rows=[line for line in output.splitlines() if 'helldivers2.exe' in line]
    connected=0
    for line in rows:
        fields=line.split()
        if len(fields)>4 and fields[4] not in ('*:*','0.0.0.0:*','[::]:*'):
            connected+=1
    return len(rows),connected

def stun_sample(host,port):
    transaction=os.urandom(12)
    request=struct.pack('!HHI',1,0,0x2112A442)+transaction
    started=time.monotonic()
    try:
        with socket.socket(socket.AF_INET,socket.SOCK_DGRAM) as stream:
            stream.settimeout(1.5)
            stream.sendto(request,(host,port))
            response,_=stream.recvfrom(2048)
        valid=False
        if len(response)>=20:
            message_type,_,cookie=struct.unpack('!HHI',response[:8])
            valid=(message_type==0x0101 and cookie==0x2112A442 and response[8:20]==transaction)
        return {'target':host,'ok':valid,
                'ms':round((time.monotonic()-started)*1000,1) if valid else None}
    except OSError:
        return {'target':host,'ok':False,'ms':None}

in_before,out_before=udp_counters()
sockets_before,connected_before=game_sockets()
samples=[]
for host,port in [('stun.cloudflare.com',3478),('stun.l.google.com',19302)]*2:
    samples.append(stun_sample(host,port))
time.sleep(3)
in_after,out_after=udp_counters()
sockets_after,connected_after=game_sockets()
valid=[s['ms'] for s in samples if s['ok'] and s['ms'] is not None]
by_target={}
for sample in samples:
    if sample['ok'] and sample['ms'] is not None:
        by_target.setdefault(sample['target'],[]).append(sample['ms'])
changes=[abs(group[index]-group[index-1])
         for group in by_target.values() for index in range(1,len(group))]
result={
    'samples':samples,
    'successes':len(valid),
    'rtt_mean_ms':round(statistics.mean(valid),1) if valid else None,
    'jitter_ms':round(statistics.mean(changes),1) if changes else None,
    'game_sockets':max(value for value in (sockets_before,sockets_after) if value is not None)
        if sockets_before is not None or sockets_after is not None else None,
    'connected_sockets':max(value for value in (connected_before,connected_after) if value is not None)
        if connected_before is not None or connected_after is not None else None,
    'in_datagrams_delta':in_after-in_before if in_before is not None and in_after is not None else None,
    'out_datagrams_delta':out_after-out_before if out_before is not None and out_after is not None else None,
}
print(json.dumps(result))
'''

def monitor_playfab():
    report_progress('playfab')
    try:
        result=json.loads(remote(PLAYFAB_PROBE,timeout=15))
    except (RuntimeError,ValueError,OSError,subprocess.TimeoutExpired):
        report_progress('playfab','unverified')
        say('PlayFab：本次检查未完成；未据此阻止游戏启动。')
        return {'target':'title.playfabapi.com','routes':{}}
    routes=result.get('routes',{}) if isinstance(result,dict) else {}
    direct=routes.get('direct',{}) if isinstance(routes.get('direct'),dict) else {}
    proxy=routes.get('proxy',{}) if isinstance(routes.get('proxy'),dict) else {}
    reachable=[name for name,value in [('直连',direct),('代理',proxy)] if value.get('state')=='reachable']
    report_progress('playfab','done' if reachable else 'unverified')
    latency='，'.join(name+' '+str(next((v.get('ms') for n,v in [('直连',direct),('代理',proxy)] if n==name),None))+' ms'
                    for name in reachable)
    if reachable:
        say('PlayFab：'+('、'.join(reachable))+' TLS 通路可达（'+latency+'）；TLS 可达不等于账号已登录。')
    else:
        say('PlayFab：直连与代理 TLS 通路均未通过；请检查节点和游戏提示。')
    return result

def monitor_udp():
    report_progress('udp')
    try:
        result=json.loads(remote(UDP_MONITOR,timeout=25))
    except (RuntimeError,ValueError,OSError,subprocess.TimeoutExpired):
        report_progress('udp','unverified')
        say('UDP：本次检查未完成；STUN 结果不会阻止游戏启动。')
        return {'samples':[]}
    samples=result.get('samples',[]) if isinstance(result,dict) else []
    successes=sum(1 for sample in samples if isinstance(sample,dict) and sample.get('ok') is True)
    total=len(samples)
    status='done' if successes>=2 else 'unverified'
    report_progress('udp',status)
    mean=result.get('rtt_mean_ms');jitter=result.get('jitter_ms')
    sockets=result.get('game_sockets')
    parts=['成功 '+str(successes)+'/'+str(total)]
    if mean is not None:parts.append('平均 '+str(mean)+' ms')
    if jitter is not None:parts.append('抖动 '+str(jitter)+' ms')
    if sockets is not None:parts.append('游戏 UDP socket '+str(sockets))
    say('UDP 探测：'+'，'.join(parts)+'；这不代表 NAT、匹配或 P2P 一定正常。')
    return result

def run_post_launch_checks():
    report={}
    for name,probe in [('playfab',monitor_playfab),('udp',monitor_udp)]:
        try:
            report[name]=probe()
        except (RuntimeError,ValueError,OSError,subprocess.SubprocessError):
            report[name]={'routes':{}} if name=='playfab' else {'samples':[]}
            report_progress(name,'unverified')
            say(('PlayFab' if name=='playfab' else 'UDP')+'：监测异常；游戏启动未受影响。')
    try:
        diagnostics.record_launch_probe(report)
    except (OSError,ValueError):
        say('启动网络监测结果未能写入诊断历史；游戏保持运行。')

STATE = r'''
import pathlib,subprocess,json,re,hashlib,time,os
s=pathlib.Path.home()/'.local/share/Steam';j=s/'compatibilitytools.d/proton-je-11.0-20261014-3'
ps=subprocess.run(['pgrep','-x','helldivers2.exe'],capture_output=True,text=True).stdout.split()
steam=subprocess.run(['pgrep','-x','steam'],capture_output=True,text=True).stdout.split()
connection_log=s/'logs/connection_log.txt'
connection_states=re.findall(r'\[(Logged On|Logged Off|Connecting|Connected|Logging On|Disconnected),',connection_log.read_text(errors='replace')[-65536:] if connection_log.exists() else '')
r=subprocess.run(['pgrep','-a','-x','reaper'],capture_output=True,text=True).stdout
ids=re.findall(r'SteamLaunch AppId=(\d+)',r)
login=s/'config/loginusers.vdf'
accounts=[]
if login.exists():
 for account,body in re.findall(r'"(765611[0-9]+)"\s*\{([^{}]*)\}',login.read_text(),re.S):
  if re.search(r'"MostRecent"\s*"1"',body):accounts.append(str(int(account)-76561197960265728))
configs=[s/'userdata'/account/'config/localconfig.vdf' for account in accounts]
configs=[p for p in configs if p.is_file()]
if not configs:configs=list((s/'userdata').glob('*/config/localconfig.vdf'))
assert len(configs)==1,'Cannot identify the active Steam account. Sign in to Steam first.'
p=configs[0];m=re.search(r'"553850"\s*\{.*?"LaunchOptions"\s*"([^"\n]*)',p.read_text(),re.S)
t=(s/'config/config.vdf').read_text();t=t[t.index('"CompatToolMapping"'):];tool=re.search(r'"553850"\s*\{[^}]*"name"\s*"([^"\n]*)',t,re.S)
env=[]
if steam:
 try:env=(pathlib.Path('/proc')/steam[0]/'environ').read_bytes().split(b'\0')
 except OSError:pass
proxy_config=pathlib.Path('/run/user')/str(os.getuid())/'systemd/user/steam.service.d/90-hd2-proxy.conf'
f=s/'steamapps/common/FEX-Emu/usr/bin/FEX';nt=j/'files/lib/wine/x86_64-windows/ntdll.dll'
core_names=['x86_64-windows/user32.dll', 'x86_64-windows/win32u.dll', 'x86_64-windows/kernelbase.dll', 'x86_64-unix/win32u.so']
wine_core={n:hashlib.sha256((j/'files/lib/wine'/n).read_bytes()).hexdigest() if (j/'files/lib/wine'/n).is_file() else None for n in core_names}
print(json.dumps({'guest_time':time.time(),'wine_core':wine_core,'vulkan':'steamac.gfx=vulkan' in pathlib.Path('/proc/cmdline').read_text(),'ipv4_only':all((pathlib.Path('/proc/sys/net/ipv6/conf')/name/'disable_ipv6').read_text().strip()=='1' for name in ['all','default','eth0','lo']),'game_pids':ps,'steam_pids':steam,'steam_logged_on':bool(connection_states and connection_states[-1]=='Logged On'),'apps':ids,'steam_proxy':any(v in env for v in [b'https_proxy=http://192.168.127.254:7890']),'steam_proxy_config':proxy_config.is_file(),'launch':m[1] if m else '', 'tool':tool[1] if tool else '', 'fex':hashlib.sha256(f.read_bytes()).hexdigest(),'ntdll':hashlib.sha256(nt.read_bytes()).hexdigest() if nt.exists() else None}))
'''
def network_ready():
    if not GVPROXY.is_file() or not GVPROXY_WRAPPER.is_file(): return False
    if hashlib.sha256(GVPROXY.read_bytes()).hexdigest() != GVPROXY_SHA256: return False
    rows = subprocess.run(['ps','-axo','command='],capture_output=True,text=True,check=True).stdout.splitlines()
    return any(row.startswith(str(GVPROXY)+' -listen-vfkit ') for row in rows)

def tun_active():
    """Return true when macOS routes public IPv4 ranges through a TUN device."""
    try:
        rows=subprocess.run(['netstat','-rn','-f','inet'],capture_output=True,text=True,timeout=5).stdout.splitlines()
    except (OSError,subprocess.SubprocessError):
        return False
    for row in rows:
        fields=row.split()
        if not fields:continue
        if fields[0]=='default' and len(fields)>3 and fields[-1].startswith('utun'):
            return True
        if fields[0] in ('0/1','128.0/1') and any(value.startswith('utun') for value in fields[1:]):
            return True
    return False

def required_launch():
    return PROXY_LAUNCH

def system_http_proxy_enabled():
    try:
        output=subprocess.run(['scutil','--proxy'],capture_output=True,text=True,timeout=5).stdout
    except (OSError,subprocess.SubprocessError):
        return False
    return bool(re.search(r'\b(?:HTTP|HTTPS)Enable\s*:\s*1\b',output))

def state():
    result = json.loads(remote(STATE))
    # A historical Logged On line cannot make a stopped Steam process online.
    result['steam_logged_on'] = bool(result.get('steam_pids') and result.get('steam_logged_on'))
    result['verified_network'] = network_ready()
    return result

def ensure_ipv4():
    code = "from pathlib import Path\nfor name in ['all','default','eth0','lo']:\n (Path('/proc/sys/net/ipv6/conf')/name/'disable_ipv6').write_text('1')\nprint('虚拟机 IPv4 网络已准备。')\n"
    command = 'python3 -c '+shlex.quote(code)
    result = subprocess.run(SSH+['sudo -n '+command],capture_output=True,text=True,timeout=20)
    if result.returncode:
        password = CLIENT.password
        if password is None:
            password = CLIENT.prompt_secret('Guest sudo password: ')
        result = subprocess.run(SSH+['sudo -S -p "" '+command],input=password+'\n',capture_output=True,text=True,timeout=20)
    if result.returncode:
        raise RuntimeError('Guest IPv4 setup failed. Check sudo permission and password.')
    say(result.stdout.strip())

def find_node():
    candidates = [shutil.which('node'), '/opt/homebrew/bin/node', '/usr/local/bin/node',
                  str(pathlib.Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node')]
    for candidate in candidates:
        if candidate and pathlib.Path(candidate).is_file():return str(candidate)
    raise RuntimeError('Node.js is required to configure Steam launch options. Install Node.js or set the options in Steam manually.')


def configure_launch_options(before, target=None):
    target = target or WORKING_LAUNCH
    node = find_node()
    backup_dir = ROOT/'launcher-20261026/backups'
    backup_dir.mkdir(parents=True,exist_ok=True)
    backup = backup_dir/('launch-options-'+time.strftime('%Y%m%d-%H%M%S')+'-'+str(time.time_ns())+'.json')
    fd = os.open(backup,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as stream:
        json.dump({'launch':before['launch'],'tool':before['tool']},stream,ensure_ascii=False,indent=2)
    expression = '''(async()=>{
      const expected=EXPECTED;
      SteamClient.Apps.SetAppLaunchOptions(553850,expected);
      let observed=null;
      const sub=appDetailsStore.RegisterForAppData(553850,d=>{if(d) observed=d.strLaunchOptions;});
      try {
        for(let i=0;i<30;i++) {
          if(observed===expected) return JSON.stringify({saved:true});
          await new Promise(r=>setTimeout(r,200));
        }
        throw Error('Steam did not confirm the launch options');
      } finally { sub.unregister(); }
    })()'''.replace('EXPECTED',json.dumps(target))
    result = subprocess.run([str(node),str(ROOT/'launcher-20261026/steam-cdp.mjs'),expression,str(SETTINGS['ssh']['cdp_local_port'])],capture_output=True,text=True,timeout=20)
    if result.returncode:
        raise RuntimeError('Steam 启动项配置未完成，原设置已备份。')
    response = json.loads(result.stdout)['result']
    if 'exceptionDetails' in response or not json.loads(response['result'].get('value','{}')).get('saved'):
        raise RuntimeError('Steam 未确认新的启动项，原设置已备份。')
    say('已保存经过验证的游戏启动项，原设置已备份。')

def configure_steam_proxy(enabled):
    """Add or remove only the launcher-owned Steam HTTP proxy drop-in."""
    say('正在准备 Steam 的游戏网络连接……' if enabled else '正在关闭 Steam 的游戏级 HTTP 代理……')
    say(remote(r'''
import pathlib,subprocess,time,re,os
ENABLED = ENABLED_VALUE
r=subprocess.run(['pgrep','-a','-x','reaper'],capture_output=True,text=True).stdout
assert not re.search(r'SteamLaunch AppId=',r),'已有游戏运行，未停止 Steam'
p=pathlib.Path('/run/user')/str(os.getuid())/'systemd/user/steam.service.d/90-hd2-proxy.conf'
text='# HD2 helper: runtime only\n[Service]\nEnvironment="https_proxy=http://192.168.127.254:7890" "http_proxy=http://192.168.127.254:7890"\n'
legacy=text.replace('192.168.127.254:7890','127.0.0.1:17890')
assert not p.exists() or p.read_text() in [text,legacy],'运行时配置已有其他内容，未覆盖'
subprocess.run(['systemctl','--user','stop','steam.service'],check=True);time.sleep(7)
assert subprocess.run(['pgrep','-x','steam'],capture_output=True).returncode==1,'存在独立 Steam 实例，请先正常退出'
if ENABLED:
 p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
elif p.exists():
 p.unlink()
subprocess.run(['systemctl','--user','daemon-reload'],check=True)
subprocess.run(['systemctl','--user','reset-failed','steam.service'],check=True)
subprocess.run(['systemctl','--user','start','steam.service'],check=True)
print('Steam 网络已准备。' if ENABLED else 'Steam 游戏级 HTTP 代理已关闭。')
'''.replace('ENABLED_VALUE',repr(bool(enabled)))))


def start_proxy():
    if reachable(7890):return
    app='/Applications/FlClash.app'
    if pathlib.Path(app).is_dir():
        say('正在打开 FlClash，等待代理连接……')
        subprocess.run(['open',app],capture_output=True,timeout=8)
        for _ in range(20):
            if reachable(7890):return
            time.sleep(1)

def main(configure_only=False):
    configure_only = configure_only or '--configure' in sys.argv
    status_only='--status' in sys.argv
    refresh_settings()
    if not status_only and not prefs.local_host(SETTINGS['ssh']['host']):
        raise RuntimeError('Automatic launch and setup require a local FX host. Remote hosts can use SSH connection testing.')
    if not status_only:report_progress('fx')
    if not vm_reachable():
        if status_only: raise RuntimeError('FX 虚拟机尚未运行。')
        running=subprocess.run(['pgrep','-f',APP+'/Contents/MacOS/'],capture_output=True).returncode==0
        if not running:
            verify_fx_profile()
            if not GVPROXY.is_file() or not GVPROXY_WRAPPER.is_file() or hashlib.sha256(GVPROXY.read_bytes()).hexdigest()!=GVPROXY_SHA256:
                raise RuntimeError('当前联机测试所需的网络组件缺失或已改变，请回到此聊天继续检查。')
            say('正在启动 FX（使用已验证的图形及当前联机测试设置）……')
            subprocess.run(['open',APP,'--args','--no-wmtr','--vulkan-driver','kosmickrisp','--gvproxy',str(GVPROXY_WRAPPER),'--ssh-port',str(SETTINGS['ssh']['port']),'--cpus','8','--mem','8192','--cmdline','console=hvc0 loglevel=4 rootwait steamac.gpu_mib=6144','--perf-stats'],check=True)
        for _ in range(60):
            if vm_reachable(): break
            time.sleep(1)
        else: raise RuntimeError('FX 仍在启动，尚未连接到虚拟机。请保留窗口，稍后再检查。')
    if not status_only:
        report_progress('fx','done')
        report_progress('ssh')
    connect(); s=state()
    if not status_only:report_progress('ssh','done',s)
    if status_only:
        say(json.dumps(s,ensure_ascii=False,indent=2)); return
    report_progress('environment')
    if not s['verified_network']:
        raise RuntimeError('当前 FX 没有使用本轮联机测试设置。请正常退出 FX 后，再双击此启动入口。')
    if configure_only and (s['game_pids'] or s['apps']):
        raise RuntimeError('游戏或安装准备步骤正在运行，请正常退出后再使用一键环境配置。当前游戏未被中断。')
    activate_fx()
    if s['game_pids']:
        say('绝地潜兵 2 已在运行，请切换到 FX 窗口继续。')
        report_progress('environment','unverified')
        report_progress('game','done')
        report_progress('eac','unverified')
        return
    if any(app!='553850' for app in s['apps']): raise RuntimeError('当前有其他 Steam 游戏运行，请先退出它，再启动绝地潜兵 2。')
    if '553850' in s['apps']:
        say('Steam 正在准备绝地潜兵 2，正在等待已有启动请求……')
        report_progress('environment','unverified')
        report_progress('game')
        wait_for_game()
        report_progress('game','done')
        report_progress('eac','unverified')
        run_post_launch_checks()
        return
    if not s['vulkan']: raise RuntimeError('当前 FX 使用的是其他图形路径。请退出 FX，再双击此启动文件。')
    mode='tun' if tun_active() else 'proxy'
    target_launch=required_launch()
    say('网络模式：'+('TUN + 游戏 Host HTTPS 代理' if mode=='tun' else 'HTTP 代理'))
    if mode=='tun' and system_http_proxy_enabled():
        raise RuntimeError('检测到 TUN，但 macOS 系统代理仍开启。请在 FlClash 关闭系统代理后重试。')
    # The successful game still explicitly connects to the Host proxy with TUN.
    # A reachable TUN alone does not make this required listener optional.
    if configure_only:start_proxy()
    if not reachable(7890): raise RuntimeError('当前网络需要现有代理的 7890 端口，请先打开原来使用的代理软件。')
    if s['fex']!='ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf' or s['ntdll']!='a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe' or s['tool']!='proton-je-11.0-20261014-3':
        raise RuntimeError('兼容组件与已验证版本不同，请回到此聊天继续检查。原文件没有被自动覆盖。')
    if s['wine_core']!=WINE_CORE_SHA256:
        raise RuntimeError('Wine 系统组件与已验证版本不一致，请回到此聊天修复兼容工具。')
    if not configure_only and ('FEX_DISKCACHE=0' not in s['launch'] or 'FEX_NEEDSSECCOMP=1' not in s['launch']):
        raise RuntimeError('游戏启动设置与已验证配置不同，请回到此聊天继续检查。')
    if not s['ipv4_only']:
        ensure_ipv4()
    proxy_wanted=mode=='proxy'
    proxy_mismatch=(proxy_wanted and not s['steam_proxy']) or (not proxy_wanted and (s['steam_proxy'] or s['steam_proxy_config']))
    if proxy_mismatch:
        configure_steam_proxy(proxy_wanted)
        s=state()
    report_progress('environment','done')
    report_progress('steam')
    opener=urllib.request.build_opener(urllib.request.ProxyHandler({}))
    stable=None;since=time.monotonic();ready=False
    say('正在等待 Steam 完成初始化和网络登录……')
    for _ in range(120):
        s=state(); now=time.monotonic()
        if s['game_pids']:
            say('游戏已在运行。')
            report_progress('steam','done',s)
            report_progress('game','done')
            report_progress('eac','unverified')
            run_post_launch_checks()
            return
        pid=s['steam_pids'][0] if s['steam_pids'] else None
        if pid!=stable:stable=pid;since=now
        try:
            pages=json.load(opener.open('http://127.0.0.1:'+str(SETTINGS['ssh']['cdp_local_port'])+'/json/list',timeout=2))
            ready=any(p.get('title')=='SharedJSContext' for p in pages)
        except Exception:ready=False
        if pid and ready and s['steam_logged_on'] and now-since>=8:break
        time.sleep(1)
    else:raise RuntimeError('Steam 尚未完成网络登录。请在 FX 中检查 Steam 的连接状态，再重新双击启动入口。')
    # Steam's API may not exist until SharedJSContext and login are ready.
    # Use the latest state and write at most once, only when options differ.
    if s['launch'].strip()!=target_launch:
        configure_launch_options(s,target_launch)
    if configure_only:
        report_progress('steam','done',s)
        say('一键环境配置完成。可以返回菜单启动游戏。')
        return
    report_progress('steam','done',s)
    report_progress('game')
    say('正在启动绝地潜兵 2……')
    say(remote(r'''
import subprocess,os
r=subprocess.run(['steam','-applaunch','553850'],env=dict(os.environ,DISPLAY=':0',XDG_RUNTIME_DIR='/run/user/'+str(os.getuid())),capture_output=True,text=True,timeout=15)
assert r.returncode==0,r.stderr
print('启动请求已交给 Steam。')
'''))
    wait_for_game()
    report_progress('game','done')
    check_eac(s.get('guest_time'))
    run_post_launch_checks()

if __name__=='__main__':
    try:main()
    except subprocess.CalledProcessError as e:
        say('启动步骤未完成（退出码 '+str(e.returncode)+'）。请保留此窗口中的提示，回到聊天继续检查。');sys.exit(1)
    except (RuntimeError,subprocess.TimeoutExpired,OSError,ValueError) as e:
        say(str(e));sys.exit(1)
