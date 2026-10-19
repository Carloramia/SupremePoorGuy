"""Validate the 20261019 r1 overlay and import its data into the existing game adapter."""
from pathlib import Path
import argparse
import json
import shutil
import ImportHexMapHandoff as handoff

ROOT = handoff.PROJECT
BASE = ROOT / handoff.CONTENT


def apply(package, patch, backup):
    manifest = handoff.read(patch / 'manifest.json')
    assert manifest['format'] == 'frontier-map-patch' and manifest['id'] == 'frontier-map-20261019-r1'
    assert handoff.digest(package / '文件清单_SHA256.json') in manifest['accepted_markers']
    payload = patch / 'payload'
    for row in manifest['files']:
        relative = Path(row['path'])
        assert not relative.is_absolute() and '..' not in relative.parts
        source = payload / relative
        assert source.is_file() and source.stat().st_size == row['bytes']
        assert handoff.digest(source) == row['sha256'], source
        old = package / relative
        assert (handoff.digest(old) if old.is_file() else '') in [row.get('old_sha256', ''), row['sha256']], old
    for row in manifest['required']:
        source = (package / row['path']).resolve()
        assert source.is_relative_to(package) and source.is_file() and handoff.digest(source) == row['sha256'], source

    def overlay(relative):
        return payload / relative if (payload / relative).is_file() else package / relative

    # Refuse to replace local authoring changes, even when the upstream package is clean.
    for name in ['hex_layout.json', 'hex_battles.json']:
        previous = BASE / 'Source' / name
        assert handoff.digest(previous) in [handoff.digest(package / handoff.SOURCE_MAPS / name),
                                           handoff.digest(overlay(handoff.SOURCE_MAPS / name))], previous
    assert not backup.exists(), 'Use a fresh backup directory.'
    backup.mkdir(parents=True)
    records = []

    def save(target, data):
        before = handoff.digest(target) if target.is_file() else ''
        if target.is_file() and target.read_bytes() == data:
            return
        relative = target.relative_to(ROOT)
        if before:
            copy = backup / relative
            copy.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(target, copy)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        records.append({'path': relative.as_posix(), 'before': before, 'after': handoff.digest(target)})

    def json_save(target, data):
        save(target, (json.dumps(data, ensure_ascii=False, indent=2)+'\n').encode('utf-8'))

    world = handoff.read(overlay(handoff.SOURCE_MAPS / 'hex_layout.json'))
    battles = handoff.read(overlay(handoff.SOURCE_MAPS / 'hex_battles.json'))
    data = {'Data/hex_layout.json': world, 'Data/hex_battles.json': battles}
    for row in battles['maps']:
        name = row['id'] + '.battlelevel.json'
        data['Data/BattleLevels/' + name] = handoff.read(overlay(Path('数据导出/逐场接入配置') / name))
    paths = handoff.read(BASE / 'Migration/asset_paths.json')
    migration = handoff.read(BASE / 'Migration/files.json')
    file_records = {r['target']: r for r in migration['files']}
    for uri in sorted({uri for value in data.values() for uri in handoff.file_refs(value)}):
        try:
            source, target = handoff.resolve(payload, uri)
        except FileNotFoundError:
            source, target = handoff.resolve(package, uri)
        save(ROOT / target, source.read_bytes())
        paths[uri] = 'res://' + target.as_posix()
        relative = source.relative_to(payload if source.is_relative_to(payload) else package).as_posix()
        file_records[target.as_posix()] = {'source': relative, 'target': target.as_posix(),
            'bytes': source.stat().st_size, 'sha256': handoff.digest(source)}
    for key, value in data.items():
        json_save(BASE / key, handoff.remap(value, paths))
    for name in ['hex_layout.json', 'hex_battles.json']:
        save(BASE / 'Source' / name, overlay(handoff.SOURCE_MAPS / name).read_bytes())
    for source in (payload / '数据导出').glob('*.json'):
        if source.name not in ['大地图完整布局.hex-layout.json', '全部战场.hex-battles.json']:
            save(BASE / 'Source/Exports' / source.name, source.read_bytes())
    links = handoff.read(overlay(Path('数据导出/战斗点与战场关联.json')))
    bindings = [{'site_id': r['site_id'], 'map_id': r['battle_map_id'], 'enemy_config_id': r['enemy_config_id'],
                 'expected_count': r['total_count'], 'enemies': r['enemies']} for r in links]
    json_save(BASE / 'Migration/enemy_bindings.json', bindings)
    json_save(BASE / 'Migration/asset_paths.json', paths)
    # Keep the supplied editor/preview sources as provenance, outside Godot's script scan.
    archive = BASE / 'Source/Patches' / manifest['id']
    for row in manifest['files']:
        save(archive / row['path'], (payload / row['path']).read_bytes())
    save(archive / 'manifest.json', (patch / 'manifest.json').read_bytes())
    save(archive / '.gdignore', b'')
    # Refresh only records whose imported snapshots changed; historical protected hashes remain.
    for row in file_records.values():
        target = ROOT / row['target']
        row.update(bytes=target.stat().st_size, sha256=handoff.digest(target))
    migration['files'] = list(file_records.values())
    migration['patch_id'] = manifest['id']
    for row in migration['derived_sources']:
        row['source_sha256'] = handoff.digest(overlay(Path(row['source'])))
    json_save(BASE / 'Migration/files.json', migration)
    report = {'patch_id': manifest['id'], 'payload_files_verified': len(manifest['files']),
        'reused_dependencies_verified': len(manifest['required']), 'world_cells': len(world['cells']),
        'sites': len(world['sites']), 'battles': len(battles['maps']), 'imported_asset_aliases': len(paths),
        'backup': str(backup), 'changes': records}
    json_save(BASE / 'Migration/patch.json', {k: v for k, v in report.items() if k not in ['backup', 'changes']})
    (backup / 'receipt.json').write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({k: v for k, v in report.items() if k != 'changes'}, ensure_ascii=False))


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', type=Path)
    parser.add_argument('patch', type=Path)
    parser.add_argument('backup', type=Path)
    args = parser.parse_args()
    apply(args.package.resolve(), args.patch.resolve(), args.backup.resolve())
