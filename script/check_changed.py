#!/usr/bin/env python3
"""Select conservative checks for changes relative to a Git base.

Usage: python3 script/check_changed.py [BASE] [--run]
Includes committed, staged, unstaged and untracked paths. Selection is a floor:
reviewers must add live acceptance and semantic checks appropriate to the task.
"""
import subprocess
import sys


def git(*args):
    return subprocess.check_output(['git', *args])


def changed(base):
    paths = set()
    for args in (('diff', '--name-only', '-z', base, '--'),
                 ('ls-files', '--others', '--exclude-standard', '-z')):
        paths.update(p.decode('utf-8', 'surrogateescape') for p in git(*args).split(b'\0') if p)
    return paths


def select(paths):
    checks = {('git', 'diff', '--check'), ('git', 'diff', '--cached', '--check')}
    notes = set()
    for path in paths:
        if path.startswith(('README', 'CHANGELOG', 'docs/')):
            checks.add(('python3', 'script/check_docs.py'))
            notes.add('Review bilingual content and screenshot provenance when affected.')
        elif path.startswith(('native-app/Localization/', 'native-app/Resources/native-locales.json')):
            checks.update({('python3', 'native-app/script/check_localization.py'),
                           ('python3', 'native-app/checks/localization_checks.py')})
            notes.add('Review translation quality and dynamic strings manually.')
        elif path.startswith('native-app/'):
            checks.add(('bash', 'native-app/script/run_checks.sh'))
            notes.add('Review affected build, UI, security and real-environment acceptance requirements.')
        elif path.startswith('script/') or path == 'AGENTS.md':
            notes.add('Run focused tests for changed development tooling and review rules.')
        else:
            notes.add('Unclassified path: select and run appropriate checks manually.')
    return sorted(checks), sorted(notes)


def main():
    args = sys.argv[1:]
    run = '--run' in args
    args = [a for a in args if a != '--run']
    if len(args) > 1:
        raise SystemExit('Usage: check_changed.py [BASE] [--run]')
    base = args[0] if args else 'origin/main'
    paths = changed(base)
    print(f'Base: {base}; changed paths: {len(paths)}', flush=True)
    for path in sorted(paths):
        print(' ', path, flush=True)
    checks, notes = select(paths)
    for note in notes:
        print('REVIEW:', note, flush=True)
    for command in checks:
        print(('RUN: ' if run else 'CHECK: ') + ' '.join(command), flush=True)
        if run:
            subprocess.run(command, check=True)
    print('Selection is not proof of acceptance; add task-specific tests and live checks.', flush=True)


if __name__ == '__main__':
    main()
