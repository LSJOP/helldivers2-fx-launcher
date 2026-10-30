"""Bilingual terminal menu for the existing, verified FX launch helper."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import shutil
import unicodedata
import re
import select
import termios
import tty
import threading

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('hd2_start', ROOT/'goal-dxmt-20261026/start-hd2.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)
prefs = helper.prefs
_ui_spec = importlib.util.spec_from_file_location('hd2fx_ui2', Path(__file__).with_name('ui2.py'))
ui2 = importlib.util.module_from_spec(_ui_spec)
_ui_spec.loader.exec_module(ui2)
i18n = ui2.i18n
_monitor_spec = importlib.util.spec_from_file_location('hd2fx_status_monitor', Path(__file__).with_name('status_monitor.py'))
status_monitor = importlib.util.module_from_spec(_monitor_spec)
_monitor_spec.loader.exec_module(status_monitor)
_network_spec = importlib.util.spec_from_file_location('hd2fx_network_profile', Path(__file__).with_name('network_profile.py'))
network_profile = importlib.util.module_from_spec(_network_spec)
_network_spec.loader.exec_module(network_profile)
_diagnostic_spec = importlib.util.spec_from_file_location('hd2fx_network_diagnostics', Path(__file__).with_name('network_diagnostics.py'))
network_diagnostics = importlib.util.module_from_spec(_diagnostic_spec)
_diagnostic_spec.loader.exec_module(network_diagnostics)
_performance_spec = importlib.util.spec_from_file_location('hd2fx_performance_profile', Path(__file__).with_name('performance_profile.py'))
performance_profile = importlib.util.module_from_spec(_performance_spec)
_performance_spec.loader.exec_module(performance_profile)
_records_spec = importlib.util.spec_from_file_location('hd2fx_network_records', Path(__file__).with_name('network_records.py'))
network_records = importlib.util.module_from_spec(_records_spec)
_records_spec.loader.exec_module(network_records)
_instance_spec = importlib.util.spec_from_file_location('hd2fx_launcher_instance', Path(__file__).with_name('launcher_instance.py'))
launcher_instance = importlib.util.module_from_spec(_instance_spec)
_instance_spec.loader.exec_module(launcher_instance)
_deps_spec = importlib.util.spec_from_file_location('hd2fx_dependencies', Path(__file__).with_name('dependencies.py'))
dependencies = importlib.util.module_from_spec(_deps_spec)
_deps_spec.loader.exec_module(dependencies)
_browser_spec = importlib.util.spec_from_file_location('hd2fx_performance_browser', Path(__file__).with_name('performance_browser.py'))
performance_browser = importlib.util.module_from_spec(_browser_spec)
_browser_spec.loader.exec_module(performance_browser)
_update_spec = importlib.util.spec_from_file_location('hd2fx_update_ui', Path(__file__).with_name('update_ui.py'))
update_ui = importlib.util.module_from_spec(_update_spec)
_update_spec.loader.exec_module(update_ui)
_help_spec = importlib.util.spec_from_file_location('hd2fx_help_center', Path(__file__).with_name('help_center.py'))
help_center = importlib.util.module_from_spec(_help_spec)
_help_spec.loader.exec_module(help_center)
_setup_spec = importlib.util.spec_from_file_location('hd2fx_setup_guide', Path(__file__).with_name('setup_guide.py'))
setup_guide = importlib.util.module_from_spec(_setup_spec)
_setup_spec.loader.exec_module(setup_guide)
LANG = 'zh'
ANSI = re.compile(r'\x1b\[[0-9;]*[A-Za-z]')
OBSERVATION = {'endpoint': None, 'ssh_at': None, 'guest_at': None, 'guest': None}
STATUS_TTL = 30
ACTIVE_PROGRESS = None


def endpoint_key():
    return json.dumps(prefs.load()['ssh'], sort_keys=True)


def reset_observation():
    OBSERVATION.update(endpoint=endpoint_key(), ssh_at=None, guest_at=None, guest=None)


def observe_ssh(guest=None):
    if OBSERVATION['endpoint'] != endpoint_key():reset_observation()
    OBSERVATION['ssh_at'] = time.monotonic()
    if guest is not None:
        OBSERVATION['guest_at'] = time.monotonic()
        OBSERVATION['guest'] = {key:guest.get(key) for key in ['steam_logged_on','game_pids']}


def dashboard_data():
    report=runtime_dependencies()
    if not report['ready']:return limited_dashboard(report)
    if OBSERVATION['endpoint'] != endpoint_key():reset_observation()
    now = time.monotonic()
    ssh_fresh = OBSERVATION['ssh_at'] is not None and now-OBSERVATION['ssh_at'] <= STATUS_TTL
    guest_fresh = OBSERVATION['guest_at'] is not None and now-OBSERVATION['guest_at'] <= STATUS_TTL
    unknown = tr('未检查', 'unchecked')
    try:
        running = subprocess.run(['pgrep','-f',helper.APP+'/Contents/MacOS/'],capture_output=True,timeout=2).returncode == 0
        fx = tr('运行中','running') if running else tr('未运行','stopped')
    except (OSError,subprocess.TimeoutExpired):
        fx = unknown
    proxy = tr('端口就绪','port open') if helper.reachable(7890) else tr('端口未就绪','port closed')
    ssh = tr('验证通过','verified') if ssh_fresh else unknown
    steam, game = unknown, unknown
    if guest_fresh:
        guest = OBSERVATION['guest']
        steam = tr('已登录','signed in') if guest['steam_logged_on'] else tr('未登录','signed out')
        game = tr('运行中','running') if guest['game_pids'] else tr('未运行','stopped')
    age = tr('远程状态未检查；菜单 3 可刷新。','Remote status unchecked; menu 3 refreshes it.')
    if guest_fresh:
        age = tr('远程状态来自 ', 'Remote status checked ')+str(int(now-OBSERVATION['guest_at']))+tr(' 秒前；30 秒后过期。','s ago; expires after 30s.')
    elif ssh_fresh:
        age = tr('仅验证了 SSH；Steam 和游戏尚未检查。','Only SSH verified; Steam and game remain unchecked.')
    def role(value):
        if value == unknown:return 'muted'
        return 'green' if value in [tr('运行中','running'),tr('端口就绪','port open'),tr('验证通过','verified'),tr('已登录','signed in')] else 'red'
    return dict(zip(['fx','ssh','steam','proxy','game'], [(value,role(value)) for value in [fx,ssh,steam,proxy,game]]), note=age,runtime_limited=False)


def runtime_dependencies():
    return dependencies.inspect_runtime(helper)


def limited_dashboard(report):
    data={name:(i18n.text('status.unchecked',LANG),'muted') for name in ['fx','ssh','steam','proxy','game']}
    data.update(runtime_missing_count=report['missing_count'],runtime_attention_count=report['attention_count'],
                runtime_limited=True,note=i18n.text('runtime.menu_available',LANG))
    return data


def refresh_dashboard(language):
    report=runtime_dependencies()
    if not report['ready']:return limited_dashboard(report)
    data=status_monitor.snapshot(prefs,helper,language)
    # Presentation flag only: use the existing report['ready'] decision above.
    data['runtime_limited']=False
    return data


def show_runtime_dependencies(report):
    print('\n'+i18n.text('runtime.title',LANG))
    for item in report['items']:
        print('  - '+i18n.text('runtime.name.'+item['id'],LANG)+': '+
              i18n.text('runtime.state.'+item['state'],LANG))
    if any(item['id'] in ['fx','gvproxy'] and item['state']=='missing' for item in report['items']):
        print(i18n.text('runtime.preview_component',LANG))
    print(i18n.text('runtime.instructions',LANG))


def require_runtime():
    report=runtime_dependencies()  # Fresh check for every launch/configure attempt.
    if report['ready']:return True
    show_runtime_dependencies(report)
    print(i18n.text('runtime.return_menu',LANG))
    return False


def render_dashboard():
    data = dashboard_data()
    fx,ssh,steam,proxy,game = [data[key][0] for key in ['fx','ssh','steam','proxy','game']]
    panel(tr('环境状态', 'ENVIRONMENT STATUS'), [
        'FX: '+fx+'  |  SSH: '+ssh+'  |  Steam: '+steam,
        tr('代理: ', 'Proxy: ')+proxy+'  |  '+tr('游戏: ', 'Game: ')+game,
        data['note'],
    ])


class LaunchProgress:
    NAMES = {
        'fx': ('等待 FX 就绪','Wait for FX'),
        'ssh': ('连接虚拟机','Connect to VM'),
        'environment': ('校验与准备环境','Check and prepare environment'),
        'steam': ('等待 Steam 就绪','Wait for Steam'),
        'game': ('启动游戏进程','Start game process'),
        'eac': ('检查本次 EAC 初始化','Check current EAC initialization'),
        'playfab': ('检查 PlayFab 通路','Check PlayFab route'),
        'udp': ('探测 UDP 与游戏 socket','Probe UDP and game sockets'),
    }

    def __init__(self, configure=False):
        self.steps = list(self.NAMES)[:4] if configure else list(self.NAMES)
        self.active = None
        self.states = {key:{'status':'waiting','started':None,'elapsed':0.0} for key in self.steps}
        self.dynamic = sys.stdout.isatty() and os.environ.get('TERM') != 'dumb'
        self.lock = threading.RLock()
        self.stop = threading.Event()
        self.paused = False
        self.waiting = False
        self.visible = False
        self.started = time.monotonic()
        self.thread = None

    def clear_line(self):
        if self.visible:
            print('\r\033[2K',end='',flush=True)
            self.visible = False

    def animate(self):
        frames = ['⠋','⠙','⠹','⠸','⠼','⠴','⠦','⠧','⠇','⠏']
        frame = 0
        while not self.stop.wait(.15):
            with self.lock:
                if self.paused or not self.waiting or self.active not in self.steps:continue
                text = frames[frame % len(frames)]+' ['+str(self.steps.index(self.active)+1)+'/'+str(len(self.steps))+'] '+tr(*self.NAMES[self.active])
                text += ' · '+str(int(time.monotonic()-self.started))+'s'
                print('\r\033[2K'+paint('  '+text),end='',flush=True)
                self.visible = True
                frame += 1

    def pause(self):
        with self.lock:
            self.paused = True
            self.clear_line()

    def resume(self):
        with self.lock:self.paused = False

    def write_message(self, message):
        with self.lock:
            self.clear_line()
            print(message,flush=True)

    def close(self):
        self.stop.set()
        if self.thread:self.thread.join(timeout=1)
        with self.lock:
            self.clear_line()
            for key, value in self.states.items():
                if value['status'] == 'waiting':value['status'] = 'skipped'
                if value['status'] == 'running':
                    value['elapsed'] = time.monotonic()-value['started']
                    value['status'] = 'unverified'
                label = tr(*self.NAMES[key])
                print('  '+label+' | '+self.status_text(value['status'])+' | '+format(value['elapsed'],'.1f')+'s')

    @staticmethod
    def status_text(status):
        return tr(*{'waiting':('等待中','waiting'),'running':('正在执行','running'),
                    'done':('已通过','passed'),'skipped':('已跳过','skipped'),
                    'unverified':('未验证','unverified'),'failed':('失败','failed')}[status])

    def update(self, stage, status='running', detail=None):
        if stage not in self.steps:return
        status = 'done' if status == 'passed' else status
        if status not in ('waiting','running','done','skipped','unverified','failed'):status='unverified'
        with self.lock:
            value = self.states[stage]
            if value['started'] is None and status != 'waiting':value['started']=time.monotonic()
            if value['started'] is not None:value['elapsed']=time.monotonic()-value['started']
            value['status']=status
            self.clear_line()
            self.active = stage
            self.waiting = status == 'running'
            if status == 'running':self.started = time.monotonic()
            if self.dynamic and self.thread is None:
                self.thread = threading.Thread(target=self.animate,daemon=True)
                self.thread.start()
        label = tr(*self.NAMES[stage])
        text = self.status_text(status)
        marker = '✓' if status == 'done' else ('…' if status == 'running' else '?')
        with self.lock:
            self.clear_line()
            print(paint('  '+marker+' ['+str(self.steps.index(stage)+1)+'/'+str(len(self.steps))+'] '+label+' — '+text, '38;5;114' if status=='done' else '38;5;220'), flush=True)
        if stage == 'ssh' and status == 'done':observe_ssh(detail)
        elif stage == 'steam' and status == 'done' and detail is not None:observe_ssh(detail)
        elif stage == 'game' and status == 'done':
            if OBSERVATION['guest'] is not None:
                OBSERVATION['guest']['game_pids'] = ['running']
                OBSERVATION['guest_at'] = time.monotonic()
        if stage == 'eac' and status == 'unverified':
            print(tr('  尚未确认本次 EAC 成功；请查看游戏提示。游戏保持运行。', '  Current EAC success is unconfirmed. Check the game message; the game was left running.'))

    def failed(self):
        self.pause()
        if self.active:
            self.update(self.active,'failed')
            print(tr('停在阶段：','Stopped at: ')+tr(*self.NAMES[self.active]))


def color_enabled():
    return sys.stdout.isatty() and os.environ.get('TERM') != 'dumb' and 'NO_COLOR' not in os.environ


def paint(text, code='38;5;220'):
    return '\033['+code+'m'+text+'\033[0m' if color_enabled() else text


STATUS_STYLES = {
    'ok': ('●', '[OK]', '38;5;114'),
    'warn': ('●', '[--]', '38;5;220'),
    'fail': ('●', '[!!]', '38;5;196'),
    'info': ('●', '[··]', '38;5;245'),
}


def status_label(state, label=''):
    kind = 'ok' if state is True else ('warn' if state is None else 'fail')
    icon, code, color = STATUS_STYLES[kind]
    text = paint(icon, '1;'+color)+' '+paint(code, color)
    return text+(' '+label if label else '')


def width(text):
    return sum(2 if unicodedata.east_asian_width(char) in ('W', 'F') else 1 for char in ANSI.sub('', text) if not unicodedata.combining(char))


def panel(title, lines):
    inner = max([width(title)+4]+[width(line)+2 for line in lines])
    print(paint('╭'+'─'*inner+'╮'))
    print(paint('│')+' '+paint(title, '1;38;5;220')+' '*(inner-width(title)-1)+paint('│'))
    print(paint('├'+'─'*inner+'┤'))
    for line in lines:
        print(paint('│')+' '+line+' '*(inner-width(line)-1)+paint('│'))
    print(paint('╰'+'─'*inner+'╯'))


def banner(reserve_rows=0):
    if sys.stdout.isatty() and os.environ.get('TERM') != 'dumb':
        print('\033[2J\033[H', end='')
    terminal = shutil.get_terminal_size((80, 24))
    columns = terminal.columns
    selection = prefs.load()['appearance']['emblem']
    asset = ('emblem-wide.txt' if columns >= 64 else 'emblem-compact.txt') if selection == 'current' else 'emblem-'+selection+'.txt'
    try:
        skull = (Path(__file__).resolve().parent/'assets'/asset).read_text(encoding='utf-8').splitlines()
    except OSError:
        skull = ['[ HELLDIVERS 2 ]']
    if skull and max(map(len, skull)) > columns:
        skull = fit_emblem(skull, max(12, columns-2))
        print(tr('  图案已适配窗口；拉宽终端可显示更多细节。', '  Emblem fitted to the window; widen it for more detail.'))
    if reserve_rows and sys.stdout.isatty():
        available = terminal.lines-reserve_rows-4
        if available < 3:
            print(paint('  HELLDIVERS 2 · FX', '1;38;5;220'))
            return
        elif len(skull) > available:
            target = max(8, int(max(map(len,skull))*available/len(skull)))
            skull = fit_emblem(skull,target)
    print()
    for line in skull:
        print(paint(line, '1;38;5;220'))
    print(paint('  H E L L D I V E R S  2', '1;38;5;255'))
    print(paint('  '+tr('为了超级地球 · 为了民主', 'FOR SUPER EARTH · FOR DEMOCRACY'), '38;5;220'))
    print()


def fit_emblem(lines, limit):
    """Scale prebuilt half-block art without introducing a runtime image dependency."""
    original_width = max(map(len, lines))
    if original_width <= limit:return lines
    pixels = []
    for line in lines:
        line = line.ljust(original_width)
        pixels.extend([[char in '█▀' for char in line], [char in '█▄' for char in line]])
    height = max(2, round(len(pixels)*limit/original_width))
    height += height % 2
    scaled = [[pixels[min(len(pixels)-1, int(y*len(pixels)/height))][min(original_width-1, int(x*original_width/limit))] for x in range(limit)] for y in range(height)]
    result = []
    for y in range(0, height, 2):
        result.append(''.join(('█' if scaled[y+1][x] else '▀') if scaled[y][x] else ('▄' if scaled[y+1][x] else ' ') for x in range(limit)).rstrip())
    return result


def prompt(text):
    return input(paint('  ❯ ', '1;38;5;220')+text).strip()


def startup_animation(duration=1.2):
    if not prefs.load()['appearance']['intro_animation'] or not sys.stdin.isatty() or not sys.stdout.isatty() or os.environ.get('TERM') == 'dumb':return
    fd = sys.stdin.fileno()
    previous = termios.tcgetattr(fd)
    try:
        tty.setcbreak(fd, termios.TCSANOW)
        print('\033[?25l',end='',flush=True)
        banner(reserve_rows=5)
        print(paint('  '+i18n.text('intro.title',LANG), '1;38;5;220'))
        print('  '+i18n.text('intro.hint',LANG))
        started = time.monotonic()
        while True:
            ratio = min(1, (time.monotonic()-started)/duration)
            filled = int(ratio*24)
            print('\r  ['+paint('█'*filled+'░'*(24-filled))+']  ☠',end='',flush=True)
            if ratio >= 1:break
            if select.select([fd],[],[],.04)[0]:
                os.read(fd,32)
                while select.select([fd],[],[],.01)[0]:os.read(fd,32)
                break
    finally:
        termios.tcsetattr(fd,termios.TCSANOW,previous)
        print('\n\033[?25h',end='',flush=True)


def select_option(title, options, default='1', header=None, **presentation):
    if header:header()
    return ui2.choose_list(title, options, default, LANG, **presentation)


MESSAGES = {
    '网络模式：TUN + 游戏 Host HTTPS 代理': 'Network mode: TUN + game Host HTTPS proxy',
    '网络模式：HTTP 代理': 'Network mode: HTTP proxy',
    '检测到 TUN，但 macOS 系统代理仍开启。请在 FlClash 关闭系统代理后重试。': 'TUN is active, but the macOS system HTTP proxy is enabled. Turn off the system proxy in FlClash and retry.',
    '正在等待虚拟机连接就绪，请保持 FX 窗口开启……': 'Waiting for the VM connection. Keep FX open...',
    '虚拟机连接尚未就绪。请保留 FX 窗口，稍后重新双击启动入口。': 'The VM connection is not ready. Keep FX open and try again shortly.',
    '未能建立游戏所需的本地连接。': 'Could not establish the local connection required by the game.',
    '本地连接仍未建立，请保留 FX 窗口并稍后检查。': 'The local connection is not ready. Keep FX open and try again shortly.',
    'FX 已运行，但未能自动切换窗口。请手动切换到 FX；游戏启动将继续。': 'FX is running. Switch to its window manually; startup will continue.',
    '正在确认游戏进程启动；若出现驱动版本提示，请在 FX 窗口选择“继续”。': 'Waiting for the game process. If FX shows a driver warning, choose Continue.',
    '已确认绝地潜兵 2 进程启动，请切换到 FX 窗口等待游戏载入。': 'Helldivers 2 has started. Switch to FX and wait for the game to load.',
    'Steam 已收到请求，但尚未检测到游戏进程。请查看 FX 中是否有登录、更新或启动错误提示，保留此窗口回到聊天检查。': 'Steam received the request, but the game process has not appeared. Check FX for login, update, or startup messages and keep this window open.',
    '虚拟机 IPv4 网络已准备。': 'VM IPv4 networking is ready.',
    '配置所需的 Node 运行环境不存在，请回到聊天检查。': 'The Node runtime required for setup is missing. Return to this chat for help.',
    'Steam 启动项配置未完成，原设置已备份。': 'Steam launch options could not be configured. The previous settings were backed up.',
    'Steam 未确认新的启动项，原设置已备份。': 'Steam did not confirm the new launch options. The previous settings were backed up.',
    '已保存经过验证的游戏启动项，原设置已备份。': 'Verified game launch options saved. The previous settings were backed up.',
    '正在打开 FlClash，等待代理连接……': 'Opening FlClash and waiting for the proxy...',
    'FX 虚拟机尚未运行。': 'The FX virtual machine is not running.',
    '当前联机测试所需的网络组件缺失或已改变，请回到此聊天继续检查。': 'The verified network component is missing or has changed. Return to this chat for help.',
    '正在启动 FX（使用已验证的图形及当前联机测试设置）……': 'Starting FX with the verified graphics and network settings...',
    'FX 仍在启动，尚未连接到虚拟机。请保留窗口，稍后再检查。': 'FX is still starting. Keep its window open and try again shortly.',
    '当前 FX 没有使用本轮联机测试设置。请正常退出 FX 后，再双击此启动入口。': 'FX is using a different network setup. Quit FX normally, then use this launcher again.',
    '游戏或安装准备步骤正在运行，请正常退出后再使用一键环境配置。当前游戏未被中断。': 'A game or installation step is running. Exit it normally before running environment setup. Your current game was left running.',
    '绝地潜兵 2 已在运行，请切换到 FX 窗口继续。': 'Helldivers 2 is already running. Switch to FX to continue.',
    '当前有其他 Steam 游戏运行，请先退出它，再启动绝地潜兵 2。': 'Another Steam game is running. Exit it before starting Helldivers 2.',
    'Steam 正在准备绝地潜兵 2，正在等待已有启动请求……': 'Steam is preparing Helldivers 2. Waiting for the existing launch request...',
    '当前 FX 使用的是其他图形路径。请退出 FX，再双击此启动文件。': 'FX is using a different graphics backend. Quit FX normally, then use this launcher again.',
    '当前网络需要现有代理的 7890 端口，请先打开原来使用的代理软件。': 'The proxy on port 7890 is unavailable. Open your existing proxy app first.',
    '兼容组件与已验证版本不同，请回到此聊天继续检查。原文件没有被自动覆盖。': 'Compatibility components differ from the verified versions. Return to this chat for help. No files were overwritten.',
    'Wine 系统组件与已验证版本不一致，请回到此聊天修复兼容工具。': 'Wine system components differ from the verified versions. Return to this chat to repair the compatibility tool.',
    '游戏启动设置与已验证配置不同，请回到此聊天继续检查。': 'Game launch options differ from the verified setup. Use menu option 2 to configure the environment.',
    '正在准备 Steam 的游戏网络连接……': 'Preparing the Steam network connection...',
    'Steam 网络已准备。': 'Steam networking is ready.',
    '正在等待 Steam 完成初始化和网络登录……': 'Waiting for Steam to initialize and sign in...',
    '游戏已在运行。': 'The game is already running.',
    'Steam 尚未完成网络登录。请在 FX 中检查 Steam 的连接状态，再重新双击启动入口。': 'Steam has not signed in yet. Check its connection in FX, then try the launcher again.',
    '一键环境配置完成。可以返回菜单启动游戏。': 'Environment setup is complete. Return to the menu to start the game.',
    '正在启动绝地潜兵 2……': 'Starting Helldivers 2...',
    '启动请求已交给 Steam。': 'The launch request has been sent to Steam.',
}


def tr(zh, en):
    return i18n.message(en, LANG)


def localize(message):
    lines=[]
    for line in str(message).split('\n'):
        english=MESSAGES.get(line,line).replace('虚拟机检查未通过：','VM check failed: ')
        lines.append(i18n.message(english,LANG))
    return '\n'.join(lines)


def output(message):
    if ACTIVE_PROGRESS is not None:
        ACTIVE_PROGRESS.write_message(localize(message))
    else:
        print(localize(message), flush=True)


helper.say = output


def secret_prompt(message):
    labels = {
        'SSH password: ': ('SSH 密码（输入不显示）：', 'SSH password (hidden): '),
        'SSH key passphrase: ': ('SSH 密钥口令（输入不显示，不保存）：', 'SSH key passphrase (hidden, not saved): '),
        'Guest sudo password: ': ('虚拟机 sudo 密码（输入不显示，不保存）：', 'Guest sudo password (hidden, not saved): '),
    }
    if ACTIVE_PROGRESS is not None:ACTIVE_PROGRESS.pause()
    try:
        return prefs.secret(tr(*labels[message]) if message in labels else message)
    finally:
        if ACTIVE_PROGRESS is not None:ACTIVE_PROGRESS.resume()


def refresh_connection():
    helper.refresh_settings()
    helper.CLIENT.prompt_secret = secret_prompt
    helper.CLIENT.notify = output


def show_performance_profile():
    columns=shutil.get_terminal_size((80,24)).columns
    title=ui2.truncate(i18n.text('performance.title',LANG),max(1,columns-6))
    lines=[ui2.truncate(i18n.text('performance.'+key,LANG),max(1,columns-4))
           for key in ('resources','graphics','hud','no_stop')]
    panel(title,lines)


def browse_performance_profiles():
    from types import SimpleNamespace
    context = SimpleNamespace(ui2=ui2,i18n=i18n,language=LANG,choose=select_option,
                              profile=performance_profile,apply=lambda:launch_game(configure=True),
                              pause=lambda:input(i18n.text('network.continue',LANG)))
    return performance_browser.run(context)


def check_updates():
    from types import SimpleNamespace
    context = SimpleNamespace(
        ui2=ui2,i18n=i18n,language=LANG,notify=output,
        choose=lambda title,rows,default='0',disabled_keys=(),**presentation:ui2.choose_list(
            title,rows,default,LANG,disabled_keys=disabled_keys,**presentation),
        read_changelog=lambda:(ROOT/'CHANGELOG.md').read_text(encoding='utf-8'),
        open_releases=lambda url:subprocess.run(['open',url],check=True,timeout=8))
    return update_ui.run(context)


def confirm_launch_change(kind, before, after):
    if ACTIVE_PROGRESS:ACTIVE_PROGRESS.pause()
    titles = {'ipv6':tr('Guest IPv6 修改（Guest sudo，非 macOS）','Guest IPv6 change (Guest sudo, not macOS)'),
              'proxy':tr('Steam 代理配置及服务变更','Steam proxy and service change'),
              'launch_options':tr('Steam 启动参数：保留并取消，或使用完整已验证配置','Steam launch options: keep and cancel, or use the full verified configuration')}
    print('\n'+titles[kind])
    if kind == 'ipv6':
        print(tr('all 开关可能影响所有 Guest 接口；下方包含原值及预计变化。','The all switch can affect every Guest interface; the snapshot and expected changes follow.'))
    if kind == 'launch_options':
        print(tr('无法可靠合并自定义参数，不自动合并；确认将替换整段。','Custom arguments cannot be merged reliably; confirmation replaces the entire string.'))
    columns = max(20,shutil.get_terminal_size((86,29)).columns-2)
    for label, value in ((tr('修改前','Before'),before),(tr('修改后','After'),after)):
        print(label+':')
        # JSON escapes control characters but preserves the complete values.
        for line in json.dumps(value,ensure_ascii=False,indent=2).splitlines():
            part = ''
            for char in line:
                if width(part+char)>columns:
                    print('  '+part);part=''
                part+=char
            print('  '+part)
    try:
        answer = input(tr('输入 APPLY 确认；直接回车保留并取消启动：','Type APPLY to confirm; Return keeps settings and cancels launch: '))
        return answer.strip() == 'APPLY'
    finally:
        if ACTIVE_PROGRESS:ACTIVE_PROGRESS.resume()


def launch_game(configure=False):
    global ACTIVE_PROGRESS
    if not require_runtime():return False
    if not prefs.load()['ssh_configured']:
        if not edit_ssh(first_run=True):return False
    if configure:show_performance_profile()
    if not configure:
        network_launch_notice()
    progress = LaunchProgress(configure)
    old_hook = helper.PROGRESS_HOOK
    old_confirm = helper.CONFIRM_HOOK
    helper.CONFIRM_HOOK = confirm_launch_change
    ACTIVE_PROGRESS = progress
    helper.PROGRESS_HOOK = progress.update
    try:
        refresh_connection()
        if configure:
            try:result=performance_profile.apply(helper)
            except performance_profile.ProfileError as error:
                raise RuntimeError(i18n.text('performance.error.'+error.code,LANG)) from None
        else:
            helper.main(configure_only=False)
    except (RuntimeError,OSError,ValueError,subprocess.SubprocessError):
        progress.failed()
        print(tr('返回主菜单后可选择 [3] 环境检查或 [4] 导出报告。不会自动重试。','Return to the menu for [3] environment checks or [4] report export. No automatic retry.'))
        raise
    finally:
        progress.close()
        helper.PROGRESS_HOOK = old_hook
        helper.CONFIRM_HOOK = old_confirm
        ACTIVE_PROGRESS = None
    if configure:
        print(i18n.text('performance.restart' if result['restart_required'] else 'performance.applied',LANG))


def test_ssh_connection():
    if not shutil.which('ssh'):
        raise RuntimeError(i18n.text('runtime.name.ssh',LANG)+': '+i18n.text('runtime.state.missing',LANG))
    reset_observation()
    client = prefs.SSHClient(prefs.load(),test=True)
    client.prompt_secret = secret_prompt
    client.notify = output
    if not client.reachable():
        raise RuntimeError(tr('SSH 端口不可连接。请先打开 FX，或检查主机和端口。', 'SSH port is unreachable. Start FX or check the host and port.'))
    client.test_connection()
    refresh_connection()
    helper.CLIENT.password = client.password
    observe_ssh()
    print(tr('SSH 认证及虚拟机 Python 检查通过。未启动或关闭游戏。', 'SSH authentication and guest Python check passed. No game was started or stopped.'))


def verify_saved_ssh():
    if not sys.stdin.isatty():
        print(tr('参数已保存，但尚未测试连接；可用菜单 8 → 2 验证。', 'Settings saved but connection untested; use menu 8 → 2 to verify.'))
        return 'saved'
    while True:
        if run_action(test_ssh_connection):return 'verified'
        choice = select_option(tr('SSH 尚未验证', 'SSH NOT VERIFIED'), [
            ('1',tr('1. 重试连接', '1. Retry connection')),
            ('2',tr('2. 修改刚才的参数', '2. Edit the parameters')),
            ('0',tr('0. 保留设置，稍后测试', '0. Keep settings and test later')),
        ])
        if choice == '2':return 'edit'
        if choice == '0':return 'saved'


def edit_ssh(first_run=False):
    while True:
        data = prefs.load()
        current = data['ssh']
        print(tr('\n首次运行：配置 SSH 连接', '\nFirst run: set up your SSH connection') if first_run else tr('\n修改 SSH 设置', '\nEdit SSH settings'))
        print(tr('参数保存在本机用户目录。密码可选择存入 macOS 钥匙串，不写入配置文件。Ctrl+C 可取消。', 'Settings stay in your user folder. Passwords can optionally use macOS Keychain, never the settings file. Ctrl+C cancels.'))
        draft = dict(current)
        for key, zh, en in [('host', '主机地址', 'Host'), ('port', 'SSH 端口', 'SSH port'), ('username', '用户名', 'Username')]:
            value = prompt(tr(zh, en)+' ['+str(current[key])+']: ')
            if value:
                draft[key] = value
        auth = prompt(tr('认证方式：1 密码 / 2 SSH 密钥', 'Authentication: 1 Password / 2 SSH key')+' ['+('1' if current['auth'] == 'password' else '2')+']: ')
        if auth not in ['', '1', '2']:
            print(tr('请输入 1 或 2。', 'Enter 1 or 2.'))
            continue
        draft['auth'] = ('key' if auth == '2' else 'password') if auth else current['auth']
        if draft['auth'] == 'key':
            value = prompt(tr('私钥路径（留空沿用，输入 - 使用 SSH Agent）', 'Private key path (Return keeps it; - uses SSH agent)')+' ['+(current['identity_file'] or 'SSH Agent')+']: ')
            if value:
                draft['identity_file'] = '' if value == '-' else str(Path(value).expanduser())
        else:
            draft['identity_file'] = ''
        if draft['auth'] == 'password':
            remember = select_option(tr('是否保存 SSH 密码？', 'SAVE SSH PASSWORD?'), [
                ('1', tr('1. 保存至 macOS 钥匙串（成功连接后保存）', '1. Save in macOS Keychain after successful authentication')),
                ('2', tr('2. 不保存，并清除当前连接已保存的密码', '2. Do not save; remove any saved password for this connection')),
                ('0', tr('0. 取消修改', '0. Cancel changes')),
            ], '1' if current['remember_password'] else '2')
            if remember == '0':return False
            if remember not in ['1', '2']:
                print(tr('请输入 1 或 2。', 'Enter 1 or 2.'))
                continue
            draft['remember_password'] = remember == '1'
        else:
            draft['remember_password'] = False
        value = prompt(tr('本地 Steam 接口端口（一般保持默认）', 'Local Steam interface port (normally keep default)')+' ['+str(current['cdp_local_port'])+']: ')
        if value:
            draft['cdp_local_port'] = value
        try:
            for key in ['port', 'cdp_local_port']:
                draft[key] = int(draft[key])
            data['ssh'] = draft
            data['ssh_configured'] = True
            prefs.validate(data)
            if draft['auth'] == 'password' and not draft['remember_password'] and current['remember_password'] and prefs.keychain.account(draft) == prefs.keychain.account(current):
                prefs.VAULT.delete(draft)
            prefs.save(data)
        except ValueError as error:
            print(tr('设置无效，尚未保存：', 'Invalid settings; nothing was saved: ')+str(error))
            continue
        refresh_connection()
        reset_observation()
        if not runtime_dependencies()['ready']:
            print(i18n.text('runtime.settings_saved',LANG))
            return True
        print(tr('SSH 参数已保存，正在验证连接。以后可通过菜单 8 修改。', 'SSH settings saved; checking the connection. Use menu 8 for future changes.'))
        if verify_saved_ssh() == 'edit':
            first_run = False
            continue
        return True


def manage_saved_password(clear=False):
    data = prefs.load()
    ssh = data['ssh']
    if clear:
        prefs.VAULT.delete(ssh)
        ssh['remember_password'] = False
        prefs.save(data)
        refresh_connection()
        helper.CLIENT.password = None
        print(tr('当前连接的已保存密码已清除。', 'The saved password for this connection has been removed.'))
        return
    if ssh['auth'] != 'password':
        print(tr('当前使用 SSH 密钥；如需保存登录密码，请先改为密码认证。', 'SSH key authentication is selected. Switch to password authentication first.'))
        return
    value = secret_prompt('SSH password: ')
    prefs.VAULT.put(ssh, value)
    ssh['remember_password'] = True
    prefs.save(data)
    refresh_connection()
    helper.CLIENT.password = None
    print(tr('密码已保存至 macOS 钥匙串。', 'Password saved in macOS Keychain.'))


def ssh_summary(data):
    # Metadata only: enabling storage does not prove a password exists in Keychain.
    T=lambda key:i18n.text('ui21.'+key,LANG)
    s=data['ssh'];state='unchecked'
    if (OBSERVATION.get('endpoint')==json.dumps(s,sort_keys=True) and
            OBSERVATION.get('ssh_at') is not None and time.monotonic()-OBSERVATION['ssh_at']<=STATUS_TTL):
        state='ready'
    return [(T('ssh.address')+': '+s['host'],'text'),(T('ssh.port')+': '+str(s['port']),'text'),
            (T('ssh.username')+': '+T('configured' if data.get('ssh_configured') and s.get('username') else 'unconfigured'),'muted'),
            (T('ssh.storage')+': '+T('enabled' if s['remember_password'] else 'disabled'),'muted'),
            (T('ssh.password')+': '+T('state.na' if s['auth']=='key' else 'state.unchecked'),'muted'),
            (T('ssh.test')+': '+T('state.'+state),ui2.status_badge(state,LANG)[1])]


def ssh_settings_menu():
    while True:
        data=prefs.load()
        choice = select_option(tr('SSH 连接设置', 'SSH CONNECTION SETTINGS'), [
            ('1', tr('1. 修改 SSH 参数与密码保存选项', '1. Edit SSH parameters and password storage')),
            ('2', tr('2. 测试 SSH 连接', '2. Test SSH connection')),
            ('3', tr('3. 保存 / 更新 SSH 密码', '3. Save / update SSH password')),
            ('4', tr('4. 清除已保存密码', '4. Remove saved password')),
            ('0', tr('0. 返回主菜单', '0. Back to main menu')),
        ],summary=ssh_summary(data))
        if choice == '0':return
        if choice == '1':
            run_action(edit_ssh)
        elif choice == '2':
            if verify_saved_ssh() == 'edit':run_action(edit_ssh)
        elif choice == '3':
            run_action(manage_saved_password)
        elif choice == '4':
            run_action(lambda: manage_saved_password(clear=True))
        else:
            print(tr('请输入 0 至 4。', 'Enter a number from 0 to 4.'))


def select_emblem():
    while True:
        current = prefs.load()['appearance']['emblem']
        options = [
            tr('1. 实心骷髅', '1. Solid skull'),
            tr('2. 翼纹徽章', '2. Winged insignia'),
            tr('3. 完整字标（建议拉宽终端）', '3. Full wordmark (wide terminal)'),
            tr('4. 线框骷髅', '4. Outline skull'),
            tr('5. 恢复原有自适应图案', '5. Restore original adaptive emblem'),
            tr('6. 启动动画：', '6. Startup animation: ')+tr('开启' if prefs.load()['appearance']['intro_animation'] else '关闭', 'on' if prefs.load()['appearance']['intro_animation'] else 'off'),
            tr('7. 显示模式：', '7. Layout: ')+tr('紧凑' if prefs.load()['appearance']['layout']=='compact' else '沉浸', 'compact' if prefs.load()['appearance']['layout']=='compact' else 'immersive'),
            tr('0. 返回', '0. Back'),
        ]
        print(tr('当前选择：', 'Current selection: ')+('5' if current=='current' else current))
        choice = select_option(tr('选择启动图案', 'CHOOSE STARTUP EMBLEM'), [(line[0], line) for line in options], '5' if current=='current' else current)
        if choice == '0':return
        if choice == '7':
            toggle_layout()
            continue
        if choice == '6':
            data = prefs.load()
            data['appearance']['intro_animation'] = not data['appearance']['intro_animation']
            prefs.save(data)
            continue
        if choice not in ['1', '2', '3', '4', '5']:
            print(tr('请输入 0 至 7。', 'Enter a number from 0 to 7.'))
            continue
        data = prefs.load()
        data['appearance']['emblem'] = 'current' if choice=='5' else choice
        prefs.save(data)
        banner()
        print(tr('图案已保存，下次启动自动沿用。', 'Emblem saved. It will be used on future launches.'))
        return


def run_action(action):
    try:
        return action() is not False
    except network_profile.ProfileError as error:
        print(i18n.text('network.error.'+error.code, LANG), flush=True)
    except subprocess.CalledProcessError as error:
        print(tr('操作未完成，退出码：', 'The operation failed. Exit code: ')+str(error.returncode), flush=True)
    except (RuntimeError, subprocess.TimeoutExpired, OSError, ValueError, KeyError) as error:
        print(tr('提示：', 'Notice: ')+localize(error), flush=True)
    return False


def collect_status():
    report=runtime_dependencies()
    if not report['ready'] or not prefs.load()['ssh_configured']:
        states={item['id']:item['state'] for item in report['items']}
        return {'time':time.strftime('%Y-%m-%d %H:%M:%S %z'),
                'runtime_dependencies':report,'fx_installed':states.get('fx')=='ready',
                'network_component_valid':states.get('gvproxy')=='ready',
                'proxy_available':None,'vm_available':None,'guest_checks':'unverified'}
    refresh_connection()
    reset_observation()
    network_mode = 'tun' if helper.tun_active() else 'proxy'
    data = {
        'runtime_dependencies':report,
        'time': time.strftime('%Y-%m-%d %H:%M:%S %z'),
        'fx_installed': Path(helper.APP).is_dir(),
        'proxy_available': helper.reachable(7890),
        'vm_available': helper.vm_reachable(),
        'network_component_valid': helper.GVPROXY.is_file() and helper.hashlib.sha256(helper.GVPROXY.read_bytes()).hexdigest() == helper.GVPROXY_SHA256,
        'network_mode': network_mode,
        'expected_launch': helper.required_launch(),
    }
    if data['vm_available']:
        helper.connect()
        data['guest'] = helper.state()
        observe_ssh(data['guest'])
    return data


def print_status(data):
    def row(zh, en, state):
        print('  '+status_label(state, tr(zh, en)))
    print(tr('\n环境检查（检查不会启动或关闭游戏）', '\nEnvironment check (leaves the game running or stopped as it is)'))
    if data.get('guest_checks')=='unverified':
        show_runtime_dependencies(data['runtime_dependencies'])
        print(i18n.text('runtime.guest_unknown',LANG))
        return
    row('FX 已安装', 'FX is installed', data['fx_installed'])
    row('代理端口 7890 可连接', 'Proxy port 7890 is reachable',
        data['proxy_available'] if data['proxy_available'] or data['vm_available'] else None)
    row('网络组件校验通过', 'Network component checksum matches', data['network_component_valid'])
    row('虚拟机已运行', 'VM is running', data['vm_available'] or None)
    s = data.get('guest')
    if not s:
        print('  '+status_label(None, tr('虚拟机未运行，其他项目暂不检查。', 'Start the VM to check the remaining items.')))
        return
    tun = data.get('network_mode') == 'tun'
    for zh, en, ok in [
        ('Vulkan 图形路径', 'Vulkan graphics backend', s['vulkan']),
        ('已验证的联机转发设置', 'Verified network forwarding settings', s['verified_network']),
        ('虚拟机使用 IPv4 配置', 'VM IPv4 settings', s['ipv4_only']),
        ('已保存游戏 Host HTTPS 代理', 'Saved game Host HTTPS proxy',
         'https_proxy=http://192.168.127.254:7890' in s['launch']),
        ('Steam HTTP 代理已关闭（TUN）' if tun else 'Steam 代理配置',
         'Steam HTTP proxy disabled (TUN)' if tun else 'Steam proxy settings',
         not (s.get('steam_proxy') or s.get('steam_proxy_config')) if tun else s['steam_proxy']),
        ('Steam 已登录', 'Steam is signed in', s['steam_logged_on']),
        ('已验证的 Proton-JE', 'Verified Proton-JE selected', s['tool'] == 'proton-je-11.0-20261014-3'),
        ('FEX 兼容组件', 'FEX compatibility component', s['fex'] == 'ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf'),
        ('Wine 系统组件版本一致', 'Wine system component versions match', s['wine_core'] == helper.WINE_CORE_SHA256 and s['ntdll'] == 'a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe'),
        ('已验证的完整启动项', 'Verified complete launch options',
         s['launch'].strip() == data.get('expected_launch',helper.WORKING_LAUNCH)),
    ]:
        row(zh, en, ok)
    game_state = True if s['game_pids'] else None
    print('  '+status_label(game_state, tr('游戏状态：', 'Game status: ')+tr('运行中' if s['game_pids'] else '未运行', 'running' if s['game_pids'] else 'stopped')))
    if LANG.startswith('zh'):
        passed, pending, failed = '通过', '需检查', '失败'
    else:
        passed, pending, failed = tr('通过','passed'), tr('需检查','needs checking'), tr('失败','failed')
    if color_enabled():
        legend = (paint('● '+passed, '38;5;114')+'   '+paint('● '+pending, '38;5;220')+
                  '   '+paint('● '+failed, '38;5;196'))
    else:
        legend = '● [OK] '+passed+'   ● [--] '+pending+'   ● [!!] '+failed
    print('  '+legend)
    print(tr('  [--] 表示需要检查；虚拟机尚未启动时属于正常情况。', '  [--] means an item needs attention; a stopped VM is normal before launch.'))


def check_environment():
    data=collect_status()
    if sys.stdin.isatty() and sys.stdout.isatty():
        import contextlib
        import io
        text=io.StringIO()
        with contextlib.redirect_stdout(text):print_status(data)
        ui2.show_text(i18n.text('home.check',LANG),text.getvalue(),LANG)
    else:print_status(data)


def installation_center():
    from types import SimpleNamespace
    return setup_guide.run(SimpleNamespace(root=ROOT,settings_file=prefs.path(),report_directory=None,
        ui2=ui2,i18n=i18n,language=LANG,ssh_settings=ssh_settings_menu,runtime_check=check_environment,
        choose=lambda title,rows,default='1',**options:ui2.choose_list(title,rows,default,LANG,**options)))


def status_json():
    # Preserve the established --status payload for configured, ready systems.
    if runtime_dependencies()['ready'] and prefs.load()['ssh_configured']:
        return helper.main()
    print(json.dumps(collect_status(),ensure_ascii=False,indent=2))


def export_report():
    data = collect_status()
    data['launcher_version']=ui2.launcher_version.get_version()
    if data.get('guest'):
        launch = data['guest'].pop('launch')
        data['guest']['launch_matches_verified'] = launch.strip() == data.get('expected_launch',helper.WORKING_LAUNCH)
        data['guest']['dx11_requested'] = '--use-d3d11' in launch
    directory = ROOT/'launcher-20261026/reports'
    directory.mkdir(exist_ok=True)
    path = directory/('environment-'+time.strftime('%Y%m%d-%H%M%S')+'-'+str(time.time_ns())+'.json')
    fd = os.open(path, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
    print(tr('诊断报告已保存：', 'Diagnostic report saved: ')+str(path))


def instructions():
    from types import SimpleNamespace
    context = SimpleNamespace(
        ui2=ui2,i18n=i18n,language=LANG,version=ui2.launcher_version,
        labels=home_labels,catalog=performance_browser.catalog,performance=performance_profile,
        updates=update_ui.checker,requirements=json.loads((ROOT/'runtime-requirements.json').read_text(encoding='utf-8')),
        choose=lambda title,rows,default='1',**presentation:ui2.choose_list(title,rows,default,LANG,**presentation))
    return help_center.run(context)


def choose_language():
    global LANG
    choices=[(str(index).zfill(2),str(index).zfill(2)+'  '+name) for index,(_,name) in enumerate(i18n.LANGUAGES,1)]
    choices.append(('0',i18n.text('language.back',LANG)))
    while True:
        current=i18n.normalize(LANG) or 'zh-CN'
        default=str(i18n.CODES.index(current)+1).zfill(2)
        choice=select_option(i18n.text('language.title',LANG),choices,default)
        if choice=='0':return False
        if choice=='':choice=default
        if choice.isdigit() and 1<=int(choice)<=len(i18n.LANGUAGES):
            LANG=i18n.CODES[int(choice)-1]
            data=prefs.load();data['appearance']['language']=LANG;prefs.save(data)
            return True
        bounds={'first':'01','last':str(len(i18n.CODES)).zfill(2)}
        message=i18n.text('language.invalid',LANG,**bounds)
        if current!='en':message+=' / '+i18n.text('language.invalid','en',**bounds)
        print(message)


def toggle_layout():
    data = prefs.load()
    data['appearance']['layout'] = 'compact' if data['appearance']['layout']=='immersive' else 'immersive'
    prefs.save(data)
    return data['appearance']


def home_labels():
    keys=['start','setup','check','report','folder','help','language','ssh','appearance','network','updates']
    return {str(index):i18n.text('home.'+key,LANG) for index,key in enumerate(keys,1)}


def network_state_path():
    return network_profile.settings_path(prefs.path())


def network_status():
    status = network_profile.inspect()
    conditions = network_profile.success_conditions()
    T = lambda key, **values: i18n.text('network.'+key, LANG, **values)
    lines = [T('route', device=status['default_interface'] or '—'),
             T('wired_yes' if status['wired_default'] else 'wired_no')]
    for wifi in status['wifi']:
        state = T('on' if wifi['on'] is True else 'off' if wifi['on'] is False else 'unknown')
        lines.append('Wi-Fi '+wifi['device']+': '+state)
    if not status['wifi']:
        lines.append(T('no_wifi'))
    lines += [T('proxy_yes' if status['proxy_available'] else 'proxy_no'),
              T('ready' if status['ready'] else 'not_ready')]
    value = lambda state: T('on' if state is True else 'off' if state is False else 'unknown')
    lines += [T('tun_state', state=value(conditions['tun_route'])),
              T('system_proxy_state', state=value(conditions['system_proxy'])),
              T('flclash_state', mode=conditions['flclash_mode'] or T('unknown'), lan=value(conditions['allow_lan'])),
              T('game_proxy'), T('node_manual')]
    columns=shutil.get_terminal_size((80,24)).columns
    panel(ui2.truncate(T('title'),max(1,columns-6)),
          [ui2.truncate(line,max(1,columns-4)) for line in lines])
    return status


def network_launch_notice():
    try:
        if not network_profile.load(network_state_path())['check_before_launch']:
            return
        status = network_profile.inspect()
        key = 'ready' if status['ready'] else 'preflight_warning'
        print(i18n.text('network.'+key, LANG))
    except network_profile.ProfileError as error:
        print(i18n.text('network.error.'+error.code, LANG))


def apply_network_profile():
    network_profile.apply(network_state_path())
    print(i18n.text('network.applied', LANG))


def restore_network_profile():
    changed = network_profile.restore(network_state_path())
    print(i18n.text('network.restored' if changed else 'network.no_backup', LANG))


def save_successful_network():
    snapshot=network_records.capture(helper,network_profile)
    path=network_records.save(snapshot,prefs.path())
    T=lambda key,**values:i18n.text('network.'+key,LANG,**values)
    print(T('snapshot_saved',path=str(path)))
    print(T('snapshot_scope'))
    print(T('snapshot_node',node=snapshot['flclash']['node_name'] or T('unknown')))
    if snapshot['guest']['status']!='available':print(T('guest_unavailable'))
    elif snapshot['guest']['saved_launch']['omitted']:print(T('launch_filtered'))
    return path


def check_steam_connection():
    T=lambda key,**values:i18n.text('network.'+key,LANG,**values)
    current=network_records.guest_snapshot(helper)
    if current['status']!='available':
        print(T('guest_unavailable'))
        return current
    steam=current['steam'];unknown=T('unknown')
    states={'Logged On':'steam_logged_on','Logged Off':'steam_logged_off','Connecting':'steam_connecting',
            'Connected':'steam_connected','Logging On':'steam_logging_on','Disconnected':'steam_disconnected',
            'stopped':'steam_stopped'}
    log_state=steam.get('log_state')
    state=T(states[log_state]) if log_state in states else unknown
    lines=[T('steam_process',state=T('on' if steam['running'] else 'off')),
           T('steam_log_state',state=state),
           T('steam_state_time',time=steam['last_state_at'] or unknown),
           T('steam_disconnect_time',time=steam['last_disconnect_at'] or unknown),
           T('steam_recovery_time',time=steam['last_recovery_at'] or unknown),
           T('steam_outage_duration',seconds=steam['outage_seconds'] if steam['outage_seconds'] is not None else unknown),
           T('steam_timezone',offset=steam['timezone_offset'] or unknown),T('steam_scope')]
    columns=shutil.get_terminal_size((80,24)).columns
    panel(ui2.truncate(T('steam_check'),max(1,columns-6)),
          [ui2.truncate(line,max(1,columns-4)) for line in lines])
    return current


def network_menu():
    while True:
        data = network_profile.load(network_state_path())
        enabled = i18n.text('network.on' if data['check_before_launch'] else 'network.off', LANG)
        choice = select_option(i18n.text('network.title',LANG), [
            ('1', '1. '+i18n.text('network.apply',LANG)),
            ('2', '2. '+i18n.text('network.inspect',LANG)),
            ('3', '3. '+i18n.text('network.restore',LANG)),
            ('4', '4. '+i18n.text('network.toggle',LANG, state=enabled)),
            ('5', '5. '+i18n.text('network.save_success',LANG)),
            ('6', '6. '+i18n.text('network.steam_check',LANG)),
            ('0', i18n.text('language.back',LANG)),
        ])
        if choice == '0':return
        if choice == '1':run_action(apply_network_profile)
        elif choice == '2':
            run_action(network_status)
            print(i18n.text('network.scope', LANG))
        elif choice == '3':run_action(restore_network_profile)
        elif choice == '4':
            network_profile.toggle_check(network_state_path())
            current = network_profile.load(network_state_path())['check_before_launch']
            print(i18n.text('network.toggle', LANG, state=i18n.text('network.on' if current else 'network.off', LANG)))
        elif choice == '5':run_action(save_successful_network)
        elif choice == '6':run_action(check_steam_connection)
        else:continue
        input(i18n.text('network.continue',LANG))


def _diagnostic_menu_context():
    from types import SimpleNamespace
    def observed_ssh():
        return ('ready' if OBSERVATION.get('endpoint')==endpoint_key() and
                OBSERVATION.get('ssh_at') is not None and
                time.monotonic()-OBSERVATION['ssh_at']<=STATUS_TTL else 'unchecked')
    return SimpleNamespace(helper=helper, ui2=ui2, LANG=LANG, select_option=select_option,
                           network_menu=network_menu, ui_observation=observed_ssh)


def menu():
    while True:
        choice = ui2.choose_home(LANG, prefs.load()['appearance'], home_labels(), dashboard_data(), toggle_layout,
                                 refresh_status=lambda language=LANG:refresh_dashboard(language))
        if choice == '0':
            return
        if choice == '7':
            choose_language()
            continue
        actions = {
            '1': launch_game,
            '2': browse_performance_profiles,
            '3': installation_center,
            '4': export_report,
            '5': lambda: subprocess.run(['open', str(ROOT)], check=True),
            '6': instructions,
            '8': ssh_settings_menu,
            '9': select_emblem,
            '10': lambda: network_diagnostics.run(_diagnostic_menu_context()),
            '11': check_updates,
        }
        if choice not in actions:
            print(i18n.text('home.invalid', LANG))
            continue
        run_action(actions[choice])
        input(tr('\n按回车返回菜单……', '\nPress Return to go back to the menu...'))


def configure_terminal_window():
    """Request the user's 101x30 size for this Apple Terminal window only."""
    if sys.platform!='darwin' or os.environ.get('TERM_PROGRAM')!='Apple_Terminal' or not sys.stdout.isatty():
        return False
    sys.stdout.write('\033[8;30;101t')
    sys.stdout.flush()
    return True


def run_cli(args):
    global LANG
    saved_language = prefs.load()['appearance']['language']
    LANG = i18n.initial_language(saved=saved_language,requested=args.lang)
    direct = {
        'launch': launch_game,
        'configure': lambda: launch_game(configure=True),
        'check': check_environment,
        'report': export_report,
        'status': status_json,
    }
    for name, action in direct.items():
        if getattr(args, name):
            return 0 if run_action(action) else 1
    configure_terminal_window()
    startup_animation()
    menu()
    return 0


def main():
    parser = argparse.ArgumentParser(description='Helldivers 2 FX launcher / 绝地潜兵 2 FX 启动助手')
    parser.add_argument('--lang', type=lambda code:i18n.normalize(code,strict=True), choices=i18n.CODES)
    group=parser.add_mutually_exclusive_group()
    for option in ['launch','configure','check','report','status']:
        group.add_argument('--'+option,action='store_true')
    args=parser.parse_args()
    # Explicit read-only CLI tools can coexist with the interactive launcher.
    if args.check or args.report or args.status:return run_cli(args)
    with launcher_instance.claim(prefs.path()) as acquired:
        if not acquired:
            language=i18n.initial_language(prefs.load()['appearance']['language'],args.lang)
            print(i18n.text('launcher.already_open',language))
            return 1
        return run_cli(args)


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (EOFError, KeyboardInterrupt):
        print(tr('\n已退出启动助手。', '\nLauncher closed.'))
    except (RuntimeError, ValueError, OSError) as error:
        print(tr('\n设置错误：', '\nSettings error: ')+localize(error))
        sys.exit(1)
