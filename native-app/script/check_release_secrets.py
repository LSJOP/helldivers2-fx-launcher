#!/usr/bin/env python3
"""Dependency-free, bounded release/index secret gate. Never prints matched data."""
import argparse
import ast
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import zipfile

MAX_FILE=64*1024*1024
MAX_TOTAL=512*1024*1024
PRIVATE=re.compile(rb'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----\s+[A-Za-z0-9+/=\r\n]{64,}-----END [A-Z0-9 ]*PRIVATE KEY-----')
TOKEN=re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[A-Z0-9]{16})')
AUTH=re.compile(rb'(?i)authorization["\x27]?\s*[:=]\s*["\x27]?(?:bearer|basic)\s+[A-Za-z0-9_./+=-]{12,}')
ASSIGN=re.compile(rb'(?i)(?:password|passphrase|sudo_password|private[_-]?key|api[_-]?key|access[_-]?token|token|client[_-]?secret)["\x27]?\s*[:=]\s*(["\x27])([^"\x27\r\n]+)\1')
SENSITIVE_KEYS={'password','ssh_password','passphrase','sudo_password','guest_sudo_password','api_token','api_key','access_token','client_secret','private_key','authorization'}

def placeholder(value):
    return value in (b'[REDACTED]',b'REDACTED') or value.startswith((b'${',b'<'))

def rules(data,label):
    found=[]
    if PRIVATE.search(data):found.append('private_key_body')
    if TOKEN.search(data):found.append('credential_token')
    if AUTH.search(data):found.append('authorization_header')
    test_source='/checks/' in '/'+label and label.endswith(('.py','.swift'))
    assignments=[]
    structured=False
    if label.endswith('.py'):
        try:
            tree=ast.parse(data);structured=True
            def key(node):
                if isinstance(node,ast.Name):return node.id
                if isinstance(node,ast.Attribute):return node.attr
                if isinstance(node,ast.Subscript):return node.slice.value if isinstance(node.slice,ast.Constant) and isinstance(node.slice.value,str) else ''
                return ''
            for node in ast.walk(tree):
                pairs=[]
                if isinstance(node,ast.Assign):pairs=[(key(x),node.value) for x in node.targets]
                elif isinstance(node,ast.AnnAssign):pairs=[(key(node.target),node.value)]
                elif isinstance(node,ast.Dict):pairs=[(k.value,v) for k,v in zip(node.keys,node.values) if isinstance(k,ast.Constant) and isinstance(k.value,str)]
                elif isinstance(node,ast.Call):pairs=[(k.arg,k.value) for k in node.keywords]
                for name,value in pairs:
                    if name and name.lower() in SENSITIVE_KEYS and isinstance(value,ast.Constant) and isinstance(value.value,str) and value.value:assignments.append(value.value.encode())
        except (SyntaxError,UnicodeError,RecursionError):pass
    if label.endswith('.json'):
        try:json.loads(data);structured=True
        except (ValueError,UnicodeError,RecursionError):pass
    if not structured:assignments.extend(match.group(2) for match in ASSIGN.finditer(data))
    for value in assignments:
        if placeholder(value):continue
        # Explicit fictional unit-test values only; release/config fixtures still scan.
        if test_source and value.startswith((b'fixture-',b'test-',b'unit-')):continue
        found.append('credential_assignment');break
    try:
        value=json.loads(data)
        catalog=isinstance(value,dict) and isinstance(value.get('strings'),dict) and isinstance(value.get('messages'),dict) and value.get('code') in ['zh-CN','en','ja','ko','ru','es','de','fr','pt-BR','zh-TW']
        def visit(item):
            if isinstance(item,dict):
                if catalog and item is value:
                    return any(visit(v) for k,v in item.items() if k not in ('strings','messages'))
                return any((k.lower() in SENSITIVE_KEYS and isinstance(v,str) and v and not placeholder(v.encode())) or visit(v) for k,v in item.items())
            if isinstance(item,list):return any(visit(x) for x in item)
            return False
        if visit(value):found.append('credential_json_field')
    except (ValueError,UnicodeError,RecursionError):pass
    return sorted(set(found))

class Scan:
    def __init__(self):self.findings=[];self.unable=[];self.files=0;self.total=0
    def label(self,value):
        # Paths are relative to the requested input, never an absolute user path.
        raw=str(value).encode('utf-8',errors='replace')
        raw=TOKEN.sub(b'[REDACTED]',raw)
        return raw.decode('utf-8',errors='replace')[:500]
    def add(self,label,data):
        self.files+=1;self.total+=len(data)
        if self.files>10000 or self.total>MAX_TOTAL or len(data)>MAX_FILE:
            self.unable.append({'file':self.label(label),'reason':'scan_limit'});return
        name=Path(label).name
        if name in ('settings.json','runtime-paths.json','UpdateSigning.local.xcconfig','.env') or name.startswith('.env.') or Path(name).suffix.lower() in ('.p12','.p8','.key','.private','.ed25519'):
            self.findings.append({'file':self.label(label),'rule':'private_configuration_or_key_file'})
        for rule in rules(data,label):self.findings.append({'file':self.label(label),'rule':rule})
        if Path(name).suffix.lower()=='.json':
            try:json.loads(data)
            except (ValueError,UnicodeError,RecursionError):self.unable.append({'file':self.label(label),'reason':'unreadable_json'})
    def path(self,root):
        root=Path(root)
        if not root.exists():self.unable.append({'file':root.name,'reason':'missing_input'});return
        candidates=[root] if root.is_file() else root.rglob('*')
        try:
            seen=set()
            for item in candidates:
                if self.files>=10000 or self.total>=MAX_TOTAL:self.unable.append({'file':root.name,'reason':'scan_limit'});break
                resolved=item.resolve()
                if root.is_dir() and root.resolve() not in resolved.parents:
                    self.unable.append({'file':self.label(item.name),'reason':'external_symlink'});continue
                if not item.is_file():continue
                if resolved in seen:continue
                seen.add(resolved)
                label=root.name+'/'+str(item.relative_to(root)) if root.is_dir() else root.name
                try:
                    if item.stat().st_size>MAX_FILE:raise ValueError('limit')
                    self.add(label,item.read_bytes())
                except (OSError,ValueError):self.unable.append({'file':self.label(label),'reason':'unreadable_or_large'})
        except OSError:self.unable.append({'file':root.name,'reason':'unreadable_directory'})
    def archive(self,path):
        path=Path(path)
        try:
            with zipfile.ZipFile(path) as archive:
                for entry in archive.infolist():
                    if self.files>=10000 or self.total>=MAX_TOTAL:self.unable.append({'file':path.name,'reason':'scan_limit'});break
                    if entry.is_dir():continue
                    label=path.name+'/'+entry.filename
                    if entry.flag_bits&1 or entry.file_size>MAX_FILE or entry.file_size/max(1,entry.compress_size)>1000 or '..' in Path(entry.filename).parts or Path(entry.filename).is_absolute():
                        self.unable.append({'file':self.label(label),'reason':'unsafe_or_unreadable_archive_entry'});continue
                    self.add(label,archive.read(entry))
        except (OSError,ValueError,zipfile.BadZipFile,RuntimeError):self.unable.append({'file':path.name,'reason':'unreadable_archive'})
    def git(self,staged=False):
        try:
            command=['git','diff','--cached','--name-only','--diff-filter=ACMR','-z'] if staged else ['git','ls-files','-z']
            paths=subprocess.check_output(command).split(b'\0')
            modes={entry.split(b'\t',1)[1]:entry.split(b' ',1)[0] for entry in subprocess.check_output(['git','ls-files','--stage','-z']).split(b'\0') if b'\t' in entry}
            for raw in paths:
                if not raw:continue
                name=os.fsdecode(raw)
                # Gitlinks identify preserved external source; the built bundle is scanned separately.
                mode=modes.get(raw)
                if mode==b'160000':continue
                try:
                    data=subprocess.check_output(['git','show',':'+name],stderr=subprocess.DEVNULL) if staged else Path(name).read_bytes()
                    self.add(name,data)
                except (OSError,subprocess.CalledProcessError):self.unable.append({'file':self.label(name),'reason':'unreadable_git_input'})
        except (OSError,subprocess.CalledProcessError):self.unable.append({'file':'git','reason':'git_unavailable'})
    def report(self):
        return {'status':'SUSPECTED' if self.findings else 'UNABLE' if self.unable else 'PASS','files_checked':self.files,'findings':self.findings,'unable':self.unable,'scope':'pattern_and_private_file_checks_not_a_proof_of_absence'}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tracked',action='store_true');parser.add_argument('--staged',action='store_true')
    parser.add_argument('--path',action='append',default=[]);parser.add_argument('--archive',action='append',default=[])
    args=parser.parse_args();scan=Scan()
    if not (args.tracked or args.staged or args.path or args.archive):parser.error('Select a concrete scan scope')
    if args.tracked or args.staged:scan.git(staged=args.staged)
    for path in args.path:scan.path(path)
    for path in args.archive:scan.archive(path)
    report=scan.report();print(json.dumps(report,ensure_ascii=False,indent=2))
    return {'PASS':0,'SUSPECTED':1,'UNABLE':2}[report['status']]

if __name__=='__main__':raise SystemExit(main())
