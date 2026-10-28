"""Validate/sync VERSION into README; never creates Git tags or releases."""
import argparse
import importlib.util
from pathlib import Path
import sys

ROOT=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location('release_version',ROOT/'launcher-20261026/launcher_version.py')
version_module=importlib.util.module_from_spec(spec);spec.loader.exec_module(version_module)
START='<!-- launcher-version:start -->'
END='<!-- launcher-version:end -->'


def readme_block(value):
    return (START+'\n**当前源码版本 / Current source version: `'+value+'`** · '
            '[VERSION](VERSION) · [CHANGELOG](CHANGELOG.md)\n'
            '源码技术预览；尚无完整安装包，版本号不代表已创建 GitHub Release。 / '
            'Source technical preview; no complete installer or GitHub Release is implied.\n'+END)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    group=parser.add_mutually_exclusive_group()
    group.add_argument('--check',action='store_true')
    group.add_argument('--set',metavar='SEMVER')
    args=parser.parse_args()
    current=version_module.get_version()
    value=args.set or current
    if not version_module.valid_version(value):
        print('VERSION must contain a valid MAJOR.MINOR.PATCH version, optionally with a prerelease suffix.',file=sys.stderr)
        return 2
    target=ROOT/'README.md';text=target.read_text(encoding='utf-8')
    if text.count(START)!=1 or text.count(END)!=1 or text.index(START)>text.index(END):
        print('README version markers are missing or invalid.',file=sys.stderr);return 2
    first=text.index(START);last=text.index(END)+len(END)
    updated=text[:first]+readme_block(value)+text[last:]
    if args.check:
        if text!=updated:print('README version is out of sync. Run tools/update_version.py.');return 1
        print('VERSION and README agree: '+value);return 0
    if args.set:(ROOT/'VERSION').write_text(value+'\n',encoding='utf-8')
    target.write_text(updated,encoding='utf-8')
    print('Updated README from VERSION: '+value)
    return 0


if __name__=='__main__':sys.exit(main())
