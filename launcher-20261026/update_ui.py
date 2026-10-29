"""Explicit, read-only UI 2.1 update center; installer remains unavailable."""
from datetime import datetime, timezone
import importlib.util
from pathlib import Path
import subprocess
import time

_spec = importlib.util.spec_from_file_location('hd2fx_update_checker',Path(__file__).with_name('update_checker.py'))
checker = importlib.util.module_from_spec(_spec);_spec.loader.exec_module(checker)


class UpdateView:
    def __init__(self, context):
        self.c = context
        self.result = checker.initial()
        self.not_before = 0  # Session-only backoff, never saved in user settings.

    def t(self, key, **values):
        return self.c.i18n.text('updates.'+key,self.c.language,**values)

    def choose(self, title, rows, disabled_keys=(), pinned=False):
        if pinned:
            summary=[];actions=[]
            for key,label in rows:
                if key.startswith('info:'):
                    role='muted'
                    if self.result['error'] and key in ('info:status','info:error','info:cause','info:http'):
                        role='warning'
                    elif key=='info:status' and self.result['status'] in ('available','current'):role='green'
                    summary.append((label,role))
                else:actions.append((key,label))
            return self.c.choose(title,actions,default=actions[0][0] if actions else '0',
                                 disabled_keys=disabled_keys,summary=summary)
        width = max(12,self.c.ui2.terminal_size((86,29)).columns-7)
        wrapped = []
        for key,label in rows:
            if not key.startswith('info:'):
                wrapped.append((key,label));continue
            wrapped.extend((key+':'+str(i),line) for i,line in enumerate(self.c.ui2.wrap_text(label,width)))
        return self.c.choose(title,wrapped,default=wrapped[0][0] if wrapped else '0',disabled_keys=disabled_keys)

    def rows(self):
        result=self.result;release=result['release']
        missing=self.t('not_checked' if result['status']=='unchecked' else ('unknown' if result['error'] else 'unavailable'))
        channel=result['channel']
        channel_label='Preview' if channel=='preview' else (self.t('stable') if channel=='stable' else channel or self.t('unknown'))
        rows=[('info:current',self.t('current')+': '+result['current']),
              ('info:channel',self.t('channel')+': '+channel_label),
              ('info:latest',self.t('latest')+': '+(release['version'] if release else missing)),
              ('info:date',self.t('date')+': '+(release['published'] if release else missing)),
              ('info:status',self.t('status')+': '+self.t('state.'+result['status']))]
        if result['error']:rows.append(('info:error',self.t('error.'+result['error'])))
        if result.get('http_status'):rows.append(('info:http','HTTP: '+str(result['http_status'])))
        if release:
            total=release.get('asset_count')
            assets=self.t('asset_count',valid=len(release.get('assets',[])),total=total if total is not None else self.t('unknown'))
        else:assets=missing
        rows.append(('info:assets',self.t('assets')+': '+assets))
        rows.append(('info:automatic',self.t('automatic')+': '+self.t('disabled')))
        if result['status']=='available':rows.append(('info:manual',self.t('manual_only')))
        notes=release['notes'] if release else ''
        summary=' '.join(line.strip() for line in notes.splitlines() if line.strip())
        rows.append(('info:summary',self.t('summary')+': '+(self.c.ui2.truncate(summary,120) if summary else self.t('no_notes'))))
        rows += [('1','[1] '+self.t('check_now')),('2','[2] '+self.t('install_disabled')),
                 ('3','[3] '+self.t('view_notes')),('4','[4] '+self.t('switch_channel')),
                 ('5','[5] '+self.t('open_releases')),('0','[0] '+self.t('back_main'))]
        return rows

    def run(self):
        while True:
            choice=self.choose(self.t('title'),self.rows(),disabled_keys=('2',),pinned=True)
            if choice=='0':return
            if choice=='1':
                self.perform_check()
                if self.result['error']:self.failure()
            elif choice=='2':self.notice(self.t('install_blocked'))
            elif choice=='3':self.notes()
            elif choice=='4':self.select_channel()
            elif choice=='5':self.open_releases()

    def perform_check(self):
        if time.time()<self.not_before:
            self.notice(self.t('retry_wait',time=self.retry_time(self.not_before)));return
        self.c.notify(self.t('checking'))
        self.result=checker.check(update_channel=self.result['channel'])
        details=self.result.get('http_details',{})
        retry=details.get('retry_at')
        if retry is not None:self.not_before=max(self.not_before,retry)

    @staticmethod
    def retry_time(value):
        return datetime.fromtimestamp(value,timezone.utc).strftime('%Y-%m-%d %H:%M:%S UTC')

    def failure(self):
        while self.result['error']:
            result=self.result;rows=[]
            if result.get('http_status'):rows.append(('info:http',self.t('http_failed',status=result['http_status'])))
            rows.append(('info:cause',self.t('error.'+result['error'])))
            details=result.get('http_details',{})
            if details.get('remaining') is not None:
                rows.append(('info:remaining',self.t('remaining',count=details['remaining'])))
            if details.get('retry_at') is not None:
                key='retry_headers' if details.get('retry_source')=='headers' else 'retry_minimum'
                rows.append(('info:retry',self.t(key,time=self.retry_time(details['retry_at']))))
            rows += [('1','[1] '+self.t('retry')),('2','[2] '+self.t('open_releases')),('0','[0] '+self.t('back'))]
            choice=self.choose(self.t('failed'),rows,pinned=True)
            if choice=='0':return
            if choice=='1':self.perform_check()
            elif choice=='2':self.open_releases()

    def open_releases(self):
        try:self.c.open_releases(checker.RELEASES_URL)
        except (OSError,subprocess.SubprocessError):self.notice(self.t('open_failed'))

    def select_channel(self):
        rows=[('info:session',self.t('channel_session')),('1','[1] Preview'),
              ('2','[2] '+self.t('stable')),('0','[0] '+self.t('back'))]
        choice=self.choose(self.t('switch_channel'),rows)
        target={'1':'preview','2':'stable'}.get(choice)
        if target and target!=self.result['channel']:
            self.result=checker.initial(update_channel=target)

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
