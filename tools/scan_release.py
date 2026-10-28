"""Scan the local export; never print suspected secret values or access accounts."""
import argparse
import ipaddress
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
# Exact public/synthetic addresses reviewed for this source snapshot.
IP_ALLOWLIST = {'127.0.0.1', '0.0.0.0', '192.168.127.254', '192.168.1.1',
                '192.168.1.2', '198.18.0.1', '1.1.1.1'}
TEXT_SUFFIXES = {'.py', '.json', '.md', '.mjs', '.txt', '.command', '.sha256'}
PATTERNS = {
    'private-key-material': r'-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----',
    'provider-token': r'gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{24,}|AKIA[0-9A-Z]{16}',
    'email-address': r'\b[A-Za-z0-9_.+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
    'personal-home-path': r'/Users/(?!example_user(?:/|\b))[A-Za-z0-9_.-]+',
}


def scan(deny_terms=()):
    findings = []
    count = 0

    def flag(rel, kind, line=None):
        findings.append({'file': rel, 'category': kind,
                         **({'line': line} if line else {})})

    for path in sorted(ROOT.rglob('*')):
        rel = path.relative_to(ROOT).as_posix()
        if '.git' in path.relative_to(ROOT).parts:
            continue
        if path.is_symlink():
            flag(rel, 'symlink')
            continue
        if path.is_dir():
            if path.name in ('__pycache__', 'backups', 'reports', 'network-snapshots', 'node_modules') or path.suffix == '.app':
                flag(rel, 'runtime-or-private-directory')
            continue
        count += 1
        if path.name in ('settings.json', 'network-profile.json', '.DS_Store') or path.suffix in ('.pem', '.key', '.log', '.plist', '.vdf', '.sqlite', '.db', '.yaml', '.yml'):
            flag(rel, 'private-or-generated-file')
        if path.suffix not in TEXT_SUFFIXES and path.name not in ('.gitignore', '.gitattributes', 'gvproxy-eim-wrapper'):
            flag(rel, 'unexpected-file-type')
        try:
            text = path.read_text(encoding='utf-8')
        except UnicodeError:
            flag(rel, 'non-text-file')
            continue
        if '\x00' in text:
            flag(rel, 'binary-content')
        for number, line in enumerate(text.splitlines(), 1):
            for category, pattern in PATTERNS.items():
                if re.search(pattern, line):
                    flag(rel, category, number)
            if any(term and term.casefold() in line.casefold() for term in deny_terms):
                flag(rel, 'denied-personal-identifier', number)
            # Steam's public ID-conversion offset is an algorithm constant.
            account_ids = re.findall(r'\b\d{17}\b', line)
            if any(value != '76561197960265728' for value in account_ids):
                flag(rel, 'possible-account-id', number)
            for token in re.findall(r'(?<![\w.])(?:\d{1,3}\.){3}\d{1,3}(?![\w.])', line):
                try:
                    address = ipaddress.IPv4Address(token)
                except ipaddress.AddressValueError:
                    continue
                documentation = any(address in ipaddress.ip_network(net) for net in ('192.0.2.0/24', '198.51.100.0/24', '203.0.113.0/24'))
                if token not in IP_ALLOWLIST and not documentation:
                    flag(rel, 'unreviewed-ip-address', number)
    return {'files_scanned': count, 'findings': findings,
            'status': 'pass' if not findings else 'review-required',
            'scope': 'Static text scan only; synthetic test secrets and technical hashes are intentionally retained.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--deny-term', action='append', default=[],
                        help='Additional personal identifier to reject; never printed in findings.')
    args = parser.parse_args()
    result = scan(args.deny_term)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0 if not result['findings'] else 1


if __name__ == '__main__':
    sys.exit(main())
