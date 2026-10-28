"""Local-only prerequisite check: exit 2 blocks the UI, exit 3 allows limited mode."""
import argparse
import importlib.util
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parent.parent


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-only',action='store_true')
    args=parser.parse_args()
    module_path=ROOT/'launcher-20261026/dependencies.py'
    if not module_path.is_file():
        print('Launcher file missing / 启动器文件缺失：launcher-20261026/dependencies.py')
        print('Download and extract the whole ZIP again / 请重新下载并解压整个 ZIP。')
        return 2
    try:
        spec=importlib.util.spec_from_file_location('launcher_dependencies',module_path)
        dependencies=importlib.util.module_from_spec(spec);spec.loader.exec_module(dependencies)
        problems=dependencies.launcher_problems(ROOT)
    except (OSError,ValueError,SyntaxError,ImportError):
        print('Launcher files cannot be loaded / 启动器文件无法读取，请重新解压完整 ZIP。')
        return 2
    if problems:
        print('Launcher prerequisites missing or invalid / 启动器基础文件缺失或损坏：')
        for name in problems:print('  - '+name)
        print('Download and extract the whole ZIP again / 请重新下载并解压整个 ZIP。')
        return 2
    print('Launcher prerequisites ready / 启动器基础依赖已就绪。')
    if args.base_only:return 0
    report=dependencies.inspect_runtime(root=ROOT)
    names={'fx':'Compatible FX application / 匹配的 FX 应用',
           'gvproxy':'Required virtual-machine network component / 虚拟机网络组件',
           'node':'Node.js','ssh':'SSH','bridge':'Steam control script / Steam 控制脚本',
           'steam':'Guest Steam','fex':'Guest FEX','proton':'Guest Proton/Wine'}
    for row in report['items']:print('['+row['state']+'] '+names[row['id']])
    if not report['ready']:
        print('Limited mode is available / 可以进入受限模式。')
        print('Installation instructions / 安装说明：docs/DEPENDENCIES.md')
    print('Guest components, EAC and multiplayer remain unverified / Guest 组件、EAC 与联机仍未验证。')
    return 0 if report['ready'] else 3


if __name__=='__main__':sys.exit(main())
