"""Read-only host diagnostics. No guest authentication or game/configuration writes.

The on-demand menu test sends HTTPS only. The launch helper may append a
separate, opt-in PlayFab/UDP launch probe. Process arguments are reduced to
allowlisted evidence before persistence.
"""
from datetime import datetime
import hashlib
import fcntl
import json
import os
from pathlib import Path
import re
import select
import socket
import statistics
import subprocess
import sys
import termios
import threading
import time
import tty
import uuid
from zoneinfo import ZoneInfo

ZONE = ZoneInfo('Asia/Shanghai')
DIRECTORY = Path.home() / 'Library/Application Support/Helldivers2FXLauncher/Diagnostics'
TARGETS = ('www.apple.com', 'www.cloudflare.com')
WINDOWS = (('afternoon', 14, 18), ('evening', 19, 24))
LIMITATION = ('PlayFab TLS and STUN reachability do not prove account login, NAT type, '
              'matchmaking, peer-to-peer connectivity or in-game UDP quality.')


class Cancelled(Exception):
    pass


def stamp():
    return datetime.now(ZONE).isoformat(timespec='seconds')


def _state(value):
    return value if value in ('reachable', 'failed', 'unverified') else 'unverified'


def _milliseconds(value):
    try:
        number = round(float(value), 1)
    except (TypeError, ValueError):
        return None
    return number if 0 <= number <= 120000 else None


def _count(value):
    try:
        return max(0, min(1000000000, int(value or 0)))
    except (TypeError, ValueError):
        return 0


def record_launch_probe(result, store=None):
    """Persist a launch-time probe after reducing it to an allowlisted shape."""
    if not isinstance(result, dict):
        raise ValueError('Invalid launch probe result')
    playfab = result.get('playfab') if isinstance(result.get('playfab'), dict) else {}
    routes = playfab.get('routes') if isinstance(playfab.get('routes'), dict) else {}
    udp = result.get('udp') if isinstance(result.get('udp'), dict) else {}
    samples = udp.get('samples') if isinstance(udp.get('samples'), list) else []
    valid_samples = [s for s in samples if isinstance(s, dict) and type(s.get('ok')) is bool]
    rtts = []
    for sample in valid_samples:
        rtt = _milliseconds(sample.get('ms'))
        if sample['ok'] and rtt is not None:
            rtts.append(rtt)

    def route(name):
        value = routes.get(name) if isinstance(routes.get(name), dict) else {}
        return _state(value.get('state')), _milliseconds(value.get('ms'))

    direct_state, direct_ms = route('direct')
    proxy_state, proxy_ms = route('proxy')
    record = {
        'kind': 'launch_probe',
        'time': stamp(),
        'playfab_target': 'title.playfabapi.com',
        'playfab_direct': direct_state,
        'playfab_direct_ms': direct_ms,
        'playfab_proxy': proxy_state,
        'playfab_proxy_ms': proxy_ms,
        'udp_samples': len(valid_samples),
        'udp_successes': sum(sample['ok'] for sample in valid_samples),
        'udp_rtt_ms': rtts,
        'udp_jitter_ms': _milliseconds(udp.get('jitter_ms')),
        'game_udp_sockets': _count(udp.get('game_sockets')),
        'game_udp_connected': _count(udp.get('connected_sockets')),
        'udp_in_datagrams_delta': _count(udp.get('in_datagrams_delta')),
        'udp_out_datagrams_delta': _count(udp.get('out_datagrams_delta')),
    }
    (store or Store()).append(record)
    return record


def command(args, timeout=2, cancel=None):
    """Bounded subprocess, including DNS; cancellation terminates and reaps child."""
    if cancel and cancel.is_set():
        raise Cancelled()
    started = time.monotonic()
    with subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                          text=True, env={'PATH': '/usr/bin:/bin:/usr/sbin:/sbin',
                                          'LC_ALL': 'en_US.UTF-8', 'LANG': 'en_US.UTF-8'}) as process:
        try:
            while True:
                if cancel and cancel.is_set():
                    raise Cancelled()
                remaining = timeout - (time.monotonic() - started)
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(args, timeout)
                try:
                    output, _ = process.communicate(timeout=min(.1, remaining))
                    return process.returncode, output
                except subprocess.TimeoutExpired:
                    continue
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()


def optional_command(args):
    try:
        code, output = command(args)
        return output if code == 0 else None
    except (OSError, subprocess.TimeoutExpired):
        return None


def snapshot(app, binary, wrapper, expected_hash, port=7890):
    # macOS truncates comm to 16 characters when another text column follows.
    # Read executable and argv separately, each as the final column.
    raw = optional_command(['/bin/ps', '-ww', '-axo', 'pid=,ppid=,comm='])
    argv_raw = optional_command(['/bin/ps', '-ww', '-axo', 'pid=,args='])
    rows = []
    for line in (raw or '').splitlines():
        match = re.match(r'^\s*(\d+)\s+(\d+)\s+(.+)$', line)
        if match:
            rows.append((match[1], match[3].strip()))
    arguments = {}
    for line in (argv_raw or '').splitlines():
        match = re.match(r'^\s*(\d+)\s+(.+)$', line)
        if match:
            arguments[match[1]] = match[2]
    fx_rows = [r for r in rows if r[1].startswith(app + '/Contents/MacOS/')]
    gv_rows = [r for r in rows if Path(r[1]).name.startswith('gvproxy')]
    expected = [r for r in gv_rows if r[1] == str(binary)]
    try:
        with Path(binary).open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest() if hasattr(hashlib, 'file_digest') else hashlib.sha256(stream.read()).hexdigest()
        binary_valid = digest == expected_hash
    except OSError:
        binary_valid = None
    try:
        wrapper_valid = Path(wrapper).read_text() == (
            '#!/bin/sh\nexport GVPROXY_UDP_PORT_MAPPING=endpoint-independent\n'
            'steamac_network_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || exit 1\n'
            'exec "$steamac_network_dir/gvproxy-eim" "$@"\n')
    except OSError:
        wrapper_valid = None
    argument_valid = (any(' -listen-vfkit ' in arguments.get(r[0], '') for r in expected)
                      if argv_raw is not None else None)
    wrapper_selected = (any(re.search(r' --gvproxy ' + re.escape(str(wrapper)) + r'(?:\s|$)',
                                        arguments.get(r[0], '')) for r in fx_rows)
                        if argv_raw is not None else None)
    # Persist flags/booleans only, never raw arguments, IPs or paths.
    evidence = {'expected_executable': bool(expected) if raw is not None else None,
                'listen_vfkit': argument_valid if raw is not None else None,
                'wrapper_selected': wrapper_selected if raw is not None else None,
                'binary_checksum': binary_valid, 'wrapper_content': wrapper_valid,
                'runtime_mapping': 'unverified'}
    try:
        with socket.create_connection(('127.0.0.1', port), timeout=.4):
            proxy = True
    except OSError:
        proxy = False
    route = optional_command(['/sbin/route', '-n', 'get', '-inet', 'default'])
    match = re.search(r'^\s*interface:\s*([\w.-]+)', route or '', re.M)
    interface = match[1] if match else None
    addresses = optional_command(['/sbin/ifconfig', interface]) if interface else None
    return {'id': uuid.uuid4().hex, 'kind': 'snapshot', 'time': stamp(),
            'process_detection': 'separate_executable_argv_v2',
            'fx': bool(fx_rows) if raw is not None else None,
            'gvproxy': bool(gv_rows) if raw is not None else None,
            'steam': None, 'steam_scope': 'guest_unverified_no_ssh',
            'proxy_port': port, 'proxy_open': proxy, 'proxy_forwarding': 'unverified',
            'interface': interface, 'ipv4': bool(re.search(r'\binet ', addresses)) if addresses is not None else None,
            'ipv6': bool(re.search(r'\binet6 ', addresses)) if addresses is not None else None,
            'eim': evidence, 'udp_configuration': 'detected' if all(evidence.get(k) is True for k in
                ('expected_executable', 'listen_vfkit', 'wrapper_selected', 'binary_checksum', 'wrapper_content')) else 'unverified',
            'udp_connectivity': 'unverified', 'nat': 'unknown'}


class Store:
    def __init__(self, directory=DIRECTORY):
        self.directory = Path(directory)

    def append(self, record):
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        payload = (json.dumps(record, ensure_ascii=False) + '\n').encode('utf-8')
        fd = os.open(self.directory / 'history.jsonl', os.O_APPEND | os.O_CREAT | os.O_RDWR, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX)
            os.fchmod(fd, 0o600)
            size = os.fstat(fd).st_size
            # Preserve interrupted data, but isolate it from the next valid row.
            if size and os.pread(fd, 1, size - 1) != b'\n':
                payload = b'\n' + payload
            pending = memoryview(payload)
            while pending:
                pending = pending[os.write(fd, pending):]
        finally:
            os.close(fd)  # Also releases the advisory lock.

    def read(self, start=None, end=None):
        """ISO date or offset-aware ISO timestamp, inclusive start/exclusive end."""
        def parse(value):
            dt = datetime.fromisoformat(value)
            return dt.replace(tzinfo=ZONE) if dt.tzinfo is None else dt.astimezone(ZONE)
        lower, upper = parse(start) if start else None, parse(end) if end else None
        records = []
        snapshots = {}
        invalidations = {}
        try:
            with (self.directory / 'history.jsonl').open(encoding='utf-8') as stream:
                for line in stream:
                    try:
                        row = json.loads(line)
                        moment = parse(row['time'])
                        if row.get('kind') == 'snapshot_invalidation' and isinstance(row.get('snapshot_id'), str):
                            invalidations[row['snapshot_id']] = row
                        if row.get('kind') == 'snapshot' and isinstance(row.get('id'), str):
                            snapshots[row['id']] = row
                        if (lower is None or moment >= lower) and (upper is None or moment < upper):
                            records.append(row)
                    except (ValueError, KeyError, TypeError):
                        continue  # An interrupted final write must not erase earlier records.
        except FileNotFoundError:
            pass
        # Preserve original lines for audit, but do not use known bad process
        # readings as evidence when displaying/exporting historical records.
        for key, correction in invalidations.items():
            if key in snapshots:
                target = snapshots[key]
                for field in ('fx', 'gvproxy'):
                    if field in correction.get('fields', []):
                        target[field] = None
                if isinstance(target.get('eim'), dict):
                    for field in ('expected_executable', 'listen_vfkit', 'wrapper_selected'):
                        target['eim'][field] = None
                target['udp_configuration'] = 'unverified'
                target['process_evidence_invalidated'] = True
        # A match/test immediately after midnight can refer to a snapshot just
        # before the query boundary. Retain only those required dependencies.
        included = {r.get('id') for r in records if r.get('kind') == 'snapshot'}
        references = {r.get('snapshot_id') for r in records
                      if r.get('kind') in ('match', 'test') and isinstance(r.get('snapshot_id'), str)}
        return [snapshots[key] for key in sorted(references - included) if key in snapshots] + records

    def record_match(self, result, current, note=''):
        if result not in ('success', 'timeout', 'disconnect'):
            raise ValueError('Invalid match result')
        self.append(current)
        row = {'kind': 'match', 'time': stamp(), 'snapshot_id': current['id'],
               'result': result, 'snapshot_scope': 'record_submission', 'note': redact_note(note)}
        self.append(row)
        return row

    def windows(self):
        path = self.directory / 'diagnostic-settings.json'
        if not path.exists():
            return WINDOWS
        try:
            data = json.loads(path.read_text(encoding='utf-8'))['windows']
        except (TypeError, KeyError):
            raise ValueError('Invalid diagnostic time windows') from None
        if not isinstance(data, list) or not data or not all(isinstance(r, list) and len(r) == 3 and
                isinstance(r[0], str) and all(type(v) is int for v in r[1:]) and
                0 <= r[1] < r[2] <= 24 for r in data):
            raise ValueError('Invalid diagnostic time windows')
        return data

    def export(self, records, windows):
        """Allowlist exported fields; free text never exported, even if imported."""
        clean = []
        fields = {'snapshot': ('id', 'time', 'process_detection', 'process_evidence_invalidated', 'fx', 'gvproxy', 'steam', 'proxy_open',
                    'ipv4', 'ipv6', 'eim', 'udp_configuration', 'udp_connectivity', 'nat'),
                  'match': ('time', 'snapshot_id', 'snapshot_scope', 'result'),
                  'test': ('time', 'snapshot_id', 'cancelled', 'host_dns', 'samples'),
                  'launch_probe': ('time', 'playfab_target', 'playfab_direct', 'playfab_direct_ms',
                                   'playfab_proxy', 'playfab_proxy_ms', 'udp_samples', 'udp_successes',
                                   'udp_rtt_ms', 'udp_jitter_ms', 'game_udp_sockets',
                                   'game_udp_connected', 'udp_in_datagrams_delta',
                                   'udp_out_datagrams_delta')}
        for row in records:
            kind = row.get('kind')
            if kind not in fields:
                continue
            item = {key: row[key] for key in fields[kind] if key in row}
            if kind == 'snapshot' and 'eim' in item:
                evidence = item['eim'] if isinstance(item['eim'], dict) else {}
                item['eim'] = {key: evidence[key] if type(evidence[key]) is bool else None for key in (
                    'expected_executable', 'listen_vfkit', 'wrapper_selected',
                    'binary_checksum', 'wrapper_content') if key in evidence}
                item['eim']['runtime_mapping'] = 'unverified'
            if kind == 'test':
                item['samples'] = [{k: s[k] for k in ('target', 'route', 'dns', 'tcp_ms', 'https', 'total_ms', 'failure')
                                    if k in s} for s in row.get('samples', [])]
            clean.append(dict(item, kind=kind))
        # Defense in depth against unexpected text in allowlisted imported fields.
        clean = scrub(clean)
        data = {'version': 1, 'time': stamp(), 'limitations': LIMITATION,
                'records': clean, 'statistics': scrub(summarize(clean, windows)),
                'privacy': 'IPs, interfaces, paths, process arguments and notes omitted'}
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        path = self.directory / ('report-' + uuid.uuid4().hex + '.json')
        fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            json.dump(data, stream, ensure_ascii=False, indent=2)
        return path


def redact_note(note):
    # Notes are optional: suppress any potentially secret-bearing content as a
    # whole, rather than trying to recognize every subscription/password format.
    text = ''.join(c if c >= ' ' and c != '\x7f' else ' ' for c in str(note)[:500])
    text = text.replace(Path.home().name, '[USER]')
    if re.search(r'(?i)https?://|password|passwd|token|api.?key|secret|订阅|密码|密钥|authorization|bearer|username|user[=:]|账号|用户名|ssh|sk-[A-Za-z0-9]|[A-Za-z0-9_=-]{32,}|://|/Users/|/Volumes/|(?:\d{1,3}\.){3}\d{1,3}|[\w.-]+@[\w.-]+|[a-fA-F0-9]*:[a-fA-F0-9:]+', text):
        return '[REDACTED]'
    return text


def scrub(value):
    if isinstance(value, dict):
        return {k: scrub(v) for k, v in value.items()}
    if isinstance(value, list):
        return [scrub(v) for v in value]
    if isinstance(value, str):
        if re.search(r'(?:\d{1,3}\.){3}\d{1,3}|/Users/|/Volumes/|https?://|[a-fA-F0-9]*:[a-fA-F0-9:]+', value) and not re.match(r'^\d{4}-\d\d-\d\dT', value):
            return '[REDACTED]'
        username = Path.home().name
        return value.replace(username, '[USER]') if username else value
    return value


def summarize(records, windows=WINDOWS):
    output = []
    for name, start, end in windows:
        selected = []
        for row in records:
            try:
                moment = datetime.fromisoformat(row['time']).astimezone(ZONE)
            except (ValueError, KeyError, TypeError):
                continue
            if start <= moment.hour < end:
                selected.append(row)
        matches = [r for r in selected if r.get('kind') == 'match' and r.get('result') in ('success', 'timeout', 'disconnect')]
        successes = sum(r['result'] == 'success' for r in matches)
        snapshots = {r.get('id'): r for r in records if r.get('kind') == 'snapshot'}
        failures = [snapshots.get(r.get('snapshot_id'), {}) for r in matches if r['result'] != 'success']
        tests = [r for r in selected if r.get('kind') == 'test']
        routes = {}
        for route in ('direct', 'proxy'):
            samples = [s for r in tests for s in r.get('samples', []) if s.get('route') == route]
            times = [s['tcp_ms'] for s in samples if s.get('tcp_ms') is not None]
            https_times = [s['total_ms'] for s in samples if s.get('https') and s.get('total_ms') is not None]
            routes[route] = {'https_mean_ms': round(statistics.mean(https_times), 2) if https_times else None,
                             'https_stdev_ms': round(statistics.pstdev(https_times), 2) if https_times else None,
                             'dns_failures': sum(s.get('dns') == 'failed' for s in samples), 'samples': len(samples), 'failures': sum(bool(s.get('failure')) for s in samples),
                             'tcp_mean_ms': round(statistics.mean(times), 2) if times else None,
                             'tcp_stdev_ms': round(statistics.pstdev(times), 2) if times else None}
        output.append({'window': name, 'hours': [start, end], 'attempts': len(matches),
                       'successes': successes, 'timeouts': sum(r['result'] == 'timeout' for r in matches),
                       'disconnects': sum(r['result'] == 'disconnect' for r in matches),
                       'success_rate': round(100 * successes / len(matches), 1) if matches else None,
                       'small_sample': len(matches) < 10,
                       'failures_with_fx_observed': sum(r.get('fx') is True for r in failures),
                       'failures_with_gvproxy_observed': sum(r.get('gvproxy') is True for r in failures),
                       'failures_with_proxy_open': sum(r.get('proxy_open') is True for r in failures),
                       'quality': routes})
    return output


def probe(host, route, cancel, timeout=2.5, runner=command):
    row = {'target': host, 'route': route, 'dns': 'unverified', 'tcp_ms': None,
           'https': False, 'total_ms': None, 'failure': None}
    args = ['/usr/bin/curl', '--disable', '--silent', '--output', '/dev/null',
            '--connect-timeout', str(timeout), '--max-time', str(timeout),
            '--noproxy', '*' if route == 'direct' else '', '--proxy',
            '' if route == 'direct' else 'http://127.0.0.1:7890',
            '--write-out', '%{http_code} %{time_connect} %{time_total}', 'https://' + host + '/']
    try:
        code, raw = runner(args, timeout=timeout + .15, cancel=cancel)
        values = raw.split()
        status, tcp, total = int(values[0]), float(values[1]), float(values[2])
        row.update(tcp_ms=round(tcp * 1000, 2) if tcp > 0 else None,
                   total_ms=round(total * 1000, 2), https=code == 0 and 200 <= status < 400)
        row['dns'] = 'failed' if code == 6 else ('resolved' if route == 'direct' and tcp > 0 else 'unverified')
        row['failure'] = None if row['https'] else ('dns' if code == 6 else 'timeout' if code == 28 else 'https')
    except (OSError, ValueError, IndexError, subprocess.TimeoutExpired):
        row['failure'] = 'timeout_or_unavailable'
    return row


def network_test(snapshot_id, cancel=None, runner=command):
    cancel = cancel or threading.Event()
    result = {'kind': 'test', 'time': stamp(), 'snapshot_id': snapshot_id,
              'cancelled': False, 'samples': [], 'limitations': LIMITATION,
              'host_dns': 'unverified'}
    started = time.monotonic()
    try:
        try:
            code, raw = runner(['/usr/bin/dscacheutil', '-q', 'host', '-a', 'name', TARGETS[0]],
                               timeout=1.5, cancel=cancel)
            result['host_dns'] = 'resolved' if code == 0 and re.search(r'(?:ip|ipv6)_address:', raw) else 'failed'
        except (OSError, subprocess.TimeoutExpired):
            result['host_dns'] = 'failed'
        # Four samples/route; a hard wall-clock budget also bounds failed DNS.
        for index in range(8):
            if cancel.is_set():
                raise Cancelled()
            remaining = 14 - (time.monotonic() - started)
            if remaining < .3:
                break
            result['samples'].append(probe(TARGETS[(index // 2) % 2],
                'direct' if index % 2 == 0 else 'proxy', cancel, min(1.5, remaining - .15), runner))
            if cancel.wait(min(1.2, max(0, 14 - (time.monotonic() - started)))):
                raise Cancelled()
    except Cancelled:
        result['cancelled'] = True
    return result


def words(language, zh, en):
    return zh if language.startswith('zh') else en


def status_lines(current, language):
    def state(value, port=False):
        if value is None:
            return words(language, '未验证', 'UNVERIFIED')
        if port:
            return words(language, '开放', 'OPEN') if value else words(language, '不可连接', 'UNREACHABLE')
        return words(language, '运行中', 'RUNNING') if value else words(language, '未运行', 'STOPPED')
    return [current['time'],
            'FX: ' + state(current['fx']) + '   GVPROXY: ' + state(current['gvproxy']),
            'STEAM (FX): ' + state(current['steam']) + '   PROXY: ' + state(current['proxy_open'], port=True),
            'UDP CONFIG: ' + current['udp_configuration'].upper(),
            'UDP: UNVERIFIED   NAT: UNKNOWN',
            'IPv4: ' + str(current['ipv4']) + '   IPv6: ' + str(current['ipv6']) + '   IF: ' + (current['interface'] or '?'),
            words(language, '进程/端口不代表转发正常；运行时 EIM 未验证。', 'Process/port presence does not verify forwarding or runtime EIM.')]


def build_frame(ui, columns, rows, current, language, selected='1'):
    frame = ui.Frame(columns, rows)
    frame.put(0, 1, words(language, '多人联机诊断', 'NETWORK DIAGNOSTICS'), 'yellow', bold=True)
    options = [('1', words(language, '运行网络测试', 'Run network test')),
               ('2', words(language, '记录匹配结果', 'Record match result')),
               ('3', words(language, '查看历史统计', 'History statistics')),
               ('4', words(language, '导出诊断报告', 'Export diagnostic report')),
               ('5', words(language, '成功网络方案设置', 'Successful network profile')),
               ('6', words(language, '刷新快照/配置证据', 'Refresh snapshot / evidence')),
               ('0', words(language, '返回主菜单', 'Back'))]
    # Short terminals keep every action visible; option 6 shows full evidence.
    available = max(0, frame.rows - len(options) - 4)
    lines = status_lines(current, language)
    for row, line in enumerate(lines[:available], 2):
        frame.put(row, 1, line, 'muted', limit=frame.columns - 2)
    start = min(2 + len(lines), frame.rows - len(options) - 2)
    if frame.rows >= 24 and frame.columns >= 60:
        for index, line in enumerate(ui.emblem('2', 18, 6)):
            frame.put(1 + index, frame.columns - 20, line, 'yellow')
        # Keep status clear of the original skull asset.
        for row, line in enumerate(lines, 2):
            frame.fill(row, 0, frame.columns - 21)
            frame.put(row, 1, line, 'muted', limit=frame.columns - 23)
    for index, (key, label) in enumerate(options):
        y = start + index
        focused = key == selected
        frame.put(y, 1, '[' + key + '] ' + label, 'background' if focused else 'yellow',
                  'yellow' if focused else 'background', limit=frame.columns - 2)
        frame.positions[key] = (y, 1, frame.columns - 2)
    frame.put(frame.rows - 1, 1, '↑↓ Enter / 0–6 / Esc', 'muted', limit=frame.columns - 2)
    return frame


def choose(ui, current, language):
    if not (sys.stdin.isatty() and sys.stdout.isatty() and os.environ.get('TERM') != 'dumb'):
        print('\n'.join(status_lines(current, language)))
        size = ui.terminal_size()
        print(build_frame(ui, size.columns, size.lines, current, language).plain())
        return input('> ').strip()
    fd = sys.stdin.fileno()
    previous = termios.tcgetattr(fd)
    values = ['1', '2', '3', '4', '5', '6', '0']
    index = 0
    last_draw = None
    try:
        tty.setcbreak(fd)
        sys.stdout.write('\033[?1049h\033[?25l')
        while True:
            size = ui.terminal_size()
            signature = (size.columns, size.lines, index)
            if signature != last_draw:
                frame = build_frame(ui, size.columns, size.lines, current, language, values[index])
                sys.stdout.write(frame.ansi('NO_COLOR' not in os.environ))
                sys.stdout.flush()
                last_draw = signature
            if not select.select([fd], [], [], .15)[0]:
                continue
            key = os.read(fd, 1)
            if key in (b'\r', b'\n'):
                return values[index]
            if key == b'\x1b':
                if not select.select([fd], [], [], .08)[0]:
                    return '0'
                sequence = os.read(fd, 2)
                if sequence == b'[A':
                    index = (index - 1) % len(values)
                elif sequence == b'[B':
                    index = (index + 1) % len(values)
            elif key in (b'\x03', b'\x04', b''):
                return '0'
            elif key == b'\t':
                index = (index + 1) % len(values)
            elif key.decode(errors='ignore') in values:
                index = values.index(key.decode())
    finally:
        termios.tcsetattr(fd, termios.TCSANOW, previous)
        sys.stdout.write('\033[0m\033[?7h\033[?25h\033[?1049l')
        sys.stdout.flush()


def show_details(menu, title, lines):
    # Existing scrolling list handles even 20x10 terminals and both languages.
    width = max(8, menu.ui2.terminal_size().columns - 10)
    wrapped = []
    for line in lines:
        part = ''
        for char in str(line):
            if menu.ui2.text_width(part + char) > width:
                wrapped.append(part)
                part = ''
            part += char
        wrapped.append(part)
    options = [('d' + str(i), line) for i, line in enumerate(wrapped)]
    options.append(('0', words(menu.LANG, '[0] 返回', '[0] Back')))
    while menu.select_option(title, options, '0') != '0':
        pass


def run_test_ui(menu, snapshot_id):
    print(words(menu.LANG, '测试 Apple/Cloudflare 公共站点，约 10–15 秒上限；路径可能与游戏不同。',
                'Testing public Apple/Cloudflare sites, 10–15s maximum; routes may differ from the game.'))
    print(words(menu.LANG, '直连 TCP 测远端；代理 TCP 仅测本机端口。按 q/Esc/Ctrl-C 取消。',
                'Direct TCP measures remote connect; proxy TCP measures localhost only. q/Esc/Ctrl-C cancels.'))
    cancel = threading.Event()
    box = {}
    def work():
        try:
            box['result'] = network_test(snapshot_id, cancel)
        except Exception:
            box['error'] = True
    worker = threading.Thread(target=work, daemon=True)
    fd = sys.stdin.fileno() if sys.stdin.isatty() else None
    previous = termios.tcgetattr(fd) if fd is not None else None
    try:
        if fd is not None:
            tty.setcbreak(fd)
        worker.start()
        while worker.is_alive():
            if fd is not None and select.select([fd], [], [], .1)[0]:
                if os.read(fd, 1) in (b'q', b'Q', b'\x1b', b'\x03', b'\x04', b''):
                    cancel.set()
            else:
                worker.join(.1)
    except KeyboardInterrupt:
        cancel.set()
    finally:
        cancel.set()
        worker.join(2)
        if previous is not None:
            termios.tcsetattr(fd, termios.TCSANOW, previous)
    if 'error' in box or 'result' not in box:
        raise OSError('Diagnostic test unavailable')
    return box['result']


def history_range(menu, store):
    print(words(menu.LANG, '按北京时间查询：YYYY-MM-DD；留空为全部，结束日期不包含在内。',
                'Filter in Asia/Shanghai: YYYY-MM-DD; blank = all, end date exclusive.'))
    start = input(words(menu.LANG, '开始日期: ', 'Start date: ')).strip()
    end = input(words(menu.LANG, '结束日期: ', 'End date: ')).strip()
    return store.read(start or None, end or None)


def run(menu):
    store = Store()
    def capture():
        return snapshot(menu.helper.APP, menu.helper.GVPROXY, menu.helper.GVPROXY_WRAPPER,
                        menu.helper.GVPROXY_SHA256)
    current = capture()
    try:
        store.append(current)
        while True:
            choice = choose(menu.ui2, current, menu.LANG)
            if choice == '0':
                return
            if choice == '5':
                menu.network_menu()
                continue
            if choice in ('1', '2', '6'):
                current = capture()
                store.append(current)
            if choice == '1':
                result = run_test_ui(menu, current['id'])
                store.append(result)
                show_details(menu, words(menu.LANG, '网络测试（不验证游戏 UDP）', 'TEST RESULTS (game UDP unverified)'),
                             [words(menu.LANG, '已取消: ', 'Cancelled: ') + str(result['cancelled']),
                              'Host DNS: ' + result['host_dns']] + [
                                 s['target'] + ' / ' + s['route'] + ' / DNS=' + s['dns'] +
                                 ' / TCP=' + str(s['tcp_ms']) + 'ms / HTTPS=' + str(s['https']) +
                                 ' / ' + str(s['failure']) for s in result['samples']] + [
                                 words(menu.LANG, '代理 TCP 仅本机端口；HTTPS 含 TLS/HTTP；非游戏 UDP 延迟。',
                                       'Proxy TCP = localhost; HTTPS includes TLS/HTTP; not game UDP latency.'),
                                 words(menu.LANG, '小样本不能确定线路、NAT 或匹配服务故障。',
                                       'Small samples cannot establish a route, NAT or matchmaking service fault.')])
            elif choice == '2':
                answer = menu.select_option(words(menu.LANG, '记录匹配结果', 'RECORD MATCH RESULT'), [
                    ('1', words(menu.LANG, '[1] 匹配成功', '[1] Match success')),
                    ('2', words(menu.LANG, '[2] 加入大厅超时', '[2] Lobby timed out')),
                    ('3', words(menu.LANG, '[3] 连接中断', '[3] Disconnected')),
                    ('0', words(menu.LANG, '[0] 取消记录', '[0] Cancel'))])
                if answer in ('1', '2', '3'):
                    note = input(words(menu.LANG, '可选备注（不要输入账号/密码/订阅）: ',
                                       'Optional note (no accounts/passwords/subscriptions): '))
                    # Capture at submission, never attach a stale entry snapshot.
                    current = capture()
                    store.record_match({'1': 'success', '2': 'timeout', '3': 'disconnect'}[answer], current, note)
            elif choice in ('3', '4'):
                records = history_range(menu, store)
                windows = store.windows()
                if choice == '4':
                    path = store.export(records, windows)
                    print(words(menu.LANG, '已导出（备注、地址、路径默认省略）: ',
                                'Exported (notes, addresses and paths omitted): ') + str(path))
                    input(words(menu.LANG, '回车继续', 'Return to continue'))
                else:
                    lines = []
                    for item in summarize(records, windows):
                        lines.append('{} {}:00–{}:00'.format(item['window'], *item['hours']))
                        lines.append(words(menu.LANG, '尝试/成功/超时/中断/成功率: ', 'Attempts/success/timeout/disconnect/rate: ') +
                            '/'.join(str(item[k]) for k in ('attempts', 'successes', 'timeouts', 'disconnects', 'success_rate')))
                        if item['small_sample']:
                            lines.append(words(menu.LANG, '样本不足 10 次，仅供参考；无记录时成功率未知。',
                                               'Fewer than 10 matches: reference only; no records means unknown rate.'))
                        lines.append(words(menu.LANG, '记录失败结果时观测到 FX/gvproxy/代理端口: ', 'Failure records with observed FX/gvproxy/proxy port: ') +
                            '/'.join(str(item[k]) for k in ('failures_with_fx_observed', 'failures_with_gvproxy_observed', 'failures_with_proxy_open')))
                        for route, data in item['quality'].items():
                            lines.append(route + ' samples/fail/mean TCP ms/stdev ms: ' + '/'.join(str(data[k]) for k in
                                ('samples', 'failures', 'tcp_mean_ms', 'tcp_stdev_ms')))
                            lines.append(route + ' HTTPS mean/stdev ms: ' + str(data['https_mean_ms']) + '/' + str(data['https_stdev_ms']))
                    lines.append(words(menu.LANG, '相关性不能证明原因；UDP/NAT/匹配服务仍未验证。',
                                       'Correlation does not establish cause; UDP/NAT/matchmaking remain unverified.'))
                    show_details(menu, words(menu.LANG, '历史统计', 'HISTORY'), lines)
            elif choice == '6':
                show_details(menu, words(menu.LANG, '只读配置证据', 'READ-ONLY EVIDENCE'),
                    status_lines(current, menu.LANG) + [k + ': ' + str(v) for k, v in current['eim'].items()] + [
                        words(menu.LANG, 'IPv4/IPv6 仅表示默认接口有地址；不验证外网连通性。',
                              'IPv4/IPv6 mean address presence on default interface, not internet reachability.'),
                        words(menu.LANG, '磁盘组件/启动参数符合预期也无法证明运行时映射和 UDP 正常。',
                              'Matching disk components/arguments cannot prove runtime mapping or UDP health.')])
    except (KeyboardInterrupt, EOFError):
        return
    except (OSError, ValueError, KeyError) as error:
        print(words(menu.LANG, '诊断未完成；请检查诊断目录权限或时间段配置。',
                    'Diagnostics incomplete; check diagnostic directory permissions or time-window settings.'))
