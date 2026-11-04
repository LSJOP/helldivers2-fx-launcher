#!/usr/bin/env python3
"""Audit credential API removal without opening or modifying any credential store."""
import json,re
from pathlib import Path
root=Path(__file__).resolve().parents[1]
forbidden=re.compile(r'\b(?:SecItemAdd|SecItemCopyMatching|SecItemUpdate|SecItemDelete|SecKeychain\w*|kSecClass\w*|kSecAttrService|kSecAttrAccount|KeychainCredentialVault|CredentialVault)\b')
errors=[];scanned=0
for folder in ['App','Core','Models','Services','Stores','Support','Views']:
 for path in (root/folder).rglob('*.swift'):
  scanned+=1
  if forbidden.search(path.read_text()):errors.append(str(path.relative_to(root)))
manager=(root/'Services/SessionCredentialManager.swift').read_text()
for marker in ['UserDefaults','FileManager','Security','CryptoKit','CredentialVault']:
 if marker in manager:errors.append('SessionCredentialManager unexpected dependency '+marker)
views=(root/'Views/SettingsView.swift').read_text()
for marker in ['setRemember','vaultError','removeAll()','CredentialVaultNotice','rememberSSH','rememberSudo']:
 if marker in views:errors.append('obsolete credential UI '+marker)
print(json.dumps({'result':'FAIL' if errors else 'PASS','swift_files':scanned,'errors':errors,
 'scope':'App credential APIs only; signing Security APIs and historical CoreSnapshot preserved; no real credential-store access'},indent=2))
raise SystemExit(bool(errors))
