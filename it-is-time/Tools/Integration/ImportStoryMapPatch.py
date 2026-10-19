"""Compile reviewed event content and bindings from the level designer patch.

Does not execute its installer, modify its authoring files or invent null values.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import re

PROJECT = Path(__file__).resolve().parents[2]
ENTRY_ALIASES = {
    'city_center': 'center', 'return_city_enchanter': 'enchanter',
    'engine_merchant': 'engine', 'engine_ghost': 'ghost',
    'giant_beast': 'giant', 'cave_duel': 'clash',
}

def read(path: Path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def write(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def between(text: str, start: str | None = None, end: str | None = None) -> str:
    if start:
        if start not in text:
            raise ValueError(f'Missing reviewed dialogue boundary: {start}')
        text = text.split(start, 1)[1]
    if end:
        if end not in text:
            raise ValueError(f'Missing reviewed dialogue boundary: {end}')
        text = text.split(end, 1)[0]
    return text.strip()

def pages(text: str) -> list[dict]:
    result = []
    for block in re.split(r'\n\s*\n', text):
        lines = []
        for line in block.splitlines():
            line = line.strip()
            if not line or line.startswith(('#', '|', '- ', '【', '（', '(')):
                continue
            if re.match(r'^\*\*(触发条件|事件流程|委托目标|显示条件|结果)[：:]', line):
                continue
            if line.startswith(('原稿', '缺任一方阵容', '此段仅', '本段')):
                continue
            lines.append(line)
        if not lines:
            continue
        paragraph = '\n'.join(lines)
        match = re.match(r'^\*\*([^*]+?)[：:]\*\*\s*(.+)', paragraph, re.S)
        result.append({'speaker': match[1], 'text': match[2]} if match else {'speaker': '', 'text': paragraph.replace('**', '')})
    return result

def compile_dialogues(e: dict) -> dict:
    """Explicit authoring boundaries prevent playing rewards and future branches."""
    number = e['number']
    raw = between(e['source_markdown'], '### 展示正文与原稿说明')
    result = {}
    if number == 1:
        result['opening'] = pages(between(raw, '### 对话', '### 结果'))
    elif number == 2:
        result['intro'] = pages(between(raw, '### 旁白', '### 结果'))
    elif number == 3:
        result['intro'] = pages(between(raw, '#### 对话', '#### 结果'))
    elif number == 4:
        for key, start, end in [('intro', '#### 初次接取', '#### 任务未完成'), ('revisit', '#### 任务未完成', '#### 交付任务'), ('submit', '#### 交付任务', '#### 结果')]:
            result[key] = pages(between(raw, start, end))
    elif number == 7:
        result['donkey'] = pages(between(raw, '（事件1）', '【我带你去找你兄弟】'))
        result['merchant'] = pages(between(raw, '（事件2）', '【是一头很老的驴吗？】'))
        result['return_dialogue'] = pages(between(raw, '（双方已发现后，通过上述任一入口播放同一段归还对话，不需要实际护送。）', '（奖励两件奇物）'))
    elif number == 10:
        result['intro'] = pages(between(raw, None, '【尝试打碎甲壳】'))
        result['failed'] = pages(between(raw, '【离开】', '甲壳碎了'))
        result['success'] = pages('甲壳碎了'+between(raw, '甲壳碎了', '（获得魔力，获得奇物）'))
    elif number == 11:
        result['intro'] = pages(between(raw, None, '【进入探索】'))
        result['victory'] = pages(between(raw, '（击败鼠群后）', '（获得符文）'))
    elif number == 12:
        result['intro'] = pages(between(raw, None, '【直接解决】'))
        result['direct_victory'] = pages(between(raw, '【直接解决】', '【路过萨尔格特城帮你问一下】'))
        result['enchanter'] = pages(between(raw, '【寻找附魔魔法师】', '【绕路离开】'))
    elif number == 14:
        result['intro'] = pages(between(raw, None, '【我买了】'))
        result['purchased'] = pages(between(raw, '【我买了】', '【离开】'))
    elif number == 15:
        result['intro'] = pages(between(raw, None, '【有点好笑】'))
        result['funny'] = pages(between(raw, '【有点好笑】', '【没那么好笑】'))
        result['kind'] = pages(between(raw, '【没那么好笑】', '（获得符文）'))
    elif number == 16:
        result['intro'] = pages(between(raw, None, '【帮他处理魔眼拱兽】'))
        result['victory'] = pages(between(raw, '【离远一点】'))
    elif number == 17:
        result['intro'] = pages(between(raw, None, '【帮忙赶走鸟】'))
        result['wood'] = pages(between(raw, '【建议用木头搭桥】', '【离开】'))
    elif number == 18:
        result['intro'] = pages(between(raw, None, '碑文上的第一次献祭：'))
        result['first'] = pages('碑文上的第一次献祭：\n'+between(raw, '碑文上的第一次献祭：', '碑文上的第二次献祭：'))
        result['second'] = pages('碑文上的第二次献祭：\n'+between(raw, '碑文上的第二次献祭：', '碑文上的第三次献祭：'))
        result['third'] = pages('碑文上的第三次献祭：\n'+between(raw, '碑文上的第三次献祭：'))
    elif number == 19:
        result['intro'] = pages(between(raw, None, '【帮助狼】'))
        result['spectator_end'] = pages('胜利者离开')
    elif number == 20:
        result['intro'] = pages(between(raw, None, '【赌就赌，我选（怪物1组）】'))
        result['settled'] = pages(between(raw, '（第1—3次结算后）', '（最多进行四次'))
    else:
        result['intro'] = pages(raw)
    if not result or not any(result.values()):
        raise ValueError(f'No player dialogue compiled for {e["id"]}')
    return result

def compile_patch(patch: Path, output: Path):
    payload = patch/'payload'
    manifest = read(patch/'manifest.json')
    for item in manifest['files']:
        # Manifest paths are data, never shell commands or installer instructions.
        relative = item.get('path', '')
        candidate = (payload/relative).resolve()
        if not candidate.is_relative_to(payload.resolve()):
            raise ValueError('Manifest path escapes payload')
        expected = item.get('new_sha256') or item.get('sha256')
        if not candidate.is_file() or not expected or hashlib.sha256(candidate.read_bytes()).hexdigest() != expected:
            raise ValueError(f'Patch payload hash mismatch: {relative}')
    source = payload/'project/frontier_toolkit/editor/hex/Data/Maps/hex_layout.json'
    layout = read(source)
    bindings = read(payload/'数据导出/事件入口绑定.json')
    definitions = read(PROJECT/'Content/Events/GrasslandEvents.json')
    by_id = {e['id']: e for e in definitions['events']}
    sites = {s['id']: s for s in layout['sites']}
    events = {e['id']: e for e in layout['event_catalog']['events'] if not e.get('auxiliary')}
    if set(events) != set(by_id) or len(events) != 20:
        raise ValueError('Twenty-event identity differs from installed state machine')
    compiled = []
    for b in bindings:
        if b['source_id'] not in sites:
            raise ValueError(f'Unknown site: {b["source_id"]}')
        if b['position'] != sites[b['source_id']]['position']:
            raise ValueError(f'Stale exported entry position: {b["source_id"]}')
        e = by_id.get(b['event_id'])
        role = ENTRY_ALIASES.get(b['entry_role'], b['entry_role'])
        if e and not role and len(e['entries']) == 1:
            role = e['entries'][0]
        if e and role not in e['entries']:
            raise ValueError(f'Unmapped entry role: {b["event_id"]}:{role}')
        compiled.append({**b, 'entrance': role, 'auxiliary': e is None})
    runtime_events = []
    gaps = []
    for e in events.values():
        params = e.get('runtime_bindings', {}).get('parameters', {})
        missing = [k for k, v in params.items() if v is None]
        runtime_events.append({'id': e['id'], 'number': e['number'], 'title': e['name'], 'dialogues': compile_dialogues(e), 'branches': e['branches'], 'parameters': params, 'runtime_bindings': e['runtime_bindings']})
        gaps.append({'event_id': e['id'], 'title': e['name'], 'missing_parameters': missing, 'unresolved': e.get('unresolved', '')})
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    write(output/'EventMapCatalog.json', {'version': 1, 'layout_sha256': digest, 'coordinate_scale': layout['coordinate_scale'], 'bindings': compiled, 'events': runtime_events})
    write(output/'IntegrationGaps.json', {'event_count': 20, 'entry_count': len(compiled), 'events': gaps})
    write(output/'Provenance.json', {'patch_id': manifest['id'], 'layout_sha256': digest, 'manifest_sha256': hashlib.sha256((patch/'manifest.json').read_bytes()).hexdigest(), 'original_base_required': manifest['base_zip'], 'original_base_sha256': manifest['base_zip_sha256']})
    print(json.dumps({'events': len(runtime_events), 'entries': len(compiled), 'missing_parameters': sum(len(g['missing_parameters']) for g in gaps), 'output': str(output)}, ensure_ascii=False))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('patch', type=Path)
    parser.add_argument('--output', type=Path, default=PROJECT/'Content/Events/MapPatch20261019')
    args = parser.parse_args()
    compile_patch(args.patch.resolve(), args.output.resolve())
