#!/usr/bin/env python3
"""Deterministic Native catalog and documentation checks; no runtime translation."""
import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess

LANGUAGES = {'en', 'zh-CN', 'zh-TW', 'ja', 'ko', 'ru', 'es', 'de', 'fr', 'pt-BR'}
FORMATS = re.compile(r'%(?:\d+\$)?[-+ #0]*(?:\d+|\*)?(?:\.\d+)?(?:ll|l|h)?[@diufseEgG]|\{[A-Za-z_][A-Za-z_0-9]*\}')
KEY = re.compile(r'"(ui\.[A-Za-z0-9_.]+)"')
LITERAL = re.compile(r'\b(?:Text|Button|Label|Toggle|TextField|SecureField)\(\s*"((?:[^"\\]|\\.)*)"')
BRANDS = {'HELLDIVERS 2', 'FX LAUNCHER'}


def read_catalog(path):
    def unique(pairs):
        value = {}
        for k, v in pairs:
            if k in value:
                raise ValueError('duplicate key: ' + k)
            value[k] = v
        return value
    return json.loads(path.read_text(), object_pairs_hook=unique)


def validate(root):
    errors, coverage = [], {}
    app = root / 'native-app'
    try:
        catalogs = read_catalog(app / 'bridge/native-locales.json')
    except (ValueError, OSError) as e:
        return [str(e)], coverage
    if set(catalogs) != LANGUAGES:
        errors.append('catalog languages differ from original ten languages')
    english = catalogs.get('en', {})
    for language in LANGUAGES:
        catalog = catalogs.get(language, {})
        missing, extra = set(english) - set(catalog), set(catalog) - set(english)
        if missing or extra:
            errors.append(f'{language}: missing={sorted(missing)} extra={sorted(extra)}')
        for key in set(catalog) & set(english):
            value = catalog[key]
            if not isinstance(value, str) or not value.strip() or value.startswith(('TODO', 'TRANSLATE', '⟦')):
                errors.append(f'{language}/{key}: empty or placeholder translation')
            elif Counter(FORMATS.findall(value.replace('%%', ''))) != Counter(FORMATS.findall(english[key].replace('%%', ''))):
                errors.append(f'{language}/{key}: format parameters differ')
        coverage[language] = {'present': len(set(catalog) & set(english)), 'required': len(english)}
        folder = {'zh-CN': 'zh-Hans', 'zh-TW': 'zh-Hant'}.get(language, language)
        resource = app / 'Localization' / (folder + '.lproj') / 'Localizable.strings'
        if not resource.is_file():
            errors.append(language + ': missing native bundle localization')
        else:
            pairs = re.findall(r'"((?:[^"\\]|\\.)*)"\s*=\s*("(?:[^"\\]|\\.)*")\s*;', resource.read_text())
            if len(pairs) != 14 or len(dict(pairs)) != len(pairs):
                errors.append(language + ': missing or duplicate update resource keys')
            for key, value in pairs:
                if json.loads(value) not in catalog.values():
                    errors.append(language + '/' + key + ': stale bundle translation')
    used = set()
    for folder in ['App', 'Views', 'Stores', 'Services', 'Models']:
        for path in (app / folder).rglob('*.swift'):
            source = path.read_text()
            used.update(KEY.findall(source))
            for match in LITERAL.finditer(source):
                value = match[1]
                # Protocol metadata, numeric badges and brand marks are not translated prose.
                if value in BRANDS or value.startswith(('\\(', 'performance_profile.')) or not re.search(r'[A-Za-z\u4e00-\u9fff]', value):
                    continue
                errors.append(f'{path.relative_to(root)}: unlocalized UI literal {value!r}')
    for path in (app / 'Support').rglob('*.swift'):
        used.update(KEY.findall(path.read_text()))
    if used - set(english):
        errors.append('missing referenced keys: ' + str(sorted(used - set(english))))
    if set(english) - used:
        errors.append('unused translation keys: ' + str(sorted(set(english) - used)))
    for name in ['README.md', 'README.zh-CN.md']:
        if not (root / name).is_file():
            errors.append('missing ' + name)
    return errors, coverage


def documentation_review(root, base=None):
    commands = [['git', 'diff', '--name-only', base + '...HEAD']] if base else [
        ['git', 'diff', '--name-only'], ['git', 'diff', '--cached', '--name-only']]
    changed = set()
    for command in commands:
        changed.update(subprocess.check_output(command, cwd=root, text=True).splitlines())
    readmes = changed & {'README.md', 'README.zh-CN.md'}
    errors = ['README edits must update both language versions'] if len(readmes) == 1 else []
    relevant = sorted(p for p in changed if p.startswith(('native-app/Views/', 'native-app/App/', 'native-app/bridge/', 'native-app/Info.plist')))
    return errors, {'review_candidates': relevant, 'readmes_updated': sorted(readmes),
                    'note': 'Human review must assess capability claims, screenshots and semantic parity; source edits alone do not require README changes.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--base', help='Compare committed files with this Git revision')
    args = parser.parse_args()
    errors, coverage = validate(args.root)
    doc_errors, review = documentation_review(args.root, args.base)
    errors.extend(doc_errors)
    print(json.dumps({'result': 'FAIL' if errors else 'PASS', 'coverage': coverage,
                      'documentation_review': review, 'errors': errors,
                      'limits': 'Static UI scanning is heuristic; naturalness and every dynamic string require review.'}, ensure_ascii=False, indent=2))
    return bool(errors)


if __name__ == '__main__':
    raise SystemExit(main())
