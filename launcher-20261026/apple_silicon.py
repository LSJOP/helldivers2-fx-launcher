"""Apple chip catalogue and read-only native hardware detection.

The catalogue describes hardware, never performance-profile compatibility.
Only independently published models are listed; see docs/PERFORMANCE_MENU.md.
"""
import json
import os
import re
import subprocess
import sys

SERIES = {
    'M1': ('Apple M1', 'Apple M1 Pro', 'Apple M1 Max', 'Apple M1 Ultra'),
    'M2': ('Apple M2', 'Apple M2 Pro', 'Apple M2 Max', 'Apple M2 Ultra'),
    'M3': ('Apple M3', 'Apple M3 Pro', 'Apple M3 Max', 'Apple M3 Ultra'),
    'M4': ('Apple M4', 'Apple M4 Pro', 'Apple M4 Max'),
    'M5': ('Apple M5', 'Apple M5 Pro', 'Apple M5 Max', 'Apple M5 Ultra'),
}


def chip_name(value):
    if not isinstance(value,str): return None
    value = ' '.join(value.split())
    return value if re.fullmatch(r'Apple M[1-9][0-9]*(?: Pro| Max| Ultra)?',value) else None


def positive_integer(value):
    if isinstance(value,bool): return None
    if isinstance(value,int): return value if value>0 else None
    if isinstance(value,str) and re.fullmatch(r'[0-9]+',value.strip()):
        parsed = int(value.strip())
        return parsed if parsed>0 else None
    return None


def gpu_cores(data, chip):
    """Use one matching built-in Apple GPU, never sum/guess model maxima."""
    if not chip or not isinstance(data,dict): return None
    rows = data.get('SPDisplaysDataType')
    if not isinstance(rows,list): return None
    matching = [row for row in rows if isinstance(row,dict) and
                chip_name(row.get('sppci_model',row.get('_name'))) == chip and
                row.get('sppci_bus') == 'spdisplays_builtin']
    if len(matching) != 1: return None
    return positive_integer(matching[0].get('sppci_cores'))


def _read(args, timeout=5):
    try:
        result = subprocess.run(args,capture_output=True,text=True,timeout=timeout,
                                env=dict(os.environ,LC_ALL='C',LANG='C'))
        return result.stdout.strip() if result.returncode == 0 else None
    except (OSError,subprocess.SubprocessError,UnicodeError): return None


def detect():
    result = {'chip':None,'memory_bytes':None,'gpu_cores':None}
    if sys.platform != 'darwin': return result
    result['chip'] = chip_name(_read(['/usr/sbin/sysctl','-n','machdep.cpu.brand_string']))
    # hw.memsize is unified memory only when the SoC is positively identified.
    memory = _read(['/usr/sbin/sysctl','-n','hw.memsize'])
    if result['chip']: result['memory_bytes'] = positive_integer(memory)
    if result['chip']:
        try:
            data = json.loads(_read(['/usr/sbin/system_profiler','-json','SPDisplaysDataType'],15) or '{}')
            result['gpu_cores'] = gpu_cores(data,result['chip'])
        except (ValueError,TypeError): pass
    return result
