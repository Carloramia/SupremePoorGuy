"""Collect source text without changing gameplay IDs, saved names or diagnostic fields."""
from pathlib import Path
import ast
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "Localization"
DOMAINS = ("ui", "creatures", "items", "maps_events", "console", "editor")
HAN = re.compile(r"[\u3400-\u9fff]")
DISPLAY = {"text", "tooltip_text", "placeholder_text", "display_name", "name", "title", "description", "effect", "detail", "unavailable_reason", "message", "label", "hint"}


def literals(source):
    """Small lexer: comments and quoted '#' are different; preserve multiline literals."""
    index = 0
    while index < len(source):
        if source[index] == '#':
            end = source.find('\n', index)
            index = len(source) if end < 0 else end + 1
            continue
        if source[index] not in "\"'":
            index += 1
            continue
        start = index
        quote = source[index]
        delimiter = quote * (3 if source.startswith(quote * 3, index) else 1)
        index += len(delimiter)
        while index < len(source):
            if source[index] == '\\':
                index += 2
            elif source.startswith(delimiter, index):
                index += len(delimiter)
                break
            else:
                index += 1
        raw = source[start:index]
        try:
            value = ast.literal_eval(raw)
        except (ValueError, SyntaxError):
            continue
        if isinstance(value, str):
            yield start, index, value


def domain(path):
    if 'addons/' in path or '/Generators/' in path or '/TA/' in path:
        return 'editor'
    if '/Debug/' in path:
        return 'console'
    if '/Map' in path or path.startswith('Content/'):
        return 'maps_events'
    if '/Items/' in path or '/Workshop/' in path or '/Materials/' in path:
        return 'items'
    if '/Creatures/' in path or path.endswith('CreatureFactory.gd'):
        return 'creatures'
    return 'ui'


def build():
    OUT.mkdir(exist_ok=True)
    old = json.loads((OUT / 'catalog.json').read_text(encoding='utf-8')) if (OUT / 'catalog.json').exists() else {}
    entries = old.get('messages', {})
    by_source = {v['source']: k for k, v in entries.items()}
    for entry in entries.values():
        entry['locations'] = []

    def add(value, path, line, kind='source'):
        if not value.strip():
            return
        group = domain(path)
        key = by_source.get(value)
        if key is None:
            key = group + '.' + hashlib.sha256(value.encode()).hexdigest()[:12]
            entries[key] = {'source': value, 'domain': group, 'locations': [], 'kind': kind}
            by_source[value] = key
        location = {'file': path, 'line': line}
        if location not in entries[key]['locations']:
            entries[key]['locations'].append(location)

    for folder in ('Scripts', 'Modules', 'Scenes', 'Resources', 'Content', 'addons'):
        for file in sorted((ROOT / folder).rglob('*')):
            if file.suffix not in ('.gd', '.tscn', '.tres', '.json') or 'Localization' in file.parts:
                continue
            path = file.relative_to(ROOT).as_posix()
            try:
                source = file.read_text(encoding='utf-8-sig')
            except UnicodeError:
                continue
            if file.suffix == '.json':
                try:
                    data = json.loads(source)
                except json.JSONDecodeError:
                    continue

                def walk(value, field=''):
                    if isinstance(value, dict):
                        for k, v in value.items():
                            walk(v, k)
                    elif isinstance(value, list):
                        for v in value:
                            walk(v, field)
                    elif isinstance(value, str) and field in DISPLAY and HAN.search(value):
                        add(value, path, 1, 'data')
                walk(data)
                continue
            for start, end, value in literals(source):
                line = source.count('\n', 0, start) + 1
                line_start = source.rfind('\n', 0, start) + 1
                prefix = source[line_start:start]
                if value in entries:
                    location = {'file': path, 'line': line}
                    if location not in entries[value]['locations']:
                        entries[value]['locations'].append(location)
                elif HAN.search(value):
                    add(value, path, line)
                elif file.suffix in ('.tscn', '.tres') and re.search(r'(?:text|tooltip_text|placeholder_text|display_name)\s*=\s*$', prefix) and re.search('[a-zA-Z]{2}', value):
                    add(value, path, line, 'display')
                elif path.endswith('RuntimeConsole.gd') and re.search(r'&?"description"\s*:\s*$', prefix):
                    add(value, path, line, 'console_help')
                elif prefix.rstrip().endswith('L10N.text('):
                    add(value, path, line, 'display')
                elif file.suffix == '.gd' and re.search(r'\.(?:text|tooltip_text|placeholder_text)\s*\+?=', prefix) and re.search('[a-zA-Z]{2}', value):
                    add(value, path, line, 'display')
    # Preserve stable keys and hand-edited translations on subsequent extractions.
    for group in DOMAINS:
        for locale in ('zh_CN', 'en'):
            file = OUT / locale / (group + '.json')
            existing = json.loads(file.read_text(encoding='utf-8')).get('messages', {}) if file.exists() else {}
            if locale == 'zh_CN':
                for key, entry in entries.items():
                    if entry['domain'] == group:
                        existing.setdefault(key, entry['source'])
            file.parent.mkdir(exist_ok=True)
            file.write_text(json.dumps({'locale': locale, 'messages': existing}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    (OUT / 'catalog.json').write_text(json.dumps({'version': 1, 'messages': entries}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('Collected', len(entries), 'messages; existing translations retained.')


if __name__ == '__main__':
    build()
