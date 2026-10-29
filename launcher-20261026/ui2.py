"""UI 2.0 presentation and keyboard navigation; no game or connection code."""
import os
import importlib.util
import math
from functools import lru_cache
from pathlib import Path
import queue
import re
import select
import shutil
import sys
import termios
import threading
import time
import tty
import unicodedata

_locale_spec=importlib.util.spec_from_file_location('hd2fx_ui_locales',Path(__file__).with_name('i18n.py'))
i18n=importlib.util.module_from_spec(_locale_spec)
_locale_spec.loader.exec_module(i18n)
_version_spec=importlib.util.spec_from_file_location('hd2fx_ui_version',Path(__file__).with_name('launcher_version.py'))
launcher_version=importlib.util.module_from_spec(_version_spec)
_version_spec.loader.exec_module(launcher_version)

COLORS = {
    'background': '#101114', 'yellow': '#FFD600', 'muted': '#737780',
    'green': '#55D68A', 'red': '#FF5757', 'warning': '#FF6B4A',
    'text': '#DFE2E8', 'line': '#41454D',
}
COLOR_INDEX = {'background':233,'yellow':220,'muted':243,'green':78,'red':203,'warning':203,'text':253,'line':238}
ANSI_FG = {'background':30,'yellow':93,'muted':90,'green':92,'red':91,'warning':91,'text':37,'line':90}
ASSETS = Path(__file__).resolve().parent/'assets'
INTERFACE_VERSION = '2.1'
ORDER = ['1','2','3','4','10','5','6','7','8','9','11','0']
LEFT = ['1','2','3','4','10']
RIGHT = ['5','6','7','8','9','11']


@lru_cache(maxsize=5)
def asset_lines(name):
    return tuple((ASSETS/name).read_text(encoding='utf-8').splitlines())


def cell_width(char):
    if unicodedata.combining(char) or char in ['\ufe0e','\ufe0f']:return 0
    return 2 if unicodedata.east_asian_width(char) in ['W','F'] else 1


def text_width(text):
    return sum(cell_width(char) for char in unicodedata.normalize('NFC',text))


def truncate(text, width):
    text=unicodedata.normalize('NFC',text)
    if text_width(text)<=width:return text
    result=''
    for char in text:
        if text_width(result)+cell_width(char)>width-1:break
        result+=char
    return result+'…' if width>0 else ''


def terminal_size(fallback=(91,27)):
    size=shutil.get_terminal_size(fallback)
    # A newly created PTY can report 0x0 without raising an exception.
    return os.terminal_size((max(20,size.columns or fallback[0]),max(10,size.lines or fallback[1])))


def rgb(role):
    color=COLORS.get(role,role).lstrip('#')
    return tuple(int(color[i:i+2],16) for i in [0,2,4])


class Frame:
    def __init__(self,columns,rows):
        self.columns=max(20,columns);self.rows=max(10,rows)
        self.cells=[[(' ','text','background',False) for _ in range(self.columns)] for _ in range(self.rows)]
        self.positions={}

    def put(self,row,column,text,fg='text',bg='background',bold=False,limit=None):
        if not 0<=row<self.rows:return
        edge=self.columns if limit is None else min(self.columns,column+limit)
        if fg=='red':fg='warning'  # Presentation alias; do not change supplied status data.
        text=truncate(plain_text(text),max(0,edge-column))
        for char in text:
            width=cell_width(char)
            if not width:continue
            if column>=0 and column+width<=edge:
                self.cells[row][column]=(char,fg,bg,bold)
                if width==2:self.cells[row][column+1]=('',fg,bg,bold)
            column+=width

    def fill(self,row,column,width,fg='text',bg='background'):
        self.put(row,column,' '*width,fg,bg)

    def rule(self,row,start=2,end=None,fg='line'):
        self.put(row,start,'─'*max(0,(end or self.columns-2)-start),fg)

    def plain(self):
        return '\n'.join(''.join(cell[0] for cell in line).rstrip() for line in self.cells)

    def ansi(self,colors=True,truecolor=True,colors256=True,clear=False):
        output=['\033[?7l\033[H'+('\033[2J' if clear else '')]
        for y,line in enumerate(self.cells):
            output.append('\033['+str(y+1)+';1H')
            previous=None
            for char,fg,bg,bold in line:
                if not char:continue
                style=(fg,bg,bold)
                if colors and style!=previous:
                    prefix='\033[0;'+('1;' if bold else '')
                    if truecolor:
                        r,g,b=rgb(fg);br,bg_,bb=rgb(bg)
                        output.append(prefix+'38;2;'+str(r)+';'+str(g)+';'+str(b)+';48;2;'+str(br)+';'+str(bg_)+';'+str(bb)+'m')
                    elif colors256:output.append(prefix+'38;5;'+str(COLOR_INDEX[fg])+';48;5;'+str(COLOR_INDEX[bg])+'m')
                    else:output.append(prefix+str(ANSI_FG[fg])+';'+str(ANSI_FG[bg]+10)+'m')
                output.append(char)
                previous=style
        output.append('\033[0m')
        return ''.join(output)


def fit_art(lines,max_width,max_rows):
    width=max(map(len,lines),default=1)
    factor=min(1,max_width/width,max_rows/max(1,len(lines)))
    if factor>=1:return lines
    pixels=[]
    for line in lines:
        line=line.ljust(width)
        pixels.extend([[c in '█▀' for c in line],[c in '█▄' for c in line]])
    target_w=max(1,round(width*factor));target_h=max(2,round(len(pixels)*factor/2)*2)
    # Area sampling retains thin wing gaps and the bottom strokes of lettering.
    # Point sampling can drop an entire half-block stroke at this small scale.
    image=[]
    for y in range(target_h):
        top=round(y*len(pixels)/target_h);bottom=max(top+1,round((y+1)*len(pixels)/target_h))
        row=[]
        for x in range(target_w):
            left=round(x*width/target_w);right=max(left+1,round((x+1)*width/target_w))
            samples=[pixels[a][b] for a in range(top,min(bottom,len(pixels))) for b in range(left,min(right,width))]
            row.append(sum(samples)>=len(samples)*.5)
        image.append(row)
    return [''.join(('█' if image[y+1][x] else '▀') if image[y][x] else ('▄' if image[y+1][x] else ' ') for x in range(target_w)).rstrip() for y in range(0,target_h,2)]


def emblem(selection,columns,rows):
    name='emblem-wide.txt' if selection=='current' else 'emblem-'+selection+'.txt'
    try:return fit_art(asset_lines(name),columns,rows)
    except OSError:return []


def wordmark(columns):
    """Readable 3x5 terminal type, independent of the four preserved emblems.

    Shrinking the 103-column official wordmark loses letter strokes at 91
    columns. Fixed-width display lettering keeps the title readable instead.
    """
    glyphs={
        'H':['101','101','111','101','101'],
        'E':['111','100','110','100','111'],
        'L':['100','100','100','100','111'],
        'D':['110','101','101','101','110'],
        'I':['111','010','010','010','111'],
        'V':['101','101','101','101','010'],
        'R':['110','101','110','101','101'],
        'S':['111','100','111','001','111'],
        '2':['111','001','111','100','111'],
        ' ':['0']*5,
    }
    pixels=['0'.join(glyphs[char][row] for char in 'HELLDIVERS 2') for row in range(5)]
    pixels.append('0'*len(pixels[0]))
    art=[''.join(('█' if b=='1' else '▀') if a=='1' else ('▄' if b=='1' else ' ') for a,b in zip(pixels[y],pixels[y+1])) for y in range(0,6,2)]
    return art if len(art[0])<=columns else ['HELLDIVERS 2']


def build_home(columns,rows,language,appearance,labels,status,selected='1'):
    f=Frame(columns,rows);c=f.columns;r=f.rows
    def T(key,**values):return i18n.text(key,language,**values)
    forced_compact=c<80 or r<25
    compact=appearance.get('layout','immersive')=='compact' or forced_compact
    margin=2 if c>=50 else 1
    mode=T('ui.compact' if compact else 'ui.immersive')
    if forced_compact and appearance.get('layout','immersive')=='immersive':mode+='·'+T('ui.auto')
    mode='[M] '+mode
    mode_x=c-margin-text_width(mode)
    title=T('app.title')+' · v'+launcher_version.get_version()
    available=max(0,mode_x-margin-2)
    if text_width(title)>available:title='HD2 · v'+launcher_version.get_version()
    f.put(0,margin,title,'muted',limit=available)
    f.put(0,mode_x,mode,'yellow')
    if compact:
        if r>=16:
            f.put(2,margin,'☠  HELLDIVERS 2 / FX LAUNCHER','yellow',bold=True)
            f.rule(3,margin,c-margin)
        else:f.rule(1,margin,c-margin)
        start=5
        if c>=72 and r>=17:
            split=int(c*.58)
            left_rows=[start+i for i in range(len(LEFT))];right_rows=[start+i for i in range(len(RIGHT))]
        else:
            split=None
            left_rows=[];right_rows=[]
    else:
        art=emblem(appearance.get('emblem','current'),max(20,int(c*.28)),7)
        for i,line in enumerate(art):f.put(1+i,margin,line,'yellow')
        title_x=max(29,int(c*.30),margin+max(map(len,art),default=0)+2)
        for i,line in enumerate(wordmark(c-title_x-margin-4)):f.put(1+i,title_x,line,'yellow',bold=True)
        for row in range(1,7):f.put(row,title_x-2,'│','yellow')
        f.put(4,title_x,'F X  L A U N C H E R  /  U I  2 . 1','text')
        f.put(6,title_x,'FOR SUPER EARTH / FOR DEMOCRACY','muted')
        # The emblem occupies rows 1–7; keep its final row intact.
        f.rule(8,margin,c-margin)
        split=int(c*.59)
        last_menu=min(19,r-7)
        # Aligned rows make horizontal navigation predictable in both columns.
        right_rows=[11+(i*(last_menu-11)+2)//(len(RIGHT)-1) for i in range(len(RIGHT))]
        left_rows=right_rows[:len(LEFT)]
    f.environment_row=3 if compact and r>=16 else (1 if compact else 9)
    if status.get('runtime_limited'):
        missing=status.get('runtime_missing_count',0)
        attention=status.get('runtime_attention_count',0)
        notice=T('runtime.missing',count=missing) if missing else T('runtime.attention',count=attention)
        if missing and attention:notice+=' · '+T('runtime.attention_short',count=attention)
        notice='[!!] '+notice;role='warning'
    elif status.get('runtime_limited') is False:
        notice='[OK] '+T('runtime.local_ready');role='green'
    else:
        notice='[--] '+T('runtime.unchecked');role='muted'
    f.fill(f.environment_row,margin,c-margin*2)
    f.put(f.environment_row,margin,notice,role,limit=c-margin*2)
    status_y=r-6
    if split is not None:
        left_x=margin;left_w=split-margin-2;right_x=split+2;right_w=c-right_x-margin
        heading=4 if compact else 10
        f.put(heading,left_x,T('ui21.games'),'muted',limit=left_w)
        f.put(heading,right_x,T('ui.tools'),'muted',limit=right_w)
        for row in range(heading+1,min(max(right_rows)+1,status_y)):f.put(row,split,'│','line')
        for keys,positions,x,width in [(LEFT,left_rows,left_x,left_w),(RIGHT,right_rows,right_x,right_w)]:
            for key,row in zip(keys,positions):
                f.positions[key]=(row,x,width)
                focused=key==selected
                primary=key=='1'
                if focused:
                    f.fill(row,x,width,'background','yellow')
                fg='background' if focused else 'text'
                bg='yellow' if focused else 'background'
                prefix='☠ ' if focused else '  '
                f.put(row,x+1,prefix+'['+key+'] '+labels[key],fg,bg,bold=focused or primary,limit=width-2)
                if width>28:f.put(row,x+width-2,'›',fg if focused else 'muted',bg)
    else:
        # A short, single-column layout is used only when a two-column grid cannot fit.
        start=4 if r>=16 else 2
        capacity=max(1,status_y-start)
        focus=ORDER.index(selected) if selected!='0' else 0
        offset=max(0,min(focus-capacity+1,len(ORDER)-1-capacity))
        for index,key in enumerate(ORDER[:-1]):
            row=start+index-offset
            f.positions[key]=(row,margin,c-margin*2)
            if not start<=row<status_y:continue
            focused=key==selected
            if focused:f.fill(row,margin,c-margin*2,'background','yellow')
            f.put(row,margin+1,('☠ ' if focused else '  ')+'['+key+'] '+labels[key],
                  'background' if focused else 'text','yellow' if focused else 'background',bold=focused,limit=c-margin*2-2)
    f.rule(status_y,margin,c-margin)
    keys=['fx','ssh','steam','proxy','game']
    names=['FX','SSH','Steam',T('ui.proxy'),T('ui.game')]
    if c>=65:
        cell=(c-margin*2)//5
        for i,(key,name) in enumerate(zip(keys,names)):
            x=margin+i*cell
            value,role=status.get(key,(T('status.unchecked'),'muted'))
            f.put(status_y+1,x,name,'text',limit=cell-1)
            f.put(status_y+2,x,'● '+value,role,limit=cell-1)
            if i:f.put(status_y+1,x-2,'│','line');f.put(status_y+2,x-2,'│','line')
    else:
        for row,indices in [(status_y+1,range(3)),(status_y+2,range(3,5))]:
            text='  '.join(names[i]+': '+status.get(keys[i],(T('status.unchecked'),'muted'))[0] for i in indices)
            f.put(row,margin,text,'muted',limit=c-margin*2)
    def latency(name):
        value=status.get('latency_'+name+'_ms')
        state=status.get('latency_'+name+'_state','unchecked')
        if state=='ready' and type(value) in [int,float] and math.isfinite(value) and value>=0:
            return ('<1 ms' if value<1 else str(round(value))+' ms'),'green'
        if state=='timeout':return T('latency.timeout'),'red'
        if state=='error':return T('latency.error'),'red'
        if state=='paused':return T('latency.paused'),'muted'
        return '—','muted'
    def playfab():
        checked=status.get('playfab_checked_routes',0)
        reachable=status.get('playfab_reachable',0)
        if type(checked) is not int or checked<=0:
            return '—','muted'
        reachable=max(0,min(checked,int(reachable)))
        value=str(reachable)+'/'+str(checked)
        ms=status.get('playfab_ms')
        if type(ms) in [int,float] and math.isfinite(ms) and ms>=0:
            value+=' '+str(round(ms))+' ms'
        return value,('green' if reachable==checked else ('yellow' if reachable else 'red'))
    def udp():
        samples=status.get('udp_samples',0)
        successes=status.get('udp_successes',0)
        if type(samples) is not int or samples<=0:
            return '—','muted'
        successes=max(0,min(samples,int(successes)))
        value=str(successes)+'/'+str(samples)
        ms=status.get('udp_ms')
        if type(ms) in [int,float] and math.isfinite(ms) and ms>=0:
            value+=' '+str(round(ms))+' ms'
        return value,('green' if successes==samples else ('yellow' if successes else 'red'))
    vm,vm_role=latency('vm');steam,steam_role=latency('steam')
    pf,pf_role=playfab();network_udp,udp_role=udp()
    full=c>=80
    segments=[('VM '+vm,vm_role),(' · ','muted'),
              (('Steam TLS ' if full else 'TLS ')+steam,steam_role),(' · ','muted'),
              (('PlayFab ' if full else 'PF ')+pf,pf_role),(' · ','muted'),
              ('UDP '+network_udp,udp_role)]
    age=status.get('probe_age_seconds')
    if type(age) is int and age>=0:
        age_text=str(age)+'s' if age<60 else (str(age//60)+'m' if age<3600 else str(age//3600)+'h')
        segments += [(' · ','muted'),(('PF/UDP ' if full else 'P/U ')+age_text,'muted')]
    x=margin
    for segment,role in segments:
        if x>=c-margin:break
        f.put(r-3,x,segment,role,limit=c-margin-x)
        x+=text_width(segment)
    footer=T('ui.footer')
    if text_width(footer)>c-margin*2:
        footer=T('ui.footer_short')
    if text_width(footer)>c-margin*2:footer='↑↓  ↵  Esc  [R]  [0]'
    if text_width(footer)>c-margin*2:footer='↑↓ ↵ Esc R 0'
    f.put(r-2,margin,footer,'muted',limit=c-margin*2)
    note=T('ui.snapshot')+status.get('note',T('ui.remote_unchecked'))
    if forced_compact and appearance.get('layout','immersive')=='immersive':
        note=T('ui.small_window',columns=c,rows=r)
    f.put(r-1,margin,note,'muted',limit=c-margin*2)
    f.positions['0']=(r-2,margin,c-margin*2)
    if selected=='0':
        label='☠ [0] '+T('ui.exit')
        x=max(margin,c-margin-text_width(label));span=min(c-margin-x,text_width(label))
        f.fill(r-2,x,span,'background','yellow')
        f.put(r-2,x,label,'background','yellow',bold=True,limit=span)
        f.positions['0']=(r-2,x,span)
    return f


def layout_notice(appearance,columns,rows,language):
    if appearance.get('layout')=='compact':
        return i18n.text('ui.switched_compact',language)
    if columns<80 or rows<25:
        return i18n.text('ui.selected_small',language,columns=columns,rows=rows)
    return i18n.text('ui.switched_immersive',language)


class StatusRefresher:
    """Run one read-only status check at a time, away from keyboard handling."""
    def __init__(self,refresh,initial,interval=10,now=time.monotonic,language='en'):
        self.refresh=refresh;self.snapshot=dict(initial);self.interval=interval;self.now=now
        self.results=queue.Queue();self.closed=threading.Event()
        self.running=False;self.next_due=now()
        self.language=language

    def request(self):
        if self.closed.is_set() or self.running:return False
        self.running=True;self.next_due=self.now()+self.interval
        def work():
            try:result=dict(self.refresh())
            except Exception:
                result=dict(self.snapshot)
                for name in ['ssh','steam','game']:result[name]=(i18n.text('status.unchecked',self.language), 'muted')
                result['note']=i18n.text('ui.refresh_failed',self.language)
                for name in ['vm','steam']:
                    result['latency_'+name+'_ms']=None;result['latency_'+name+'_state']='error'
            if not self.closed.is_set():self.results.put(result)
        threading.Thread(target=work,name='hd2fx-status',daemon=True).start()
        return True

    def poll(self):
        if self.closed.is_set():return False
        changed=False
        try:
            self.snapshot=self.results.get_nowait();self.running=False;changed=True
        except queue.Empty:pass
        if self.now()>=self.next_due:changed=self.request() or changed
        return changed

    def close(self):
        self.closed.set()


def move_selection(current,direction,positions):
    single_column=len({positions[key][1] for key in ORDER[:-1] if key in positions})==1
    if single_column:
        index=ORDER.index(current)
        step=-1 if direction in ['up','left'] else 1
        return ORDER[(index+step)%len(ORDER)]
    if current=='0':return '1' if direction in ['down','right'] else RIGHT[-1]
    if direction in ['left','right']:
        if (direction=='left' and current in LEFT) or (direction=='right' and current in RIGHT):return current
        group=RIGHT if current in LEFT else LEFT
        available=[key for key in group if key in positions]
        if not available:return current
        row=positions[current][0]
        return min(available,key=lambda key:abs(positions[key][0]-row))
    group=LEFT if current in LEFT else RIGHT
    group=[key for key in group if key in positions]
    index=group.index(current)
    if direction=='up':return group[index-1] if index else '0'
    return group[index+1] if index+1<len(group) else '0'


def plain_text(value):
    """Terminal text only: never interpret controls from status or file content."""
    value=re.sub(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\|$)', '', str(value))
    value=re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', value)
    return ''.join(c for c in value if unicodedata.category(c) not in ('Cc','Cf','Cs'))


def normalize_options(options):
    result=[]
    for key,label in options:
        label=plain_text(label)
        if key.isdigit():label='['+key+'] '+re.sub(r'^\s*(?:\[\d+\]|\d+[.)]|\d+(?=\s))\s*','',label)
        result.append((key,label))
    return result


def wrap_text(text,width):
    rows=[]
    for paragraph in str(text).splitlines():
        line=''
        for char in plain_text(paragraph).expandtabs(4):
            if text_width(line+char)>width:
                cut=line.rfind(' ')
                if cut>0 and text_width(line[cut+1:]+char)<=width:
                    rows.append(line[:cut]);line=line[cut+1:]
                else:rows.append(line);line=''
            line+=char
        rows.append(line)
    return rows


def status_badge(state,language='en'):
    # Unknown is deliberately neutral; presence alone is not end-to-end health.
    roles={'unchecked':'muted','checking':'yellow','ready':'green','error':'warning',
           'unverified':'muted','unknown':'muted','na':'muted'}
    state=state if state in roles else 'unknown'
    return i18n.text('ui21.state.'+state,language),roles[state]


def page_header(frame,title):
    frame.put(0,2,'HELLDIVERS 2 / FX LAUNCHER · UI '+INTERFACE_VERSION,'muted',limit=frame.columns-4)
    frame.put(2,2,plain_text(title),'yellow',bold=True,limit=frame.columns-4)
    frame.rule(3)


def show_text(title,text,language='en'):
    def options():
        lines=wrap_text(text,max(8,terminal_size().columns-8))
        def role(line):
            if '[OK]' in line:return 'success:'
            if '[!!]' in line:return 'warning:'
            return 'info:'
        return [(role(line)+str(i),line) for i,line in enumerate(lines)]+[
            ('0','[0] '+i18n.text('updates.back',language))]
    while choose_list(title,options(),language=language,options_factory=options)!='0':pass


def status_panel(frame,summary,start=4,limit=None):
    for row,item in enumerate(summary[:limit] if limit is not None else summary,start):
        if isinstance(item,dict):
            cells=item.get('cells',[]);width=max(1,(frame.columns-4)//max(1,len(cells)))
            for i,(label,value,role) in enumerate(cells):
                x=2+i*width;prefix=plain_text(label)+': '
                frame.put(row,x,prefix,'text',limit=width-1)
                consumed=min(text_width(prefix),width-1)
                frame.put(row,x+consumed,plain_text(value),role,limit=width-consumed-1)
        else:
            label,role=item
            frame.put(row,2,plain_text(label),role,limit=frame.columns-4)


def help_footer(frame,options,offset,visible,language,pending='',refresh_key=None):
    if frame.rows<13:
        frame.put(frame.rows-1,1,'↑↓ Enter Esc 0'+(' R' if refresh_key else ''),'muted',limit=frame.columns-2)
        return
    frame.rule(frame.rows-4)
    actions=[key for key,_ in options if key.isdigit() and key!='0']
    if all(key.isdigit() for key,_ in options):
        counter=i18n.text('ui21.items',language,count=len(actions))
    else:
        counter=i18n.text('ui21.range',language,first=offset+1,last=min(offset+visible,len(options)),total=len(options))
    frame.put(frame.rows-3,2,counter,'muted',limit=frame.columns-4)
    help_text=i18n.text('list.help',language)
    if refresh_key:help_text+=' · R: '+i18n.text('ui21.refresh',language)
    if text_width(help_text)>frame.columns-4:help_text='↑↓  PgUp/PgDn  Enter  Esc  0'+('  R' if refresh_key else '')
    frame.put(frame.rows-2,2,help_text,'muted',limit=frame.columns-4)
    frame.put(frame.rows-1,2,i18n.text('list.input',language)+' '+pending,'yellow',limit=frame.columns-4)


def build_list(columns,rows,title,options,index=0,pending='',language='en',disabled_keys=(),
               summary=(),descriptions=None,refresh_key=None):
    """Shared MenuList, read-only StatusPanel and ScrollableContent, no probes."""
    frame=Frame(columns,rows);c=frame.columns;r=frame.rows
    options=normalize_options(options);index=max(0,min(index,len(options)-1))
    if r<13:frame.put(0,1,plain_text(title),'yellow',bold=True,limit=c-2)
    else:page_header(frame,title)
    # Menus win over supplementary information on small terminals.
    summary_size=0 if r<13 else min(len(summary),max(0,r-8-min(len(options),max(1,r-8))))
    status_panel(frame,summary,limit=summary_size)
    start=1 if r<13 else 4+summary_size
    capacity=max(1,r-start-(1 if r<13 else 4))
    offset=max(0,min(index-capacity+1,len(options)-capacity))
    pane=descriptions and c>=100 and r>=13
    edge=c//2 if pane else c-2
    for row,(key,label) in enumerate(options[offset:offset+capacity],start):
        focused=offset+row-start==index
        if focused:frame.fill(row,2,edge-2,'background','yellow')
        role='muted' if key.startswith('i:') else 'text'
        if key.startswith('warning:'):role='warning'
        elif key.startswith('success:'):role='green'
        if key in disabled_keys:role='muted'
        frame.put(row,3,('☠ ' if focused else '  ')+label,
                  'background' if focused else role,'yellow' if focused else 'background',bold=focused,limit=edge-4)
        frame.positions[key]=(row,3,edge-4)
    if pane and options:
        text=descriptions.get(options[index][0],'')
        for row in range(4,r-4):frame.put(row,edge,'│','line')
        for row,line in enumerate(wrap_text(text,c-edge-5)[:r-8],4):
            frame.put(row,edge+3,line,'muted',limit=c-edge-5)
    help_footer(frame,options,offset,capacity,language,pending,refresh_key)
    return frame


def choose_list(title,options,default='1',language='en',disabled_keys=(),summary=(),descriptions=None,
                renderer=None,refresh_key=None,options_factory=None):
    options=normalize_options(options)
    values=[key for key,_ in options]
    if not values:return '0'
    index=values.index(default) if default in values else 0
    terminal=terminal_size((80,24))
    interactive=sys.stdin.isatty() and sys.stdout.isatty() and os.environ.get('TERM')!='dumb'
    if not interactive:
        # Pipes retain the complete list; screen scrolling is for real terminals.
        print(title)
        for item in summary:
            if not isinstance(item,dict):print(item[0])
            else:print(' · '.join(label+': '+str(value) for label,value,_ in item.get('cells',[])))
        for _,label in options:print(label)
        return input(i18n.text('list.input',language)+' ').strip()
    fd=sys.stdin.fileno();previous=termios.tcgetattr(fd);pending=''
    digits=max([len(key) for key in values if key.isdigit()]+[1])
    colors='NO_COLOR' not in os.environ
    truecolor=os.environ.get('COLORTERM','').lower() in ['truecolor','24bit'] or os.environ.get('HD2FX_TRUECOLOR')=='1'
    def match(value):
        return next((key for key in values if key.isdigit() and value.isdigit() and int(key)==int(value)),value)
    last_size=None
    def draw():
        nonlocal options,values,index,last_size
        size=terminal_size((80,24))
        if options_factory:
            key=values[index];options=normalize_options(options_factory());values=[value for value,_ in options]
            index=values.index(key) if key in values else min(index,len(values)-1)
        frame=(renderer(size.columns,size.lines,index,pending) if renderer else
               build_list(size.columns,size.lines,title,options,index,pending,language,disabled_keys,
                          summary,descriptions,refresh_key))
        size_key=(size.columns,size.lines)
        sys.stdout.write(frame.ansi(colors,truecolor,'256color' in os.environ.get('TERM','').lower(),clear=size_key!=last_size));sys.stdout.flush()
        last_size=size_key
        return frame
    try:
        tty.setcbreak(fd,termios.TCSANOW)
        sys.stdout.write('\033[?1049h\033[?25l');sys.stdout.flush()
        frame=draw()
        while True:
            if not select.select([fd],[],[],.15)[0]:
                size=terminal_size((80,24))
                if (size.columns,size.lines)!=(frame.columns,frame.rows):frame=draw()
                continue
            key=os.read(fd,1)
            if key==b'':return '0'
            if refresh_key and key in (b'r',b'R'):return refresh_key
            if key in [b'\r',b'\n']:return match(pending) if pending else values[index]
            if key in [b'\x03',b'\x04']:raise KeyboardInterrupt
            if key==b'\x1b':
                sequence=b''
                while select.select([fd],[],[],.08)[0]:
                    sequence+=os.read(fd,1)
                    if sequence[-1:].isalpha() or sequence.endswith(b'~'):break
                if not sequence:return '0' if '0' in values else ''
                if sequence in [b'[A',b'OA',b'[D',b'OD']:index=(index-1)%len(values)
                elif sequence in [b'[B',b'OB',b'[C',b'OC']:index=(index+1)%len(values)
                elif sequence in [b'[H',b'OH',b'[1~']:index=0
                elif sequence in [b'[F',b'OF',b'[4~']:index=len(values)-1
                elif sequence==b'[5~':index=max(0,index-max(1,frame.rows-8))
                elif sequence==b'[6~':index=min(len(values)-1,index+max(1,frame.rows-8))
                else:continue
                pending=''
            elif key==b'\t':index=(index+1)%len(values);pending=''
            elif key in [b'\x7f',b'\x08']:
                pending=pending[:-1]
                candidate=match(pending)
                if candidate in values:index=values.index(candidate)
            elif b'0'<=key<=b'9':
                pending=(pending+key.decode())[-digits:]
                candidate=match(pending)
                if candidate in values:index=values.index(candidate)
            else:continue
            frame=draw()
    finally:
        try:termios.tcsetattr(fd,termios.TCSANOW,previous)
        finally:
            sys.stdout.write('\033[0m\033[?7h\033[?25h\033[?1049l');sys.stdout.flush()


def choose_home(language,appearance,labels,status,toggle_layout,refresh_status=None,refresh_interval=10):
    """Return the same numeric actions consumed by the existing menu dispatcher."""
    terminal=terminal_size()
    selected='1';pending=''
    interactive=sys.stdin.isatty() and sys.stdout.isatty() and os.environ.get('TERM')!='dumb'
    if not interactive:
        while True:
            frame=build_home(terminal.columns,terminal.lines,language,appearance,labels,status,selected)
            print(frame.plain())
            choice=input(i18n.text('ui.choose',language)+' ').strip()
            if choice.lower()=='m':
                appearance=toggle_layout()
                print(layout_notice(appearance,terminal.columns,terminal.lines,language))
                continue
            if choice.lower()=='r' and refresh_status:
                status=refresh_status();continue
            return choice
    fd=sys.stdin.fileno();previous=termios.tcgetattr(fd)
    colors='NO_COLOR' not in os.environ
    truecolor=os.environ.get('COLORTERM','').lower() in ['truecolor','24bit'] or os.environ.get('HD2FX_TRUECOLOR')=='1'
    worker=StatusRefresher(refresh_status,status,refresh_interval,language=language) if refresh_status else None
    notice='';notice_until=0;last_size=None
    def draw():
        nonlocal last_size
        size=terminal_size()
        snapshot=dict(worker.snapshot) if worker else status
        if worker and worker.running:
            snapshot['note']=i18n.text('ui.checking',language)
        frame=build_home(size.columns,size.lines,language,appearance,labels,snapshot,selected)
        if notice:
            frame.fill(frame.rows-1,0,frame.columns)
            frame.put(frame.rows-1,2,notice,'yellow',limit=frame.columns-4)
        size_key=(size.columns,size.lines)
        sys.stdout.write(frame.ansi(colors,truecolor,'256color' in os.environ.get('TERM','').lower(),clear=size_key!=last_size));sys.stdout.flush()
        last_size=size_key
        return frame
    try:
        tty.setcbreak(fd,termios.TCSANOW)
        sys.stdout.write('\033[?1049h\033[?25l');sys.stdout.flush()
        frame=draw()
        while True:
            # Poll results only; all status probes run in the background worker.
            changed=worker.poll() if worker else False
            if notice and time.monotonic()>=notice_until:notice='';changed=True
            if changed:frame=draw()
            if not select.select([fd],[],[],.15)[0]:
                size=terminal_size()
                if (size.columns,size.lines)!=(frame.columns,frame.rows):frame=draw()
                continue
            key=os.read(fd,1)
            if key in [b'\r',b'\n']:return pending or selected
            if key in [b'\x03',b'\x04']:raise KeyboardInterrupt
            if key in [b'r',b'R']:
                if worker:worker.request();frame=draw();continue
                return '3'
            if key in [b'm',b'M']:
                appearance=toggle_layout();pending=''
                size=terminal_size()
                notice=layout_notice(appearance,size.columns,size.lines,language);notice_until=time.monotonic()+4
                frame=draw();continue
            if key==b'\t':
                selected=ORDER[(ORDER.index(selected)+1)%len(ORDER)];pending='';frame=draw();continue
            if key==b'\x1b':
                sequence=b''
                while select.select([fd],[],[],.08)[0]:
                    sequence+=os.read(fd,1)
                    if sequence[-1:].isalpha() or sequence.endswith(b'~'):break
                if not sequence:return '0'
                direction={b'[A':'up',b'OA':'up',b'[B':'down',b'OB':'down',b'[D':'left',b'OD':'left',b'[C':'right',b'OC':'right'}.get(sequence)
                if sequence in [b'[H',b'[1~',b'OH']:selected='1'
                elif sequence in [b'[F',b'[4~',b'OF']:selected='0'
                elif direction:selected=move_selection(selected,direction,frame.positions)
                pending=''
            elif key in [b'\x7f',b'\x08']:
                pending=pending[:-1]
                if pending in ORDER:selected=pending
            elif key in [bytes([n]) for n in range(48,58)]:
                candidate=pending+key.decode()
                pending=candidate if any(option.startswith(candidate) for option in ORDER) else key.decode()
                if pending in ORDER:selected=pending
            else:continue
            frame=draw()
    finally:
        if worker:worker.close()
        try:termios.tcsetattr(fd,termios.TCSANOW,previous)
        finally:
            sys.stdout.write('\033[0m\033[?7h\033[?25h\033[?1049l');sys.stdout.flush()
