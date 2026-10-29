"""Local help using the existing scrolling UI; no probes or configuration writes."""
TOPICS = ('quick', 'launch', 'performance', 'environment', 'network', 'ssh', 'updates', 'appearance', 'faq')


def wrap(text, width, measure):
    """Wrap words where possible; bound individual CJK characters and long tokens."""
    rows = []
    for paragraph in text.splitlines():
        line = ''
        for char in paragraph.expandtabs(4):
            if measure(line + char) > width:
                cut = line.rfind(' ')
                if cut > 0 and measure(line[cut+1:] + char) <= width:
                    rows.append(line[:cut]);line = line[cut+1:]
                else:
                    rows.append(line);line = ''
            line += char
        rows.append(line)
    return rows


class HelpCenter:
    def __init__(self, context):
        self.c = context
        self.selected = '1'

    def t(self, key, **values):
        return self.c.i18n.text('help.center.'+key, self.c.language, **values)

    def values(self):
        # All capabilities are supplied by existing modules, never a second table.
        profiles = self.c.catalog.PROFILES
        states = [self.c.catalog.status(p,self.c.performance) for p in profiles]
        return dict(version=self.c.version.get_version(),
                    performance_name=self.c.labels()['2'],
                    profiles=str(len(profiles)),
                    verified=str(states.count('verified')),
                    experimental=str(states.count('experimental')),
                    parameters=str(self.c.performance.SETTINGS),
                    components=', '.join(item['name'] for item in self.c.requirements['components']),
                    update_state=self.t('install.enabled' if self.c.updates.INSTALL_ENABLED else 'install.disabled'))

    def home_rows(self):
        return [(str(i),'['+str(i)+'] '+self.t(topic+'.title')) for i,topic in enumerate(TOPICS,1)]+[
            ('0','[0] '+self.t('back.main'))]

    def page_rows(self, topic):
        values = self.values()
        text = self.t(topic+'.body',**values)
        width = max(8,self.c.ui2.terminal_size((86,29)).columns-8)
        rows = [('info:version','HELLDIVERS 2 FX Launcher · '+values['version'])]
        for i,line in enumerate(wrap(text,width,self.c.ui2.text_width)):
            role = 'warning:' if line.startswith('! ') else 'info:'
            rows.append((role+str(i),line))
        rows.append(('0','[0] '+self.t('back.help')))
        return rows

    def page(self, topic):
        selected = 'info:version'
        while True:
            rows = self.page_rows(topic)  # Rewrap after terminal resize/redraw.
            choice = self.c.choose(self.t(topic+'.title'),rows,default=selected,
                                   options_factory=lambda:self.page_rows(topic))
            if choice == '0':return
            selected = choice if any(key==choice for key,_ in rows) else 'info:version'

    def run(self):
        while True:
            descriptions={str(i):self.t(topic+'.body',**self.values()).splitlines()[0]
                          for i,topic in enumerate(TOPICS,1)}
            choice = self.c.choose(self.t('title')+' · '+self.c.version.get_version(),self.home_rows(),
                                   default=self.selected,descriptions=descriptions)
            if choice == '0':return
            if choice in [str(i) for i in range(1,len(TOPICS)+1)]:
                self.selected = choice
                self.page(TOPICS[int(choice)-1])


def run(context):
    HelpCenter(context).run()
