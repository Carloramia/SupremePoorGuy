"""Validate catalogs, keys, printf/named placeholders and BBCode payloads."""
from pathlib import Path
import collections
import json
import re

ROOT = Path(__file__).resolve().parents[2] / 'Localization'


def unique(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate JSON key: ' + key)
        result[key] = value
    return result


def read(path):
    return json.loads(path.read_text(encoding='utf-8'), object_pairs_hook=unique)


def signature(value):
    printf = re.findall(r'%(?:[-+0 #]*\d*(?:\.\d+)?)?[sdifxXocbeEgG]|%%', value)
    named = collections.Counter(re.findall(r'\{[A-Za-z_]\w*\}', value))
    tags = collections.Counter(re.findall(r'\[/?[A-Za-z][^\]]*\]', value))
    return printf, named, tags


def main():
    config = read(ROOT / 'config.json')
    catalog = read(ROOT / 'catalog.json')['messages']
    assert config['default_locale'] in config['locales']
    assert config['fallback_locale'] in config['locales']
    fallback = {}
    for locale, definition in config['locales'].items():
        messages = {}
        for path in definition['files']:
            resolved = (ROOT / path).resolve()
            assert resolved.is_relative_to(ROOT.resolve()), path
            data = read(resolved)
            assert data['locale'] == locale, path
            for key, value in data['messages'].items():
                assert key in catalog, f'Unknown key: {path}: {key}'
                assert key not in messages, f'Duplicate locale key: {locale}: {key}'
                assert isinstance(value, str) and value, f'Empty/non-text message: {key}'
                assert signature(value) == signature(catalog[key]['source']), f'Placeholder/BBCode mismatch: {locale}: {key}'
                messages[key] = value
        print(locale, f'{len(messages)}/{len(catalog)} entries; {len(catalog)-len(messages)} use fallback')
        if locale == config['fallback_locale']:
            fallback = messages
    assert set(fallback) == set(catalog), 'Fallback locale must contain every key'
    print('LOCALIZATION_CATALOG_PASSED')


if __name__ == '__main__':
    main()
