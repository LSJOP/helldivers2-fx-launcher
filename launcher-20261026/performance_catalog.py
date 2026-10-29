"""Profile scope/status metadata, independent of the Apple hardware catalogue.

Do not copy CPU/RAM/graphics values here: the retained profile module owns them.
Historical validation is restricted to its documented chip and memory category.
"""
from copy import deepcopy

PROFILES = ({
    'id':'historical-m4pro-24',
    'chip':'Apple M4 Pro',
    'memory_bytes':24 * 1024**3,
    'status':'verified',
    'name_key':'performance.browser.original',
    'source':'performance_profile.SETTINGS',
    'evidence':'docs/COMPATIBILITY.md',
},)


def profiles_for(chip):
    return [deepcopy(profile) for profile in PROFILES if profile['chip'] == chip]


def parameters(profile, existing):
    if profile.get('source') == 'performance_profile.SETTINGS':
        return deepcopy(existing.SETTINGS)
    # Future profiles must bring real parameters; a chip name creates no preset.
    values = profile.get('parameters')
    return deepcopy(values) if isinstance(values,dict) else {}


def status(profile, existing):
    if not parameters(profile,existing): return 'none'
    state = profile.get('status')
    if state == 'verified' and profile.get('evidence'): return 'verified'
    return 'experimental' if state == 'experimental' else 'none'


def can_apply(profile, device, existing):
    # Only the existing application handler is available in this UI-only change.
    # GPU eligibility is unknown in the historical record, never inferred.
    return (status(profile,existing) == 'verified' and
            profile.get('source') == 'performance_profile.SETTINGS' and
            profile.get('chip') == device.get('chip') and
            profile.get('memory_bytes') == device.get('memory_bytes') and
            parameters(profile,existing) == existing.SETTINGS)
