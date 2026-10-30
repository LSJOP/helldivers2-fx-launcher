#!/bin/zsh
# English and Chinese shortcuts share this one entry point.
emulate -L zsh
cd -- "${0:A:h}" || exit 1
if [[ ! -r tools/runtime_paths.sh ]]; then
    print 'Launcher file missing / 启动器文件缺失：tools/runtime_paths.sh'
    exit 2
fi
source tools/runtime_paths.sh
hd2_setup_paths

pause_before_closing() {
    if [[ -t 0 ]]; then
        print ''
        read -r '?Press Return to close / 按回车关闭：'
    fi
}

if [[ "${1:-}" == '--help' ]]; then
    print 'HELLDIVERS 2 · Start / 启动'
    print 'Double-click Start.command to check this Mac and open the launcher.'
    print '双击 Start.command 或 启动绝地潜兵2.command，先检查依赖，再打开启动器。'
    print 'Keep this folder intact. Read README.md for the setup guide.'
    print '请保留完整文件夹，安装步骤请看 README.md。'
    print 'Options / 参数：--check-local; --setup-check (static checklist / 静态清单); --setup-report (export / 导出)'
    exit 0
fi

print 'HELLDIVERS 2 · Start / 启动'
print 'Checking required files / 正在检查所需文件…'
print ''

launcher_python=$(hd2_find_python) || launcher_python=''

show_setup_commands() {
    print 'From any folder, copy the following command / 可从任意目录复制以下命令：'
    printf '  /bin/bash %q --check\n' "$PWD/tools/install_dependencies.sh"
    print 'To prepare missing tools after confirmation / 经确认准备缺失工具：'
    printf '  /bin/bash %q\n' "$PWD/tools/install_dependencies.sh"
    print 'Uses existing Homebrew only after confirmation; no Homebrew is installed automatically.'
    print '仅经确认使用已有 Homebrew；不会自动安装 Homebrew 或修改系统环境变量。'
    print 'Python: https://www.python.org/downloads/macos/'
    print 'Node.js: https://nodejs.org/en/download'
    print 'Guide / 指引：docs/SETUP.md'
}

if [[ -z "$launcher_python" ]]; then
    print 'Python 3.9 or newer is needed. Install Python for macOS, then open this file again.'
    print '需要 Python 3.9 或更新版本。请先安装 macOS 版 Python，然后重新打开此文件。'
    show_setup_commands
    pause_before_closing
    exit 2
fi

if [[ "${1:-}" == '--setup-check' || "${1:-}" == '--setup-report' ]]; then
    "$launcher_python" tools/check_dependencies.py --base-only || exit $?
    if [[ "${1:-}" == '--setup-report' ]]; then
        "$launcher_python" launcher-20261026/setup_guide.py --report
    else
        "$launcher_python" launcher-20261026/setup_guide.py
    fi
    exit $?
fi

if [[ "${1:-}" == '--check-local' ]]; then
    "$launcher_python" tools/check_dependencies.py
    exit $?
fi

"$launcher_python" tools/check_dependencies.py --base-only
launcher_result=$?
if [[ $launcher_result -ne 0 ]]; then
    pause_before_closing
    exit "$launcher_result"
fi

print ''
# Node is a runtime tool, never a prerequisite for the local UI.
launcher_node=$(hd2_find_node) || launcher_node=''
if [[ -z "$launcher_node" ]] || ! "$launcher_python" -c 'import subprocess,sys
try:
    sys.exit(subprocess.run(sys.argv[1:],capture_output=True,timeout=5).returncode)
except (OSError,subprocess.SubprocessError):sys.exit(2)' "$launcher_node" tools/check_node.cjs; then
    print 'Node.js is missing or unsuitable (>=22 + fetch/WebSocket); menus remain available.'
    print 'Node.js 缺失或不满足条件（>=22 + fetch/WebSocket）；仍可进入受限模式。'
    show_setup_commands
fi
print 'New device? Open [3] for read-only checks and installation guidance.'
print '新设备请在 [3] 打开只读检查与安装指引；不会自动安装或连接 Guest。'
print 'Opening the launcher menu / 正在打开启动器菜单…'
"$launcher_python" launcher-20261026/menu.py "$@"
launcher_result=$?
if [[ $launcher_result -ne 0 ]]; then
    print ''
    print 'Please keep the error above when asking for help. Remove account details and passwords.'
    print '求助时请保留上方错误文字，并遮住账号、密码等个人信息。'
    pause_before_closing
fi
exit "$launcher_result"
