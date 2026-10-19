"""Stage the 2026-10-19 hex handoff; never replace the live map catalog."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
import xml.etree.ElementTree as ET

PROJECT = Path(__file__).resolve().parents[2]
CONTENT = Path('Content/Maps/FrontierEditor_20261019')
LIVE = Path('Content/Maps/FrontierDelivery_20261015/Data/Maps/index.json')
PLANNER = Path('project/frontier_toolkit/editor/hex/Tools/hex-planner')
SOURCE_MAPS = Path('project/frontier_toolkit/editor/hex/Data/Maps')


def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def file_refs(value):
    if isinstance(value, dict):
        for item in value.values():
            yield from file_refs(item)
    elif isinstance(value, list):
        for item in value:
            yield from file_refs(item)
    elif isinstance(value, str) and value.startswith(('res://', 'assets/')):
        yield value


def resolve(package, uri):
    if uri.startswith('assets/'):
        relative = PLANNER / uri
        destination = Path('Assets/HexPlanner') / uri[len('assets/'):]
    elif uri.startswith('res://editor/hex/Tools/hex-planner/assets/'):
        suffix = uri[len('res://editor/hex/Tools/hex-planner/'):]
        relative = PLANNER / suffix
        destination = Path('Assets/HexPlanner') / suffix[len('assets/'):]
    elif uri.startswith('res://Assets/Maps/'):
        suffix = uri[len('res://Assets/Maps/'):]
        relative = Path('美术源文件/历史路径资源/Assets/Maps') / suffix
        if not (package / relative).is_file():
            relative = Path('project/it-is-time/Content/Maps/FrontierDelivery_20261015/Assets/Maps') / suffix
        destination = Path('Assets/LegacyMaps') / suffix
    else:
        raise ValueError('Unmapped resource URI: ' + uri)
    source = (package / relative).resolve()
    target = (CONTENT / destination)
    if not source.is_relative_to(package) or not (PROJECT / target).resolve().is_relative_to(PROJECT / CONTENT):
        raise ValueError('Resource path escapes its root: ' + uri)
    if not source.is_file():
        raise FileNotFoundError(source)
    return source, target


def remap(value, paths):
    if isinstance(value, dict):
        return {key: remap(item, paths) for key, item in value.items()}
    if isinstance(value, list):
        return [remap(item, paths) for item in value]
    if isinstance(value, str):
        return paths.get(value, value)
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path, nargs='?')
    parser.add_argument('--verify', action='store_true', help='Recheck staged bytes without copying or activating maps.')
    args = parser.parse_args()
    if args.verify:
        print(json.dumps(validate(PROJECT / CONTENT), ensure_ascii=False))
        return
    if args.package is None:
        parser.error('package is required unless --verify is used')
    package = args.package.resolve()
    destination = PROJECT / CONTENT
    if destination.exists():
        raise SystemExit('Version already exists; verify it instead of overwriting local edits.')
    manifest = read(package / '文件清单_SHA256.json')
    expected = {item['path']: item for item in manifest['files']}
    world = read(package / SOURCE_MAPS / 'hex_layout.json')
    battles = read(package / SOURCE_MAPS / 'hex_battles.json')
    assert world['format'] == 'frontier_hex_layout'
    assert battles['format'] == 'frontier_hex_battles'
    payloads = {'Data/hex_layout.json': world, 'Data/hex_battles.json': battles}
    originals = {key: package / SOURCE_MAPS / Path(key).name for key in payloads}
    for file in sorted((package / '数据导出/逐场接入配置').glob('*.battlelevel.json')):
        data = read(file)
        assert data['format'] == 'frontier-battle-level' and data['version'] == 1
        assert file.name == data['map']['id'] + '.battlelevel.json'
        key = 'Data/BattleLevels/' + file.name
        payloads[key], originals[key] = data, file
    assert len(payloads) == len(battles['maps']) + 2
    assert {m['id'] for m in battles['maps']} == {d['map']['id'] for d in payloads.values() if d.get('format') == 'frontier-battle-level'}

    # Include nested edge_background resources and all HD tiles, not just top-level assets.
    refs = {uri for data in payloads.values() for uri in file_refs(data)}
    resolved = {uri: resolve(package, uri) for uri in sorted(refs)}
    files = {source: target for source, target in resolved.values()}
    fingerprints = {}
    for source in set(files) | set(originals.values()):
        record = expected[source.relative_to(package).as_posix()]
        fingerprint = digest(source)
        if source.stat().st_size != record['bytes'] or fingerprint != record['sha256']:
            raise ValueError('Source does not match handoff manifest: ' + str(source))
        fingerprints[source] = fingerprint
    target_hashes = {}
    for source, target in files.items():
        if target in target_hashes and target_hashes[target] != fingerprints[source]:
            raise ValueError('Different source assets map to the same destination: ' + str(target))
        target_hashes[target] = fingerprints[source]
    path_mapping = {uri: 'res://' + target.as_posix() for uri, (_, target) in resolved.items()}
    live_index = read(PROJECT / LIVE)
    protected = [PROJECT / LIVE, PROJECT / 'Resources/Application/FrontierDeliveryBattle.tres',
                 PROJECT / 'Scripts/Application/CreatureFactory.gd', PROJECT / 'Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd']
    protected += [PROJECT / row['data'][6:] for row in live_index['maps'].values()]
    protected_hashes = {p.relative_to(PROJECT).as_posix(): digest(p) for p in protected}

    # Verify every source before the first copy; retain originals byte-for-byte separately.
    records = []
    for source, target in sorted(files.items()):
        output = PROJECT / target
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, output)
        records.append({'source': source.relative_to(package).as_posix(), 'target': target.as_posix(),
                        'bytes': source.stat().st_size, 'sha256': fingerprints[source]})
    for key, data in payloads.items():
        write_json(destination / key, remap(data, path_mapping))
    source_copies = {
        SOURCE_MAPS / 'hex_layout.json': 'Source/hex_layout.json',
        SOURCE_MAPS / 'hex_battles.json': 'Source/hex_battles.json',
        Path('完整系统对接文档.md'): 'Documentation/handoff.md',
        Path('核对记录/接入检查.json'): 'Documentation/source_checks.json',
        Path('核对记录/自动测试结果.json'): 'Documentation/source_tests.json',
        Path('核对记录/资源与模块缺件.json'): 'Documentation/source_missing_modules.json',
    }
    for file in (package / '数据导出').glob('*.json'):
        # Layout/workset are already kept as the two authoritative source files.
        if file.name not in ['大地图完整布局.hex-layout.json', '全部战场.hex-battles.json']:
            source_copies[file.relative_to(package)] = 'Source/Exports/' + file.name
    for relative, output in source_copies.items():
        source = package / relative
        record = expected[relative.as_posix()]
        if digest(source) != record['sha256']:
            raise ValueError('Source snapshot hash mismatch: ' + str(relative))
        target = destination / output
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        records.append({'source': relative.as_posix(), 'target': target.relative_to(PROJECT).as_posix(),
                        'bytes': source.stat().st_size, 'sha256': record['sha256']})

    assets_by_scope = {'world': world['assets'], 'battle': battles['assets']}
    old_assets = live_index['assets']
    old_art = live_index.get('world_art', {}).get('assets', {})
    asset_correspondence = []
    for scope, entries in assets_by_scope.items():
        for asset in entries:
            current = (old_art if scope == 'world' else old_assets).get(asset['id'], {})
            old_uri = current.get('path', '')
            new_uri = path_mapping[asset['path']]
            same_file = bool(old_uri.startswith('res://') and (PROJECT / old_uri[6:]).is_file()
                             and digest(PROJECT / old_uri[6:]) == digest(PROJECT / new_uri[6:]))
            asset_correspondence.append({'scope': scope, 'asset_id': asset['id'], 'name': asset.get('name', ''),
                'source_path': asset['path'], 'target_path': new_uri, 'current_path': old_uri,
                'same_bytes': same_file, 'action': 'reuse_candidate' if same_file else 'review_changed_asset' if current else 'new_asset'})
    old_world = read(PROJECT / live_index['maps']['frontier_layout']['data'][6:])
    old_sites = {item['id']: item for item in old_world['objects']}
    site_rows = []
    links = read(package / '数据导出/战斗点与战场关联.json')
    for site in world['sites']:
        current = old_sites.get(site['id'], {})
        site_rows.append({'site_id': site['id'], 'name': site['name'], 'kind': site['kind'],
            'position': site['position'], 'battle_map_id': site.get('battle_map_id', ''),
            'current_name': current.get('name', ''), 'current_position': current.get('position'),
            'current_battle_map_id': current.get('battle_map_id', ''),
            'same_id_exists': bool(current)})
    maps = []
    for battle in battles['maps']:
        current = live_index['maps'].get(battle['id'], {})
        linked = [row for row in links if row['battle_map_id'] == battle['id']]
        maps.append({'map_id': battle['id'], 'name': battle['name'], 'current_name': current.get('name', ''),
            'current_data': current.get('data', ''), 'current_scene_3d': current.get('scene_3d', ''),
            'new_data': 'res://' + (CONTENT / ('Data/BattleLevels/' + battle['id'] + '.battlelevel.json')).as_posix(),
            'action': 'same_id_recompile_and_review_roster' if current else 'new_map_requires_runtime_scene',
            'sites': [{'site_id': row['site_id'], 'name': row['site_name'], 'enemy_config_id': row['enemy_config_id'],
                       'count': row['total_count']} for row in linked]})
    factory = (PROJECT / 'Scripts/Application/CreatureFactory.gd').read_text(encoding='utf-8-sig')
    definition_block = factory.split('const DEFINITIONS := {', 1)[1].split('const SUMMON_POOL', 1)[0]
    definitions = set(re.findall(r'^\s*"([^"]+)":\s*\{', definition_block, re.MULTILINE))
    rosters = {p.stem for p in (PROJECT / 'Resources/Application/EnemyRosters').glob('*.tres')}
    enemy_rows = []
    for row in links:
        enemy_rows.append({'site_id': row['site_id'], 'map_id': row['battle_map_id'],
            'enemy_config_id': row['enemy_config_id'], 'expected_count': row['total_count'],
            'current_roster_file_exists': row['enemy_config_id'] in rosters,
            'unbound_species': sorted({str(e.get('monster_species', '')) for e in row['enemies'] if e.get('definition_id') not in definitions}),
            'enemies': row['enemies'], 'status': 'review_required_not_activated'})
    migration = destination / 'Migration'
    write_json(migration / 'asset_paths.json', path_mapping)
    write_json(migration / 'asset_correspondence.json', asset_correspondence)
    write_json(migration / 'map_correspondence.json', maps)
    write_json(migration / 'site_correspondence.json', site_rows)
    write_json(migration / 'enemy_bindings.json', enemy_rows)
    write_json(migration / 'files.json', {'source_package': package.name, 'files': records,
        'derived_sources': [{'source': f.relative_to(package).as_posix(), 'target': (CONTENT / key).as_posix(),
                             'source_sha256': fingerprints[f]} for key, f in originals.items()],
        'protected_runtime_files': protected_hashes, 'status': 'staged_not_active'})
    for folder in ['Source', 'Documentation', 'Migration']:
        (destination / folder / '.gdignore').write_text('', encoding='utf-8')
    report = validate(destination)
    write_json(migration / 'validation.json', report)
    print(json.dumps(report, ensure_ascii=False))


def validate(destination):
    from PIL import Image
    records = read(destination / 'Migration/files.json')
    images, svg_count = 0, 0
    for item in records['files']:
        path = PROJECT / item['target']
        assert path.stat().st_size == item['bytes'] and digest(path) == item['sha256'], path
        if path.suffix.lower() in ['.png', '.webp']:
            with Image.open(path) as image:
                image.verify()
            images += 1
        elif path.suffix == '.svg':
            root = ET.parse(path).getroot()
            for element in root.iter():
                for key, value in element.attrib.items():
                    if key.split('}')[-1] == 'href':
                        assert value.startswith(('data:', '#')), (path, value)
            svg_count += 1
    integrated = (destination / 'Runtime/integration.json').is_file()
    adapted = ['Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd', 'Scripts/Application/CreatureFactory.gd'] if integrated else []
    for relative, expected in records['protected_runtime_files'].items():
        if relative in adapted:
            continue  # The later runtime integration deliberately adds version selection here.
        assert digest(PROJECT / relative) == expected, 'Live runtime was changed: ' + relative
    paths = read(destination / 'Migration/asset_paths.json')
    data_files = list((destination / 'Data').rglob('*.json'))
    ref_count = 0
    unique_refs = set()
    for path in data_files:
        for uri in file_refs(read(path)):
            unique_refs.add(uri)
            ref_count += 1
    for uri in unique_refs:
        assert uri.startswith('res://' + CONTENT.as_posix() + '/Assets/'), uri
        assert (PROJECT / uri[6:]).is_file(), uri
    world = read(destination / 'Data/hex_layout.json')
    battles = read(destination / 'Data/hex_battles.json')
    assert len({s['id'] for s in world['sites']}) == len(world['sites'])
    maps = {m['id'] for m in battles['maps']}
    assert len(maps) == len(battles['maps'])
    assert all(not s.get('battle_map_id') or s['battle_map_id'] in maps for s in world['sites'])
    tiles = world['background']['source_tiles']
    clips = read(PROJECT / tiles['clip_asset'][6:])
    assert {t['id'] for t in tiles['tiles']} == set(clips['tiles'])
    return {'status': 'passed', 'runtime_activation': integrated, 'copied_files': len(records['files']),
        'unique_map_asset_files': len(set(paths.values())), 'asset_uri_aliases': len(paths),
        'raster_images_verified': images, 'svg_files_verified': svg_count, 'derived_json_files': len(data_files),
        'resolved_reference_occurrences': ref_count, 'cells': len(world['cells']), 'sites': len(world['sites']),
        'battles': len(battles['maps']), 'hd_tiles': len(tiles['tiles']),
        'protected_runtime_files_unchanged': len(records['protected_runtime_files'])-len(adapted),
        'subsequently_adapted_files': adapted}


if __name__ == '__main__':
    main()
