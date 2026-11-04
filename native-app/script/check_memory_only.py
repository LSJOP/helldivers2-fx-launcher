#!/usr/bin/env python3
"""Audit no-Keychain credential storage without opening or modifying any credential store."""
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
for marker in ['UserDefaults','FileManager','Security','CredentialVault']:
 if marker in manager:errors.append('SessionCredentialManager unexpected dependency '+marker)
store=(root/'Services/LocalCredentialStore.swift').read_text()
for marker in ['AES.GCM.seal', 'AES.GCM.open', 'O_NOFOLLOW', '0o600', '0o700', 'authenticating:', 'LOCK_EX']:
 if marker not in store:errors.append('encrypted-store guard missing '+marker)
views=(root/'Views/SettingsView.swift').read_text()
for marker in ['setRemember','vaultError','removeAll()','CredentialVaultNotice','rememberSSH','rememberSudo']:
 if marker in views:errors.append('obsolete credential UI '+marker)
print(json.dumps({'result':'FAIL' if errors else 'PASS','swift_files':scanned,'errors':errors,
 'scope':'No Keychain APIs; manager has no plaintext file/preferences dependencies; LocalCredentialStore uses owner-only AES-GCM storage under current user authorization; signing Security APIs preserved'},indent=2))
raise SystemExit(bool(errors))
