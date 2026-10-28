#!/bin/bash
# Python and Node.js only. No VM, SSH, Steam or game operations.
HD2_SETUP_ROOT=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd) || exit 2
. "$HD2_SETUP_ROOT/tools/runtime_paths.sh" || exit 2

hd2_platform_supported() {
    [ "$(uname -s)" = Darwin ] && [ "$(uname -m)" = arm64 ]
}

hd2_find_brew() {
    if [ -x /opt/homebrew/bin/brew ]; then printf '%s\n' /opt/homebrew/bin/brew
    else command -v brew 2>/dev/null
    fi
}

hd2_check_tools() {
    HD2_SETUP_PYTHON=$(hd2_find_python) || HD2_SETUP_PYTHON=''
    HD2_SETUP_NODE=$(hd2_find_node) || HD2_SETUP_NODE=''
    HD2_SETUP_NEED_PYTHON=1
    HD2_SETUP_NEED_NODE=1
    if [ -n "$HD2_SETUP_PYTHON" ]; then
        HD2_SETUP_NEED_PYTHON=0
        printf '[OK] Python: %s\n' "$HD2_SETUP_PYTHON"
        "$HD2_SETUP_PYTHON" --version
    else printf '[NEEDED / 需要准备] Python >= 3.9\n'
    fi
    if [ -n "$HD2_SETUP_NODE" ]; then
        printf 'Node.js: %s\n' "$HD2_SETUP_NODE"
        if "$HD2_SETUP_NODE" "$HD2_SETUP_ROOT/tools/check_node.cjs"; then HD2_SETUP_NEED_NODE=0; fi
    else printf '[NEEDED / 需要准备] Node.js >= 22 with fetch + WebSocket\n'
    fi
    [ "$HD2_SETUP_NEED_PYTHON" -eq 0 ] && [ "$HD2_SETUP_NEED_NODE" -eq 0 ]
}

hd2_official_options() {
    printf '\nHomebrew not available. Choose a method / 没有 Homebrew，请选择方式：\n'
    printf '1. Homebrew official instructions / 查看 Homebrew 官方安装说明\n'
    printf '2. Official Python/Node installers / 使用 Python、Node 官方安装包\n'
    printf '0. Cancel / 取消\n> '
    local choice=''
    IFS= read -r choice || choice=0
    case "$choice" in
        1) printf 'https://brew.sh/\nhttps://docs.brew.sh/Installation\nInstall Homebrew yourself, then rerun this script.\n请自行阅读并确认安装 Homebrew，然后重新运行本脚本。\n' ;;
        2) printf 'Choose macOS / Apple Silicon installers / 选择 macOS / Apple Silicon 安装包。\n'
           [ "$HD2_SETUP_NEED_PYTHON" -eq 0 ] || printf 'Python: https://www.python.org/downloads/macos/\n'
           [ "$HD2_SETUP_NEED_NODE" -eq 0 ] || printf 'Node.js LTS: https://nodejs.org/en/download\n'
           printf 'After installation, rerun with --check / 安装完成后使用 --check 重新检查。\n' ;;
        *) printf 'No installation performed / 未执行安装。\n' ;;
    esac
    return 2
}

hd2_install_main() {
    local mode="${1:-}" brew_path='' prefix='' answer='' result=0
    local -a packages
    packages=()
    case "$mode" in ''|--check) ;; --help)
        printf 'Usage: bash tools/install_dependencies.sh [--check]\nPython >= 3.9; Node.js >= 22 + fetch + WebSocket.\nDefault: inspect, ask, then install missing tools using existing native Homebrew.\n默认先检查，再确认，仅通过已有 Homebrew 安装缺失工具；--check 只检查。\n'
        return 0 ;; *) printf 'Unknown option / 未知参数：%s\n' "$mode";return 2 ;;
    esac
    if ! hd2_platform_supported; then
        printf 'Use a native arm64 Terminal on an Apple Silicon Mac.\n请在 Apple Silicon Mac 上使用原生 arm64 终端；本脚本不支持 Rosetta / Intel / Linux。\n'
        return 2
    fi
    if [ ! -r "$HD2_SETUP_ROOT/tools/check_node.cjs" ]; then
        printf 'Project probe missing; extract the complete ZIP / 检查脚本缺失，请重新解压完整 ZIP。\n'
        return 2
    fi
    hd2_setup_paths
    printf 'Checking only Python and Node.js / 仅检查 Python 与 Node.js。\n'
    if hd2_check_tools; then
        printf 'Both requirements satisfied; skipped installation.\n两项均满足要求，已跳过安装。\n'
        return 0
    fi
    [ "$mode" != --check ] || return 2
    brew_path=$(hd2_find_brew) || brew_path=''
    if [ -z "$brew_path" ]; then hd2_official_options;return $?;fi
    prefix=$("$brew_path" --prefix) || return 2
    if [ "$prefix" != /opt/homebrew ]; then
        printf 'Expected native Homebrew at /opt/homebrew; use the official installers instead.\n现有 Homebrew 不是标准原生路径 /opt/homebrew，请使用官方安装包，不自动修改其安装位置。\n'
        return 2
    fi
    [ "$HD2_SETUP_NEED_PYTHON" -eq 0 ] || packages+=(python@3.14)
    [ "$HD2_SETUP_NEED_NODE" -eq 0 ] || packages+=(node@24)
    printf '\nInstall missing/unsuitable tools and their Homebrew dependencies / 安装缺失或不满足条件的工具及其 Homebrew 依赖：\n'
    printf '  %s\n' "${packages[@]}"
    printf 'Already suitable tools are skipped. Continue? [y/N]\n已满足要求的工具不会重复安装。是否继续？[y/N]\n> '
    IFS= read -r answer || answer=''
    case "$answer" in y|Y|yes|YES) ;; *) printf 'Cancelled; nothing installed / 已取消，未安装。\n';return 2;; esac
    HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 "$brew_path" install "${packages[@]}" || result=1
    hash -r
    hd2_setup_paths
    printf '\nRechecking using the launcher path rules / 按启动器相同路径规则重新检测：\n'
    hd2_check_tools || result=1
    if [ "$result" -eq 0 ]; then
        printf 'Verified. Start.command will use Python: %s\n' "$HD2_SETUP_PYTHON"
        printf '检查通过。可以重新双击 Start.command；这不代表游戏运行环境已经就绪。\n'
    else
        printf 'Checks failed. Review the output; do not repeatedly reinstall.\n检查未通过，请查看路径、版本及错误，不要反复重装。见 docs/AI_INSTALL.md。\n'
    fi
    return "$result"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then hd2_install_main "$@";exit $?;fi
