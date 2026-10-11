"""Build portable GLB paper planes and frozen Godot part scenes from existing PNGs.

Run with a Python installation that has Pillow. Output is confined to this folder.
The source PNGs are never modified. Units: 100 original atlas pixels = 1 metre.
"""
from pathlib import Path
from collections import deque
import hashlib
import json
import math
import struct
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parent.parent
PROJECT = next(p for p in OUT.parents if (p / 'project.godot').is_file())
SOURCE = PROJECT / 'Assets/2DResources/StumpBeast'
PPU = 100.0
THICKNESS = 0.02
BASE = json.loads((SOURCE / 'Metadata/parts_manifest.json').read_text(encoding='utf-8'))
LEGACY_IMAGE_PATHS = {'Textures/Torso/SubTorsoPlate.png': '01_body_light_plate.png', 'Textures/Torso/TorsoMain.png': '02_body_main.png', 'Textures/Head/EarLeft.png': '03_ear_left.png', 'Textures/Head/EarRight.png': '04_ear_right.png', 'Textures/Head/HeadMain.png': '05_head.png', 'Textures/Legs/Whole/LegLeft.png': '06_leg_left.png', 'Textures/Legs/Whole/LegCenter.png': '07_leg_center.png', 'Textures/Legs/Whole/LegRight.png': '08_leg_right.png', 'Textures/Head/Tongue.png': '09_tongue.png', 'Textures/Head/JawLight.png': '10_jaw_light.png', 'Textures/Head/JawDark.png': '11_jaw_dark.png', 'Textures/Connectors/Connector01.png': '12_connector_01.png', 'Textures/Connectors/Connector02.png': '13_connector_02.png', 'Textures/Connectors/Connector03.png': '14_connector_03.png', 'Textures/Connectors/Connector04.png': '15_connector_04.png', 'Textures/Connectors/Connector05.png': '16_connector_05.png', 'Textures/Connectors/Connector06.png': '17_connector_06.png', 'Textures/Connectors/Connector07.png': '18_connector_07.png', 'Textures/Legs/Left/UpperLeg.png': '06_leg_left_parts/01_upper_leg.png', 'Textures/Legs/Left/MiddleLeg.png': '06_leg_left_parts/02_middle_leg.png', 'Textures/Legs/Left/LowerLeg.png': '06_leg_left_parts/03_lower_leg.png', 'Textures/Legs/Left/Foot.png': '06_leg_left_parts/04_foot.png', 'Textures/Legs/Right/UpperLeg.png': '08_leg_right_parts/01_upper_leg.png', 'Textures/Legs/Right/MiddleLowerMerged.png': '08_leg_right_parts/02_03_middle_lower_merged.png', 'Textures/Legs/Right/MiddleLeg.png': '08_leg_right_parts/02_middle_leg.png', 'Textures/Legs/Right/LowerLeg.png': '08_leg_right_parts/03_lower_leg.png', 'Textures/Legs/Right/Foot.png': '08_leg_right_parts/04_foot.png'}
ASSET_LAYOUT = {'Base/01_body_light_plate': 'Torso/SubTorsoPlate', 'Base/02_body_main': 'Torso/TorsoMain', 'Base/03_ear_left': 'Head/EarLeft', 'Base/04_ear_right': 'Head/EarRight', 'Base/05_head': 'Head/HeadMain', 'Base/06_leg_left': 'Legs/Whole/LegLeft', 'Base/07_leg_center': 'Legs/Whole/LegCenter', 'Base/08_leg_right': 'Legs/Whole/LegRight', 'Base/09_tongue': 'Head/Tongue', 'Base/10_jaw_light': 'Head/JawLight', 'Base/11_jaw_dark': 'Head/JawDark', 'Base/12_connector_01': 'Connectors/Connector01', 'Base/13_connector_02': 'Connectors/Connector02', 'Base/14_connector_03': 'Connectors/Connector03', 'Base/15_connector_04': 'Connectors/Connector04', 'Base/16_connector_05': 'Connectors/Connector05', 'Base/17_connector_06': 'Connectors/Connector06', 'Base/18_connector_07': 'Connectors/Connector07', 'LeftLeg/01_upper_leg': 'Legs/Left/UpperLeg', 'LeftLeg/02_middle_leg': 'Legs/Left/MiddleLeg', 'LeftLeg/03_lower_leg': 'Legs/Left/LowerLeg', 'LeftLeg/04_foot': 'Legs/Left/Foot', 'RightLeg/01_upper_leg': 'Legs/Right/UpperLeg', 'RightLeg/02_03_middle_lower_merged': 'Legs/Right/MiddleLowerMerged', 'RightLeg/02_middle_leg': 'Legs/Right/MiddleLeg', 'RightLeg/03_lower_leg': 'Legs/Right/LowerLeg', 'RightLeg/04_foot': 'Legs/Right/Foot'}
REST_HEIGHTS = {
    '06_leg_left_parts': {'01_upper_leg': 217, '02_middle_leg': 276, '03_lower_leg': 186, '04_foot': 84},
    '08_leg_right_parts': {'01_upper_leg': 201, '02_middle_leg': 146, '03_lower_leg': 146, '04_foot': 124, '02_03_middle_lower_merged': 146},
}


def resource(path):
    return 'res://' + path.relative_to(PROJECT).as_posix()


def hole_centres(image):
    """Find enclosed alpha holes, ignoring isolated low-alpha texture noise."""
    small = image.copy()
    small.thumbnail((320, 320), Image.Resampling.LANCZOS)
    binary = small.getchannel('A').point(lambda a: 255 if a >= 128 else 0)
    ImageDraw.floodfill(binary, (0, 0), 128, thresh=0)
    pixels = binary.load()
    holes = []
    for y in range(small.height):
        for x in range(small.width):
            if pixels[x, y] != 0:
                continue
            pixels[x, y] = 128
            queue = deque([(x, y)])
            sx = sy = count = 0
            while queue:
                px, py = queue.popleft()
                sx += px
                sy += py
                count += 1
                for nx, ny in ((px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)):
                    if 0 <= nx < small.width and 0 <= ny < small.height and pixels[nx, ny] == 0:
                        pixels[nx, ny] = 128
                        queue.append((nx, ny))
            if count >= max(3, small.width * small.height * 0.00025):
                holes.append(((sx / count + .5) * image.width / small.width, (sy / count + .5) * image.height / small.height, count))
    return sorted(holes, key=lambda point: point[1])


def convex_hull(points):
    points = sorted(set(points))
    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])
    lower, upper = [], []
    for point in points:
        while len(lower) > 1 and cross(lower[-2], lower[-1], point) <= 0:
            lower.pop()
        lower.append(point)
    for point in reversed(points):
        while len(upper) > 1 and cross(upper[-2], upper[-1], point) <= 0:
            upper.pop()
        upper.append(point)
    return lower[:-1] + upper[:-1]


def collision_points(image, pivot, unit):
    small = image.copy()
    small.thumbnail((80, 80), Image.Resampling.LANCZOS)
    alpha = small.getchannel('A')
    samples = []
    for y in range(small.height):
        row = [x for x in range(small.width) if alpha.getpixel((x, y)) >= 128]
        if row:
            for x in (row[0], row[-1] + 1):
                for ey in (y, y + 1):
                    samples.append((x * image.width / small.width, ey * image.height / small.height))
    hull = convex_hull(samples)
    return [((x - pivot[0]) * unit, (pivot[1] - y) * unit, z) for z in (-THICKNESS / 2, THICKNESS / 2) for x, y in hull]


def plane_glb(record, image_path, output):
    w, h = record['texture_size']
    px, py = record['pivot_pixel']
    u = record['units_per_texture_pixel']
    positions = [(-px*u, py*u, 0), (-px*u, (py-h)*u, 0), ((w-px)*u, (py-h)*u, 0), ((w-px)*u, py*u, 0)]
    normals = [(0, 0, 1)] * 4
    uv = [(0, 0), (0, 1), (1, 1), (1, 0)]
    blob = bytearray()
    views = []
    def append(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        index = len(views)
        view = {'buffer': 0, 'byteOffset': len(blob), 'byteLength': len(data)}
        if target:
            view['target'] = target
        views.append(view)
        blob.extend(data)
        return index
    def floats(values):
        flat = [v for row in values for v in row]
        return struct.pack('<' + 'f' * len(flat), *flat)
    pview = append(floats(positions), 34962)
    nview = append(floats(normals), 34962)
    uview = append(floats(uv), 34962)
    iview = append(struct.pack('<6H', 0, 1, 2, 0, 2, 3), 34963)
    image_view = append(image_path.read_bytes())
    end = record['joint_out_local']
    document = {
        'asset': {'version': '2.0', 'generator': 'ItIsTime paper parts builder'},
        'extensionsUsed': ['KHR_materials_unlit'],
        'scene': 0, 'scenes': [{'nodes': [0]}],
        'nodes': [{'name': record['name'], 'children': [1, 2, 3], 'extras': {'source_png': record['source'], 'units_per_original_pixel': .01}}, {'name': 'Visual', 'mesh': 0}, {'name': 'JointIn', 'translation': [0, 0, 0]}, {'name': 'JointOut', 'translation': end}],
        'meshes': [{'name': record['name'], 'primitives': [{'attributes': {'POSITION': 0, 'NORMAL': 1, 'TEXCOORD_0': 2}, 'indices': 3, 'material': 0, 'mode': 4}]}],
        'materials': [{'name': 'PaperDoubleSided', 'doubleSided': True, 'alphaMode': 'MASK', 'alphaCutoff': .5, 'extensions': {'KHR_materials_unlit': {}}, 'pbrMetallicRoughness': {'baseColorTexture': {'index': 0}, 'baseColorFactor': [1, 1, 1, 1], 'metallicFactor': 0, 'roughnessFactor': 1}}],
        'textures': [{'sampler': 0, 'source': 0}],
        'samplers': [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 33071, 'wrapT': 33071}],
        'images': [{'bufferView': image_view, 'mimeType': 'image/png', 'name': image_path.stem}],
        'bufferViews': views,
        'accessors': [
            {'bufferView': pview, 'componentType': 5126, 'count': 4, 'type': 'VEC3', 'min': [min(p[i] for p in positions) for i in range(3)], 'max': [max(p[i] for p in positions) for i in range(3)]},
            {'bufferView': nview, 'componentType': 5126, 'count': 4, 'type': 'VEC3'},
            {'bufferView': uview, 'componentType': 5126, 'count': 4, 'type': 'VEC2'},
            {'bufferView': iview, 'componentType': 5123, 'count': 6, 'type': 'SCALAR'}],
        'buffers': [{'byteLength': len(blob)}],
    }
    encoded = json.dumps(document, separators=(',', ':')).encode()
    encoded += b' ' * (-len(encoded) % 4)
    blob.extend(b'\x00' * (-len(blob) % 4))
    total = 12 + 8 + len(encoded) + 8 + len(blob)
    output.write_bytes(struct.pack('<III', 0x46546C67, 2, total) + struct.pack('<II', len(encoded), 0x4E4F534A) + encoded + struct.pack('<II', len(blob), 0x004E4942) + blob)
    # Validate container alignment, embedded source texture and winding.
    raw = output.read_bytes()
    assert struct.unpack_from('<III', raw) == (0x46546C67, 2, len(raw))
    assert image_path.read_bytes() == bytes(blob[views[image_view]['byteOffset']:views[image_view]['byteOffset'] + views[image_view]['byteLength']])
    assert all(math.isfinite(v) for p in positions for v in p)
    assert u > 0


def part_scene(record, image):
    glb = OUT / record['glb']
    point_text = ', '.join(f'{v:.8f}' for point in collision_points(image, record['pivot_pixel'], record['units_per_texture_pixel']) for v in point)
    marker = ', '.join(f'{v:.8f}' for v in record['joint_out_local'])
    content = f'''[gd_scene load_steps=3 format=3]

[ext_resource type="PackedScene" path="{resource(glb)}" id="1_model"]

[sub_resource type="ConvexPolygonShape3D" id="Shape"]
points = PackedVector3Array({point_text})

[node name="{record['name']}" type="RigidBody3D"]
freeze = true
freeze_mode = 1
mass = 0.1
metadata/source_png = "{record['source']}"
metadata/pivot_is_initial_estimate = true

[node name="Model" parent="." instance=ExtResource("1_model")]

[node name="CollisionShape3D" type="CollisionShape3D" parent="."]
shape = SubResource("Shape")

[node name="JointIn" type="Marker3D" parent="."]

[node name="JointOut" type="Marker3D" parent="."]
position = Vector3({marker})
'''
    (OUT / record['scene']).write_text(content, encoding='utf-8')


def make_record(path):
    relative = Path(LEGACY_IMAGE_PATHS[path.relative_to(SOURCE).as_posix()])
    group = 'Base' if len(relative.parts) == 1 else ('LeftLeg' if relative.parts[0] == '06_leg_left_parts' else 'RightLeg')
    image = Image.open(path).convert('RGBA')
    bounds = image.getchannel('A').point(lambda a: 255 if a >= 16 else 0).getbbox()
    holes = hole_centres(image)
    pivot = list(holes[0][:2]) if holes else [image.width / 2, image.height / 2]
    if group == 'Base':
        original = next(p for p in BASE['parts'] if p['file'] == relative.name)
        unit = 1 / PPU
        reference_origin = [original['source_box_xyxy'][0] - original['padding'], original['source_box_xyxy'][1] - original['padding']]
        frame = 'ToSplit_1.jpg'
    else:
        height = REST_HEIGHTS[relative.parts[0]][relative.stem]
        unit = height / (bounds[3] - bounds[1]) / PPU
        frame = '06_leg_left.png' if group == 'LeftLeg' else '08_leg_right.png'
        if not holes:
            pivot = [bounds[0] + (bounds[2] - bounds[0]) * (.8 if 'middle' in relative.stem else .5), bounds[1] + (bounds[3] - bounds[1]) * .15]
        if group == 'RightLeg':
            anchors = {'01_upper_leg': (85, 85), '04_foot': (119, 235)}
            if relative.stem in anchors:
                anchor = anchors[relative.stem]
                reference_origin = [anchor[i] - pivot[i] * unit * PPU for i in range(2)]
            else:
                top_left = (40, 139) if 'merged' in relative.stem else ((40, 140) if 'middle' in relative.stem else (84, 139))
                reference_origin = [top_left[i] - bounds[i] * unit * PPU for i in range(2)]
                anchor = (99, 161) if 'middle' in relative.stem else (114, 154)
                pivot = [(anchor[i] - reference_origin[i]) / (unit * PPU) for i in range(2)]
        else:
            reference_origin = [0, 0]
    joint_pixel = list(holes[-1][:2]) if len(holes) > 1 else [bounds[0] + (bounds[2] - bounds[0]) / 2, bounds[1] + (bounds[3] - bounds[1]) * .85]
    if group == 'RightLeg':
        targets = {'01_upper_leg': (99, 161), '02_middle_leg': (114, 154), '03_lower_leg': (119, 235), '02_03_middle_lower_merged': (119, 235)}
        if relative.stem in targets:
            joint_pixel = [(targets[relative.stem][i] - reference_origin[i]) / (unit * PPU) for i in range(2)]
    record = {'name': relative.stem, 'group': group, 'source': resource(path), 'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'texture_size': list(image.size), 'world_size': [image.width * unit, image.height * unit], 'units_per_texture_pixel': unit, 'pivot_pixel': pivot, 'joint_out_local': [(joint_pixel[0] - pivot[0]) * unit, (pivot[1] - joint_pixel[1]) * unit, 0], 'reference_frame': frame, 'reference_origin_pixel': reference_origin, 'reference_pivot_pixel': [reference_origin[i] + pivot[i] * unit * PPU for i in range(2)], 'glb': 'Models/' + ASSET_LAYOUT[f'{group}/{relative.stem}'] + '.glb', 'scene': 'Scenes/' + ASSET_LAYOUT[f'{group}/{relative.stem}'] + '.tscn'}
    (OUT / record['glb']).parent.mkdir(parents=True, exist_ok=True)
    (OUT / record['scene']).parent.mkdir(parents=True, exist_ok=True)
    plane_glb(record, path, OUT / record['glb'])
    import_path = Path(str(OUT / record['glb']) + '.import')
    if not import_path.exists():
        import_path.write_text('[remap]\nimporter="scene"\n\n[params]\ngltf/embedded_image_handling=3\n', encoding='utf-8')
    part_scene(record, image)
    return record


def assembly(records, names, filename):
    selected = [next(r for r in records if r['group'] == 'RightLeg' and r['name'] == name) for name in names]
    lines = [f'[gd_scene load_steps={len(selected) + 1} format=3]\n']
    for i, r in enumerate(selected):
        lines.append(f'[ext_resource type="PackedScene" path="{resource(OUT / r["scene"])}" id="{i + 1}_part"]\n')
    lines.append('[node name="RightLeg" type="Node3D"]\n')
    parent = '.'
    previous = [0, 0, 0]
    for i, r in enumerate(selected):
        px, py = r['reference_pivot_pixel']
        current = [px / PPU, (339 - py) / PPU, i * .015]
        delta = [current[j] - previous[j] for j in range(3)]
        name = f'Pivot{i + 1}'
        lines.append(f'[node name="{name}" type="Node3D" parent="{parent}"]\nposition = Vector3({", ".join(f"{v:.8f}" for v in delta)})\n')
        parent = name if parent == '.' else parent + '/' + name
        lines.append(f'[node name="Part" parent="{parent}" instance=ExtResource("{i + 1}_part")]\ncollision_layer = 0\ncollision_mask = 0\n')
        previous = current
    (OUT / filename).write_text('\n'.join(lines), encoding='utf-8')


def demo_scene():
    (OUT / 'Previews/RightLegPreview.tscn').write_text(f'''[gd_scene load_steps=4 format=3]

[ext_resource type="PackedScene" path="{resource(OUT / 'Previews/RightLegCombined.tscn')}" id="1_leg"]
[ext_resource type="Script" path="{resource(OUT / 'Previews/PreviewMotion.gd')}" id="2_motion"]

[sub_resource type="Environment" id="Environment"]
background_mode = 1
background_color = Color(0.22, 0.26, 0.3, 1)
ambient_light_source = 3
ambient_light_color = Color(1, 1, 1, 1)
ambient_light_energy = 1.0
tonemap_mode = 0

[node name="RightLegPreview" type="Node3D"]
script = ExtResource("2_motion")

[node name="RightLeg" parent="." instance=ExtResource("1_leg")]

[node name="Camera3D" type="Camera3D" parent="."]
position = Vector3(1.1, 1.7, 8)
projection = 1
size = 3.8
current = true

[node name="WorldEnvironment" type="WorldEnvironment" parent="."]
environment = SubResource("Environment")
''', encoding='utf-8')
    (OUT / 'Previews/PreviewMotion.gd').write_text('''extends Node3D
## Rest-pose assembly demo. Disable animate to inspect the original placement.
@export var animate: bool = true
var elapsed: float = 0.0
@onready var hip: Node3D = $RightLeg/Pivot1
@onready var knee: Node3D = $RightLeg/Pivot1/Pivot2
@onready var ankle: Node3D = $RightLeg/Pivot1/Pivot2/Pivot3

func _process(delta: float) -> void:
    elapsed += delta
    if not animate:
        hip.rotation.z = 0.0
        knee.rotation.z = 0.0
        ankle.rotation.z = 0.0
        return
    hip.rotation.z = sin(elapsed * 1.5) * 0.12
    knee.rotation.z = sin(elapsed * 1.5 + 0.8) * 0.2
    ankle.rotation.z = -hip.rotation.z - knee.rotation.z
''', encoding='utf-8')


def contact_sheet(records):
    columns, cw, ch = 6, 260, 285
    preview = Image.new('RGB', (columns * cw, math.ceil(len(records) / columns) * ch), '#e5e9ee')
    draw = ImageDraw.Draw(preview)
    font = ImageFont.truetype(r'C:\Windows\Fonts\arial.ttf', 12)
    for i, r in enumerate(records):
        cx, cy = (i % columns) * cw, (i // columns) * ch
        for y in range(cy + 8, cy + ch - 44, 16):
            for x in range(cx + 8, cx + cw - 8, 16):
                if ((x - cx) // 16 + (y - cy) // 16) % 2 == 0:
                    draw.rectangle((x, y, min(x + 15, cx + cw - 9), min(y + 15, cy + ch - 45)), fill='#d1dbe5')
        raw = (OUT / r['glb']).read_bytes()
        length = struct.unpack_from('<I', raw, 12)[0]
        doc = json.loads(raw[20:20 + length])
        bin_start = 20 + length + 8
        view = doc['bufferViews'][doc['images'][0]['bufferView']]
        from io import BytesIO
        texture = Image.open(BytesIO(raw[bin_start + view['byteOffset']:bin_start + view['byteOffset'] + view['byteLength']])).convert('RGBA')
        texture.thumbnail((cw - 30, ch - 68), Image.Resampling.LANCZOS)
        preview.paste(texture, (cx + (cw - texture.width) // 2, cy + 12 + (ch - 68 - texture.height) // 2), texture)
        draw.text((cx + 10, cy + ch - 34), r['group'] + '/' + r['name'], font=font, fill='#243343')
        draw.text((cx + 10, cy + ch - 18), f"{r['world_size'][0]:.2f} x {r['world_size'][1]:.2f} units | 2 triangles", font=font, fill='#526174')
    preview.save(OUT / 'Previews/ModelOverview.png')


def main():
    (OUT / 'Previews').mkdir(parents=True, exist_ok=True)
    (OUT / 'Metadata').mkdir(parents=True, exist_ok=True)
    pngs = sorted(SOURCE / name for name in LEGACY_IMAGE_PATHS)
    assert len(pngs) == 27, f'Unexpected PNG count: {len(pngs)}'
    original_hashes = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in pngs}
    records = [make_record(p) for p in pngs]
    assembly(records, ['01_upper_leg', '02_03_middle_lower_merged', '04_foot'], 'Previews/RightLegCombined.tscn')
    assembly(records, ['01_upper_leg', '02_middle_leg', '03_lower_leg', '04_foot'], 'Previews/RightLegSeparated.tscn')
    demo_scene()
    manifest = {'model_count': len(records), 'geometry': 'XY plane, four vertices/two triangles per model; front normal +Z; zero visual thickness', 'material': 'embedded original RGBA PNG, double-sided, unlit, alpha mask cutoff 0.5', 'units': '100 ORIGINAL image pixels = 1 world unit; AI restored parts use inferred original heights', 'collision': 'Simplified convex alpha silhouette extruded to 0.02 units; holes omitted from collision; frozen RigidBody3D wrappers', 'pivots': 'Initial image-based estimates, editable JointIn/JointOut markers; reconstructed images have no exact original registration', 'assemblies': ['Previews/RightLegCombined.tscn', 'Previews/RightLegSeparated.tscn'], 'preview_scene': 'Previews/RightLegPreview.tscn', 'models': records}
    (OUT / 'Metadata/model_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding='utf-8')
    contact_sheet(records)
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == h for p, h in original_hashes.items())
    print(json.dumps({'output': str(OUT), 'models': len(records), 'glb_checks': 'passed', 'source_images_unchanged': True}, indent=2))


if __name__ == '__main__':
    main()
