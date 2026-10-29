"""Read-only chip/profile browsing over the existing UI 2.0 list control.

Application is an explicit confirmed delegation to the unchanged profile handler.
No settings are written by this module; no launch dependency is needed to browse.
"""
import importlib.util
from pathlib import Path
import subprocess

HERE = Path(__file__).resolve().parent

def _load(name):
    spec = importlib.util.spec_from_file_location('hd2fx_'+name,HERE/(name+'.py'))
    module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
    return module

hardware = _load('apple_silicon')
catalog = _load('performance_catalog')


class Browser:
    def __init__(self, context):
        self.c = context
        self.device = None

    def t(self, key, **values):
        return self.c.i18n.text('performance.browser.'+key,self.c.language,**values)

    def choice(self, title, rows, default='0'):
        columns = max(12,self.c.ui2.terminal_size((86,29)).columns-7)
        wrapped = []
        for key,label in rows:
            if not key.startswith('i:'):
                wrapped.append((key,label));continue
            parts = [];part = ''
            for char in label:
                if self.c.ui2.text_width(part+char)>columns:
                    parts.append(part);part=''
                part+=char
            parts.append(part)
            wrapped.extend((key+':'+str(i),line) for i,line in enumerate(parts))
        return self.c.choose(title,wrapped,default=default)

    def action(self, key, label):
        return key,'['+key+'] '+label

    def value(self, value):
        if value is None:return self.t('not_set')
        if isinstance(value,bool):return self.t('on' if value else 'off')
        return str(value)

    def saved(self):
        values = {};errors = set()
        for key in self.c.profile.SETTINGS:
            try:values[key] = self.c.profile.read_setting(key)
            except (self.c.profile.ProfileError,OSError,ValueError,subprocess.SubprocessError):
                values[key] = None;errors.add(key)
        return values,errors

    def root_rows(self):
        rows = [self.action(str(i),self.t('series',series=series))
                for i,series in enumerate(hardware.SERIES,1)]
        return rows+[self.action('6',self.t('detect')),self.action('7',self.t('current')),
                     self.action('0',self.t('back_main'))]

    def run(self):
        while True:
            key = self.choice(self.c.i18n.text('home.setup',self.c.language),self.root_rows(),'1')
            if key == '0':return
            if key in ('1','2','3','4','5'):self.series('M'+key)
            elif key == '6':self.detected()
            elif key == '7':self.current()

    def series_rows(self, series):
        return [self.action(str(i),chip[6:])
                for i,chip in enumerate(hardware.SERIES[series],1)]+[self.action('0',self.t('back'))]

    def series(self, series):
        while True:
            key = self.choice(self.t('series',series=series),self.series_rows(series),'1')
            if key == '0':return
            chips = {str(i):chip for i,chip in enumerate(hardware.SERIES[series],1)}
            if key in chips:self.chip(chips[key])

    def detected_rows(self):
        device = self.device
        memory = device['memory_bytes']
        rows = [('i:chip',self.t('chip')+': '+(device['chip'] or self.t('unknown'))),
                ('i:memory',self.t('memory')+': '+(format(memory/1024**3,'g')+' GiB' if memory else self.t('unknown'))),
                ('i:gpu',self.t('gpu')+': '+(str(device['gpu_cores']) if device['gpu_cores'] else self.t('unknown')))]
        if any(device['chip'] in chips for chips in hardware.SERIES.values()):
            rows.append(self.action('1',self.t('show_chip')))
        else:rows.append(('i:unlisted',self.t('unlisted')))
        return rows+[self.action('0',self.t('back'))]

    def detected(self):
        self.device = hardware.detect()
        while True:
            key = self.choice(self.t('detected'),self.detected_rows())
            if key == '0':return
            if key == '1' and any(self.device['chip'] in chips for chips in hardware.SERIES.values()):
                self.chip(self.device['chip'])

    def chip(self, chip):
        profiles = catalog.profiles_for(chip)
        while True:
            rows = []
            for i,profile in enumerate(profiles,1):
                state = catalog.status(profile,self.c.profile)
                memory = profile.get('memory_bytes')
                scope = ' / '+format(memory/1024**3,'g')+' GiB' if memory else ''
                rows.append(self.action(str(i),self.t(profile['name_key'].split('.')[-1])+scope+' · '+self.t('status.'+state)))
            if not profiles:rows.append(('i:none',self.t('none')))
            rows.append(self.action('0',self.t('back')))
            key = self.choice(chip,rows,'1' if profiles else '0')
            if key == '0':return
            selected = {str(i):p for i,p in enumerate(profiles,1)}
            if key in selected:self.details(selected[key])

    def scope(self, profile):
        memory = profile.get('memory_bytes')
        return self.t('scope')+': '+profile['chip']+' / '+(format(memory/1024**3,'g')+' GiB' if memory else self.t('unknown'))

    def details_rows(self, profile):
        state = catalog.status(profile,self.c.profile)
        rows = [('i:status',self.t('status')+': '+self.t('status.'+state)),
                ('i:scope',self.scope(profile)),('i:evidence',self.t('evidence')+': '+profile.get('evidence',self.t('unknown')))]
        values = catalog.parameters(profile,self.c.profile)
        rows += [('i:'+key,self.t('param.'+key)+': '+self.value(value)) for key,value in values.items()]
        if not values:rows.append(('i:none',self.t('none')))
        rows.append(('i:historical',self.t('historical')))
        if catalog.can_apply(profile,self.device or {},self.c.profile):
            rows.append(self.action('1',self.t('apply')))
        else:rows.append(('i:mismatch',self.t('mismatch')))
        return rows+[self.action('0',self.t('back'))]

    def details(self, profile):
        if self.device is None:self.device = hardware.detect()
        while True:
            key = self.choice(self.t('parameters'),self.details_rows(profile))
            if key == '0':return
            if key == '1' and catalog.can_apply(profile,self.device,self.c.profile):
                self.confirm(profile)

    def current(self):
        while True:
            values,errors = self.saved()
            rows = [('i:readonly',self.t('readonly'))]
            rows += [('i:'+key,self.t('param.'+key)+': '+(self.t('unknown') if key in errors else self.value(value)))
                     for key,value in values.items()]
            rows.append(self.action('0',self.t('back')))
            if self.choice(self.t('current'),rows) == '0':return

    def confirm(self, profile):
        before,errors = self.saved()
        target = catalog.parameters(profile,self.c.profile)
        rows = [('i:scope',self.scope(profile)),('i:flow',self.t('flow'))]
        rows += [('i:'+key,self.t('param.'+key)+': '+(self.t('unknown') if key in errors else self.value(before[key]))+' → '+self.value(value))
                 for key,value in target.items()]
        if errors:rows.append(('i:read_failed',self.t('read_failed')))
        else:rows.append(self.action('1',self.t('confirm')))
        rows.append(self.action('0',self.t('cancel')))
        while True:
            key = self.choice(self.t('difference'),rows)
            if key == '0':return
            if key == '1' and not errors:
                fresh,failed = self.saved()
                self.device = hardware.detect()
                if failed or fresh != before or not catalog.can_apply(profile,self.device,self.c.profile):
                    self.notice(self.t('changed'));return
                # The existing function rechecks dependencies/SSH and retains its
                # original backup and application behavior. No new parameter path.
                self.c.apply()
                self.c.pause()  # Leave dependency/failure/success output readable.
                return

    def notice(self, message):
        while self.choice(self.t('parameters'),[('i:notice',message),self.action('0',self.t('back'))]) != '0':pass


def run(context):
    Browser(context).run()
