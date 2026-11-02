"""Launcher release identity. VERSION is the only authoritative version value."""
from pathlib import Path
from functools import lru_cache
import re

VERSION_FILE=Path(__file__).resolve().parent.parent/'VERSION'
# SemVer core, optional prerelease and build metadata; reject numeric leading zeros.
_SEMVER=re.compile(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
                   r'(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
                   r'(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?'
                   r'(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?')


def valid_version(value):
    return isinstance(value,str) and len(value)<=128 and _SEMVER.fullmatch(value) is not None


@lru_cache(maxsize=8)
def _read_version(path,size,mtime,ctime):
    value=Path(path).read_text(encoding='utf-8').strip()
    return value if valid_version(value) else 'unknown'


def get_version():
    try:
        info=VERSION_FILE.stat()
        if info.st_size>256:return 'unknown'
        return _read_version(str(VERSION_FILE),info.st_size,info.st_mtime_ns,info.st_ctime_ns)
    except (OSError,UnicodeError):return 'unknown'
