"""Session-only SSH adapters and diagnostic redaction. No Keychain/storage APIs."""
import re

REDACTED='[REDACTED]'
PRIVATE_KEY=re.compile(r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?(?:-----END [A-Z0-9 ]*PRIVATE KEY-----|$)',re.S)
TOKEN=re.compile(r'(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})')
ASSIGNMENT=re.compile(r'(?i)(?:password|passphrase|sudo_password|private[_-]?key|api[_-]?key|access[_-]?token|token|client[_-]?secret)["\x27]?\s*[:=]\s*(?:"[^"]*"|\x27[^\x27]*\x27|[^\s,;}]+)')

class Redactor:
    def __init__(self,secrets=()):self.secrets=sorted((x for x in secrets if isinstance(x,str) and x),key=len,reverse=True)
    def text(self,value):
        for secret in self.secrets:value=value.replace(secret,REDACTED)
        value=PRIVATE_KEY.sub(REDACTED,value)
        value=TOKEN.sub(REDACTED,value)
        value=re.sub(r'(?im)authorization["\x27]?\s*[:=]\s*[^\r\n]+',REDACTED,value)
        value=ASSIGNMENT.sub(REDACTED,value)
        return re.sub(r'(?i)https?://[^\s/@:]+:[^\s/@]+@',REDACTED,value)
    def contains_secret(self,value):
        if isinstance(value,dict):
            for key,item in value.items():
                if key.lower() in ('password','passphrase','sudo_password','token','api_token','api_key','private_key','authorization') and isinstance(item,str) and item:return True
                if self.contains_secret(item):return True
            return False
        if isinstance(value,(list,tuple)):return any(self.contains_secret(x) for x in value)
        if not isinstance(value,str):return False
        return bool(PRIVATE_KEY.search(value) or TOKEN.search(value) or ASSIGNMENT.search(value) or re.search(r'(?i)authorization\s*:',value) or any(len(x)>=4 and x in value for x in self.secrets))

class DisabledCredentialStore:
    def get(self,*args):return None
    def put(self,*args):raise RuntimeError('Persistent SSH credential storage is disabled in Native App')
    def delete(self,*args):raise RuntimeError('Native App never deletes existing Keychain credentials')

def session_only(preferences):
    # Class overrides also cover CLIENT instances constructed during the original import.
    preferences.VAULT=DisabledCredentialStore()
    preferences.SSHClient._saved_password=lambda self:None
    preferences.SSHClient._remember_authenticated_password=lambda self:None

def bind_session_sudo(helper,params):
    original=helper.safety.request
    def request(target,data,sudo=False):
        if not sudo:return original(target,data,sudo=False)
        client=target.CLIENT;ssh_password=client.password
        try:
            # Do not silently treat an SSH password/passphrase as a sudo credential.
            client.password=params.get('sudo_password') or None
            return original(target,data,sudo=True)
        finally:client.password=ssh_password
    helper.safety.request=request
