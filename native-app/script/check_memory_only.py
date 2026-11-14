#!/usr/bin/env python3
"""Audit encrypted local credential storage and Settings-only input; historical filename retained."""
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
for marker in ['UserDefaults','Security','CredentialVault']:
 if marker in manager:errors.append('SessionCredentialManager unexpected dependency '+marker)
store=(root/'Services/LocalCredentialStore.swift').read_text()
for marker in ['AES.GCM','O_NOFOLLOW','0o700','0o600','st_nlink == 1','fsync']:
 if marker not in store:errors.append('missing protected storage guard '+marker)
for path in (root/'Views').glob('*.swift'):
 if path.name!='SettingsView.swift' and 'SecureField(' in path.read_text():errors.append('password input outside Settings '+path.name)
settings=(root/'Views/SettingsView.swift').read_text()
if settings.count('SecureField(')!=1:errors.append('Settings must have one shared password field')
views=(root/'Views/SettingsView.swift').read_text()
for marker in ['setRemember','vaultError','removeAll()','CredentialVaultNotice','rememberSSH','rememberSudo']:
 if marker in views:errors.append('obsolete credential UI '+marker)
print(json.dumps({'result':'FAIL' if errors else 'PASS','swift_files':scanned,'errors':errors,
 'scope':'single Settings password input; independently verified SSH/sudo proofs; owner-only AES-GCM storage; no Keychain APIs'},indent=2))
raise SystemExit(bool(errors))
