"""Local-only JSON translations; launcher language never changes game settings."""
from functools import lru_cache
import json
from pathlib import Path
import re
import string
import sys

LOCALES=Path(__file__).resolve().parent/'locales'
LANGUAGES=(('zh-CN','简体中文'),('en','English'),('ja','日本語'),('ko','한국어'),
           ('ru','Русский'),('es','Español'),('de','Deutsch'),('fr','Français'),
           ('pt-BR','Português (Brasil)'),('zh-TW','繁體中文'))
CODES=tuple(code for code,_ in LANGUAGES)


def supported_language(code):
    """Match a BCP-47 preference, without turning an unsupported entry into English."""
    if not isinstance(code,str):return None
    value=code.strip().replace('_','-').lower()
    if not re.fullmatch(r'[a-z]{2,3}(?:-[a-z0-9]{2,8})*',value):return None
    aliases={item.lower():item for item in CODES}
    parts=value.split('-')
    if parts[0]=='zh':
        target='zh-TW' if 'hant' in parts else ('zh-CN' if 'hans' in parts else
               ('zh-TW' if any(region in parts for region in ['tw','hk','mo']) else 'zh-CN'))
        return target if target in CODES else None
    if value in aliases:return aliases[value]
    if parts[0] in aliases:return aliases[parts[0]]
    return next((item for item in CODES if item.lower().split('-')[0]==parts[0]),None)


def normalize(code,strict=False):
    if code is None:return None
    value=supported_language(code)
    if value is None and strict:raise ValueError('Unsupported launcher language: '+str(code))
    return value or 'en'


def apple_languages():
    """Read only AppleLanguages using native CFPreferences; no subprocess or network."""
    if sys.platform!='darwin':return []
    import ctypes
    cf=ctypes.CDLL('/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation')
    ptr=ctypes.c_void_p;index=ctypes.c_long;utf8=0x08000100
    signatures={
        'CFStringCreateWithCString':([ptr,ctypes.c_char_p,ctypes.c_uint32],ptr),
        'CFPreferencesCopyValue':([ptr,ptr,ptr,ptr],ptr),
        'CFGetTypeID':([ptr],ctypes.c_ulong),
        'CFArrayGetTypeID':([],ctypes.c_ulong),
        'CFStringGetTypeID':([],ctypes.c_ulong),
        'CFArrayGetCount':([ptr],index),
        'CFArrayGetValueAtIndex':([ptr,index],ptr),
        'CFStringGetLength':([ptr],index),
        'CFStringGetMaximumSizeForEncoding':([index,ctypes.c_uint32],index),
        'CFStringGetCString':([ptr,ptr,index,ctypes.c_uint32],ctypes.c_bool),
        'CFRelease':([ptr],None),
    }
    for name,(args,result) in signatures.items():
        function=getattr(cf,name);function.argtypes=args;function.restype=result
    key=cf.CFStringCreateWithCString(None,b'AppleLanguages',utf8)
    value=None
    try:
        if not key:return []
        domains=[ptr.in_dll(cf,name).value for name in
                 ['kCFPreferencesAnyApplication','kCFPreferencesCurrentUser','kCFPreferencesAnyHost']]
        value=cf.CFPreferencesCopyValue(key,*domains)
        if not value or cf.CFGetTypeID(value)!=cf.CFArrayGetTypeID():return []
        languages=[]
        for position in range(min(256,max(0,cf.CFArrayGetCount(value)))):
            item=cf.CFArrayGetValueAtIndex(value,position)
            if not item or cf.CFGetTypeID(item)!=cf.CFStringGetTypeID():continue
            size=cf.CFStringGetMaximumSizeForEncoding(cf.CFStringGetLength(item),utf8)+1
            if not 0<size<=65536:continue
            buffer=ctypes.create_string_buffer(size)
            if cf.CFStringGetCString(item,buffer,size,utf8):languages.append(buffer.value.decode('utf-8'))
        return languages
    finally:
        if value:cf.CFRelease(value)
        if key:cf.CFRelease(key)


def initial_language(saved=None,requested=None):
    # Explicit CLI selection retains its existing precedence over saved settings.
    for choice in [requested,saved]:
        matched=supported_language(choice)
        if matched:return matched
    try:
        preferred=apple_languages()
        if not isinstance(preferred,(list,tuple)):return 'en'
        for choice in preferred:
            matched=supported_language(choice)
            if matched:return matched
    except Exception:
        pass  # Native preference failure must never block the launcher.
    return 'en'


@lru_cache(maxsize=20)
def catalog(code):
    code=normalize(code) or 'en'
    try:
        data=json.loads((LOCALES/(code+'.json')).read_text(encoding='utf-8'))
        if not isinstance(data,dict):return {}
        return {section:{key:value for key,value in data.get(section,{}).items() if isinstance(key,str) and isinstance(value,str) and value.strip()}
                for section in ['strings','messages'] if isinstance(data.get(section,{}),dict)}
    except (OSError,ValueError,TypeError):return {}


def fields(value):
    return {name for _,name,_,_ in string.Formatter().parse(value) if name is not None}


def text(key,language='en',**values):
    english=catalog('en').get('strings',{}).get(key,key)
    selected=catalog(normalize(language) or 'en').get('strings',{}).get(key,english)
    try:
        if fields(selected)!=fields(english):selected=english
        return selected.format(**values) if values else selected
    except (KeyError,ValueError,IndexError,AttributeError):
        try:return english.format(**values) if values else english
        except (KeyError,ValueError,IndexError,AttributeError):return english


def message(english,language='en'):
    messages=catalog(normalize(language) or 'en').get('messages',{})
    if english in messages:return messages[english]
    # Keep menu numbers, indentation and trailing prompt spaces out of reusable
    # message keys. JSON files can translate a label without duplicating 1./2.
    match=re.fullmatch(r'(\s*(?:\d+\.\s+)?)(.*?)(\s*)',english,re.S)
    if match and match[2] in messages:return match[1]+messages[match[2]]+match[3]
    return english
