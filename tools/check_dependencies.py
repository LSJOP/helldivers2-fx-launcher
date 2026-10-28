"""Beginner-friendly local checks. Never connects to SSH or opens applications."""
import hashlib
import json
import platform
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent


def notice(ready, english, chinese):
    label = 'OK / 已就绪' if ready else 'NEEDED / 需要准备'
    print('['+label+'] '+english+' / '+chinese)


def node_ready():
    candidates = [shutil.which('node'), '/opt/homebrew/bin/node', '/usr/local/bin/node',
                  str(Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node')]
    for candidate in candidates:
        if not candidate or not Path(candidate).is_file():
            continue
        try:
            result = subprocess.run(
                [str(candidate), '-e',
                 "process.exit(typeof fetch === 'function' && typeof WebSocket === 'function' ? 0 : 1)"],
                capture_output=True, timeout=5)
        except (OSError, subprocess.SubprocessError):
            return False
        # Match the backend: it also uses the first existing Node candidate.
        return result.returncode == 0
    return False


def main():
    try:
        data = json.loads((ROOT/'runtime-requirements.json').read_text(encoding='utf-8'))
    except (OSError, ValueError):
        print('Some project files are missing. Download and extract the whole ZIP again.')
        print('项目文件缺失或损坏。请重新下载并解压完整 ZIP 文件。')
        return 2
    ready = True
    host_ok = platform.system() == 'Darwin' and platform.machine() in ('arm64', 'aarch64')
    notice(host_ok, 'Mac with Apple silicon (M-series chip)', '搭载 Apple 芯片的 Mac（M 系列）')
    ready = host_ok and ready
    python_ok = sys.version_info >= (3, 9)
    notice(python_ok, 'Python 3.9 or newer', 'Python 3.9 或更新版本')
    ready = python_ok and ready
    node_ok = node_ready()
    notice(node_ok, 'Node.js with the required features', '具备所需功能的 Node.js')
    if not node_ok:
        print('  Install Node.js for macOS / 安装 macOS 版 Node.js：https://nodejs.org/en/download')
    ready = node_ok and ready
    ssh_ok = bool(shutil.which('ssh'))
    notice(ssh_ok, 'macOS SSH connection tool', 'macOS SSH 连接工具')
    ready = ssh_ok and ready
    files_ok = True
    names = {'FX steamac-vm': ('Compatible FX application', '匹配的 FX 应用'),
             'gvproxy-eim': ('Required virtual-machine network component', '所需的虚拟机网络组件')}
    for item in data['components']:
        if 'path' not in item:
            continue
        path = ROOT/item['path']
        try:
            ok = path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256']
        except OSError:
            ok = False
        notice(ok, *names.get(item['name'], (item['name'], item['name'])))
        files_ok = files_ok and ok
    ready = files_ok and ready
    if not files_ok:
        print('')
        print('The full compatibility package is not available in this download yet.')
        print('完整兼容组件包目前尚未提供下载。')
        print('For a first-time installation, wait for the complete setup release.')
        print('如果你是第一次安装，请等待完整安装版本。')
        print('An ordinary FX installation alone does not satisfy these checks.')
        print('只安装普通 FX 还不能通过这些检查。')
    print('')
    print('Next steps: read README.md in this folder.')
    print('下一步：打开本文件夹中的 README.md，按对应说明操作。')
    print('These checks do not verify Steam, guest compatibility components, EAC or multiplayer.')
    print('本次检查不验证 Steam、虚拟机内的兼容组件、EAC 或联机状态。')
    return 0 if ready else 2


if __name__ == '__main__':
    sys.exit(main())
