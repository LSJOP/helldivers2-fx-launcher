"""Local-only JSON translations; launcher language never changes game settings."""
from functools import lru_cache
import json
from pathlib import Path
import re
import string

LOCALES=Path(__file__).resolve().parent/'locales'
LANGUAGES=(('zh-CN','简体中文'),('en','English'),('ja','日本語'),('ko','한국어'),
           ('ru','Русский'),('es','Español'),('de','Deutsch'),('fr','Français'),
           ('pt-BR','Português (Brasil)'),('zh-TW','繁體中文'))
CODES=tuple(code for code,_ in LANGUAGES)


def normalize(code,strict=False):
    if code is None:return None
    aliases={value.lower():value for value in CODES}
    aliases.update({'zh':'zh-CN','zh-hans':'zh-CN','zh-hant':'zh-TW'})
    value=aliases.get(str(code).replace('_','-').lower())
    if value is None and strict:raise ValueError('Unsupported launcher language: '+str(code))
    return value or 'en'


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
