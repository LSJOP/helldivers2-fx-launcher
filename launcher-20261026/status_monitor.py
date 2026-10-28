"""Read-only dashboard probes. Never authenticates, starts or configures anything."""
import json
import importlib.util
from datetime import datetime
from pathlib import Path
import subprocess
import socket
import ssl
from functools import lru_cache
import statistics
import time

_locale_spec=importlib.util.spec_from_file_location('hd2fx_monitor_locales',Path(__file__).with_name('i18n.py'))
i18n=importlib.util.module_from_spec(_locale_spec)
_locale_spec.loader.exec_module(i18n)

STEAM_TARGET='store.steampowered.com:443'
DIAGNOSTICS_HISTORY=Path.home()/'Library/Application Support/Helldivers2FXLauncher/Diagnostics/history.jsonl'


@lru_cache(maxsize=1)
def tls_context():
    return ssl.create_default_context()


def steam_latency(timeout=1.5):
    """Time verified TLS setup through the same local proxy used for gaming.

    Includes proxy routing/DNS/TCP/TLS; an optimistic proxy CONNECT response alone
    is insufficient. Sends no account/game data and validates the server cert.
    """
    try:
        context=tls_context()
        started=time.monotonic()
        with socket.create_connection(('127.0.0.1',7890),timeout=timeout) as stream:
            stream.sendall(('CONNECT '+STEAM_TARGET+' HTTP/1.1\r\nHost: '+STEAM_TARGET+'\r\n\r\n').encode('ascii'))
            response=b''
            while b'\r\n\r\n' not in response and len(response)<4096:
                remaining=timeout-(time.monotonic()-started)
                if remaining<=0:return None,'timeout'
                stream.settimeout(remaining)
                chunk=stream.recv(1024)
                if not chunk:break
                response+=chunk
            first=response.split(b'\r\n',1)[0].split()
            if len(first)>=2 and first[0].startswith(b'HTTP/') and first[1]==b'200' and b'\r\n\r\n' in response:
                remaining=timeout-(time.monotonic()-started)
                if remaining<=0:return None,'timeout'
                with context.wrap_socket(stream,server_hostname='store.steampowered.com',do_handshake_on_connect=False) as secure:
                    secure.settimeout(remaining)
                    secure.do_handshake()
                return round((time.monotonic()-started)*1000,1),'ready'
            return None,'error'
    except (socket.timeout,TimeoutError):return None,'timeout'
    except OSError:return None,'error'


def latest_launch_probe(path=None):
    """Read the newest allowlisted launch probe without sending network traffic."""
    path=Path(path) if path is not None else DIAGNOSTICS_HISTORY
    try:
        with path.open('rb') as stream:
            stream.seek(0,2)
            stream.seek(max(0,stream.tell()-131072))
            lines=stream.read().decode('utf-8',errors='replace').splitlines()
    except OSError:
        return {}
    row=None
    for line in reversed(lines):
        try:
            candidate=json.loads(line)
        except (ValueError,TypeError):
            continue
        if isinstance(candidate,dict) and candidate.get('kind')=='launch_probe':
            row=candidate
            break
    if row is None:
        return {}
    direct=row.get('playfab_direct')
    proxy=row.get('playfab_proxy')
    checked=sum(value in ('reachable','failed') for value in (direct,proxy))
    reachable=sum(value=='reachable' for value in (direct,proxy))
    latencies=[value for value in (row.get('playfab_direct_ms'),row.get('playfab_proxy_ms'))
               if type(value) in (int,float) and 0<=value<=120000 and value>0]
    try:
        samples=max(0,min(64,int(row.get('udp_samples') or 0)))
        successes=max(0,min(samples,int(row.get('udp_successes') or 0)))
        rtts=[float(value) for value in row.get('udp_rtt_ms',[])
              if type(value) in (int,float) and 0<=value<=120000]
    except (TypeError,ValueError):
        samples=successes=0;rtts=[]
    jitter=row.get('udp_jitter_ms')
    if type(jitter) not in (int,float) or not 0<=jitter<=120000:
        jitter=None
    age=None
    try:
        moment=datetime.fromisoformat(row['time'])
        if moment.tzinfo is None:
            moment=moment.astimezone()
        age=max(0,int((datetime.now().astimezone()-moment.astimezone()).total_seconds()))
    except (KeyError,ValueError,TypeError,OverflowError):
        pass
    return {
        'playfab_checked_routes':checked,
        'playfab_reachable':reachable,
        'playfab_ms':round(min(latencies),1) if latencies else None,
        'udp_samples':samples,
        'udp_successes':successes,
        'udp_ms':round(statistics.mean(rtts),1) if rtts else None,
        'udp_jitter_ms':round(jitter,1) if jitter is not None else None,
        'probe_age_seconds':age,
    }

GUEST_STATUS = r'''
import json,pathlib,re,subprocess
def running(name):
 r=subprocess.run(['pgrep','-x',name],capture_output=True,timeout=1)
 return True if r.returncode==0 else (False if r.returncode==1 else None)
steam=running('steam');game=running('helldivers2.exe');logged_on=None
if steam is False:logged_on=False
elif steam:
 try:
  with (pathlib.Path.home()/'.local/share/Steam/logs/connection_log.txt').open('rb') as stream:
   stream.seek(0,2);stream.seek(max(0,stream.tell()-65536))
   states=re.findall(r'\[(Logged On|Logged Off|Connecting|Connected|Logging On|Disconnected),',stream.read().decode(errors='replace'))
  if states:logged_on=states[-1]=='Logged On'
 except OSError:pass
print(json.dumps({'steam_logged_on':logged_on,'game_running':game}))
'''


def snapshot(prefs,helper,language):
    def tr(a,b):return i18n.message(b,language)
    unknown=(tr('未检查','unchecked'),'muted')
    data={name:unknown for name in ['fx','ssh','steam','proxy','game']}
    data.update(latency_vm_ms=None,latency_vm_state='unchecked',latency_steam_ms=None,latency_steam_state='unchecked',
                playfab_checked_routes=0,playfab_reachable=0,playfab_ms=None,
                udp_samples=0,udp_successes=0,udp_ms=None,udp_jitter_ms=None,probe_age_seconds=None)
    detail=tr('远程待连接；[3] 检查','Remote needs a session; [3] checks')
    try:
        result=subprocess.run(['pgrep','-f',helper.APP+'/Contents/MacOS/'],capture_output=True,timeout=2)
        if result.returncode in [0,1]:
            data['fx']=(tr('运行中','running'),'green') if result.returncode==0 else (tr('未运行','stopped'),'muted')
    except (OSError,subprocess.TimeoutExpired):pass
    data['proxy']=(tr('端口就绪','port open'),'green') if helper.reachable(7890) else (tr('端口未就绪','port closed'),'red')
    game_running=None
    try:
        settings=prefs.load()
        client=prefs.SSHClient(settings)
        ssh=settings['ssh']
        # Reuse an existing authenticated master only. ProxyCommand=false makes
        # an ordinary network connection impossible if the master disappears.
        # Ignore user ssh_config so no auth helper or alternative proxy runs.
        command=['ssh','-F','/dev/null','-S',client.socket,'-p',str(ssh['port']),'-l',ssh['username'],
                 '-o','BatchMode=yes','-o','ControlMaster=no','-o','ProxyCommand=false',
                 '-o','StrictHostKeyChecking=yes','-o','ClearAllForwardings=yes',
                 '-o','ForwardAgent=no','-o','ForwardX11=no']
        if not settings['ssh_configured'] or not Path(client.socket).exists():
            data['ssh']=(tr('待连接','no session'),'muted')
            data['latency_vm_state']='no_session'
        else:
            master=subprocess.run(command+['-O','check',ssh['host']],capture_output=True,timeout=1.5)
            if master.returncode:
                data['ssh']=(tr('连接中断','disconnected'),'red')
            else:
                started=time.monotonic()
                result=subprocess.run(command+[ssh['host'],'python3 -'],input=GUEST_STATUS,text=True,capture_output=True,timeout=4)
                if result.returncode:raise RuntimeError('Status probe failed')
                guest=json.loads(result.stdout)
                if not isinstance(guest,dict) or not all(guest.get(key) is None or type(guest[key]) is bool for key in ['steam_logged_on','game_running']):
                    raise ValueError('Invalid status response')
                game_running=guest.get('game_running')
                data['ssh']=(tr('已连接','connected'),'green')
                data['latency_vm_ms']=round((time.monotonic()-started)*1000,1)
                data['latency_vm_state']='ready'
                for key,field,yes,no in [('steam','steam_logged_on',tr('已登录','signed in'),tr('未登录','signed out')),
                                          ('game','game_running',tr('运行中','running'),tr('未运行','stopped'))]:
                    if guest.get(field) is not None:data[key]=(yes,'green') if guest[field] else (no,'muted')
                if guest.get('game_running') is True:
                    data.update(latest_launch_probe())
                detail=''
    except (OSError,ValueError,RuntimeError,subprocess.SubprocessError) as error:
        data['ssh']=(tr('检查失败','check failed'),'red')
        data['latency_vm_state']='timeout' if isinstance(error,subprocess.TimeoutExpired) else 'error'
        detail=tr('远程检查失败；R 重试','Remote check failed; R retries')
    # Leave only local/SSH observations while a game is running or unverified.
    # No automatic external TLS traffic is needed to paint the status footer.
    if game_running is False and data['proxy'][1]=='green':
        data['latency_steam_ms'],data['latency_steam_state']=steam_latency()
    else:
        data['latency_steam_state']='paused'
    data['note']=i18n.text('status.updated',language,time=time.strftime('%H:%M:%S'))+(' · '+detail if detail else '')
    return data
