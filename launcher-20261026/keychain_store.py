"""Store only this launcher's opted-in SSH passwords in the macOS Keychain."""
import ctypes
import hashlib
import json

SERVICE = b'org.hd2fx.launcher.ssh-password.v1'
NOT_FOUND = -25300


class KeychainError(RuntimeError):
    pass


def account(settings):
    endpoint = [settings['host'].lower(), settings['port'], settings['username']]
    return hashlib.sha256(json.dumps(endpoint).encode()).hexdigest().encode()


class Keychain:
    def __init__(self):
        self.api = None

    def _load(self):
        if self.api is not None:
            return
        try:
            self.api = ctypes.CDLL('/System/Library/Frameworks/Security.framework/Security')
            self.core = ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
        except OSError as error:
            raise KeychainError('macOS Keychain is unavailable.') from error
        ptr = ctypes.c_void_p
        uint = ctypes.c_uint32
        self.api.SecKeychainFindGenericPassword.argtypes = [ptr, uint, ctypes.c_char_p, uint, ctypes.c_char_p, ctypes.POINTER(uint), ctypes.POINTER(ptr), ctypes.POINTER(ptr)]
        self.api.SecKeychainAddGenericPassword.argtypes = [ptr, uint, ctypes.c_char_p, uint, ctypes.c_char_p, uint, ptr, ctypes.POINTER(ptr)]
        self.api.SecKeychainItemModifyAttributesAndData.argtypes = [ptr, ptr, uint, ptr]
        self.api.SecKeychainItemFreeContent.argtypes = [ptr, ptr]
        self.api.SecKeychainItemDelete.argtypes = [ptr]
        for name in ['SecKeychainFindGenericPassword', 'SecKeychainAddGenericPassword', 'SecKeychainItemModifyAttributesAndData', 'SecKeychainItemFreeContent', 'SecKeychainItemDelete']:
            getattr(self.api, name).restype = ctypes.c_int32
        self.core.CFRelease.argtypes = [ptr]
        self.core.CFRelease.restype = None

    def _check(self, status):
        if status:
            raise KeychainError('macOS Keychain operation failed (status '+str(status)+'). Password was not written to a file.')

    def _find(self, settings, length=None, data=None, item=None):
        self._load()
        identity = account(settings)
        return self.api.SecKeychainFindGenericPassword(None, len(SERVICE), SERVICE, len(identity), identity, length, data, item)

    def get(self, settings):
        length, data = ctypes.c_uint32(), ctypes.c_void_p()
        status = self._find(settings, ctypes.byref(length), ctypes.byref(data))
        if status == NOT_FOUND:
            return None
        self._check(status)
        try:
            return ctypes.string_at(data, length.value).decode('utf-8')
        finally:
            self.api.SecKeychainItemFreeContent(None, data)

    def put(self, settings, password):
        if not password or '\n' in password or '\r' in password:
            raise ValueError('Enter a non-empty SSH password without newlines.')
        self._load()
        encoded = password.encode('utf-8')
        buffer = ctypes.create_string_buffer(encoded)
        item = ctypes.c_void_p()
        status = self._find(settings, item=ctypes.byref(item))
        if status == NOT_FOUND:
            identity = account(settings)
            self._check(self.api.SecKeychainAddGenericPassword(None, len(SERVICE), SERVICE, len(identity), identity, len(encoded), buffer, None))
            return
        self._check(status)
        try:
            self._check(self.api.SecKeychainItemModifyAttributesAndData(item, None, len(encoded), buffer))
        finally:
            self.core.CFRelease(item)

    def delete(self, settings):
        item = ctypes.c_void_p()
        status = self._find(settings, item=ctypes.byref(item))
        if status == NOT_FOUND:
            return
        self._check(status)
        try:
            self._check(self.api.SecKeychainItemDelete(item))
        finally:
            self.core.CFRelease(item)
