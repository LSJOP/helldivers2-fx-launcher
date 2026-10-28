#!/bin/zsh
# English and Chinese shortcuts share this one entry point.
emulate -L zsh
cd -- "${0:A:h}" || exit 1
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

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
    print 'Options / 参数：--check-local  (local checks only / 仅本地检查)'
    exit 0
fi

print 'HELLDIVERS 2 · Start / 启动'
print 'Checking required files / 正在检查所需文件…'
print ''

launcher_python=''
for candidate in "$(command -v python3 2>/dev/null)" /opt/homebrew/bin/python3 /usr/local/bin/python3 /usr/bin/python3; do
    if [[ -n "$candidate" && -x "$candidate" ]] && "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' >/dev/null 2>&1; then
        launcher_python="$candidate"
        break
    fi
done

if [[ -z "$launcher_python" ]]; then
    print 'Python 3.9 or newer is needed. Install Python for macOS, then open this file again.'
    print '需要 Python 3.9 或更新版本。请先安装 macOS 版 Python，然后重新打开此文件。'
    print 'https://www.python.org/downloads/macos/'
    pause_before_closing
    exit 2
fi

"$launcher_python" tools/check_dependencies.py
launcher_result=$?
if [[ $launcher_result -ne 0 ]]; then
    pause_before_closing
    exit "$launcher_result"
fi

if [[ "${1:-}" == '--check-local' ]]; then
    print 'Local checks finished. Guest and game are not verified.'
    print '本地检查已完成，虚拟机内部和游戏状态仍未验证。'
    exit 0
fi

print ''
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
