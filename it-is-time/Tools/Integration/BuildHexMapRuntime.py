"""Compile the migrated hex snapshot for the existing application; keep legacy content intact."""
from pathlib import Path
from copy import deepcopy
import json
import math
import re
import hashlib
import shutil
from PIL import Image, ImageDraw, ImageChops
import FrontierBattleSceneWriter as writer

ROOT = Path(__file__).resolve().parents[2]
BASE = Path('Content/Maps/FrontierEditor_20261019')
OUT = ROOT / BASE / 'Runtime'
URI = 'res://' + BASE.as_posix() + '/Runtime'


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def local(uri):
    if not uri.startswith('res://') or '..' in uri:
        raise ValueError('Invalid project resource path: ' + uri)
    path = (ROOT / uri[6:]).resolve()
    if not path.is_relative_to(ROOT):
        raise ValueError('Resource path escapes the project: ' + uri)
    return path


def safe_id(value):
    if not isinstance(value, str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_-]*', value):
        raise ValueError('Invalid generated resource ID: ' + str(value))
    return value


def activate_asset(asset):
    result = deepcopy(asset)
    for field in ['path', 'render_path']:
        if field not in result:
            continue
        source = local(result[field])
        name = hashlib.sha256(source.read_bytes()).hexdigest()[:24] + source.suffix
        target = OUT / 'Textures/Assets' / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if source.suffix == '.svg':
            # Godot needs flattened symbols; authoring originals remain byte-for-byte untouched.
            original = source.read_bytes()
            target.write_bytes(writer.flatten_svg(original) or original)
        elif not target.exists():
            shutil.copy2(source, target)
        result[field] = URI + '/Textures/Assets/' + name
    if 'edge_background' in result:
        result['edge_background'] = activate_asset(result['edge_background'])
    return result


def shape(size, offset=(0, 0)):
    return {'enabled': True, 'shape': 'rect', 'offset': list(offset), 'size': size,
            'rotation': 0, 'points': [], 'layer': 1}


def compile_world(source, assets, roster_errors):
    objects = []
    for site in source['sites']:
        obj = deepcopy(site)
        visual = site.get('visual', {})
        asset = assets.get(visual.get('asset_id'), {})
        width = visual.get('width', asset.get('width', 180))
        height = width * asset.get('height', 1) / max(asset.get('width', 1), 1) * visual.get('height_scale', 1)
        anchor = visual.get('anchor', asset.get('anchor', [0.5, 1]))
        obj.update({'type': 'house' if site['kind'] == 'event' else site['kind'], 'scale': [1, 1],
            'rotation': 0, 'source_visual': visual, 'interaction_radius': 350,
            'hide_name_label': site['kind'] in ['camp', 'event', 'destructible'],
            'interaction_offset': [0, 0], 'requires_near_interaction': True,
            'visual': {'asset': visual.get('asset_id', ''), 'size': [width, height],
                       'z_index': max(-800, min(800, visual.get('z_index', 0))), 'opacity': 1,
                       'visible': True, 'tint': '#ffffff', 'anchor': anchor},
            'click_area': shape([max(width, 100), max(height, 100)], [(0.5-anchor[0])*width, (0.5-anchor[1])*height])})
        if site['kind'] != 'decoration':
            obj['discovery'] = {'known': site['kind'] == 'town', 'radius': source['vision_radius']}
        obj['collision'] = {'enabled': False, 'shape': 'rect', 'size': [0, 0], 'offset': [0, 0], 'rotation': 0}
        if site['id'] == 'layout_summoning_hut':
            obj['location_id'] = 'summoning_hut'
        if site['kind'] == 'camp':
            error = roster_errors.get(site.get('enemy_config_id'), '敌方编队尚未配置。')
            obj['integration_error'] = error
            obj['encounter'] = {'enabled': bool(site.get('auto_trigger')) and site['difficulty'] < 3 and not error,
                'diameter': site['radius']*2, 'probability': 1, 'battle_map_id': site.get('battle_map_id', ''),
                'enemy_config_id': site.get('enemy_config_id', ''), 'event_id': site.get('event_id', ''),
                'reset_on_exit': True, 'disable_after_clear': True}
        objects.append(obj)
    for road in source['roads']:
        obj = deepcopy(road)
        obj.update({'type': 'road', 'position': [0, 0], 'scale': [1, 1], 'rotation': 0,
                    'visual': {'asset': '', 'z_index': 0}, 'speed_multiplier': road.get('speed_multiplier', 1.5)})
        objects.append(obj)
    return {'id': 'frontier_layout', 'name': source['name'], 'kind': 'exploration', 'map_version': '20261019',
        'bounds': source['bounds'], 'spawn': source['spawn'], 'player_radius': 6,
        'fog': {'enabled': source['fog']['enabled'], 'radius': source['vision_radius'], 'paint': [],
                'default_state': 'unknown', 'unknown_color': '#354840', 'explored_color': '#182b26', 'explored_opacity': 0.76},
        'objects': objects, 'hex_grid': source['grid'], 'hex_cells': source['cells'],
        'crossings': source['crossings'], 'background': source['background'],
        'travel_animation_speed': math.sqrt(3)*source['grid']['cell_width']/2/source['traversal']['hex_step_seconds'],
        'events': [{'id': e['id'], 'name': e['name'], 'status': 'pending_binding'} for e in source['event_catalog']['events']]}


def bake_tiles(world):
    spec = world['background']['source_tiles']
    clips = read(local(spec['clip_asset']))['tiles']
    for tile in spec['tiles']:
        destination = OUT / 'Textures/Background' / (tile['id'] + '.png')
        tile['clipped_path'] = URI + '/Textures/Background/' + tile['id'] + '.png'
        if destination.exists():
            continue
        with Image.open(local(tile['path'])) as source:
            image = source.convert('RGBA')
        x, y, w, h = tile['rect']
        ox, oy = tile.get('offset', [0, 0])
        mask = Image.new('1', image.size, 0)
        for ring in clips[tile['id']]['clip']:
            part = Image.new('1', image.size, 0)
            points = [((p[0]-x-ox)*image.width/w, (p[1]-y-oy)*image.height/h) for p in ring]
            ImageDraw.Draw(part).polygon(points, fill=1)
            mask = ImageChops.logical_xor(mask, part)
        image.putalpha(ImageChops.multiply(image.getchannel('A'), mask.convert('L')))
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.save(destination)


def main():
    source = read(ROOT / BASE / 'Data/hex_layout.json')
    workset = read(ROOT / BASE / 'Data/hex_battles.json')
    links = read(ROOT / BASE / 'Migration/enemy_bindings.json')
    for row in links: safe_id(row['enemy_config_id'])
    for row in workset['maps']: safe_id(row['id'])
    for row in workset['assets']: safe_id(row['id'])
    factory = (ROOT / 'Scripts/Application/CreatureFactory.gd').read_text(encoding='utf-8-sig')
    factory = factory.split('const DEFINITIONS := {', 1)[1].split('const SUMMON_POOL', 1)[0]
    definitions = set(re.findall(r'^\s*"([^"]+)":\s*\{', factory, re.MULTILINE))
    errors = {}
    roster_paths = {}
    for link in links:
        missing = sorted({e.get('monster_species', '') for e in link['enemies'] if e.get('definition_id') not in definitions})
        error = '此战场缺少已绑定的生物：' + '、'.join(missing) if missing else ''
        errors[link['enemy_config_id']] = error
        members = [e['definition_id'] for e in link['enemies'] for _ in range(e.get('count', 1))] if not missing else []
        assert missing or len(members) == link['expected_count']
        path = OUT / 'EnemyRosters' / (link['enemy_config_id'] + '.tres')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('[gd_resource type="Resource" script_class="EnemyRosterData" load_steps=2 format=3]\n'
            '[ext_resource type="Script" path="res://Scripts/Application/EnemyRosterData.gd" id="script"]\n'
            '[resource]\nscript = ExtResource("script")\nenabled = '+str(not missing).lower()+'\n'
            'definitions = Array[String]('+json.dumps(members)+')\nunavailable_reason = '+json.dumps(error, ensure_ascii=False)+'\n', encoding='utf-8')
        roster_paths[link['enemy_config_id']] = URI + '/EnemyRosters/' + path.name
    lines = ['[gd_resource type="Resource" script_class="DeliveryBattleSettings" load_steps='+str(len(roster_paths)+2)+' format=3]',
        '[ext_resource type="Script" path="res://Scripts/Application/DeliveryBattleSettings.gd" id="script"]']
    for i, path in enumerate(roster_paths.values()):
        lines.append('[ext_resource type="Resource" path='+json.dumps(path)+' id="r'+str(i)+'"]')
    lines += ['[resource]', 'script = ExtResource("script")', 'unit_scale = 8.0', 'enemy_rosters = {']
    lines += [json.dumps(key)+': ExtResource("r'+str(i)+'"),' for i, key in enumerate(roster_paths)]
    lines += ['}']
    (OUT / 'BattleSettings.tres').write_text('\n'.join(lines)+'\n', encoding='utf-8')
    original_assets = {a['id']: a for a in source['assets']}
    world = compile_world(source, original_assets, errors)
    counts = {row['site_id']: row['expected_count'] for row in links}
    for obj in world['objects']:
        if obj['id'] in counts: obj['enemy_count'] = counts[obj['id']]
    world_ids = {v['asset_id'] for s in source['sites'] for v in [s.get('visual', {}), *s.get('visual', {}).get('layers', [])] if v.get('asset_id')}
    assets = {key: activate_asset(original_assets[key]) for key in sorted(world_ids)}
    bake_tiles(world)
    world['background']['asset'] = activate_asset({'path': world['background']['asset']})['path']
    world['background']['source_tiles']['clip_asset'] = activate_asset({'path': world['background']['source_tiles']['clip_asset']})['path']
    for tile in world['background']['source_tiles']['tiles']:
        tile['path'] = activate_asset({'path': tile['path']})['path']
    write(OUT / 'Maps/frontier_layout.json', world)
    index = {'version': '20261019', 'maps': {}, 'assets': assets,
        'catalogs': {'conditions': [{'id': 'has_monster', 'kind': 'monster_count', 'minimum': 1}]}}
    index['maps']['frontier_layout'] = {'id': 'frontier_layout', 'name': world['name'], 'kind': 'exploration',
        'data': URI+'/Maps/frontier_layout.json', 'scene': URI+'/Scenes/Maps/frontier_layout.tscn'}
    scene = OUT/'Scenes/Maps/frontier_layout.tscn'
    scene.parent.mkdir(parents=True, exist_ok=True)
    scene.write_text('[gd_scene load_steps=2 format=3]\n[ext_resource type="Script" path="res://Scripts/Application/HexWorldScene.gd" id="s"]\n[node name="HexWorld" type="Node2D"]\nscript = ExtResource("s")\n', encoding='utf-8')
    original_battle_assets = {a['id']: a for a in workset['assets']}
    battle_ids = {workset['art_bindings'].get(m['id'], {}).get(o['id'], o['visual'].get('asset', ''))
                  for m in workset['maps'] for o in m['objects']
                  if o['visual'].get('visible', True) and o['type'] not in ['enemy', 'deployment', 'reveal_area']}
    battle_assets = {key: activate_asset(original_battle_assets[key]) for key in sorted(battle_ids) if key}
    used_parts = {}
    writer.ROOT = OUT
    writer.PAPER_PARTS = {asset_id: URI+'/PaperParts/'+asset_id+'.tscn' for asset_id in battle_assets}
    (OUT/'Scenes/Maps3D').mkdir(parents=True, exist_ok=True)
    for item in workset['maps']:
        payload = read(ROOT / BASE / 'Data/BattleLevels' / (item['id']+'.battlelevel.json'))
        battle = payload['map']
        bindings = workset['art_bindings'].get(battle['id'], {})
        for obj in battle['objects']:
            visual = obj['visual']
            visual['asset'] = bindings.get(obj['id'], visual.get('asset', ''))
            if obj['type'] in ['enemy', 'deployment', 'reveal_area']:
                visual['visible'] = False
                visual['asset'] = ''
            if obj.get('condition_ref') or obj.get('effect_ref'):
                obj['integration_unresolved'] = True
            # Decoration keeps disabled collisions; standalone authored obstacles remain solid.
            if obj['type'] == 'decoration' and obj.get('collision', {}).get('enabled'):
                obj['collision']['enabled'] = False
            if visual['asset'] and visual.get('visible', True) and obj['type'] != 'edge_decoration':
                asset = battle_assets[visual['asset']]
                ground = obj['type'] in ['mud', 'web', 'thorns', 'pit', 'broken_barricade']
                key = visual['asset']
                used_parts[key] = {'id': key, 'path': asset.get('render_path', asset['path']), 'ground': ground}
        write(OUT/'Maps'/(battle['id']+'.json'), battle)
        writer.convert_battle_3d(battle, battle_assets)
        path = OUT/'Scenes/Maps3D'/(battle['id']+'.tscn')
        text = path.read_text(encoding='utf-8').replace('res://Scripts/Map/', 'res://Modules/FrontierDelivery/Scripts/Map/')
        text = text.replace('res://Data/Maps/', URI+'/Maps/')
        path.write_text(text, encoding='utf-8')
        index['maps'][battle['id']] = {'id': battle['id'], 'name': battle['name'], 'kind': 'battle',
            'data': URI+'/Maps/'+battle['id']+'.json', 'scene_3d': URI+'/Scenes/Maps3D/'+battle['id']+'.tscn'}
    index['battle_assets'] = battle_assets
    write(OUT/'index.json', index)
    write(OUT/'paper_parts.json', list(used_parts.values()))
    report = {'status': 'compiled', 'runtime_activation': True, 'version': '20261019', 'battle_maps': len(workset['maps']),
        'enabled_camps': sum(not e for e in errors.values()), 'blocked_camps': sum(bool(e) for e in errors.values()),
        'roster_errors': {key: error for key, error in errors.items() if error}, 'paper_assets': len(used_parts),
        'hd_tiles': 48, 'default_for_new_games': True, 'legacy_saves': 'keep_20261015'}
    write(OUT/'integration.json', report)
    print(json.dumps(report, ensure_ascii=False))


if __name__ == '__main__':
    main()
