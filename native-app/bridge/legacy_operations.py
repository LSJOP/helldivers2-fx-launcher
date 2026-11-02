"""Explicit Native operations over pinned legacy Core; no import-time system changes."""
import contextlib
import copy
import fcntl
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import signal
import stat
import sys
import tempfile
import time
import uuid

class OperationError(Exception):
    def __init__(self, code, details=None):
        self.code, self.details = code, details or {}
        super().__init__(code)

OPERATIONS = {
    'read_configuration': ('settings', False, False),
    'save_configuration': ('settings', True, False),
    'inspect_legacy_runtime': ('fx', False, True),
    'inspect_network': ('environment', False, True),
    'test_network': ('environment', False, True),
    'test_ssh': ('environment', True, True),
    'inspect_guest': ('environment', True, True),
    'launch_game': ('dashboard', True, True),
    'apply_performance': ('settings', True, True),
    'read_performance': ('settings', False, False),
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

class Operations:
    def __init__(self, root, emit=None, settings_file=None, data_dir=None):
        self.root = Path(root)
        self.emit = emit or (lambda event: None)
        self.settings = Path(settings_file) if settings_file else Path.home()/'Library/Application Support/Helldivers2FXLauncher/settings.json'
        self.data = Path(data_dir) if data_dir else Path.home()/'Library/Application Support/Helldivers2FXLauncher/native'
        self.modules = {}
        self.secret_values = []

    def module(self, name):
        if name not in ('preferences','dependencies','network_profile','network_diagnostics','network_records','performance_profile','performance_catalog','update_checker','i18n','launcher_version','apple_silicon'):
            raise OperationError('INVALID_ARGUMENT')
        if name not in self.modules:
            path = self.root/'launcher-20261026'/(name+'.py')
            spec = importlib.util.spec_from_file_location('native_legacy_'+name, path)
            value = importlib.util.module_from_spec(spec); spec.loader.exec_module(value)
            self.modules[name] = value
        return self.modules[name]

    def scrub(self, value):
        if isinstance(value, dict): return {k:self.scrub(v) for k,v in value.items() if not re.search(r'password|passphrase|token|secret',k,re.I)}
        if isinstance(value, (list,tuple)): return [self.scrub(x) for x in value[:200]]
        if isinstance(value,Path): return str(value)
        if not isinstance(value,str): return value
        for secret in self.secret_values:
            if secret:value=value.replace(secret,'[REDACTED]')
        value=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',value)
        value=re.sub(r'(?i)(password|passphrase|token|authorization)\s*[:=]\s*\S+',r'\1=[REDACTED]',value)
        value=re.sub(r'/Users/[^/\s]+', '~/…', value)
        value=re.sub(r'(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])','[IP]',value)
        return value[:4000]

    def event(self, level, message, **extra):
        self.emit(dict(level=level, message=self.scrub(message), **extra))

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
        self.secret_values=[params.get('password',''),params.get('passphrase',''),params.get('sudo_password','')]
        def secret(prompt):
            key='passphrase' if 'passphrase' in prompt.lower() else 'sudo_password' if 'sudo' in prompt.lower() else 'password'
            if not params.get(key):raise OperationError('AUTH_REQUIRED')
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
            plan={'kind':kind,'before':before,'after':after,'target':{'runtime_root':str(root),'ssh_fingerprint':hashlib.sha256(json.dumps(helper.SETTINGS['ssh'],sort_keys=True).encode()).hexdigest(),'boot':getattr(helper.SAFETY_SESSION,'boot',None)}}
            approved=params.get('approved_changes',[])
            if not isinstance(approved,list) or plan not in approved:
                raise OperationError('CHANGE_CONFIRMATION_REQUIRED',{'change':plan})
            return True
        helper.CONFIRM_HOOK=confirm
        helper.refresh_settings()
        return helper

    def run(self, method, params):
        if method not in OPERATIONS or not isinstance(params,dict):raise OperationError('INVALID_ARGUMENT')
        allowed={'confirmed','runtime_root','password','passphrase','sudo_password','approved_changes','configuration','expected_revision','channel','match_result','note'}
        if set(params)-allowed:raise OperationError('INVALID_ARGUMENT')
        if OPERATIONS[method][1] and params.get('confirmed') is not True:raise OperationError('CONFIRMATION_REQUIRED')
        for key in ['password','passphrase','sudo_password','note','runtime_root']:
            if key in params and (not isinstance(params[key],str) or len(params[key])>4096 or '\x00' in params[key]):raise OperationError('INVALID_ARGUMENT')
        self.event('INFO',method+' started')
        if method=='read_configuration':
            _,config,revision=self.read_config()
            return {'configuration':config,'revision':revision,'target':str(self.settings)}
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
            profile=self.module('performance_profile');catalog=self.module('performance_catalog')
            return {'current':{k:profile.read_setting(k) for k in profile.SETTINGS},'profiles':getattr(catalog,'PROFILES',[]),'effective':'unverified'}
        if method in ('read_network_history','record_match','export_network_report'):
            diag=self.module('network_diagnostics');store=diag.Store(self.data/'diagnostics')
            history=store.directory/'history.jsonl'
            if history.is_symlink() or (history.exists() and history.stat().st_size>8*1024*1024):raise OperationError('OUTPUT_LIMIT')
            records=store.read()[-100:]
            if method=='read_network_history':return {'records':diag.scrub(records),'summary':diag.summarize(records)}
            if method=='export_network_report':return {'export':str(store.export(records,store.windows()))}
            if params.get('match_result') not in ('success','timeout','disconnect'):raise OperationError('INVALID_ARGUMENT')
            # Submission is a user's observation, never an automatically verified match.
            current={'id':uuid.uuid4().hex,'kind':'snapshot','time':diag.stamp(),'fx':None,'gvproxy':None,'steam':None,'udp_connectivity':'unverified','nat':'unknown'}
            return {'record':store.record_match(params['match_result'],current,params.get('note','')),'source':'user_reported'}
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
        if method in ('test_ssh','inspect_guest','save_network_snapshot'):
            if method=='test_ssh':
                test=helper.prefs.SSHClient(helper.prefs.load(),test=True)
                test.prompt_secret=helper.CLIENT.prompt_secret;test.notify=helper.CLIENT.notify
                test.test_connection()
                return {'ssh':'authenticated','guest_python':'checked','game':'unverified','eac':'unverified','multiplayer':'unverified'}
            helper.CLIENT.connect_once()
            records=self.module('network_records')
            if method=='inspect_guest':return self.scrub(records.guest_snapshot(helper))
            value=records.capture(helper,self.module('network_profile'));path=records.save(value,self.settings)
            return {'saved':str(path),'snapshot':self.scrub(value)}
        if method=='launch_game':
            helper.main();return {'operation':'completed','game':'see_stage_evidence','eac':'see_stage_evidence','multiplayer':'unverified'}
        if method=='apply_performance':
            profile=self.module('performance_profile');catalog=self.module('performance_catalog')
            device=self.module('apple_silicon').detect()
            if not any(catalog.can_apply(row,device,profile) for row in catalog.PROFILES):raise OperationError('PROFILE_NOT_APPLICABLE')
            before={k:profile.read_setting(k) for k in profile.SETTINGS}
            plan={'kind':'fx_performance_preferences','before':before,'after':profile.SETTINGS}
            if plan not in params.get('approved_changes',[]):raise OperationError('CHANGE_CONFIRMATION_REQUIRED',{'change':plan})
            return self.scrub(self.apply_performance(profile,helper,before))
        raise OperationError('NOT_IMPLEMENTED')

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
