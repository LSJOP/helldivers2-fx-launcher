"""Read-only, anonymous GitHub Releases checks. No download/install operations.

Repository commits, tags without Releases and remote text are never executed.
"""
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from functools import cmp_to_key
import http.client
import importlib.util
import json
from pathlib import Path
import re
import socket
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request

REPOSITORY = 'LSJOP/helldivers2-fx-launcher'
API_ROOT = 'https://api.github.com/repos/'+REPOSITORY+'/releases'
RELEASES_URL = 'https://github.com/'+REPOSITORY+'/releases'
MAX_PAGES = 5
MAX_RESPONSE_BYTES = 1024 * 1024
TIMEOUT = 8
INSTALL_ENABLED = False  # Phase 1: deliberately no installation implementation.
CHANNELS = ('preview', 'stable')
_spec = importlib.util.spec_from_file_location('hd2fx_update_version',Path(__file__).with_name('launcher_version.py'))
versions = importlib.util.module_from_spec(_spec);_spec.loader.exec_module(versions)


class CheckError(RuntimeError):
    def __init__(self, code):
        self.code = code
        super().__init__(code)


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise CheckError('redirect')


def version_parts(value):
    if not versions.valid_version(value): raise ValueError('Invalid semantic version')
    value = value.split('+',1)[0]
    core,separator,pre = value.partition('-')
    return tuple(int(part) for part in core.split('.')), tuple(pre.split('.')) if separator else ()


def compare_versions(left, right):
    a,ap = version_parts(left);b,bp = version_parts(right)
    if a != b: return (a>b)-(a<b)
    if not ap or not bp: return (not ap)-(not bp)
    for x,y in zip(ap,bp):
        if x == y: continue
        if x.isdigit() and y.isdigit(): return (int(x)>int(y))-(int(x)<int(y))
        if x.isdigit() != y.isdigit(): return -1 if x.isdigit() else 1
        return (x>y)-(x<y)
    return (len(ap)>len(bp))-(len(ap)<len(bp))


def channel(value):
    _,pre = version_parts(value)
    return pre[0] if pre else 'stable'


def plain_text(value, limit=20000):
    """Untrusted release Markdown is text: strip OSC/CSI/control/bidi sequences."""
    if not isinstance(value,str): return ''
    value = value[:limit*2]
    value = re.sub(r'\x1b\][^\x07\x1b]*(?:\x07|\x1b\\|$)','',value)
    value = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]','',value)
    value = value.replace('\u2028','\n').replace('\u2029','\n')
    value = ''.join(char for char in value if char in '\n\t' or unicodedata.category(char) not in ('Cc','Cf','Cs'))
    return value.replace('\t','    ')[:limit]


def release_date(value):
    if not isinstance(value,str): return None
    try:
        parsed = datetime.fromisoformat(value.replace('Z','+00:00'))
        if parsed.tzinfo is None: return None
        return parsed.astimezone(timezone.utc).strftime('%Y-%m-%d %H:%M UTC')
    except (ValueError, OverflowError): return None


def official_release_url(tag):
    return RELEASES_URL+'/tag/'+urllib.parse.quote(tag,safe='')


def asset_records(rows, tag):
    """Parse official asset metadata for display/audit only; never fetch an asset."""
    if not isinstance(rows,list):return []
    assets = []
    for row in rows[:100]:
        if not isinstance(row,dict):continue
        name = row.get('name');ident = row.get('id');size = row.get('size')
        if (not isinstance(name,str) or not name or name!=plain_text(name,256) or
                '/' in name or '\\' in name or name in ('.','..') or
                type(ident) is not int or ident<=0 or type(size) is not int or size<0 or
                row.get('state')!='uploaded'):continue
        url = RELEASES_URL+'/download/'+urllib.parse.quote(tag,safe='')+'/'+urllib.parse.quote(name,safe='')
        if row.get('browser_download_url')!=url:continue
        digest = row.get('digest')
        digest = digest if isinstance(digest,str) and re.fullmatch('sha256:[a-fA-F0-9]{64}',digest) else None
        assets.append({'id':ident,'name':name,'size':size,'digest':digest,'url':url})
    return assets


def release_record(row):
    if not isinstance(row,dict) or row.get('draft') is not False: return None
    tag = row.get('tag_name')
    if not isinstance(tag,str): return None
    value = tag[1:] if tag.startswith('v') else tag
    if not versions.valid_version(value): return None
    pre = bool(version_parts(value)[1])
    # A stable-looking tag marked prerelease (or vice versa) is inconsistent.
    if type(row.get('prerelease')) is not bool or row['prerelease'] != pre: return None
    published = release_date(row.get('published_at'))
    if published is None: return None
    return {'version':value,'tag':tag,'channel':channel(value),'prerelease':pre,
            'published':published,'notes':plain_text(row.get('body')),
            'url':official_release_url(tag),'assets':asset_records(row.get('assets'),tag),
            'asset_count':len(row['assets']) if isinstance(row.get('assets'),list) else None}


def selected_channel(current, update_channel=None):
    """Default to the installed channel; explicit switches are session-only."""
    default = channel(current)  # Always validate VERSION, even with an override.
    if update_channel is None: return default
    if update_channel not in CHANNELS: raise CheckError('channel')
    return update_channel


def initial(current=None, update_channel=None):
    """Local state only; opening the update center never sends a request."""
    current=versions.get_version() if current is None else current
    result={'current':current,'channel':None,'release':None,'status':'unchecked',
            'install_allowed':False,'error':None,'http_status':None,'http_details':{}}
    try:result['channel']=selected_channel(current,update_channel)
    except ValueError:result.update(status='error',error='current_version')
    except CheckError as error:result.update(status='error',error=error.code)
    return result


def http_details(status, headers, now=None):
    """Keep only bounded numeric timing metadata, never raw headers/body/proxies.

    Reset alone is not evidence of a limit. A generic 403 remains forbidden.
    Retry-After is respected even if the reason for denial is not established.
    """
    now=time.time() if now is None else now
    def header(name):
        matches=[v for k,v in (headers.items() if headers is not None else ()) if isinstance(k,str) and k.lower()==name]
        value=matches[0].strip() if len(matches)==1 and isinstance(matches[0],str) else None
        return value if value is not None and len(value)<=128 else None
    def number(value):
        return int(value) if isinstance(value,str) and re.fullmatch(r'[0-9]{1,12}',value) else None
    remaining=number(header('x-ratelimit-remaining'))
    reset=number(header('x-ratelimit-reset'))
    reset=reset if reset is not None and now<reset<=now+7*86400 else None
    retry=header('retry-after');seconds=number(retry)
    retry_at=now+seconds if seconds is not None and seconds<=7*86400 else None
    if retry and seconds is None:
        try:
            date=parsedate_to_datetime(retry)
            if date.tzinfo is not None and now<date.timestamp()<=now+7*86400:retry_at=date.timestamp()
        except (ValueError,TypeError,OverflowError):pass
    limited=status==429 or (status==403 and remaining==0)
    wait_until=max([value for value in (retry_at,reset if limited else None) if value is not None],default=None)
    source='headers' if wait_until is not None else None
    if limited and wait_until is None:wait_until=now+60;source='minimum_wait'
    return {'remaining':remaining,'reset_at':reset,'retry_at':wait_until,
            'retry_source':source,'rate_limited':limited}


def select_release(rows, current, update_channel=None):
    current_channel = selected_channel(current, update_channel)
    records = [record for record in (release_record(row) for row in rows) if record]
    candidates = [record for record in records if record['channel'] == current_channel]
    result = initial(current,update_channel);result['status']='no_release'
    if not candidates:
        if records:result['status'] = 'no_channel_release'
        elif rows:result['status'] = 'unusable_metadata'
        return result
    latest = max(candidates,key=cmp_to_key(lambda a,b:compare_versions(a['version'],b['version'])))
    order = compare_versions(latest['version'],current)
    result.update(release=latest,status='available' if order>0 else ('current' if order==0 else 'ahead'))
    return result


def _page(page, opener):
    url = API_ROOT+'?per_page=100&page='+str(page)
    request = urllib.request.Request(url,headers={
        'Accept':'application/vnd.github+json',
        'X-GitHub-Api-Version':'2026-03-10',
        'User-Agent':'Helldivers2FXLauncher/'+versions.get_version(),
    })
    with opener.open(request,timeout=TIMEOUT) as response:
        if response.geturl() != url: raise CheckError('redirect')
        if response.status != 200:
            raise urllib.error.HTTPError(url,response.status,'',response.headers,None)
        body = response.read(MAX_RESPONSE_BYTES+1)
        if len(body)>MAX_RESPONSE_BYTES: raise CheckError('response_limit')
        try: rows = json.loads(body.decode('utf-8'))
        except (ValueError,UnicodeError,RecursionError): raise CheckError('metadata') from None
        if not isinstance(rows,list) or len(rows)>100: raise CheckError('metadata')
        more = bool(re.search(r';\s*rel="next"',response.headers.get('Link','')))
        # Do not follow server-supplied URLs; construct every next request locally.
        return rows,more


def check(current=None, opener=None, update_channel=None):
    current = versions.get_version() if current is None else current
    result = initial(current,update_channel)
    if result['error']:return result
    result['status']='error'
    try:
        result['channel'] = selected_channel(current, update_channel)
        opener = opener or urllib.request.build_opener(NoRedirect())
        rows = []
        for page in range(1,MAX_PAGES+1):
            batch,more = _page(page,opener);rows.extend(batch)
            if not more: return select_release(rows,current,update_channel)
        raise CheckError('page_limit')
    except ValueError: result['error'] = 'current_version'
    except CheckError as error: result['error'] = error.code
    except urllib.error.HTTPError as error:
        details=http_details(error.code,error.headers)
        result['error'] = 'rate_limit' if details['rate_limited'] else ('forbidden' if error.code==403 else 'http')
        result['http_status'] = error.code
        result['http_details'] = details
        if error.fp is not None:
            try: error.close()
            except OSError: pass  # Cleanup must not mask the original HTTP result.
    except (TimeoutError,socket.timeout): result['error'] = 'timeout'
    except urllib.error.URLError as error:
        result['error'] = 'timeout' if isinstance(error.reason,(TimeoutError,socket.timeout)) else 'network'
    except (OSError,UnicodeError,http.client.HTTPException): result['error'] = 'network'
    return result
