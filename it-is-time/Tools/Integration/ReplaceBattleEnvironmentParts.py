"""Replace native 3D battle decals with paper parts; retain authored effect regions."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil

PROJECT = Path(__file__).resolve().parents[2]
CONTENT = PROJECT / 'Content/Maps/FrontierDelivery_20261015'
BASE = PROJECT / 'Assets/3DResources/Environment/FrontierBattle'
REF = re.compile(r'(ExtResource|SubResource)\("([^"\n]+)"\)')


def local(path):
    return PROJECT / path.removeprefix('res://')


def attributes(block):
    return dict(re.findall(r'(\w+)="([^"]*)"', block.splitlines()[0]))


def prop(block, key, default=None):
    match = re.search(r'^' + re.escape(key) + r' = (.*)$', block, re.M)
    if match:
        return match[1]
    assert default is not None, (key, block[:120])
    return default


def set_prop(block, key, value):
    pattern = r'^' + re.escape(key) + r' = .*?$'
    replacement = key + ' = ' + value
    if re.search(pattern, block, re.M):
        return re.sub(pattern, lambda _: replacement, block, flags=re.M)
    return block.rstrip() + '\n' + replacement + '\n\n'


def vector(text):
    return [float(v) for v in text[text.index('(') + 1:text.rindex(')')].split(',')]


def fmt(value):
    return format(value, '.12g')


def migrate(path, definition, catalog, records):
    original = path.read_text(encoding='utf-8')
    blocks = [b for b in re.split(r'(?m)(?=^\[)', original) if b.strip()]
    subs = {attributes(b)['id']: b for b in blocks if b.startswith('[sub_resource ')}
    objects = {o['id']: o for o in definition['objects']}
    bindings = catalog['battle_art']['object_assets'].get(definition['id'], {})
    resources = {}
    replacements = {}
    already = set()
    for i, block in enumerate(blocks):
        if not block.startswith('[node '):
            continue
        node = attributes(block)
        parent = node.get('parent', '')
        if not parent.startswith('Objects/') or parent.count('/') != 1:
            continue
        object_id = parent.split('/')[1]
        obj = objects[object_id]
        asset_id = bindings.get(object_id, obj['visual']['asset'])
        if obj['type'] == 'edge_decoration' or not asset_id:
            continue
        record = records[asset_id]
        if node['name'] == 'PhysicalPart':
            already.add(object_id)
            continue
        if node['name'] != 'Visual':
            continue
        assert node.get('type') == 'MeshInstance3D'
        mesh_id = re.fullmatch(r'SubResource\("([^"]+)"\)', prop(block, 'mesh'))[1]
        width, height = vector(prop(subs[mesh_id], 'size'))
        native_width, native_height = [v * record['units_per_pixel'] for v in record['texture_size']]
        sx, sy = width / native_width, height / native_height
        position = vector(prop(block, 'position', 'Vector3(0, 0, 0)'))
        # Props stand on their bottom pivot; keep the authored image centre along X.
        position[0] += (record['pivot_pixel'][0] - record['texture_size'][0] / 2) * record['units_per_pixel'] * sx
        resource_id = 'Part_' + record['name']
        resources[resource_id] = record['physical_scene']
        blocks[i] = (
            f'[node name="PhysicalPart" parent="{parent}" instance=ExtResource("{resource_id}")]\n'
            f'position = Vector3({", ".join(fmt(v) for v in position)})\n'
            f'visible = {prop(block, "visible", "true")}\n'
            'collision_enabled = false\n'
            f'image_scale = Vector2({fmt(sx)}, {fmt(sy)})\n'
            f'opacity = {fmt(obj["visual"]["opacity"])}\n'
            f'metadata/source_asset_id = "{asset_id}"\n\n'
        )
        replacements[object_id] = record['name']
    targets = set(replacements) | already
    expected = {o['id'] for o in definition['objects'] if o['type'] != 'edge_decoration' and o['visual']['asset']}
    assert targets == expected, (definition['id'], expected - targets)
    for i, block in enumerate(blocks):
        if not block.startswith('[node '):
            continue
        node = attributes(block)
        if node.get('parent') in {'Objects/' + k for k in targets} and node['name'] == 'collision':
            block = set_prop(block, 'collision_layer', '0')
            blocks[i] = set_prop(block, 'collision_mask', '0')
        if node.get('parent') in {'Objects/' + k + '/collision' for k in targets} and node.get('type') == 'CollisionShape3D':
            blocks[i] = set_prop(block, 'disabled', 'true')
    additions = [f'[ext_resource type="PackedScene" path="{p}" id="{key}"]\n\n' for key, p in sorted(resources.items())]
    blocks[1:1] = additions
    # Drop the old decal planes/materials/textures that no remaining node references.
    resource_blocks = {}
    for block in blocks:
        for header, kind in [('[ext_resource ', 'ExtResource'), ('[sub_resource ', 'SubResource')]:
            if block.startswith(header):
                resource_blocks[(kind, attributes(block)['id'])] = block
    used = set(REF.findall(''.join(b for b in blocks if b.startswith(('[node ', '[connection ')))))
    pending = list(used)
    while pending:
        key = pending.pop()
        assert key in resource_blocks, key
        for dependency in REF.findall(resource_blocks[key]):
            if dependency not in used:
                used.add(dependency)
                pending.append(dependency)
    retained = []
    for block in blocks:
        kind = 'ExtResource' if block.startswith('[ext_resource ') else 'SubResource' if block.startswith('[sub_resource ') else None
        if kind is None or (kind, attributes(block)['id']) in used:
            retained.append(block)
    retained[0] = re.sub(r'load_steps=\d+', 'load_steps=' + str(len(used) + 1), retained[0])
    result = ''.join(retained)
    if result != original:
        path.write_text(result, encoding='utf-8', newline='\n')
    return {'map_id': definition['id'], 'parts': len(targets), 'new_references': len(replacements),
            'before_sha256': hashlib.sha256(original.encode()).hexdigest(),
            'after_sha256': hashlib.sha256(result.encode()).hexdigest()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--backup-dir', type=Path)
    args = parser.parse_args()
    catalog = json.loads((CONTENT / 'Data/Maps/index.json').read_text(encoding='utf-8'))
    manifest = json.loads((BASE / 'Metadata/model_manifest.json').read_text(encoding='utf-8'))
    records = {key: record for record in manifest['models'] for key in record['asset_ids']}
    reports = []
    for map_id, info in catalog['maps'].items():
        if info['kind'] != 'battle':
            continue
        scene = local(info['scene_3d'])
        if args.backup_dir:
            args.backup_dir.mkdir(parents=True, exist_ok=True)
            backup = args.backup_dir / scene.name
            if not backup.exists():
                shutil.copy2(scene, backup)
        report = migrate(scene, json.loads(local(info['data']).read_text(encoding='utf-8')), catalog, records)
        reports.append(report)
        print(json.dumps(report, ensure_ascii=False))
    report_path = BASE / 'Metadata/battle_map_bindings.json'
    if any(r['new_references'] for r in reports) or not report_path.exists():
        report_path.write_text(json.dumps({'maps': reports, 'collision_enabled': False}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('BATTLE_PARTS_BOUND maps=', len(reports), 'instances=', sum(r['parts'] for r in reports))


if __name__ == '__main__':
    main()
