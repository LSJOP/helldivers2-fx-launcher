#!/usr/bin/env python3
"""Select conservative checks for changes relative to a Git base.

Usage: python3 script/check_changed.py [BASE] [--run] [--release]
Includes committed, staged, unstaged and untracked paths. Selection is a floor:
reviewers must add live acceptance and semantic checks appropriate to the task.
"""
import subprocess
import sys


def git(*args):
    return subprocess.check_output(['git', *args])


def changed(base):
    paths = set()
    for args in (('diff', '--name-only', '-z', base, 'HEAD', '--'),
                 ('diff', '--name-only', '-z', '--cached', '--'),
                 ('diff', '--name-only', '-z', '--'),
                 ('ls-files', '--others', '--exclude-standard', '-z')):
        paths.update(p.decode('utf-8', 'surrogateescape') for p in git(*args).split(b'\0') if p)
    return paths


def select(paths, release=False):
    checks = {('git', 'diff', '--check'), ('git', 'diff', '--cached', '--check')}
    notes = set()
    if release:
        checks.add(('bash', 'native-app/script/run_checks.sh'))
        notes.add('Release requires full build, signing, installation, upgrade and rollback acceptance; run the release gates separately.')
    for path in paths:
        if path.startswith(('README', 'CHANGELOG', 'docs/')):
            checks.add(('python3', 'script/check_docs.py'))
            notes.add('Review bilingual content and screenshot provenance when affected.')
        elif path.startswith(('native-app/Localization/', 'native-app/Resources/native-locales.json')):
            checks.update({('python3', 'native-app/script/check_localization.py'),
                           ('python3', 'native-app/checks/localization_checks.py')})
            notes.add('Review translation quality and dynamic strings manually.')
        elif path == 'native-app/checks/PerformanceChecks.swift':
            checks.add(('bash', 'script/check_performance_fixture.sh'))
            notes.add('Focused fixture only; changes to its source dependencies trigger full Native checks.')
        elif path.startswith('native-app/'):
            category = ('UI' if path.startswith(('native-app/Views/', 'native-app/App/')) else
                        'service' if path.startswith('native-app/Services/') else
                        'core/shared state' if path.startswith(('native-app/Core/', 'native-app/Stores/', 'native-app/Models/')) else
                        'resources/build/other')
            notes.add(f'{category}: dependency impact is uncertain; use full Native checks and assess the build.')
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
    release = '--release' in args
    args = [a for a in args if a not in ('--run', '--release')]
    if len(args) > 1:
        raise SystemExit('Usage: check_changed.py [BASE] [--run] [--release]')
    base = args[0] if args else 'origin/main'
    paths = changed(base)
    print(f'Base: {base}; changed paths: {len(paths)}', flush=True)
    for path in sorted(paths):
        print(' ', path, flush=True)
    checks, notes = select(paths, release)
    for note in notes:
        print('REVIEW:', note, flush=True)
    for command in checks:
        print(('RUN: ' if run else 'CHECK: ') + ' '.join(command), flush=True)
        if run:
            subprocess.run(command, check=True)
    print('Selection is not proof of acceptance; add task-specific tests and live checks.', flush=True)


if __name__ == '__main__':
    main()
