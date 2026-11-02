"""Explicit Native operations over pinned legacy Core; no import-time system changes."""
import contextlib
import copy
import fcntl
import hashlib
import importlib.util
import json
import os
import plistlib
from pathlib import Path
import re
import signal
import stat
import subprocess
import sys
import tempfile
import time
import uuid

_security_spec=importlib.util.spec_from_file_location('native_credential_security',Path(__file__).with_name('credential_security.py'))
security=importlib.util.module_from_spec(_security_spec);_security_spec.loader.exec_module(security)

_perf_spec=importlib.util.spec_from_file_location('native_performance_configuration',Path(__file__).with_name('performance_configuration.py'))
performance_configuration=importlib.util.module_from_spec(_perf_spec);_perf_spec.loader.exec_module(performance_configuration)

class OperationError(Exception):
    def __init__(self, code, details=None):
        self.code, self.details = code, details or {}
        super().__init__(code)

GUEST_ENVIRONMENT_READ = r"""
import json,pathlib,platform,re,subprocess
steam=pathlib.Path.home()/'.local/share/Steam'
roots=[steam]
folders=steam/'steamapps/libraryfolders.vdf'
if folders.is_file():
 for value in re.findall(r'"path"\s*"([^"\n]+)"',folders.open('rb').read(262144).decode(errors='replace'))[:8]:
  candidate=pathlib.Path(value)
  if candidate.is_absolute() and candidate not in roots:roots.append(candidate)
manifest=None;game=None
for root in roots:
 p=root/'steamapps/appmanifest_553850.acf'
 if p.is_file():
  text=p.open('rb').read(65536).decode(errors='replace')
  match=re.search(r'"installdir"\s*"([^"\n]+)"',text)
  if match and 0<len(match[1])<=128 and pathlib.Path(match[1]).name==match[1] and '/' not in match[1] and '\\' not in match[1]:
   manifest=p;game=root/'steamapps/common'/match[1];break
components={'steam_files':steam.is_dir(),'game_manifest':manifest is not None,'game_directory':bool(game and game.is_dir()),
 'game_executable':bool(game and (game/'bin/helldivers2.exe').is_file()),
 'proton_files':(steam/'compatibilitytools.d/proton-je-11.0-20261014-3/proton').is_file(),
 'fex_files':(steam/'steamapps/common/FEX-Emu/usr/bin/FEX').is_file()}
def count(name):
 r=subprocess.run(['pgrep','-x',name],capture_output=True,text=True,timeout=5)
 if r.returncode not in (0,1):raise RuntimeError('Unable to inspect process state')
 return len(r.stdout.split())
print(json.dumps({'guest_os':platform.system()+' '+platform.release(),'guest_arch':platform.machine(),'guest_python':platform.python_version(),
 'components':components,'steam_process_count':count('steam'),'game_process_count':count('helldivers2.exe'),
 'scope':'read_only_file_presence_and_processes','eac':'unverified','multiplayer':'unverified','main_menu':'unverified'}))
"""

OPERATIONS = {
    'performance_read': ('performance', False, False),
    'performance_preview': ('performance', False, False),
    'performance_restore_preview': ('performance', False, False),
    'performance_apply': ('performance', True, False),
    'performance_restore': ('performance', True, False),
    'read_configuration': ('settings', False, False),
    'save_configuration': ('settings', True, False),
    'inspect_legacy_runtime': ('fx', False, True),
    'inspect_network': ('environment', False, True),
    'test_network': ('environment', False, True),
    'test_ssh': ('environment', True, True),
    'test_guest_sudo': ('settings', True, True),
    'connect_fx': ('environment', True, True),
    'inspect_guest_environment': ('environment', True, True),
    'check_fx_state': ('fx', False, True),
    'start_fx': ('fx', True, True),
    'start_steam': ('fx', True, True),
    'inspect_guest': ('environment', True, True),
    'launch_game': ('dashboard', True, True),
    'preflight_launch': ('dashboard', False, True),
    'observe_launch': ('dashboard', True, True),
    'apply_performance': ('settings', True, True),
    'read_performance': ('performance', False, False),
    'apply_network_profile': ('environment', True, True),
    'restore_network_profile': ('environment', True, True),
    'toggle_network_check': ('environment', True, False),
    'save_network_snapshot': ('environment', True, True),
    'record_match': ('environment', True, False),
    'read_network_history': ('environment', False, False),
    'export_network_report': ('logs', True, False),
    'export_environment_report': ('logs', True, False),
    'check_updates': ('settings', False, True),
    'get_legacy_catalog': ('settings', False, False),
}

def fx_process_view(rows, executable):
    """Normalize only the observed one-supervisor/one-direct-VM-child topology.

    The original guard still verifies the supervisor's complete descendant tree,
    listeners, SSH peer, CDP forward and binary hashes. Retain raw child identity
    in the returned proof so child replacement cannot evade Session.verify().
    """
    matches=[pid for pid,row in rows.items() if row[2]==executable]
    if len(matches)==1:return rows,[]
    if len(matches)!=2:raise OperationError('FX_IDENTITY_UNVERIFIED')
    edges=[(rows[pid][0],pid) for pid in matches if rows[pid][0] in matches]
    if len(edges)!=1:raise OperationError('FX_IDENTITY_UNVERIFIED')
    parent,child=edges[0]
    if rows[parent][0]==child:raise OperationError('FX_IDENTITY_UNVERIFIED')
    view=dict(rows)
    view[child]=(rows[child][0],rows[child][1],executable+' [verified VM child]')
    return view,[(child,rows[child])]

class Operations:
    def __init__(self, root, emit=None, settings_file=None, data_dir=None):
        self.root = Path(root)
        self.emit = emit or (lambda event: None)
        self.settings = Path(settings_file) if settings_file else Path.home()/'Library/Application Support/Helldivers2FXLauncher/settings.json'
        self.data = Path(data_dir) if data_dir else Path.home()/'Library/Application Support/Helldivers2FXLauncher/native'
        self.modules = {}
        self.secret_values = []
        self.launch_stage = None

    def module(self, name):
        if name not in ('preferences','dependencies','network_profile','network_diagnostics','network_records','performance_profile','performance_catalog','update_checker','i18n','launcher_version','apple_silicon'):
            raise OperationError('INVALID_ARGUMENT')
        if name not in self.modules:
            path = self.root/'launcher-20261026'/(name+'.py')
            spec = importlib.util.spec_from_file_location('native_legacy_'+name, path)
            value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
            if name=='preferences':security.session_only(value)
            self.modules[name] = value
        return self.modules[name]

    def scrub(self, value):
        if isinstance(value, dict): return {k:self.scrub(v) for k,v in value.items() if not re.search(r'password|passphrase|token|secret|authorization|private[_-]?key|api[_-]?key',k,re.I)}
        if isinstance(value, (list,tuple)): return [self.scrub(x) for x in value[:200]]
        if isinstance(value,Path): value=str(value)
        if not isinstance(value,str): return value
        value=security.Redactor(self.secret_values).text(value)
        value=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',value)
        value=re.sub(r'(?i)(password|passphrase|token|authorization)\s*[:=]\s*\S+',r'\1=[REDACTED]',value)
        value=re.sub(r'/Users/[^/\s]+', '~/…', value)
        value=re.sub(r'(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])','[IP]',value)
        return value[:4000]

    def event(self, level, message, **extra):
        self.emit(self.scrub(dict(level=level, message=message, **extra)))

    def read_config(self):
        prefs = self.module('preferences')
        if self.settings.is_symlink(): raise OperationError('UNSAFE_PATH')
        raw = self.settings.read_bytes() if self.settings.exists() else b''
        if len(raw)>262144: raise OperationError('OUTPUT_LIMIT')
        data = json.loads(raw) if raw else copy.deepcopy(prefs.DEFAULTS)
        known = prefs.validate(data)
        return data, known, hashlib.sha256(raw).hexdigest()

    def save_config(self, params):
        if not isinstance(params.get('expected_revision'),str) or not isinstance(params.get('configuration'),dict): raise OperationError('INVALID_ARGUMENT')
        original, _, digest = self.read_config()
        if digest != params['expected_revision']: raise OperationError('CONFIG_CHANGED')
        patch = params['configuration']
        if security.Redactor().contains_secret(original) or security.Redactor().contains_secret(patch):raise OperationError('SENSITIVE_CONFIGURATION')
        if set(patch)-{'ssh','ssh_configured','appearance','version'}: raise OperationError('INVALID_ARGUMENT')
        candidate=copy.deepcopy(original)
        for key,value in patch.items():
            if isinstance(value,dict) and isinstance(candidate.get(key),dict): candidate[key].update(value)
            else:candidate[key]=value
        if type(candidate.get('version')) is not int:raise OperationError('INVALID_ARGUMENT')
        known=self.module('preferences').validate(candidate)
        # Preserve unknown fields already on disk, but never accept new unknown fields or credentials.
        for key,value in patch.items():
            if isinstance(value,dict) and set(value)-set(known.get(key,{})): raise OperationError('INVALID_ARGUMENT')
        for key,value in known.items():
            if isinstance(value,dict): candidate.setdefault(key,{}).update(value)
            else:candidate[key]=value
        directory=self.settings.parent
        directory.mkdir(parents=True,exist_ok=True,mode=0o700)
        info=directory.lstat()
        if directory.is_symlink() or info.st_uid!=os.getuid() or info.st_mode & 0o022:raise OperationError('UNSAFE_PATH')
        lock=directory/'.native-config.lock'
        fd=os.open(str(lock),os.O_CREAT|os.O_RDWR|getattr(os,'O_NOFOLLOW',0),0o600)
        try:
            fcntl.flock(fd,fcntl.LOCK_EX|fcntl.LOCK_NB)
            _,_,fresh=self.read_config()
            if fresh!=digest: raise OperationError('CONFIG_CHANGED')
            backup=None
            if self.settings.exists():
                backup=directory/('settings.native-backup-'+uuid.uuid4().hex+'.json')
                bfd=os.open(str(backup),os.O_CREAT|os.O_EXCL|os.O_WRONLY,0o600)
                with os.fdopen(bfd,'wb') as stream:
                    stream.write(self.settings.read_bytes());stream.flush();os.fsync(stream.fileno())
            temp_fd,name=tempfile.mkstemp(prefix='.native-settings-',dir=str(directory))
            try:
                with os.fdopen(temp_fd,'w') as stream:
                    os.fchmod(stream.fileno(),0o600);json.dump(candidate,stream,ensure_ascii=False,indent=2);stream.write('\n');stream.flush();os.fsync(stream.fileno())
                if self.read_config()[2]!=digest: raise OperationError('CONFIG_CHANGED')
                os.replace(name,self.settings)
            finally:
                if os.path.exists(name):os.unlink(name)
            return {'saved':True,'target':str(self.settings),'backup':str(backup) if backup else None,'revision':self.read_config()[2]}
        finally:os.close(fd)

    def runtime(self, params):
        text=params.get('runtime_root')
        if not isinstance(text,str) or not text or len(text)>4096: raise OperationError('RUNTIME_ROOT_REQUIRED')
        root=Path(text).expanduser().resolve(strict=True)
        if not root.is_dir():raise OperationError('INVALID_ARGUMENT')
        # Execute only bundled Python. Root-dependent JS/wrapper must match the pinned archive.
        for relative in ['launcher-20261026/steam-cdp.mjs','tools/check_node.cjs','goal-fx-multiplayer-20261026/gvproxy-eim-wrapper']:
            p=root/relative;expected=self.root/relative
            if p.is_symlink() or not p.is_file() or hashlib.sha256(p.read_bytes()).digest()!=hashlib.sha256(expected.read_bytes()).digest():
                raise OperationError('SOURCE_MISMATCH',{'file':relative})
        path=self.root/'goal-dxmt-20261026/start-hd2.py'
        spec=importlib.util.spec_from_file_location('native_guarded_start',path)
        helper=importlib.util.module_from_spec(spec);sys.modules[spec.name]=helper;spec.loader.exec_module(helper)
        helper.ROOT=root
        helper.APP=str(root/'performance-stutter-20261027/FX HUD隔离诊断.app')
        helper.GVPROXY=root/'goal-fx-multiplayer-20261026/gvproxy-eim'
        helper.GVPROXY_WRAPPER=root/'goal-fx-multiplayer-20261026/gvproxy-eim-wrapper'
        helper.NETWORK_DIR=helper.GVPROXY.parent
        helper.dependencies.ROOT=root
        original_identity=helper.safety.host_identity
        def native_identity(target):
            original_table=helper.safety.process_table
            children=[]
            def table(text):
                view,proof=fx_process_view(original_table(text),str(Path(target.APP)/'Contents/MacOS/steamac-vm'))
                children.extend(proof)
                return view
            helper.safety.process_table=table
            try:
                result=original_identity(target)
                result['native_fx_children']=children
                return result
            finally:helper.safety.process_table=original_table
        helper.safety.host_identity=native_identity
        original_store=helper.diagnostics.Store
        native_directory=self.data/'diagnostics'
        class NativeStore(original_store):
            def __init__(self, directory=None):
                super().__init__(native_directory if directory is None else directory)
        helper.diagnostics.Store=NativeStore
        # Reuse the Native discovery guard before the legacy capability probe executes Node.
        guard_spec=importlib.util.spec_from_file_location('native_node_guard',Path(__file__).with_name('core_adapter.py'))
        guard_adapter=importlib.util.module_from_spec(guard_spec);guard_spec.loader.exec_module(guard_adapter)
        metadata_root=Path(__file__).parent.parent/'core'
        if not metadata_root.is_dir():metadata_root=Path(__file__).parent.parent/'CoreSnapshot/native-app-core-snapshot'
        discovery=guard_adapter.load_module(metadata_root,'dependency_discovery')
        original_node=helper.dependencies.node_state
        def checked_node():
            import shutil
            candidates=[shutil.which('node'),'/opt/homebrew/bin/node','/usr/local/bin/node',str(Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node')]
            for candidate in candidates:
                if candidate and Path(candidate).is_file():
                    try:
                        if not discovery.native_node(Path(candidate).resolve()):return 'invalid'
                    except OSError:return 'unknown'
                    return original_node()
            return 'missing'
        helper.dependencies.node_state=checked_node
        helper.prefs.path=lambda:self.settings
        def credential_status(kind):
            rejected=kind.endswith('_rejected')
            role=kind.split('_')[0]
            # _remember_authenticated_password runs only after an actual password
            # challenge; an existing SSH master does not emit authentication proof.
            if role=='ssh' and not params.get('password'):return
            self.event('INFO','Credential authentication result',kind='credential_status',credential_kind=role,status='rejected' if rejected else 'authenticated')
        security.session_only(helper.prefs,credential_status)
        def session_settings():
            _,config,revision=self.read_config()
            if any(self.secret_values) and revision!=params.get('credential_revision'):raise OperationError('CREDENTIAL_SCOPE_CHANGED')
            return config
        helper.prefs.load=session_settings
        def secret(prompt):
            key='passphrase' if 'passphrase' in prompt.lower() else 'sudo_password' if 'sudo' in prompt.lower() else 'password'
            if not params.get(key):raise OperationError('AUTH_REQUIRED',{'credential_kind':key})
            return params[key]
        def connect_settings():
            helper.refresh_settings()
            helper.CLIENT.prompt_secret=secret
            helper.CLIENT.notify=lambda text:self.event('INFO',text)
        old_refresh=helper.refresh_settings
        def refresh():
            old_refresh();helper.CLIENT.prompt_secret=secret;helper.CLIENT.notify=lambda text:self.event('INFO',text)
        helper.refresh_settings=refresh
        helper.say=lambda text:self.event('INFO',text)
        def progress(stage,status='running',detail=None):
            self.event('SUCCESS' if status in ('done','passed') else 'ERROR' if status=='failed' else 'INFO',stage,stage=stage,status=status)
        helper.PROGRESS_HOOK=progress
        def confirm(kind,before,after):
            if security.Redactor(self.secret_values).contains_secret(before) or security.Redactor(self.secret_values).contains_secret(after):
                raise OperationError('SENSITIVE_CHANGE_BLOCKED')
            plan={'kind':kind,'before':before,'after':after,'target':{'runtime_root':str(root),'ssh_fingerprint':hashlib.sha256(json.dumps(helper.SETTINGS['ssh'],sort_keys=True).encode()).hexdigest(),'boot':getattr(helper.SAFETY_SESSION,'boot',None)}}
            approved=params.get('approved_changes',[])
            if not isinstance(approved,list) or plan not in approved:
                raise OperationError('CHANGE_CONFIRMATION_REQUIRED',{'change':plan})
            return True
        helper.CONFIRM_HOOK=confirm
        helper.refresh_settings()
        security.bind_session_sudo(helper,params,credential_status)
        return helper

    def run(self, method, params):
        if method not in OPERATIONS or not isinstance(params,dict):raise OperationError('INVALID_ARGUMENT')
        self.secret_values=[params.get('password',''),params.get('passphrase',''),params.get('sudo_password','')]
        allowed={'confirmed','runtime_root','password','passphrase','sudo_password','credential_revision','approved_changes','configuration','expected_revision','channel','match_result','note','values','preview_token'}
        if set(params)-allowed:raise OperationError('INVALID_ARGUMENT')
        if OPERATIONS[method][1] and params.get('confirmed') is not True:raise OperationError('CONFIRMATION_REQUIRED')
        for key in ['password','passphrase','sudo_password','note','runtime_root']:
            if key in params and (not isinstance(params[key],str) or len(params[key])>4096 or '\x00' in params[key]):raise OperationError('INVALID_ARGUMENT')
        if any(self.secret_values) and params.get('credential_revision')!=self.read_config()[2]:raise OperationError('CREDENTIAL_SCOPE_CHANGED')
        self.event('INFO',method+' started')
        if method.startswith('performance_'):
            try:
                helper=self.runtime(params)
                rules=performance_configuration.capabilities(helper.APP)
                manager=performance_configuration.Manager(performance_configuration.Preferences(),self.data/'performance-v2',performance_configuration.stopped,rules)
                if method=='performance_read':return manager.snapshot()
                restore=method in ('performance_restore','performance_restore_preview')
                if method in ('performance_preview','performance_restore_preview'):
                    return manager.preview(params.get('values'),params.get('expected_revision'),restore)
                return manager.commit(params.get('values'),params.get('expected_revision'),params.get('preview_token'),restore,
                                      emit=lambda status:self.event('INFO','Performance configuration',performance_status=status))
            except performance_configuration.ConfigurationError as error:
                raise OperationError(error.code)
        if method in ('connect_fx','inspect_guest_environment','check_fx_state','start_fx','start_steam'):
            return self.gui_operation(method,params)
        if method in ('launch_game','preflight_launch','observe_launch'):
            return self.launch_operation(method,params)
        if method=='read_configuration':
            _,config,revision=self.read_config()
            return {'configuration':config,'revision':revision,'target':str(self.settings),'credential_policy':'session_memory_only_keychain_ignored'}
        if method=='save_configuration':return self.save_config(params)
        if method=='get_legacy_catalog':
            locale=self.module('i18n')
            return {'languages':[{'code':c,'name':n} for c,n in locale.LANGUAGES],
                    'operations':[{'method':m,'scope':v[0],'confirmation':v[1],'external_effects':v[2]} for m,v in OPERATIONS.items()],
                    'help':dict(list(( (k,v) for k,v in locale.catalog('en').get('strings',{}).items() if k.startswith('help.')))[:60]),'help_scope':'bounded_summary_full_catalogs_bundled','automatic_install':False}
        if method=='check_updates':
            channel=params.get('channel','preview')
            if channel not in ('preview','stable'):raise OperationError('INVALID_ARGUMENT')
            return self.module('update_checker').check(update_channel=channel)
        if method=='read_performance':
            profile=self.module('performance_profile');hardware=self.module('apple_silicon')
            device=hardware.detect()
            device['cpu_cores']=hardware.positive_integer(hardware._read(['/usr/sbin/sysctl','-n','hw.physicalcpu']))
            device['os_version']=__import__('platform').mac_ver()[0] or 'unknown'
            current={};issues=[]
            for key in profile.SETTINGS:
                try:current[key]=profile.read_setting(key)
                except (OSError,subprocess.SubprocessError,profile.ProfileError):
                    current[key]=None;issues.append(key)
            return {'hardware':device,'current':current,'reference':dict(profile.SETTINGS),
                    'source':'performance_profile.SETTINGS','preference_domain':profile.DOMAIN,
                    'read_errors':issues,'effective':'unverified','can_apply':False,'can_restore':False,
                    'reason':'no_validated_inference_ranges_or_scoped_restore_backend'}
        if method in ('read_network_history','record_match','export_network_report'):
            diag=self.module('network_diagnostics');store=diag.Store(self.data/'diagnostics')
            history=store.directory/'history.jsonl'
            if history.is_symlink() or (history.exists() and history.stat().st_size>8*1024*1024):raise OperationError('OUTPUT_LIMIT')
            records=self.scrub(store.read()[-100:])
            if method=='read_network_history':return {'records':diag.scrub(records),'summary':diag.summarize(records)}
            if method=='export_network_report':return {'export':str(store.export(records,self.scrub(store.windows())))}
            if params.get('match_result') not in ('success','timeout','disconnect'):raise OperationError('INVALID_ARGUMENT')
            # Submission is a user's observation, never an automatically verified match.
            current={'id':uuid.uuid4().hex,'kind':'snapshot','time':diag.stamp(),'fx':None,'gvproxy':None,'steam':None,'udp_connectivity':'unverified','nat':'unknown'}
            return {'record':store.record_match(params['match_result'],current,self.scrub(params.get('note',''))),'source':'user_reported'}
        if method=='toggle_network_check':
            module=self.module('network_profile');path=module.settings_path(self.settings)
            if path.exists() and set(json.loads(path.read_text()))-set(module.DEFAULTS):raise OperationError('UNSUPPORTED_CONFIGURATION')
            module.toggle_check(path);return module.load(path)
        if method=='export_environment_report':
            self.data.mkdir(parents=True,exist_ok=True,mode=0o700)
            path=self.data/('environment-'+uuid.uuid4().hex+'.json')
            result={'time':time.time(),'scope':'host_metadata_only','runtime':'unverified','arch':__import__('platform').machine(),'python':__import__('platform').python_version()}
            fd=os.open(str(path),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
            with os.fdopen(fd,'w') as stream:json.dump(result,stream)
            return {'export':str(path),'report':result}
        if method=='inspect_network':
            module=self.module('network_profile');return {'host':module.inspect(),'conditions':module.success_conditions(),'guest':'unverified','multiplayer':'unverified'}
        if method=='test_network':
            diag=self.module('network_diagnostics');return diag.network_test(uuid.uuid4().hex)
        if method in ('apply_network_profile','restore_network_profile'):
            module=self.module('network_profile');path=module.settings_path(self.settings)
            if path.exists() and set(json.loads(path.read_text()))-set(module.DEFAULTS):raise OperationError('UNSUPPORTED_CONFIGURATION')
            if method=='apply_network_profile':
                before=module.inspect()
                plan={'kind':'host_wifi','before':before,'after':{'disable_wifi':[x['device'] for x in before['wifi'] if x['on']]}}
                if plan not in params.get('approved_changes',[]):raise OperationError('CHANGE_CONFIRMATION_REQUIRED',{'change':plan})
                original_inspect=module.inspect
                first=[True]
                def guarded_inspect():
                    value=original_inspect()
                    if first[0] and value!=before:raise OperationError('CONFIG_CHANGED')
                    first[0]=False
                    return value
                module.inspect=guarded_inspect
            try:
                value=module.apply(path) if method=='apply_network_profile' else module.restore(path)
            except BaseException:
                if method=='apply_network_profile':
                    try:module.restore(path)
                    except Exception:self.event('ERROR','Network rollback incomplete; use the recorded recovery profile')
                raise
            return {'result':value,'profile':module.load(path)}
        helper=self.runtime(params)
        if method=='inspect_legacy_runtime':
            result=helper.dependencies.inspect_runtime(helper)
            result.update(runtime_path=helper.APP,gvproxy_path=str(helper.GVPROXY),guest='unverified',eac='unverified',multiplayer='unverified')
            return result
        if method=='test_guest_sudo':
            self.check_fx_entry(helper,require_running=True)
            helper.CLIENT.connect_once()
            helper.safety.Session(helper).bind()  # Bind the configured FX/Guest, never an arbitrary SSH host.
            probe=helper.subprocess.run(helper.SSH+['sudo -n -v'],capture_output=True,text=True,timeout=15)
            if probe.returncode==0:return {'sudo':'available_without_password_prompt','password_verified':False,'configuration_changed':False}
            value=params.get('sudo_password')
            if not value:raise OperationError('AUTH_REQUIRED',{'credential_kind':'sudo_password'})
            marker='[HD2_NATIVE_SUDO_AUTH]'
            result=helper.subprocess.run(helper.SSH+['sudo -S -p "'+marker+'" -v'],input=value+'\n',capture_output=True,text=True,timeout=20)
            if result.returncode:raise OperationError('SUDO_AUTH_FAILED')
            verified=marker in (result.stderr or '')
            if verified:self.event('INFO','Credential authentication result',kind='credential_status',credential_kind='sudo',status='authenticated')
            return {'sudo':'authenticated','password_verified':verified,'configuration_changed':False}
        if method in ('test_ssh','inspect_guest','save_network_snapshot'):
            if method=='test_ssh':
                test=helper.prefs.SSHClient(helper.prefs.load(),test=True)
                test.prompt_secret=helper.CLIENT.prompt_secret;test.notify=helper.CLIENT.notify
                try:test.test_connection()
                except helper.prefs.AuthenticationError as error:
                    if str(error).startswith('SSH authentication failed.'):raise OperationError('SSH_AUTH_FAILED') from None
                    raise
                return {'ssh':'authenticated','guest_python':'checked','game':'unverified','eac':'unverified','multiplayer':'unverified'}
            try:helper.CLIENT.connect_once()
            except helper.prefs.AuthenticationError as error:
                if str(error).startswith('SSH authentication failed.'):raise OperationError('SSH_AUTH_FAILED') from None
                raise
            records=self.module('network_records')
            if method=='inspect_guest':return self.scrub(records.guest_snapshot(helper))
            value=records.capture(helper,self.module('network_profile'));path=records.save(value,self.settings)
            return {'saved':str(path),'snapshot':self.scrub(value)}
        if method=='apply_performance':
            profile=self.module('performance_profile');catalog=self.module('performance_catalog')
            device=self.module('apple_silicon').detect()
            if not any(catalog.can_apply(row,device,profile) for row in catalog.PROFILES):raise OperationError('PROFILE_NOT_APPLICABLE')
            before={k:profile.read_setting(k) for k in profile.SETTINGS}
            plan={'kind':'fx_performance_preferences','before':before,'after':profile.SETTINGS}
            if plan not in params.get('approved_changes',[]):raise OperationError('CHANGE_CONFIRMATION_REQUIRED',{'change':plan})
            return self.scrub(self.apply_performance(profile,helper,before))
        raise OperationError('NOT_IMPLEMENTED')

    def launch_operation(self, method, params):
        stages={'fx':'StartingFX','ssh':'WaitingForGuest','environment':'CheckingCompatibility',
                'steam':'StartingSteam','game':'LaunchingGame','eac':'CheckingEAC'}
        self.launch_stage='CheckingEnvironment'
        sequence=[0]
        def progress(stage,status='running',detail=None):
            mapped=stages.get(stage,stage)
            if stage=='game' and status in ('done','passed'):mapped='GameProcessDetected'
            if stage=='fx' and status in ('done','passed'):
                # A listening SSH port is not proof that the selected FX entry ran.
                self.launch_stage='CheckingFXEntry'
                self.check_fx_entry(helper,require_running=True)
            self.launch_stage=mapped
            sequence[0]+=1
            self.event('ERROR' if status=='failed' else 'INFO',mapped,stage=mapped,status=status,sequence=sequence[0])
        try:
            progress('CheckingEnvironment')
            helper=self.runtime(params)
            self.read_config()  # Reject malformed settings instead of legacy fallback to defaults.
            info=Path(helper.APP)/'Contents/Info.plist'
            version=plistlib.loads(info.read_bytes()).get('CFBundleShortVersionString') if info.is_file() else None
            self.event('INFO','Selected FX launch target',kind='launch_context',fx_path=helper.APP,fx_version=version or 'unknown')
            progress('CheckingFXEntry')
            self.check_fx_entry(helper)
            progress('CheckingFXEntry','done')
            if method=='observe_launch':
                progress('WaitingForGuest')
                helper.safety.Session(helper).bind()  # Read-only target identity, not merely a reachable port.
                current=helper.state()  # BatchMode only; never starts a new master or writes Guest configuration.
                detected=bool(current.get('game_pids'))
                progress('GameProcessDetected' if detected else 'WaitingForGame','done' if detected else 'unverified')
                return {'game_process_detected':detected,'game_process_count':len(current.get('game_pids',[])),
                        'steam_process_count':len(current.get('steam_pids',[])),
                        'main_menu':'unverified','single_player':'unverified','eac':'unverified','multiplayer':'unverified'}
            report=helper.dependencies.inspect_runtime(helper)
            problems=helper.dependencies.launcher_problems()
            if problems:raise OperationError('LAUNCHER_FILES_MISSING',{'files':problems})
            for row in report['items']:
                if row['state'] in ('ready','unverified'):continue
                code={'fx':'FX_UNAVAILABLE','gvproxy':'GVPROXY_UNAVAILABLE','node':'NODE_UNAVAILABLE','ssh':'SSH_UNAVAILABLE','bridge':'SOURCE_MISMATCH'}.get(row['id'],'ENVIRONMENT_CHECK_FAILED')
                raise OperationError(code,{'component':row['id'],'state':row['state']})
            if not report['ready']:raise OperationError('ENVIRONMENT_CHECK_FAILED')
            try:helper.verify_fx_profile()
            except RuntimeError as error:raise OperationError('FX_PROFILE_MISMATCH',{'summary':self.scrub(str(error))}) from None
            progress('CheckingEnvironment','done')
            if method=='preflight_launch':
                return {'host_ready':True,'items':report['items'],'fx_version':version,'fx_path':helper.APP,
                        'guest':'unverified','main_menu':'unverified','single_player':'unverified','eac':'unverified','multiplayer':'unverified'}
            helper.PROGRESS_HOOK=progress
            original_state=helper.state
            def checked_state():
                current=original_state()
                if current.get('verified_network') is not True:
                    self.launch_stage='CheckingFXEntry'
                    self.check_fx_entry(helper,require_running=True)
                    raise OperationError('FX_ENTRY_MISMATCH',{'stage':'CheckingFXEntry','source':'legacy state().verified_network','reason':'legacy_transport_readiness_not_verified','action':'inspect_entry_and_relaunch_normally'})
                return current
            helper.state=checked_state
            original_wait=helper.wait_for_game
            def wait_for_game():
                progress('WaitingForGame')
                original_wait()
                progress('GameProcessDetected','done')
            helper.wait_for_game=wait_for_game
            # Multiplayer probes are outside Phase 2. Keep original EAC requirements intact.
            helper.run_post_launch_checks=lambda:self.event('INFO','Optional multiplayer probes not requested',stage='Multiplayer',status='not_requested')
            helper.main()
            current=helper.state()
            if not current.get('game_pids'):raise OperationError('GAME_EXITED',{'summary':'No game process remains at final observation'})
            progress('GameProcessDetected','done')
            return {'game_process_detected':True,'game_process_count':len(current['game_pids']),
                    'steam_process_count':len(current.get('steam_pids',[])),
                    'main_menu':'unverified','single_player':'unverified','multiplayer':'not_requested',
                    'eac':'see_separate_stage_evidence'}
        except OperationError as error:
            error.details.setdefault('stage',self.launch_stage)
            self.event('ERROR',error.code,stage=self.launch_stage,status='failed')
            raise
        except Exception as error:
            code={'CheckingEnvironment':'ENVIRONMENT_CHECK_FAILED','StartingFX':'FX_START_FAILED',
                  'WaitingForGuest':'SSH_CONNECTION_FAILED','CheckingCompatibility':'COMPATIBILITY_CHECK_FAILED',
                  'StartingSteam':'STEAM_START_FAILED','LaunchingGame':'GAME_START_FAILED',
                  'WaitingForGame':'GAME_START_FAILED','GameProcessDetected':'GAME_EXITED','CheckingEAC':'EAC_CHECK_FAILED'}.get(self.launch_stage,'LAUNCH_FAILED')
            # The preserved Core distinguishes refusal before any Guest mutation.
            # Do not misreport a rejected sudo credential as component incompatibility.
            if isinstance(error,getattr(getattr(locals().get('helper'),'safety',None),'NotWrittenError',())):
                code='SUDO_AUTH_FAILED'
            if isinstance(error,getattr(getattr(locals().get('helper'),'prefs',None),'AuthenticationError',())) and str(error).startswith('SSH authentication failed.'):
                code='SSH_AUTH_FAILED'
            if isinstance(error,security.GuestTransactionFailure):code='GUEST_TRANSACTION_FAILED'
            if type(error).__name__=='Deadline' or isinstance(error,subprocess.TimeoutExpired):code='TIMEOUT'
            details={'stage':self.launch_stage,'summary':self.scrub(str(error))}
            if isinstance(error,subprocess.CalledProcessError):
                details['exit_code']=error.returncode
                if error.stderr:
                    text=error.stderr.decode('utf-8',errors='replace') if isinstance(error.stderr,bytes) else error.stderr
                    details['stderr']=self.scrub(text)
            self.event('ERROR',code,stage=self.launch_stage,status='failed')
            raise OperationError(code,details) from None

    def fx_host_state(self,helper):
        self.check_fx_entry(helper)
        rows=helper.safety.process_table(helper.safety.output(['ps','-ww','-axo','pid=,ppid=,lstart=,comm=']))
        executable=str(Path(helper.APP)/'Contents/MacOS/steamac-vm')
        selected=[pid for pid,row in rows.items() if row[2]==executable]
        if selected:fx_process_view(rows,executable)
        info=Path(helper.APP)/'Contents/Info.plist'
        version=plistlib.loads(info.read_bytes()).get('CFBundleShortVersionString','unknown') if info.is_file() else 'unknown'
        return {'fx_host_running':bool(selected),'fx_process_count':len(selected),'fx_path':helper.APP,'fx_version':version,'transport_verified':bool(selected) and helper.network_ready(),
                'guest':'unverified','ssh_connected':False,'main_menu':'unverified','eac':'unverified','multiplayer':'unverified'}

    def gui_operation(self,method,params):
        stage='CheckingFXEntry'
        try:
            helper=self.runtime(params)
            if not helper.prefs.local_host(helper.SETTINGS['ssh']['host']):raise OperationError('LOCAL_FX_REQUIRED')
            host=self.fx_host_state(helper)
            if method=='check_fx_state':return host
            if method=='start_fx':
                with helper.safety.target_lock(helper.SETTINGS):
                    host=self.fx_host_state(helper)
                    helper.verify_fx_profile()
                    if host['fx_host_running']:
                        self.check_fx_entry(helper,require_running=True)
                        return dict(host,already_running=True)
                    report=helper.dependencies.inspect_runtime(helper)
                    if not report['ready']:raise OperationError('ENVIRONMENT_CHECK_FAILED')
                    stage='StartingFX'
                    # Same verified entry/wrapper and arguments as archived start-hd2.py.
                    helper.subprocess.run(['open',helper.APP,'--args','--no-wmtr','--vulkan-driver','kosmickrisp','--gvproxy',str(helper.GVPROXY_WRAPPER),'--ssh-port',str(helper.SETTINGS['ssh']['port']),'--cpus','8','--mem','8192','--cmdline','console=hvc0 loglevel=4 rootwait steamac.gpu_mib=6144','--perf-stats'],check=True,timeout=15)
                    deadline=time.monotonic()+30
                    while time.monotonic()<deadline:
                        current=self.fx_host_state(helper)
                        if current['fx_host_running'] and helper.network_ready():
                            self.check_fx_entry(helper,require_running=True)
                            return dict(current,already_running=False)
                        time.sleep(.25)
                    raise OperationError('TIMEOUT',{'stage':stage})
            if not host['fx_host_running']:raise OperationError('FX_NOT_RUNNING')
            self.check_fx_entry(helper,require_running=True)
            stage='WaitingForGuest'
            helper.connect()
            session=helper.safety.Session(helper)
            plan=session.bind()  # Original host/listener/SSH-peer/Guest-boot identity guard.
            connected=dict(host,ssh_connected=True,guest_ready=True,guest_service=plan['service'])
            if method=='connect_fx':return connected
            if method=='start_steam':
                stage='StartingSteam'
                with helper.safety.target_lock(helper.SETTINGS):
                    session.verify()
                    result=session.steam()  # Original idle/managed-service check, one controlled start.
                    final=session.verify()
                    if final['service']!='running':raise OperationError('STEAM_START_FAILED')
                    return dict(connected,steam_running=True,steam_started=bool(result.get('started')))
            stage='ReadingGuest'
            facts=json.loads(helper.remote(GUEST_ENVIRONMENT_READ,timeout=25))
            session.verify()  # Do not publish a snapshot after target/boot replacement.
            facts.update(connected)
            return facts
        except OperationError as error:
            error.details.setdefault('stage',stage)
            raise
        except Exception as error:
            code='TIMEOUT' if type(error).__name__=='Deadline' or isinstance(error,subprocess.TimeoutExpired) else 'GUEST_INSPECTION_FAILED' if stage=='ReadingGuest' else 'STEAM_START_FAILED' if stage=='StartingSteam' else 'FX_START_FAILED' if stage=='StartingFX' else 'SSH_CONNECTION_FAILED'
            if isinstance(error,getattr(getattr(locals().get('helper'),'prefs',None),'AuthenticationError',())) and str(error).startswith('SSH authentication failed.'):code='SSH_AUTH_FAILED'
            raise OperationError(code,{'stage':stage,'summary':self.scrub(str(error))}) from None

    def check_fx_entry(self, helper, require_running=False):
        rows=helper.safety.process_table(helper.safety.output(['ps','-ww','-axo','pid=,ppid=,lstart=,comm=']))
        executable=str(Path(helper.APP)/'Contents/MacOS/steamac-vm')
        active={pid:row for pid,row in rows.items() if Path(row[2]).name=='steamac-vm'}
        foreign=[row[2] for row in active.values() if row[2]!=executable]
        if foreign:
            names=sorted({next((p.name for p in Path(value).parents if p.suffix=='.app'),'unknown FX') for value in foreign})
            raise OperationError('FX_INSTANCE_MISMATCH',{'stage':'CheckingFXEntry','running_apps':names,'reason':'different_fx_copy','action':'quit_other_fx_normally_then_retry'})
        if require_running:
            selected={pid:row for pid,row in active.items() if row[2]==executable}
            if not selected:raise OperationError('FX_INSTANCE_MISMATCH',{'stage':'CheckingFXEntry','reason':'selected_fx_process_not_observed','action':'inspect_fx_window_then_retry'})
            fx_process_view(rows,executable)
            if not helper.network_ready():
                raise OperationError('FX_ENTRY_MISMATCH',{'stage':'CheckingFXEntry','source':'legacy network_ready() on host','reason':'expected_gvproxy_not_verified','action':'quit_selected_fx_normally_then_relaunch_from_native'})

    def apply_performance(self, profile, helper, before):
        # The archive handles ordinary preference failures. Extend recovery to
        # cancellation/timeouts, without overwriting an intervening foreign value.
        attempted=[]
        original_write=profile.write_setting
        def tracked(key,value):
            attempted.append(key)
            return original_write(key,value)
        profile.write_setting=tracked
        try:
            return profile.apply(helper)
        except BaseException:
            for key in reversed(list(dict.fromkeys(attempted))):
                try:
                    current=profile.read_setting(key)
                    if current==profile.SETTINGS[key] and current!=before[key]:
                        original_write(key,before[key])
                    elif current!=before[key]:
                        self.event('ERROR','Preference changed concurrently; recovery requires review: '+key)
                except Exception:
                    self.event('ERROR','Preference recovery incomplete: '+key)
            self.event('ERROR','Operation interrupted; recheck FX/Guest state and the original recovery receipt')
            raise
        finally:
            profile.write_setting=original_write
