"""Read-only Level 1 setup checks and stateless UI 2.1 installation guidance.

Never connects to Guest, reads credentials, installs software or saves settings.
Only explicit report export creates a new private file; existing files are refused.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent.parent


def _module(name):
    spec = importlib.util.spec_from_file_location('hd2_setup_'+name, Path(__file__).with_name(name+'.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


dependencies = _module('dependencies')
hardware = _module('apple_silicon')
version = _module('launcher_version')
i18n = _module('i18n')
discovery = _module('dependency_discovery')
IDS = ('platform','python','source','node','ssh','ssh_config','fx','gvproxy',
       'fex','proton','guest_tools','steam','game')
STATES = ('ready','installed_unverified','missing','version_mismatch','detection_failed','not_applicable','unverified')
GUEST_IDS = ('fex','proton','guest_tools','steam','game')
TOPICS = ('base','fx','fex','proton','network','steam','ssh','verify','report')
METHODS = dict(platform='native macOS/platform and sysctl',python='current Python version',
    source='required source readability and syntax',node='local check_node.cjs (no requests)',
    ssh='executable lookup only',ssh_config='settings schema only; no credentials',
    fx='bounded file/version/hash discovery; runtime path unchanged',gvproxy='bounded file/hash/wrapper discovery; runtime path unchanged',
    **{key:'not inspected: requires Guest' for key in GUEST_IDS})
REASONS = ('supported_host','host_unverified','python_version','source_complete','source_incomplete',
    'node_capabilities','node_version','node_probe_failed','tool_absent','tool_present','permission',
    'settings_valid','settings_unconfigured','settings_invalid','expected_path_missing',
    'hash_or_permission_mismatch','file_check_failed','hash_matches_runtime_unverified','needs_guest','candidate_found')


def settings_path():
    return _module('preferences').path()


def _version(value):
    return value if isinstance(value,str) and re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,3}(?:[-+][0-9A-Za-z.-]+)?',value) else None


def node_details(root, session=None):
    selected=(session or discovery.Session(root)).scan('node')['selected']
    state=selected['state']
    mapping={'ready':('ready','node_capabilities'),'path_missing':('missing','tool_absent'),
             'version_mismatch':('version_mismatch','node_version'),'probe_failed':('detection_failed','node_probe_failed'),
             'unusable':('installed_unverified','permission'),'found_unverified':('installed_unverified','candidate_found')}
    result,reason=mapping.get(state,('detection_failed','node_probe_failed'))
    return result,selected.get('version'),reason


def collect(root=None, settings_file=None, discovery_session=None):
    """No network/SSH/process startup. Installed files do not imply runtime success."""
    root = Path(root) if root is not None else ROOT
    setting = Path(settings_file) if settings_file is not None else settings_path()
    device = hardware.detect()
    session = discovery_session or discovery.Session(root)
    rows = []
    def add(key,state,reason,observed=None):
        rows.append(dict(id=key,state=state,reason=reason,version=observed,method=METHODS[key]))
    supported = sys.platform == 'darwin' and platform.machine() == 'arm64'
    add('platform','ready' if supported else 'not_applicable','supported_host' if supported else 'host_unverified')
    add('python','ready' if sys.version_info >= (3,9) else 'version_mismatch','python_version',platform.python_version())
    problems = dependencies.launcher_problems(root)
    for name in ('VERSION','Start.command','启动绝地潜兵2.command','tools/check_node.cjs','tools/check_dependencies.py','launcher-20261026/steam-cdp.mjs'):
        try:
            content = (root/name).read_text(encoding='utf-8')
            if not content.strip() or (name=='VERSION' and not version.valid_version(content.strip())):raise ValueError('Invalid source file')
        except (OSError,ValueError,UnicodeError):problems.append(name)
    add('source','missing' if problems else 'ready','source_incomplete' if problems else 'source_complete')
    state,observed,reason = node_details(root,session)
    if 'node' not in session.results:
        # Preserve the row when a caller supplies a capability adapter.
        summary_state={'ready':'ready','missing':'path_missing','version_mismatch':'version_mismatch','installed_unverified':'found_unverified'}.get(state,'probe_failed')
        session.results['node']={'items':[],'selected':{'state':summary_state}}
    add('node',state,reason,observed)
    ssh = shutil.which('ssh')
    add('ssh','installed_unverified' if ssh else 'missing','tool_present' if ssh else 'tool_absent')
    try:
        if not setting.exists():add('ssh_config','unverified','settings_unconfigured')
        else:
            # Validation returns a filtered object, which is NEVER written back.
            prefs = _module('preferences')
            data = prefs.validate(json.loads(setting.read_text(encoding='utf-8')))
            configured = data['ssh_configured']
            add('ssh_config','installed_unverified' if configured else 'unverified',
                'settings_valid' if configured else 'settings_unconfigured')
    except (OSError,ValueError,KeyError,TypeError,UnicodeError):add('ssh_config','detection_failed','settings_invalid')
    for key in ('fx','gvproxy'):
        selected=session.scan(key)['selected'];state=selected['state']
        if state=='ready':add(key,'installed_unverified','hash_matches_runtime_unverified',selected.get('version'))
        elif state=='path_missing':add(key,'missing','expected_path_missing')
        elif state=='probe_failed':add(key,'detection_failed','file_check_failed')
        elif state in ('hash_mismatch','version_mismatch','unusable'):add(key,'installed_unverified','hash_or_permission_mismatch',selected.get('version'))
        else:add(key,'installed_unverified','candidate_found',selected.get('version'))
    for key in GUEST_IDS:add(key,'unverified','needs_guest')
    try:
        release = (root/'VERSION').read_text(encoding='utf-8').strip()
        release = release if version.valid_version(release) else None
    except (OSError,UnicodeError):release = None
    data = dict(schema=1,level=1,launcher_version=release,
                checked_at=time.strftime('%Y-%m-%d %H:%M:%S %z'),
                device=dict(macos=platform.mac_ver()[0],architecture=platform.machine(),**device),items=rows,
                discovery=discovery.public_summary(session.results))
    return safe_report(data)


REPORT_STEPS = {
    'candidate_found':'Locate and inspect existing candidates. Discovery never changes the runtime path; do not reinstall or replace a working environment.',
    'supported_host':'Continue local checks; macOS minimum remains unverified.',
    'host_unverified':'Use native Apple Silicon macOS; do not change the existing OS for a check.',
    'python_version':'Use the shared Python 3.9+ tool helper/path rules if this interpreter is unsuitable.',
    'source_complete':'Preserve this source tree and custom edits; readiness is not signed integrity.',
    'source_incomplete':'Extract a complete separate source copy; keep custom edits and user data.',
    'node_capabilities':'Skip installation; no network functionality was exercised.',
    'node_version':'Inspect the selected Node path and capabilities before consented tool preparation.',
    'node_probe_failed':'Review tool/probe availability; do not repeatedly reinstall.',
    'tool_absent':'Review official tool guidance in docs/DEPENDENCIES.md.',
    'tool_present':'Skip installation. Connection and identity need separate explicit validation.',
    'permission':'File exists; inspect permissions manually without automatic replacement.',
    'settings_valid':'Preserve all settings. Confirm target identity separately before any connection.',
    'settings_unconfigured':'Configure SSH explicitly in menu 8 only when ready for Guest access.',
    'settings_invalid':'Preserve the original file and unknown fields; do not reset settings.',
    'expected_path_missing':'Check the documented location and existing installations; do not reinstall automatically.',
    'hash_or_permission_mismatch':'Keep existing files. Confirm the exact matching build/provenance with the maintainer.',
    'file_check_failed':'Leave files unchanged and review local readability and component provenance.',
    'hash_matches_runtime_unverified':'Skip installation. Version and actual runtime still need separate verification.',
    'needs_guest':'Requires Guest evidence. Only choose explicit Level 2 when ready; Level 3 remains original menu 1.',
}


def safe_report(data):
    """Positive field/value allowlist, never redact-and-dump raw probe/settings data."""
    device = data.get('device',{})
    def integer(key):
        value=device.get(key)
        return value if type(value) is int and value>0 else None
    rows = []
    for item in data.get('items',[]):
        key = item.get('id')
        if key not in IDS:continue
        rows.append(dict(id=key,state=item.get('state') if item.get('state') in STATES else 'detection_failed',
            reason=item.get('reason') if item.get('reason') in REASONS else 'file_check_failed',
            version=_version(item.get('version')),method=METHODS[key],
            guide='docs/SETUP.md',recommendation=REPORT_STEPS[item.get('reason') if item.get('reason') in REASONS else 'file_check_failed']))
    stamp = data.get('checked_at','')
    result = dict(schema=1,level=1,launcher_version=_version(data.get('launcher_version')),
        checked_at=stamp if isinstance(stamp,str) and re.fullmatch(r'\d{4}-\d\d-\d\d \d\d:\d\d:\d\d [+-]\d{4}',stamp) else None,
        device=dict(macos=_version(device.get('macos')),architecture=device.get('architecture') if device.get('architecture') in ('arm64','aarch64','x86_64') else None,
            chip=hardware.chip_name(device.get('chip')),memory_bytes=integer('memory_bytes'),gpu_cores=integer('gpu_cores')),
        items=rows)
    if isinstance(data.get('discovery'),dict):result['discovery']=discovery.public_summary(data['discovery'])
    result['missing']=[r['id'] for r in rows if r['state']=='missing']
    result['pending']=[r['id'] for r in rows if r['state'] in ('installed_unverified','unverified','detection_failed','version_mismatch','not_applicable')]
    return result


def export_report(data, directory=None):
    """Write a new 0600 report only on explicit request. Do not copy user files."""
    directory = Path(directory) if directory is not None else settings_path().parent/'reports'/'installation'
    directory.mkdir(parents=True,exist_ok=True,mode=0o700)
    target = directory/('installation-'+str(time.time_ns())+'.json')
    flags = os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0)
    fd = os.open(target,flags,0o600)
    with os.fdopen(fd,'w',encoding='utf-8') as stream:
        json.dump(safe_report(data),stream,ensure_ascii=False,indent=2)
        stream.write('\n')
    return target


class SetupCenter:
    def __init__(self,context):
        self.c=context
        self.session=discovery.Session(context.root)
        self.data=collect(context.root,context.settings_file,self.session)
        self.selected='1'

    def t(self,key,**values):return self.c.i18n.text('setup.'+key,self.c.language,**values)

    def rows(self):
        result=[]
        device=self.data['device']
        result.append(('info:device',self.t('device',chip=device['chip'] or self.t('unknown'),
            os=device['macos'] or self.t('unknown'),memory=(str(round(device['memory_bytes']/1024**3,1))+' GiB') if device['memory_bytes'] else self.t('unknown'))))
        result.append(('info:stateless',self.t('stateless')))
        # Keep all five actions visible even at 80x24; full evidence is in Verify.
        for section,keys in (('launcher',('python',)),('tools',('node',)),('runtime',('fx','gvproxy'))):
            result.append(('i:'+section,self.t(section)))
            for item in self.data['items']:
                if item['id'] in keys:
                    entry=self.data.get('discovery',{}).get(item['id'])
                    if entry:
                        state=entry['state'];role=self.discovery_role(state)
                        label=self.t('discovery.state.'+state)
                        selected=self.session.results.get(item['id'],{}).get('selected',{})
                        if selected.get('reason')=='runtime_differs':label=self.t('discovery.runtime_mismatch')
                    else:
                        role=('success:' if item['state']=='ready' else 'warning:' if item['state'] in ('missing','version_mismatch','detection_failed') else 'i:')
                        label=self.t('state.'+item['state'])
                    result.append((role+item['id'],self.t('name.'+item['id'])+': '+label+(' · '+item['version'] if item['version'] else '')))
        result.append(('i:guest',self.t('guest.pending')))
        return result+[(str(i),'['+str(i)+'] '+self.t('action.'+str(i))) for i in range(1,6)]+[('0','[0] '+self.t('back'))]

    def verify(self):
        parts=[self.t('level1'),self.t('stateless')]
        for item in self.data['items']:
            parts.append('\n'+self.t('name.'+item['id'])+': '+self.t('state.'+item['state']))
            parts.append(self.t('reason.'+item['reason']))
        self.c.ui2.show_text(self.t('title'),'\n'.join(parts),self.c.language)

    def guide(self):
        selected='1'
        while True:
            rows=[(str(i),'['+str(i)+'] '+self.t(topic+'.title')) for i,topic in enumerate(TOPICS,1)]+[('0','[0] '+self.t('back'))]
            choice=self.c.choose(self.t('guide'),rows,default=selected)
            if choice=='0':return
            if choice not in [str(i) for i in range(1,10)]:continue
            selected=choice;topic=TOPICS[int(choice)-1]
            if topic=='verify':self.data=collect(self.c.root,self.c.settings_file,self.session);self.verify()
            elif topic=='report':self.report()
            else:
                evidence=[]
                related={'base':('python','source','node'),'fx':('fx',),'fex':('fex',),'proton':('proton',),
                         'network':('gvproxy',),'steam':('guest_tools','steam','game'),'ssh':('ssh','ssh_config')}[topic]
                for item in self.data['items']:
                    if item['id'] in related:
                        evidence.append(self.t('name.'+item['id'])+': '+self.t('state.'+item['state'])+'\n'+self.t('reason.'+item['reason']))
                self.c.ui2.show_text(self.t(topic+'.title'),'\n\n'.join(evidence)+'\n\n'+self.t(topic+'.body'),self.c.language)
                if topic=='ssh':
                    choice=self.c.choose(self.t('ssh.title'),[('1','[1] '+self.t('ssh.open')),('0','[0] '+self.t('back'))],default='0')
                    if choice=='1':self.c.ssh_settings()

    @staticmethod
    def discovery_role(state):
        return {'ready':'success:','found_unverified':'pending:','path_missing':'pending:',
                'version_mismatch':'warning:','hash_mismatch':'warning:','unusable':'error:','probe_failed':'i:'}.get(state,'i:')

    def discovery_text(self,key,row=None):
        result=self.session.results.get(key) or self.session.scan(key)
        public=self.data['discovery'].get(key,{})
        lines=[self.t('discovery.readonly'),self.t('discovery.count',count=public.get('candidate_count',0),found=public.get('found_count',0)),
               self.t('discovery.required',path=self.session.display_path(self.session.manifest.get(key)) if key!='node' else self.t('discovery.node_requirement')),
               self.t('discovery.runtime',path=self.session.display_path(self.session.runtime.get(key)))]
        if public.get('scan_incomplete') or public.get('scope_limited'):lines.append(self.t('discovery.limited'))
        if row:
            lines += [self.t('discovery.candidate',path=self.session.display_path(row.get('candidate_path',row.get('path')))),
                      self.t('discovery.verified_path',path=self.session.display_path(row.get('resolved'))),
                      self.t('discovery.sources',sources=', '.join(self.t('discovery.source.'+name) for name in row.get('sources',[]) if name in discovery.SOURCES)),
                      self.t('discovery.state.'+row['state']),self.t('discovery.reason.'+row['reason']),
                      self.t('discovery.version',version=row.get('version') or self.t('unknown'))]
            for name in ('manifest_match','runtime_hash_match','runtime_match','wrapper_verified','wrapper_runtime_match','version_match','fetch','websocket','symlink'):
                value=row.get(name)
                lines.append(self.t('discovery.field.'+name)+': '+self.t('discovery.yes' if value is True else 'discovery.no' if value is False else 'unknown'))
        return '\n'.join(lines)

    def candidate_list(self,component=None):
        selected='1'
        while True:
            entries=[(key,row) for key in ((component,) if component else discovery.COMPONENTS)
                     for row in self.session.results.get(key,{}).get('items',[])]
            options=[]
            for i,(key,row) in enumerate(entries,1):
                label='['+str(i)+'] '+self.t('name.'+key)+' · '+self.t('discovery.state.'+row['state'])
                options.append((str(i),label))
            options.append(('0','[0] '+self.t('back')))
            choice=self.c.choose(self.t('discovery.candidates'),options,default=selected)
            if choice=='0':return
            if choice not in [str(i) for i in range(1,len(entries)+1)]:continue
            selected=choice;key,row=entries[int(choice)-1]
            self.c.ui2.show_text(self.t('name.'+key),self.discovery_text(key,row),self.c.language)

    def locate_component(self,key):
        selected='1'
        while True:
            options=[('i:notice',self.t('discovery.readonly'))]+[
                (str(i),'['+str(i)+'] '+self.t('discovery.action.'+str(i))) for i in range(1,4)]+[('0','[0] '+self.t('back'))]
            choice=self.c.choose(self.t('name.'+key),options,default=selected)
            if choice=='0':return
            if choice not in ('1','2','3'):continue
            selected=choice
            if choice=='1':
                self.session.scan(key);self.data=collect(self.c.root,self.c.settings_file,self.session)
                self.c.ui2.show_text(self.t('name.'+key),self.discovery_text(key,self.session.results[key]['selected']),self.c.language)
            elif choice=='2':
                try:
                    value=input(self.t('discovery.prompt')+' ')
                    if value.strip()=='0':continue
                    if not self.session.add_manual(key,value):continue
                    self.data=collect(self.c.root,self.c.settings_file,self.session)
                    self.c.ui2.show_text(self.t('name.'+key),self.discovery_text(key),self.c.language)
                    self.candidate_list(key)
                except (ValueError,OSError):self.c.ui2.show_text(self.t('discovery.title'),self.t('discovery.invalid_path'),self.c.language)
            else:self.candidate_list(key)

    def locate(self):
        selected='1'
        while True:
            options=[(str(i),'['+str(i)+'] '+self.t('name.'+key)) for i,key in enumerate(discovery.COMPONENTS,1)]
            options += [('4','[4] '+self.t('discovery.candidates')),('0','[0] '+self.t('back'))]
            choice=self.c.choose(self.t('discovery.title'),options,default=selected)
            if choice=='0':return
            if choice not in ('1','2','3','4'):continue
            selected=choice
            if choice=='4':self.candidate_list()
            else:self.locate_component(discovery.COMPONENTS[int(choice)-1])

    def report(self):
        try:
            directory = self.c.report_directory if self.c.report_directory is not None else Path(self.c.settings_file).parent/'reports'/'installation'
            target=export_report(self.data,directory)
            self.c.ui2.show_text(self.t('report.title'),self.t('report.saved',path=str(target)),self.c.language)
        except OSError:
            self.c.ui2.show_text(self.t('report.title'),self.t('report.failed'),self.c.language)

    def run(self):
        while True:
            choice=self.c.choose(self.t('title')+' · '+str(self.data['launcher_version'] or self.t('unknown')),self.rows(),default=self.selected)
            if choice=='0':return
            if choice not in ('1','2','3','4','5'):continue
            self.selected=choice
            if choice=='1':self.guide()
            elif choice=='2':self.data=collect(self.c.root,self.c.settings_file,self.session);self.verify()
            elif choice=='3':self.report()
            elif choice=='5':self.locate()
            elif choice=='4':
                choice=self.c.choose(self.t('level2.title'),[('warning:notice',self.t('level2.notice')),('1','[1] '+self.t('level2.confirm')),('0','[0] '+self.t('back'))],default='0')
                if choice=='1':self.c.runtime_check()


def run(context):return SetupCenter(context).run()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report',action='store_true')
    args=parser.parse_args()
    data=collect()
    if args.report:
        try:print(export_report(data))
        except OSError:
            print('Report creation failed; no existing file was replaced. / 无法新建报告，未覆盖已有文件。')
            return 2
    else:print(json.dumps(data,ensure_ascii=False,indent=2))
    return 0


if __name__=='__main__':sys.exit(main())
