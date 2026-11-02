#!/usr/bin/env python3
"""JSONL v1 bridge: read-only refresh and allowlisted, explicit Core actions."""
import contextlib
import os
from datetime import datetime, timezone
import importlib.util
import json
from pathlib import Path
import re
import signal
import sys

PROTOCOL = 1
MAX_LINE = 65536
METHODS = ('handshake', 'get_launcher_version', 'get_system_info', 'get_environment_status',
           'get_dependencies', 'list_fx_versions', 'get_logs', 'inspect_launch_target')


class Deadline(Exception):
    pass


def alarm_handler(signum, frame):
    raise Deadline()


def stamp():
    return datetime.now(timezone.utc).isoformat()


def error(rid, code, message, details=None):
    return {'protocol': PROTOCOL, 'request_id': rid, 'ok': False,
            'error': {'code': code, 'message': message, 'details': details or {}}}


def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate field')
        result[key] = value
    return result


class Bridge:
    def __init__(self, adapter):
        self.adapter = adapter
        here=Path(__file__).resolve().parent
        spec=importlib.util.spec_from_file_location('native_operations',here/'legacy_operations.py')
        self.operations_module=importlib.util.module_from_spec(spec);spec.loader.exec_module(self.operations_module)
        root=here.parent/'legacy' if (here.parent/'legacy').is_dir() else here.parent/'CoreSnapshot'
        self.operations=self.operations_module.Operations(root)
        self.active_rid=None
        self.event_sink=lambda row: None
        self.operations.emit=self.emit_event
        self.logs = [{'at': stamp(), 'message': 'Read-only bridge started'}]

    def emit_event(self, row):
        row=dict(at=stamp(),source='core',**row)
        self.logs.append(row);self.logs=self.logs[-100:]
        self.event_sink({'protocol':1,'request_id':self.active_rid,'event':row})

    def reply(self, request):
        rid = request.get('request_id')
        if not isinstance(rid, str) or not re.fullmatch(r'[A-Za-z0-9_-]{1,128}', rid):
            return error(None, 'INVALID_ARGUMENT', 'A valid request_id is required')
        if type(request.get('protocol')) is not int or request['protocol'] != PROTOCOL:
            return error(rid, 'PROTOCOL_MISMATCH', 'Only protocol version 1 is supported')
        if set(request) - {'request_id', 'protocol', 'method', 'params', 'timeout_ms'}:
            return error(rid, 'INVALID_ARGUMENT', 'Unexpected request fields')
        params = request.get('params', {})
        method = request.get('method')
        timeout = request.get('timeout_ms', 3000)
        operation = isinstance(method,str) and method in self.operations_module.OPERATIONS
        target_inspection = method == 'inspect_launch_target'
        if not isinstance(method, str) or not isinstance(params, dict) or (params and not operation and not target_inspection) or type(timeout) is not int or not 1 <= timeout <= (900000 if operation else 5000):
            return error(rid, 'INVALID_ARGUMENT', 'Invalid method, parameters or timeout')
        if target_inspection and (set(params) != {'runtime_root'} or not isinstance(params['runtime_root'], str) or not params['runtime_root'] or len(params['runtime_root']) > 4096 or '\x00' in params['runtime_root']):
            return error(rid, 'INVALID_ARGUMENT', 'A selected runtime directory is required')
        if method not in METHODS and not operation:
            return error(rid, 'NOT_IMPLEMENTED', 'Method is unavailable')
        self.active_rid=rid
        try:
            signal.signal(signal.SIGALRM, alarm_handler)
            signal.setitimer(signal.ITIMER_REAL, timeout / 1000)
            # Audited legacy imports/prints may never contaminate protocol stdout.
            with contextlib.redirect_stdout(sys.stderr):
                if method == 'handshake':
                    result = {'protocol_min': 1, 'protocol_max': 1, 'capabilities': list(METHODS)+list(self.operations_module.OPERATIONS), 'read_only': False, 'permission_model':'explicit_actions', 'read_only_default':True}
                elif target_inspection:
                    result = self.adapter.launch_target(params['runtime_root'])
                elif operation:
                    result=self.operations.run(method,params)
                    # Normalize Path results without publishing raw exception messages.
                    result=json.loads(json.dumps(result,default=lambda value: str(value) if isinstance(value,Path) else None))
                elif method == 'get_logs':
                    result = {'entries': self.logs[-100:], 'source': 'bridge_process_session',
                              'game_logs': 'NOT_IMPLEMENTED', 'next_cursor': None}
                else:
                    name = {'get_launcher_version': 'launcher_version',
                            'get_system_info': 'system_info',
                            'get_environment_status': 'environment',
                            'get_dependencies': 'dependency_info',
                            'list_fx_versions': 'fx_versions'}[method]
                    result = getattr(self.adapter, name)()
            response = {'protocol': PROTOCOL, 'request_id': rid, 'ok': True, 'result': result,
                        'observed_at': stamp()}
        except self.operations_module.OperationError as failure:
            details=dict(failure.details)
            for key in ('summary','stderr','stdout','message'):
                if isinstance(details.get(key),str):details[key]=self.operations.scrub(details[key])
            response=error(rid,failure.code,'Core operation requires attention',details)
        except Deadline:
            response = error(rid, 'TIMEOUT', 'Operation timed out; recheck actual state')
        except (OSError, ValueError, RuntimeError, AttributeError, TypeError, KeyError) as failure:
            # Never serialize raw paths, configuration contents or exception strings.
            print('Read-only Core operation unavailable', file=sys.stderr, flush=True)
            response = error(rid, 'CORE_UNAVAILABLE', 'Core data is unavailable', {'summary':self.operations.scrub(str(failure))} if operation else {})
        finally:
            signal.setitimer(signal.ITIMER_REAL, 0)
        self.logs.append({'at': stamp(), 'message': method + ': ' + ('OK' if response['ok'] else response['error']['code'])})
        self.logs = self.logs[-100:]
        return response


def serve(adapter, input_stream, output_stream):
    bridge = Bridge(adapter)
    def emit(row):
        output_stream.write(json.dumps(row,ensure_ascii=False,default=str)+'\n');output_stream.flush()
    bridge.event_sink=emit
    def cancelled(signum,frame):
        raise bridge.operations_module.OperationError('CANCELLED')
    signal.signal(signal.SIGTERM,cancelled)
    while True:
        line = input_stream.readline(MAX_LINE + 1)
        if not line:
            return
        if len(line) > MAX_LINE:
            response = error(None, 'PROTOCOL_ERROR', 'Request exceeds frame limit')
            output_stream.write(json.dumps(response) + '\n'); output_stream.flush()
            return  # Do not drain an unbounded malicious frame.
        try:
            request = json.loads(line, object_pairs_hook=unique_pairs,
                                 parse_constant=lambda value: (_ for _ in ()).throw(ValueError('Nonfinite number')))
            if not isinstance(request, dict):
                raise ValueError('Expected object')
            response = bridge.reply(request)
        except (ValueError, UnicodeError, RecursionError):
            response = error(None, 'PROTOCOL_ERROR', 'Malformed JSON request')
        payload = json.dumps(response, ensure_ascii=False, separators=(',', ':'), allow_nan=False)
        if len(payload.encode('utf-8')) > MAX_LINE:
            payload = json.dumps(error(response['request_id'], 'OUTPUT_LIMIT', 'Response exceeds frame limit'))
        output_stream.write(payload + '\n'); output_stream.flush()


def main():
    if hasattr(os,'setsid'):
        try:os.setsid()
        except OSError:pass
    here = Path(__file__).resolve().parent
    # Dev layout is native-app/bridge; bundled layout is Resources/bridge + Resources/core.
    root = here.parent / 'core' if (here.parent / 'core').is_dir() else here.parent / 'CoreSnapshot/native-app-core-snapshot'
    try:
        spec = importlib.util.spec_from_file_location('native_core_adapter', here / 'core_adapter.py')
        module = importlib.util.module_from_spec(spec)
        with contextlib.redirect_stdout(sys.stderr):
            spec.loader.exec_module(module)
            adapter = module.CoreAdapter(root)
        serve(adapter, sys.stdin.buffer, sys.stdout)
    except (OSError, ImportError, ValueError, RuntimeError):
        print('Read-only bridge could not initialize Core', file=sys.stderr, flush=True)
        return 70
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
