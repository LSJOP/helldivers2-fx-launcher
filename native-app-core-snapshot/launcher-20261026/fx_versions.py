"""FX file/compatibility evidence. No activation, persistence or validation runs."""
from dataclasses import dataclass
from datetime import datetime
import importlib.util
from pathlib import Path
import re

_spec=importlib.util.spec_from_file_location('hd2_fx_versions_helpers',Path(__file__).with_name('fx_updates.py'))
updates=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(updates)


def facts(row):
    """A hash mismatch is not evidence of incompatibility; no fabricated records."""
    baseline=(row.get('manifest_match') is True and row.get('runtime_hash_match') is True)
    if False in (row.get('manifest_match'),row.get('runtime_hash_match')):baseline=False
    elif not baseline:baseline=None
    return dict(version=row.get('bundle_version') or row.get('version'),sha256=row.get('sha256'),
                found=row.get('exists'),structure=row.get('structure_valid'),file_verified=row.get('file_verified'),
                historical_match=baseline,launch='unverified',eac='unverified',multiplayer='unverified',
                incompatibility='unverified')


@dataclass(frozen=True)
class ValidationEvidence:
    """Future record contract; no records are created or saved by the launcher.

    Even an evidence record applies only to its full environment identity.
    Unknown fields are rejected here, never parsed/saved over user settings.
    """
    fx_version: str
    fx_sha256: str
    gvproxy_sha256: str
    fex_build: str
    proton_build: str
    game_build: str
    verified_at: str
    launch: str
    eac: str
    multiplayer: str
    evidence_source: str

    def __post_init__(self):
        if updates.version(self.fx_version) is None:raise ValueError('FX version required')
        for value in (self.fx_sha256,self.gvproxy_sha256):
            if not isinstance(value,str) or not re.fullmatch('[a-f0-9]{64}',value):raise ValueError('Build hashes required')
        for value in (self.fex_build,self.proton_build,self.game_build,self.evidence_source):
            if not isinstance(value,str) or not value.strip() or len(value)>512 or updates.helpers.plain_text(value,512)!=value:raise ValueError('Build/source evidence required')
        if not isinstance(self.verified_at,str) or len(self.verified_at)>64:raise ValueError('Validation time required')
        try:date=datetime.fromisoformat(self.verified_at.replace('Z','+00:00'))
        except ValueError:raise ValueError('Invalid validation time') from None
        if date.tzinfo is None:raise ValueError('Validation timezone required')
        for value in (self.launch,self.eac,self.multiplayer):
            if value not in ('passed','failed','unverified'):raise ValueError('Invalid validation stage')

    def matches(self,environment):
        return all(environment.get(key)==getattr(self,key) for key in
                   ('fx_version','fx_sha256','gvproxy_sha256','fex_build','proton_build','game_build'))


def installed(session):
    result=session.results.get('fx') or session.scan('fx')
    rows=[row for row in result['items'] if row.get('exists') is True and row.get('regular_file') is True]
    from functools import cmp_to_key
    def compare(a,b):
        va=updates.version(facts(a)['version']);vb=updates.version(facts(b)['version'])
        if va and vb:return updates.helpers.compare_versions(vb,va)
        return int(vb is not None)-int(va is not None)
    return sorted(rows,key=cmp_to_key(compare))
