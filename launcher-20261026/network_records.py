"""Credential-free network snapshots and Steam history, using an existing SSH master."""
from datetime import datetime
import json
import os
from pathlib import Path
import plistlib
import re
import shlex
import sqlite3
import subprocess
import tempfile
from urllib.parse import urlsplit, urlunsplit
import uuid


def stamp():
    return datetime.now().astimezone().isoformat(timespec='seconds')


def clean_label(value):
    if not isinstance(value,str) or not value.strip():return None
    if re.search(r'://|password|passwd|token|secret|subscription|订阅',value,re.I):return None
    return ''.join(c for c in value if c.isprintable()).strip()[:100] or None


def safe_proxy(value):
    try:
        parsed=urlsplit(value)
        if parsed.scheme not in ['http','https','socks5','socks5h'] or not parsed.hostname:return None
        host=parsed.hostname
        if ':' in host:host='['+host+']'
        return urlunsplit((parsed.scheme,host+(':'+str(parsed.port) if parsed.port else ''),'','',''))
    except (ValueError,TypeError):return None


SAFE_ENV={'VKD3D_CONFIG':{'single_queue'},'FEX_NEEDSSECCOMP':{'0','1'},
          'FEX_DISKCACHE':{'0','1'},'WINEDEBUG':{'-all'},'PROTON_USE_XALIA':{'0','1'},
          'PROTON_LOG':{'0','1'},'PROTON_LOG_DIR':{'/tmp'},'PROTON_USE_WINED3D':{'0','1'}}
PROXIES={'https_proxy','http_proxy','all_proxy','HTTPS_PROXY','HTTP_PROXY','ALL_PROXY'}
CPU_PREFIX='taskset -c $(cat /sys/devices/system/cpu/online)'


def safe_environment(values):
    result={}
    if not isinstance(values,dict):return result
    for key,value in values.items():
        if key in PROXIES:
            cleaned=safe_proxy(value)
            if cleaned:result[key]=cleaned
        elif key in SAFE_ENV and value in SAFE_ENV[key]:result[key]=value
    return result


def safe_launch(text):
    """Keep only recognized launch syntax; never persist arbitrary custom text."""
    if not isinstance(text,str):return {'text':None,'omitted':True}
    try:tokens=shlex.split(text.replace(CPU_PREFIX,'__HD2_ALL_CPUS__'))
    except ValueError:return {'text':None,'omitted':True}
    kept=[];omitted=False
    for token in tokens:
        if token=='__HD2_ALL_CPUS__':kept.append(CPU_PREFIX)
        elif token in ['%command%','--use-d3d11','-dx11','--dx11','-d3d11','--d3d11']:kept.append(token)
        elif '=' in token:
            key,value=token.split('=',1);values=safe_environment({key:value})
            if key in values:
                kept.append(key+'='+values[key]);omitted=omitted or values[key]!=value
            else:omitted=True
        else:omitted=True
    return {'text':' '.join(kept),'omitted':omitted}


def flclash_selection(home=None):
    home=Path(home) if home else Path.home()
    result={'node_name':None,'source':'unavailable','runtime_verified':False,
            'configured_mode':None,'tun_setting':None,'system_proxy_setting':None,
            'allow_lan_setting':None,'ipv6_setting':None,'mixed_port':None}
    try:
        values=plistlib.loads((home/'Library/Preferences/com.follow.clash.plist').read_bytes())
        config=json.loads(values.get('flutter.config','{}'))
        patch=config.get('patchClashConfig',{})
        mode=patch.get('mode')
        result['configured_mode']=mode if mode in ['global','rule','direct'] else None
        for target,value in [('tun_setting',config.get('vpnProps',{}).get('enable')),
                             ('system_proxy_setting',config.get('networkProps',{}).get('systemProxy')),
                             ('allow_lan_setting',patch.get('allow-lan')),('ipv6_setting',patch.get('ipv6'))]:
            result[target]=value if type(value) is bool else None
        port=patch.get('mixed-port')
        result['mixed_port']=port if type(port) is int and 1<=port<=65535 else None
        profile_id=config.get('currentProfileId')
        if not isinstance(profile_id,(str,int)):return result
        database=home/'Library/Application Support/com.follow.clash/database.sqlite'
        uri=database.resolve().as_uri()+'?mode=ro'
        connection=sqlite3.connect(uri,uri=True,timeout=.5)
        try:
            row=connection.execute('SELECT selected_map,current_group_name FROM profiles WHERE id=?',(profile_id,)).fetchone()
        finally:connection.close()
        if not row:return result
        selections=json.loads(row[0]);group='GLOBAL' if mode=='global' else row[1]
        if not isinstance(selections,dict):return result
        result['node_name']=clean_label(selections.get(group))
        if result['node_name']:
            result['source']='flclash_saved_GLOBAL' if mode=='global' else 'flclash_saved_display_group'
        return result
    except (OSError,ValueError,TypeError,AttributeError,sqlite3.Error,plistlib.InvalidFileException):
        return result


GUEST_READ = r'''
import pathlib,re,json,subprocess,datetime,time
steam=pathlib.Path.home()/'.local/share/Steam'
log=steam/'logs/connection_log.txt';text='';truncated=False
if log.is_file():
 with log.open('rb') as stream:
  size=log.stat().st_size;truncated=size>524288;stream.seek(max(0,size-524288));text=stream.read().decode(errors='replace')
events=re.findall(r'^\[(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d)\].*?\[(Logged On|Logged Off|Connecting|Connected|Logging On|Disconnected),',text,re.M)
steam_pids=subprocess.run(['pgrep','-x','steam'],capture_output=True,text=True).stdout.split()
games=[]
for pid in subprocess.run(['pgrep','-x','helldivers2.exe'],capture_output=True,text=True).stdout.split():
 try:
  env=dict(x.split(b'=',1) for x in (pathlib.Path('/proc')/pid/'environ').read_bytes().split(b'\0') if b'=' in x)
  names=['VKD3D_CONFIG','FEX_NEEDSSECCOMP','FEX_DISKCACHE','WINEDEBUG','PROTON_USE_XALIA','PROTON_LOG','PROTON_LOG_DIR','https_proxy','http_proxy','all_proxy','HTTPS_PROXY','HTTP_PROXY','ALL_PROXY']
  games.append({'pid':int(pid),'environment':{k:env[k.encode()].decode(errors='replace') for k in names if k.encode() in env}})
 except OSError:pass
launch=None
login=steam/'config/loginusers.vdf';accounts=[]
if login.is_file():
 for account,body in re.findall(r'"(765611[0-9]+)"\s*\{([^{}]*)\}',login.read_text(),re.S):
  if re.search(r'"MostRecent"\s*"1"',body):accounts.append(str(int(account)-76561197960265728))
configs=[steam/'userdata'/account/'config/localconfig.vdf' for account in accounts]
configs=[p for p in configs if p.is_file()]
if not configs:configs=list((steam/'userdata').glob('*/config/localconfig.vdf'))
if len(configs)==1:
 m=re.search(r'"553850"\s*\{.*?"LaunchOptions"\s*"([^"\n]*)',configs[0].read_text(),re.S)
 if m:launch=m[1]
ipv6={name:(pathlib.Path('/proc/sys/net/ipv6/conf')/name/'disable_ipv6').read_text().strip() for name in ['all','default','eth0','lo'] if (pathlib.Path('/proc/sys/net/ipv6/conf')/name/'disable_ipv6').is_file()}
print(json.dumps({'read_at':time.time(),'timezone_offset':datetime.datetime.now().astimezone().strftime('%z'),
 'steam_running':bool(steam_pids),'log_available':log.is_file(),'log_truncated':truncated,
 'log_mtime':log.stat().st_mtime if log.is_file() else None,'events':events,'saved_launch_raw':launch,'games':games,'ipv6_disabled':ipv6}))
'''


def summarize_steam(data):
    events=data.get('events',[]);state=None;last_time=None;pending=None
    disconnected=None;recovered=None;duration=None
    for row in events:
        if not isinstance(row,(list,tuple)) or len(row)!=2:continue
        at,current=row
        try:moment=datetime.strptime(at,'%Y-%m-%d %H:%M:%S')
        except (ValueError,TypeError):continue
        if current not in ['Logged On','Logged Off','Connecting','Connected','Logging On','Disconnected']:continue
        state=current;last_time=at
        if current in ['Logged Off','Disconnected'] and pending is None:
            pending=moment;disconnected=at;recovered=None;duration=None
        if current=='Logged On' and pending is not None:
            elapsed=(moment-pending).total_seconds()
            if elapsed>=0:recovered=at;duration=int(elapsed)
            pending=None
    return {'running':bool(data.get('steam_running')),'state':state if data.get('steam_running') else 'stopped',
            'log_state':state,
            'last_state_at':last_time,'last_disconnect_at':disconnected,'last_recovery_at':recovered,
            'outage_seconds':duration,'outage_open':pending is not None,
            'timezone_offset':data.get('timezone_offset'),'log_available':bool(data.get('log_available')),
            'history_truncated':bool(data.get('log_truncated'))}


def guest_snapshot(helper):
    """Never authenticate or reconnect if the existing master is unavailable."""
    try:
        helper.refresh_settings()
        client=helper.CLIENT
        check=subprocess.run(client.base()+['-O','check',client.settings['host']],capture_output=True,timeout=4)
        if check.returncode:return {'status':'unavailable','reason':'no_existing_session'}
        args=client.command()
        args=args[:-1]+['-o','ControlMaster=no','-o','ProxyCommand=false']+args[-1:]
        p=subprocess.run(args+['python3 -'],input=GUEST_READ,text=True,capture_output=True,timeout=12)
        if p.returncode:return {'status':'unavailable','reason':'existing_session_read_failed'}
        raw=json.loads(p.stdout)
        ipv6=raw.get('ipv6_disabled',{})
        return {'status':'available','read_at':raw.get('read_at'),'steam':summarize_steam(raw),
                'saved_launch':safe_launch(raw.get('saved_launch_raw')),
                'ipv6_disabled':{k:ipv6[k]=='1' for k in ['all','default','eth0','lo'] if isinstance(ipv6,dict) and ipv6.get(k) in ['0','1']},
                'games':[{'pid':g['pid'],'environment':safe_environment(g.get('environment',{}))}
                         for g in raw.get('games',[]) if isinstance(g,dict) and type(g.get('pid')) is int]}
    except (OSError,ValueError,TypeError,KeyError,subprocess.SubprocessError):
        return {'status':'unavailable','reason':'read_failed'}


def capture(helper,network):
    local=network.inspect();conditions=network.success_conditions()
    return {'version':1,'kind':'user_designated_successful_network_profile','captured_at':stamp(),
            'verification':'user_designated_not_an_automatic_multiplayer_test',
            'network':{'default_interface':local.get('default_interface'),'wired_default':local.get('wired_default'),
                       'wifi':[{'device':w.get('device'),'on':w.get('on')} for w in local.get('wifi',[])],
                       'proxy_7890_available':local.get('proxy_available'),
                       'public_tun_route':conditions.get('tun_route'),'system_proxy':conditions.get('system_proxy')},
            'flclash':flclash_selection(),'guest':guest_snapshot(helper)}


def save(snapshot,settings_file):
    directory=Path(settings_file).parent/'network-snapshots';directory.mkdir(parents=True,exist_ok=True,mode=0o700)
    target=directory/('success-'+datetime.now().strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]+'.json')
    fd,temporary=tempfile.mkstemp(prefix='.success-',dir=str(directory))
    try:
        with os.fdopen(fd,'w',encoding='utf-8') as stream:
            json.dump(snapshot,stream,ensure_ascii=False,indent=2);stream.write('\n');stream.flush();os.fsync(stream.fileno())
        os.chmod(temporary,0o600);os.replace(temporary,target)
        return target
    finally:
        if os.path.exists(temporary):os.unlink(temporary)
