"""Build HornedBeast paper models without modifying any source image.
Usage: python build_models.py [--physical]
Default builds GLBs and frozen wrappers; run BakeHornedBeastVolumes.gd next,
then --physical emits inherited Parts. Existing output scenes are preserved;
delete an output deliberately before regenerating manually edited markers.
"""
from pathlib import Path
from PIL import Image
import hashlib,json,math,struct,shutil,sys
OUT=Path(__file__).resolve().parent.parent
PROJECT=next(p for p in OUT.parents if (p/'project.godot').is_file())
SOURCE=PROJECT/'Assets/2DResources/HornedBeast/Separated'
THICKNESS=.02
def resource(path): return 'res://'+path.relative_to(PROJECT).as_posix()
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



def write_new(path,content):
    path.parent.mkdir(parents=True,exist_ok=True)
    if not path.exists(): path.write_text(content,encoding='utf-8')

def physical_scene(record):
    shape=record['collision_points']
    points=', '.join(f'{v:.8f}' for point in shape for v in point)
    marker=', '.join(f'{v:.8f}' for v in record['joint_out_local'])
    tags=', '.join(str(v) for v in record['tags'])
    depth=record['thickness']
    text=f'''[gd_scene load_steps=5 format=3]
[ext_resource type="PackedScene" path="res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn" id="1_base"]
[ext_resource type="PackedScene" path="{resource(OUT/record['glb'])}" id="2_model"]
[ext_resource type="ArrayMesh" path="{record['volume_mesh']}" id="3_mesh"]
[sub_resource type="ConvexPolygonShape3D" id="Shape"]
resource_local_to_scene = true
points = PackedVector3Array({points})
[node name="HornedBeast_{record['name']}" instance=ExtResource("1_base")]
mass = {record['mass']}
geometry_mode = 1
custom_model_path = NodePath("Model")
paper_volume_enabled = true
paper_volume_thickness = {depth}
sprite_visible = false
mesh_visible = true
tags = Array[int]([{tags}])
metadata/source_png = "{record['source']}"
metadata/pivot_is_initial_estimate = true
[node name="CollisionShape3D" parent="." index="0"]
position = Vector3(0, 0, 0)
shape = SubResource("Shape")
[node name="MeshInstance3D" parent="." index="2"]
visible = false
mesh = null
[node name="Model" parent="." instance=ExtResource("2_model")]
[node name="PaperVolume" type="MeshInstance3D" parent="Model"]
scale = Vector3(1, 1, {depth})
mesh = ExtResource("3_mesh")
metadata/flat_collision_depth = 0.02
[node name="JointIn" type="Marker3D" parent="."]
[node name="JointOut" type="Marker3D" parent="."]
position = Vector3({marker})
'''
    write_new(PROJECT/record['physical_scene'].removeprefix('res://'),text)

def preview(records):
    lines=['[gd_scene format=3]']
    for i,r in enumerate(records):
        lines.append(f'[ext_resource type="PackedScene" path="{r["physical_scene"]}" id="{i+1}"]')
    lines.extend(['[sub_resource type="Environment" id="Env"]','background_mode = 1','background_color = Color(0.16, 0.18, 0.22, 1)','[node name="HornedBeastPartsPreview" type="Node3D"]','[node name="Camera3D" type="Camera3D" parent="."]','position = Vector3(0, 0, 35)','projection = 1','size = 42.0','current = true','[node name="WorldEnvironment" type="WorldEnvironment" parent="."]','environment = SubResource("Env")'])
    for i,r in enumerate(records):
        x=(i%5-2)*8
        y=(1-i//5)*7
        lines.extend([f'[node name="{r["name"]}" parent="." instance=ExtResource("{i+1}")]',
                      f'position = Vector3({x}, {y}, 0)','freeze = true','collision_layer = 0','collision_mask = 0',
                      f'[node name="Label{i}" type="Label3D" parent="."]',
                      f'position = Vector3({x}, {y-3.2}, 1)',f'text = "{r["name"]}"','font_size = 40','pixel_size = 0.015'])
    write_new(OUT/'Previews/HornedBeastPartsPreview.tscn','\n'.join(lines)+'\n')

def main():
    settings=json.loads((OUT/'Metadata/build_settings.json').read_text(encoding='utf-8'))
    records=[]
    for spec in settings['parts']:
        source=SOURCE/spec['file']
        with Image.open(source) as image:
            assert image.mode=='RGBA'
            alpha=image.getchannel('A')
            bounds=alpha.point(lambda a:255 if a>=128 else 0).getbbox()
            assert bounds
            x0,y0,x1,y1=bounds
            extent=(x1-x0) if spec['size_axis']=='width' else (y1-y0)
            unit=spec['visible_size']/extent
            pivot=[x0+spec['joint_in'][0]*(x1-x0),y0+spec['joint_in'][1]*(y1-y0)]
            end=[x0+spec['joint_out'][0]*(x1-x0),y0+spec['joint_out'][1]*(y1-y0)]
            category=spec['category']+'/'+spec['name']
            record=dict(spec,source=resource(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                        texture_size=list(image.size),alpha_bounds=list(bounds),pivot_pixel=pivot,
                        units_per_texture_pixel=unit,visible_world_size=[(x1-x0)*unit,(y1-y0)*unit],
                        joint_out_local=[(end[0]-pivot[0])*unit,(pivot[1]-end[1])*unit,0],
                        glb='Models/'+category+'.glb',scene='Scenes/'+category+'.tscn',
                        volume_mesh='res://Resources/Meshes/HornedBeast/'+category+'.res',
                        physical_scene='res://Scenes/Creatures/Bodyparts/HornedBeast/'+category+'.tscn')
            record['collision_points']=collision_points(image,pivot,unit)
            if '--physical' in sys.argv:
                assert (PROJECT/record['volume_mesh'].removeprefix('res://')).exists(),'Bake volumes first'
                physical_scene(record)
            else:
                model=OUT/record['glb']
                model.parent.mkdir(parents=True,exist_ok=True)
                if not model.exists(): plane_glb(record,source,model)
                write_new(Path(str(model)+'.import'),'[remap]\nimporter="scene"\n\n[params]\ngltf/embedded_image_handling=3\n')
                texture=OUT/'Textures'/Path(category+'.png')
                texture.parent.mkdir(parents=True,exist_ok=True)
                if not texture.exists(): shutil.copyfile(source,texture)
                wrapper=OUT/record['scene']
                wrapper.parent.mkdir(parents=True,exist_ok=True)
                if not wrapper.exists(): part_scene(record,image)
            records.append(record)
    (OUT/'Metadata/model_manifest.json').write_text(json.dumps({'model_count':len(records),'models':records,'coordinates':'XY image plane, +X right, +Y up, +Z front; markers estimated'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if '--physical' in sys.argv: preview(records)
    print('PASS: prepared',len(records),'HornedBeast', 'PhysicalParts' if '--physical' in sys.argv else 'GLB models and wrappers')
if __name__=='__main__': main()
