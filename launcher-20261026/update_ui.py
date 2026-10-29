"""Phase-one update view using existing UI 2.0 controls; installer stays disabled."""
import importlib.util
from pathlib import Path
import subprocess

_spec = importlib.util.spec_from_file_location('hd2fx_update_checker',Path(__file__).with_name('update_checker.py'))
checker = importlib.util.module_from_spec(_spec);_spec.loader.exec_module(checker)


class UpdateView:
    def __init__(self, context):
        self.c = context
        self.result = None

    def t(self, key, **values):
        return self.c.i18n.text('updates.'+key,self.c.language,**values)

    def choose(self, title, rows, disabled_keys=()):
        width = max(12,self.c.ui2.terminal_size((86,29)).columns-7)
        wrapped = []
        for key,label in rows:
            if not key.startswith('info:'):
                wrapped.append((key,label));continue
            part = '';parts = []
            for char in label:
                if self.c.ui2.text_width(part+char)>width:
                    parts.append(part);part=''
                part+=char
            parts.append(part)
            wrapped.extend((key+':'+str(i),line) for i,line in enumerate(parts))
        return self.c.choose(title,wrapped,default=wrapped[0][0] if wrapped else '0',disabled_keys=disabled_keys)

    def rows(self):
        result = self.result;release = result['release']
        rows = [('info:current',self.t('current')+': '+result['current']),
                ('info:latest',self.t('latest')+': '+(release['version'] if release else self.t('unavailable'))),
                ('info:date',self.t('date')+': '+(release['published'] if release else self.t('unavailable'))),
                ('info:channel',self.t('channel')+': '+(self.t('stable') if result['channel']=='stable' else (result['channel'] or self.t('unknown')))),
                ('info:status',self.t('status')+': '+self.t('state.'+result['status']))]
        if result['error']:rows.append(('info:error',self.t('error.'+result['error'])))
        notes = release['notes'] if release else ''
        summary = ' '.join(line.strip() for line in notes.splitlines() if line.strip())
        summary = self.c.ui2.truncate(summary,120) if summary else self.t('no_notes')
        rows += [('info:summary',self.t('summary')+': '+summary),('info:install',self.t('install_blocked')),
                 ('1','[1] '+self.t('view_notes')),('2','[2] '+self.t('install_disabled')),
                 ('3','[3] '+self.t('open_releases')),('0','[0] '+self.t('back'))]
        return rows

    def run(self):
        self.c.notify(self.t('checking'))
        self.result = checker.check()
        while True:
            choice = self.choose(self.t('title'),self.rows(),disabled_keys=('2',))
            if choice == '0':return
            if choice == '1':self.notes()
            elif choice == '2':self.notice(self.t('install_blocked'))
            elif choice == '3':
                try:self.c.open_releases(checker.RELEASES_URL)
                except (OSError,subprocess.SubprocessError):self.notice(self.t('open_failed'))

    def notes(self):
        release = self.result['release']
        rows = []
        if release:
            rows.append(('info:online',self.t('online_notes')+' · '+release['version']))
            text = release['notes'] or self.t('no_notes')
            rows.extend(('info:remote'+str(i),'│ '+line) for i,line in enumerate(text.splitlines()))
        rows.append(('info:local',self.t('local_notes')))
        try:local = checker.plain_text(self.c.read_changelog())
        except (OSError,UnicodeError):local = self.t('notes_failed')
        rows.extend(('info:local'+str(i),'│ '+line) for i,line in enumerate(local.splitlines()))
        rows.append(('0','[0] '+self.t('back')))
        while self.choose(self.t('view_notes'),rows) != '0':pass

    def notice(self, text):
        while self.choose(self.t('title'),[('info:notice',text),('0','[0] '+self.t('back'))]) != '0':pass


def run(context):
    UpdateView(context).run()
