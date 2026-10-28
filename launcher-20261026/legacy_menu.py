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


def render_dashboard():
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
    panel(tr('环境状态', 'ENVIRONMENT STATUS'), [
        'FX: '+fx+'  |  SSH: '+ssh+'  |  Steam: '+steam,
        tr('代理: ', 'Proxy: ')+proxy+'  |  '+tr('游戏: ', 'Game: ')+game,
        age,
    ])


class LaunchProgress:
    NAMES = {
        'fx': ('等待 FX 就绪','Wait for FX'),
        'ssh': ('连接虚拟机','Connect to VM'),
        'environment': ('校验与准备环境','Check and prepare environment'),
        'steam': ('等待 Steam 就绪','Wait for Steam'),
        'game': ('启动游戏进程','Start game process'),
        'eac': ('检查本次 EAC 初始化','Check current EAC initialization'),
    }

    def __init__(self, configure=False):
        self.steps = list(self.NAMES)[:4] if configure else list(self.NAMES)
        self.active = None
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
        with self.lock:self.clear_line()

    def update(self, stage, status='running', detail=None):
        if stage not in self.steps:return
        with self.lock:
            self.clear_line()
            self.active = stage
            self.waiting = status == 'running'
            if status == 'running':self.started = time.monotonic()
            if self.dynamic and self.thread is None:
                self.thread = threading.Thread(target=self.animate,daemon=True)
                self.thread.start()
        label = tr(*self.NAMES[stage])
        if status == 'running':
            text = tr('进行中','working')
        elif status == 'done':
            text = tr('通过','passed')
        else:
            text = tr('未确认','unverified')
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
            print(tr('停在阶段：','Stopped at: ')+tr(*self.NAMES[self.active]))


def color_enabled():
    return sys.stdout.isatty() and os.environ.get('TERM') != 'dumb' and 'NO_COLOR' not in os.environ


def paint(text, code='38;5;220'):
    return '\033['+code+'m'+text+'\033[0m' if color_enabled() else text


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
        print(paint('  SUPER EARTH TERMINAL // STARTING INTERFACE', '1;38;5;220'))
        print(tr('  开场动画 · 任意键跳过 · 实际状态稍后检查', '  Visual intro · Any key skips · Status checks follow'))
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


def select_option(title, options, default='1', header=None):
    """Arrow-key navigation on a real terminal; retain line input for pipes/tests."""
    if not sys.stdin.isatty() or not sys.stdout.isatty() or os.environ.get('TERM') == 'dumb':
        if header:header()
        panel(title, [label for value, label in options])
        return prompt(tr('输入数字并按回车：', 'Enter a number and press Return: '))
    values = [value for value, label in options]
    index = values.index(default) if default in values else 0
    pending = ''
    lines = len(options)+6
    fd = sys.stdin.fileno()
    previous = termios.tcgetattr(fd)
    last_header = time.monotonic()

    def draw(first=False, refresh_header=False):
        nonlocal last_header
        if header and (first or refresh_header):
            header()
            last_header = time.monotonic()
        elif not first:
            print('\033['+str(lines)+'A\r\033[J', end='')
        highlight = '1;30;48;5;220' if int(time.monotonic()*2)%4 != 0 else '1;30;48;5;178'
        labels = [paint('☠ '+label, highlight) if i == index else '  '+label for i, (value, label) in enumerate(options)]
        panel(title, labels)
        print(paint(tr('  ↑/↓ 选择 · 回车确认 · Esc 返回 · 也可输入数字', '  ↑/↓ Select · Return Confirm · Esc Back · Numbers supported'), '38;5;245'))
        print('  ❯ '+pending, flush=True)

    try:
        tty.setcbreak(fd, termios.TCSANOW)
        print('\033[?25l', end='', flush=True)
        draw(True)
        last_pulse = int(time.monotonic()*2)
        while True:
            if not select.select([fd],[],[],.2)[0]:
                pulse = int(time.monotonic()*2)
                refresh_header = header is not None and time.monotonic()-last_header >= 2
                if (pulse != last_pulse and color_enabled()) or refresh_header:
                    draw(refresh_header=refresh_header)
                    last_pulse = pulse
                continue
            key = os.read(fd, 1)
            if key in [b'\r', b'\n']:
                return pending or values[index]
            if key == b'\x03':
                raise KeyboardInterrupt
            if key == b'\x1b':
                sequence = b''
                while select.select([fd], [], [], .08)[0]:
                    sequence += os.read(fd, 1)
                    if sequence[-1:].isalpha() or sequence.endswith(b'~'):
                        break
                if not sequence:
                    return '0' if '0' in values else ''
                if sequence in [b'[A', b'OA', b'[D', b'OD']:
                    index = (index-1) % len(options)
                elif sequence in [b'[B', b'OB', b'[C', b'OC']:
                    index = (index+1) % len(options)
                elif sequence in [b'[H', b'[1~']:
                    index = 0
                elif sequence in [b'[F', b'[4~']:
                    index = len(options)-1
                else:
                    continue
                pending = ''
            elif key in [b'\x7f', b'\x08']:
                pending = ''
            elif key == b'\x04':
                raise EOFError
            elif key in [bytes([n]) for n in range(48, 58)]:
                pending = key.decode()
                if pending in values:
                    index = values.index(pending)
            else:
                continue
            draw(refresh_header=header is not None and time.monotonic()-last_header >= 2)
    finally:
        termios.tcsetattr(fd, termios.TCSANOW, previous)
        print('\033[?25h', end='', flush=True)

MESSAGES = {
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
    return zh if LANG == 'zh' else en


def localize(message):
    if LANG == 'zh':
        translated = {
            'Keychain password could not be read. Please enter it manually.': '无法从钥匙串读取密码，请手动输入。',
            'SSH connected, but the password could not be saved in Keychain.': 'SSH 已连接，但未能将密码保存至钥匙串。',
            'SSH authentication failed. Check the username, password or key in SSH settings.': 'SSH 认证失败，请在 SSH 设置中检查用户名、密码或密钥。',
            'A password is required. Run the launcher in an interactive terminal.': '需要输入密码，请在交互式终端中打开启动助手。',
            'SSH connection is not ready.': 'SSH 连接尚未就绪。',
            'SSH connection timed out.': 'SSH 连接超时。',
            'The local Steam interface port is busy. Change it in SSH settings.': '本地 Steam 接口端口被占用，请在 SSH 设置中更换端口。',
            'The selected SSH private key does not exist.': '所选 SSH 私钥文件不存在。',
            'Enter a non-empty SSH password without newlines.': '请输入非空 SSH 密码，不能包含换行。',
        }
        return translated.get(str(message), str(message))
    return '\n'.join(MESSAGES.get(line, line).replace('虚拟机检查未通过：', 'VM check failed: ') for line in str(message).split('\n'))


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


def launch_game(configure=False):
    global ACTIVE_PROGRESS
    progress = LaunchProgress(configure)
    old_hook = helper.PROGRESS_HOOK
    ACTIVE_PROGRESS = progress
    helper.PROGRESS_HOOK = progress.update
    try:
        refresh_connection()
        helper.main(configure_only=configure)
    except (RuntimeError,OSError,ValueError,subprocess.SubprocessError):
        progress.failed()
        raise
    finally:
        progress.close()
        helper.PROGRESS_HOOK = old_hook
        ACTIVE_PROGRESS = None


def test_ssh_connection():
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


def ssh_settings_menu():
    while True:
        s = prefs.load()['ssh']
        print('\n  '+s['username']+' @ '+s['host']+' : '+str(s['port']))
        print(tr('  密码保存：', '  Password storage: ')+tr('允许使用钥匙串' if s['remember_password'] else '不保存', 'Keychain enabled' if s['remember_password'] else 'not saved'))
        choice = select_option(tr('SSH 连接设置', 'SSH CONNECTION SETTINGS'), [
            ('1', tr('1. 修改 SSH 参数与密码保存选项', '1. Edit SSH parameters and password storage')),
            ('2', tr('2. 测试 SSH 连接', '2. Test SSH connection')),
            ('3', tr('3. 保存 / 更新 SSH 密码', '3. Save / update SSH password')),
            ('4', tr('4. 清除已保存密码', '4. Remove saved password')),
            ('0', tr('0. 返回主菜单', '0. Back to main menu')),
        ])
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
            tr('0. 返回，不修改', '0. Back without changing'),
        ]
        print(tr('当前选择：', 'Current selection: ')+('5' if current=='current' else current))
        choice = select_option(tr('选择启动图案', 'CHOOSE STARTUP EMBLEM'), [(line[0], line) for line in options], '5' if current=='current' else current)
        if choice == '0':return
        if choice == '6':
            data = prefs.load()
            data['appearance']['intro_animation'] = not data['appearance']['intro_animation']
            prefs.save(data)
            continue
        if choice not in ['1', '2', '3', '4', '5']:
            print(tr('请输入 0 至 6。', 'Enter a number from 0 to 6.'))
            continue
        data = prefs.load()
        data['appearance']['emblem'] = 'current' if choice=='5' else choice
        prefs.save(data)
        banner()
        print(tr('图案已保存，下次启动自动沿用。', 'Emblem saved. It will be used on future launches.'))
        return


def run_action(action):
    try:
        action()
        return True
    except subprocess.CalledProcessError as error:
        print(tr('操作未完成，退出码：', 'The operation failed. Exit code: ')+str(error.returncode), flush=True)
    except (RuntimeError, subprocess.TimeoutExpired, OSError, ValueError, KeyError) as error:
        print(tr('提示：', 'Notice: ')+localize(error), flush=True)
    return False


def collect_status():
    refresh_connection()
    reset_observation()
    data = {
        'time': time.strftime('%Y-%m-%d %H:%M:%S %z'),
        'fx_installed': Path(helper.APP).is_dir(),
        'proxy_available': helper.reachable(7890),
        'vm_available': helper.vm_reachable(),
        'network_component_valid': helper.GVPROXY.is_file() and helper.hashlib.sha256(helper.GVPROXY.read_bytes()).hexdigest() == helper.GVPROXY_SHA256,
    }
    if data['vm_available']:
        helper.connect()
        data['guest'] = helper.state()
        observe_ssh(data['guest'])
    return data


def print_status(data):
    def row(zh, en, ok):
        print(('  [OK] ' if ok else '  [--] ')+tr(zh, en))
    print(tr('\n环境检查（检查不会启动或关闭游戏）', '\nEnvironment check (leaves the game running or stopped as it is)'))
    row('FX 已安装', 'FX is installed', data['fx_installed'])
    row('代理端口 7890 可连接', 'Proxy port 7890 is reachable', data['proxy_available'])
    row('网络组件校验通过', 'Network component checksum matches', data['network_component_valid'])
    row('虚拟机已运行', 'VM is running', data['vm_available'])
    s = data.get('guest')
    if not s:
        print(tr('  虚拟机未运行，其他项目暂不检查。', '  Start the VM to check the remaining items.'))
        return
    for zh, en, ok in [
        ('Vulkan 图形路径', 'Vulkan graphics backend', s['vulkan']),
        ('已验证的联机转发设置', 'Verified network forwarding settings', s['verified_network']),
        ('虚拟机使用 IPv4 配置', 'VM IPv4 settings', s['ipv4_only']),
        ('Steam 代理配置', 'Steam proxy settings', s['steam_proxy']),
        ('Steam 已登录', 'Steam is signed in', s['steam_logged_on']),
        ('已验证的 Proton-JE', 'Verified Proton-JE selected', s['tool'] == 'proton-je-11.0-20261014-3'),
        ('FEX 兼容组件', 'FEX compatibility component', s['fex'] == 'ce93cadae7b7d3ef01376ba2acd58aedb602a7fc077e49592179766d13c294bf'),
        ('Wine 系统组件版本一致', 'Wine system component versions match', s['wine_core'] == helper.WINE_CORE_SHA256 and s['ntdll'] == 'a699b73899f8a3ae464dd5ee237dd1f1f1587287a0941fbab5934698d633cbfe'),
        ('已验证的完整启动项', 'Verified complete launch options', s['launch'].strip() == helper.WORKING_LAUNCH),
    ]:
        row(zh, en, ok)
    print(tr('  游戏状态：', '  Game status: ')+tr('运行中' if s['game_pids'] else '未运行', 'running' if s['game_pids'] else 'stopped'))
    print(tr('  [--] 表示需要检查；虚拟机尚未启动时属于正常情况。', '  [--] means an item needs attention; a stopped VM is normal before launch.'))


def check_environment():
    print_status(collect_status())


def export_report():
    data = collect_status()
    if data.get('guest'):
        launch = data['guest'].pop('launch')
        data['guest']['launch_matches_verified'] = launch.strip() == helper.WORKING_LAUNCH
        data['guest']['dx11_requested'] = '--use-d3d11' in launch
    directory = ROOT/'launcher-20261026/reports'
    directory.mkdir(exist_ok=True)
    path = directory/('environment-'+time.strftime('%Y%m%d-%H%M%S')+'-'+str(time.time_ns())+'.json')
    fd = os.open(path, os.O_WRONLY|os.O_CREAT|os.O_EXCL, 0o600)
    with os.fdopen(fd, 'w') as stream:
        json.dump(data, stream, ensure_ascii=False, indent=2)
    print(tr('诊断报告已保存：', 'Diagnostic report saved: ')+str(path))


def instructions():
    print(tr('''
使用说明
1. 日常使用选 1；已有的游戏启动参数会保留。
2. 首次配置或启动参数改乱时选 2：检查现有 FX/FEX/Proton-JE，准备 IPv4、代理和 Steam 网络，备份并保存已验证的 D3D12 启动项。
   配置只准备环境，不会启动游戏。必要时会重启 Steam；游戏或安装步骤运行中会停止配置。
   FX 未运行时自动使用已验证参数启动；如果现有 FX 模式不一致，请先正常退出 FX 再配置。
3. 选 3 检查环境；选 4 导出报告；选 5 打开启动入口所在文件夹。
4. 组件版本不匹配时会提示修复，不会自动下载或替换兼容工具。
5. 若提示无法自动切换窗口，手动切换到 FX 即可。驱动提示选择“继续”。
6. 菜单 8 可修改 SSH、测试连接、保存/更新或清除钥匙串密码；菜单 9 选择四款图案。首次配置后不再重复引导。
7. 使用 ↑/↓ 选择、回车确认、Esc 返回，或输入数字后按回车。密码可选存入 macOS 钥匙串，不写入配置文件。
备份：launcher-20261026/backups；报告：launcher-20261026/reports。
''', '''
Instructions
1. Use option 1 for normal launches. It preserves your current game launch options.
2. Use option 2 for initial setup or to restore launch options: check the installed FX/FEX/Proton-JE, prepare IPv4, the proxy and Steam networking, then back up and save the verified D3D12 launch options.
   Setup does not start the game. Steam may restart if needed. Setup refuses to run while a game or installation step is active.
   If FX is stopped, it starts with the verified settings. If a running FX uses different settings, quit FX normally before setup.
3. Option 3 checks the environment; 4 exports a report; 5 opens the launcher folder.
4. A component version mismatch requires repair. Setup does not download or replace compatibility tools.
5. If automatic window switching fails, switch to FX manually. Choose Continue for the driver warning.
6. Menu 8 edits SSH settings, tests connections, and saves/removes Keychain passwords. Menu 9 selects an emblem. Initial setup runs only once.
7. Use ↑/↓, Return and Esc, or enter a number and press Return. Optional password storage uses macOS Keychain, never the settings file.
Backups: launcher-20261026/backups. Reports: launcher-20261026/reports.
'''))


def choose_language():
    global LANG
    while True:
        banner()
        choice = select_option('语言 / LANGUAGE', [('1','1. 中文'), ('2','2. English'), ('0','0. 退出 / Exit')])
        if choice in ('', '1', '2'):
            LANG = 'en' if choice == '2' else 'zh'
            return True
        if choice == '0':
            return False
        print('请输入 0、1 或 2 / Enter 0, 1, or 2.')


def menu():
    while True:
        def home_header():
            banner(reserve_rows=23)
            render_dashboard()
        items = [
            tr('1. 启动游戏', '1. Start game'),
            tr('2. 一键环境配置（不启动游戏）', '2. Set up environment (without starting the game)'),
            tr('3. 检查环境与网络', '3. Check environment and network'),
            tr('4. 导出诊断报告', '4. Export diagnostic report'),
            tr('5. 打开启动文件夹', '5. Open launcher folder'),
            tr('6. 使用说明', '6. Instructions'),
            tr('7. 切换语言 / Change language', '7. Change language / 切换语言'),
            tr('8. 修改 SSH 设置 / 测试连接', '8. Edit SSH settings / Test connection'),
            tr('9. 选择启动图案', '9. Choose startup emblem'),
            tr('0. 退出', '0. Exit'),
        ]
        choice = select_option(tr('绝地潜兵 2 · FX 启动助手', 'Helldivers 2 · FX Launcher'), [(line[0], line) for line in items],header=home_header)
        if choice == '0':
            return
        if choice == '7':
            if not choose_language():return
            continue
        actions = {
            '1': launch_game,
            '2': lambda: launch_game(configure=True),
            '3': check_environment,
            '4': export_report,
            '5': lambda: subprocess.run(['open', str(ROOT)], check=True),
            '6': instructions,
            '8': ssh_settings_menu,
            '9': select_emblem,
        }
        if choice not in actions:
            print(tr('请输入 0 至 9。', 'Enter a number from 0 to 9.'))
            continue
        if choice == '2':
            print(tr('将备份并恢复已验证的 D3D12 启动项，准备网络环境；必要时重启 Steam。', 'This backs up and restores the verified D3D12 launch options and prepares networking. Steam may restart if needed.'))
        run_action(actions[choice])
        input(tr('\n按回车返回菜单……', '\nPress Return to go back to the menu...'))


def main():
    global LANG
    parser = argparse.ArgumentParser(description='Helldivers 2 FX launcher / 绝地潜兵 2 FX 启动助手')
    parser.add_argument('--lang', choices=['zh', 'en'])
    group = parser.add_mutually_exclusive_group()
    for option in ['launch', 'configure', 'check', 'report', 'status']:
        group.add_argument('--'+option, action='store_true')
    args = parser.parse_args()
    LANG = args.lang or 'zh'
    if any(getattr(args, name) for name in ['launch', 'configure', 'check', 'report', 'status']) and not prefs.load()['ssh_configured']:
        print(tr('首次使用请先不带参数运行脚本，完成 SSH 配置。', 'First run: open the launcher without action flags to set up SSH.'))
        return 1
    direct = {
        'launch': launch_game,
        'configure': lambda: launch_game(configure=True),
        'check': check_environment,
        'report': export_report,
        'status': helper.main,
    }
    for name, action in direct.items():
        if getattr(args, name):
            return 0 if run_action(action) else 1
    startup_animation()
    if args.lang or choose_language():
        if not prefs.load()['ssh_configured']:
            if not edit_ssh(first_run=True):return 0
        menu()
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (EOFError, KeyboardInterrupt):
        print(tr('\n已退出启动助手。', '\nLauncher closed.'))
    except (RuntimeError, ValueError, OSError) as error:
        print(tr('\n设置错误：', '\nSettings error: ')+localize(error))
        sys.exit(1)
