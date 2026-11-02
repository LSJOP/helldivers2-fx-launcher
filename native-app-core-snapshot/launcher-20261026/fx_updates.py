"""Anonymous, explicit FX official release checks; no assets are downloaded.

Independent repository, state and channels from the launcher's update checker.
Only its pure SemVer/text/date/HTTP safety helpers are reused.
"""
import http.client
import importlib.util
import json
from pathlib import Path
import re
import socket
import urllib.error
import urllib.parse
import urllib.request

_spec=importlib.util.spec_from_file_location('hd2_fx_http_helpers',Path(__file__).with_name('update_checker.py'))
helpers=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(helpers)
API_ROOT='https://api.github.com/repos/fxgl/steamac/releases'
RELEASES_URL='https://github.com/fxgl/steamac/releases'
MAX_PAGES=3
MAX_BYTES=1024*1024
TIMEOUT=8
INSTALL_ENABLED=False


def version(value):
    if not isinstance(value,str) or len(value)>128:return None
    text=value[1:] if value.startswith('v') else value
    # FX official history includes v1.9: explicit numeric comparison policy,
    # not an assertion about the binary build. Keep the original release tag.
    if re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)',text):text+='.0'
    return text if helpers.versions.valid_version(text) else None


def initial(current=None,channel='stable'):
    return dict(current=version(current),channel=channel,release=None,status='unchecked',
                error=None,http_status=None,http_details={},install_allowed=False)


def record(row):
    if not isinstance(row,dict) or row.get('draft') is not False or type(row.get('prerelease')) is not bool:return None
    tag=row.get('tag_name');date=helpers.release_date(row.get('published_at'))
    if not isinstance(tag,str) or not tag or len(tag)>128 or helpers.plain_text(tag,128)!=tag or date is None:return None
    value=version(tag)
    if value and bool(helpers.version_parts(value)[1])!=row['prerelease']:value=None
    return dict(version=value,tag=tag,prerelease=row['prerelease'],published=date,
                notes=helpers.plain_text(row.get('body')),url=RELEASES_URL+'/tag/'+urllib.parse.quote(tag,safe=''),
                asset_count=len(row['assets']) if isinstance(row.get('assets'),list) else None)


def select(rows,current=None,channel='stable'):
    result=initial(current,channel)
    if channel not in ('stable','preview'):return dict(result,status='error',error='channel')
    records=[r for r in (record(row) for row in rows) if r]
    candidates=[r for r in records if channel=='preview' or not r['prerelease']]
    if not candidates:
        drafts_only=rows and all(isinstance(r,dict) and r.get('draft') is True for r in rows)
        return dict(result,status='no_channel_release' if records else 'no_release' if not rows or drafts_only else 'unusable_metadata')
    unknown=[r for r in candidates if r['version'] is None]
    if unknown:
        # Do not silently discard a potentially newer nonstandard release.
        return dict(result,status='uncomparable',release=unknown[0])
    from functools import cmp_to_key
    latest=max(candidates,key=cmp_to_key(lambda a,b:helpers.compare_versions(a['version'],b['version'])))
    if result['current'] is None:return dict(result,status='uncomparable',release=latest)
    order=helpers.compare_versions(latest['version'],result['current'])
    return dict(result,release=latest,status='available' if order>0 else 'current' if order==0 else 'ahead')


def check(current=None,channel='stable',opener=None):
    result=initial(current,channel)
    if channel not in ('stable','preview'):return dict(result,status='error',error='channel')
    try:
        opener=opener or urllib.request.build_opener(helpers.NoRedirect())
        rows=[]
        for page in range(1,MAX_PAGES+1):
            url=API_ROOT+'?per_page=100&page='+str(page)
            request=urllib.request.Request(url,headers={'Accept':'application/vnd.github+json',
                'X-GitHub-Api-Version':'2022-11-28','User-Agent':'Helldivers2FXLauncher/'+helpers.versions.get_version()})
            with opener.open(request,timeout=TIMEOUT) as response:
                if response.geturl()!=url:raise helpers.CheckError('redirect')
                if response.status!=200:raise urllib.error.HTTPError(url,response.status,'',response.headers,None)
                body=response.read(MAX_BYTES+1)
                if len(body)>MAX_BYTES:raise helpers.CheckError('response_limit')
                try:batch=json.loads(body.decode('utf-8'))
                except (ValueError,UnicodeError,RecursionError):raise helpers.CheckError('metadata') from None
                if not isinstance(batch,list) or len(batch)>100:raise helpers.CheckError('metadata')
                rows.extend(batch)
                more=bool(re.search(r';\s*rel="next"',response.headers.get('Link','')))
            if not more:return select(rows,current,channel)
        raise helpers.CheckError('page_limit')
    except urllib.error.HTTPError as error:
        details=helpers.http_details(error.code,error.headers)
        result.update(error='rate_limit' if details['rate_limited'] else 'forbidden' if error.code==403 else 'http',
                      http_status=error.code,http_details=details)
        if error.fp is not None:
            try:error.close()
            except OSError:pass
    except helpers.CheckError as error:result['error']=error.code
    except (TimeoutError,socket.timeout):result['error']='timeout'
    except urllib.error.URLError as error:result['error']='timeout' if isinstance(error.reason,(TimeoutError,socket.timeout)) else 'network'
    except (OSError,UnicodeError,http.client.HTTPException):result['error']='network'
    return dict(result,status='error')
