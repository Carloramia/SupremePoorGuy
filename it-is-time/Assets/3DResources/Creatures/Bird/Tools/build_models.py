"""Prepare Bird model metadata, then run BakeBirdVolumes.gd and --physical.
Reuses the existing contour collision writer. Authored Part scenes are not overwritten.
"""
from pathlib import Path
from PIL import Image
import hashlib, importlib.util, json, shutil, sys
sys.dont_write_bytecode = True
OUT=Path(__file__).resolve().parent.parent
P=next(p for p in OUT.parents if (p/'project.godot').is_file())
S=P/'Assets/2DResources/Bird/Separated'
spec=importlib.util.spec_from_file_location('bird_paper_writer',P/'Assets/3DResources/Creatures/Wolf/Tools/build_models.py')
writer=importlib.util.module_from_spec(spec); spec.loader.exec_module(writer)
writer.PROJECT=P; writer.OUT=OUT; writer.SOURCE=S


def physical(r):
    points=', '.join(f'{v:.8f}' for point in r['collision_points'] for v in point)
    marker=', '.join(f'{v:.8f}' for v in r['joint_out_local'])
    tags=', '.join(str(v) for v in r['tags'])
    text=f'''[gd_scene load_steps=4 format=3]
[ext_resource type="PackedScene" path="res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn" id="base"]
[ext_resource type="PackedScene" path="{r['model_scene']}" id="model"]
[sub_resource type="ConvexPolygonShape3D" id="Shape"]
resource_local_to_scene = true
points = PackedVector3Array({points})
metadata/body_part_collision_depth_multiplier = 2.0
[node name="Bird{r['set']}{r['name']}" instance=ExtResource("base")]
mass = {r['mass']}
geometry_mode = 1
custom_model_path = NodePath("Model")
paper_volume_enabled = true
paper_volume_thickness = {r['thickness']}
sprite_visible = false
mesh_visible = true
tags = Array[int]([{tags}])
metadata/source_png = "{r['source']}"
metadata/anatomical_role = "{r['role']}"
metadata/part_key = "{r['key']}"
metadata/pivot_is_initial_estimate = true
[node name="CollisionShape3D" parent="." index="0"]
position = Vector3(0, 0, 0)
shape = SubResource("Shape")
[node name="MeshInstance3D" parent="." index="2"]
visible = false
mesh = null
[node name="Model" parent="." instance=ExtResource("model")]
[node name="JointIn" type="Marker3D" parent="."]
[node name="JointOut" type="Marker3D" parent="."]
position = Vector3({marker})
'''
    writer.write_new(P/r['physical_scene'].removeprefix('res://'),text)


def preview(records,v):
    cols=5; rows=(len(records)+cols-1)//cols
    lines=['[gd_scene format=3]']
    for i,r in enumerate(records): lines.append(f'[ext_resource type="PackedScene" path="{r["physical_scene"]}" id="{i}"]')
    lines+=['[sub_resource type="Environment" id="Env"]','background_mode = 1','background_color = Color(0.93, 0.93, 0.93, 1)',
            f'[node name="Bird{v}PartsPreview" type="Node3D"]','[node name="Camera3D" type="Camera3D" parent="."]',
            'position = Vector3(0, 0, 80)','projection = 1',f'size = {max(32,rows*5+2)}','current = true',
            '[node name="WorldEnvironment" type="WorldEnvironment" parent="."]','environment = SubResource("Env")']
    for i,r in enumerate(records):
        x=(i%cols-2)*7; y=((rows-1)/2-i//cols)*5
        x0,y0,x1,y1=r['alpha_bounds']; px,py=r['pivot_pixel']; unit=r['units_per_texture_pixel']
        cx=((x0+x1)/2-px)*unit; cy=(py-(y0+y1)/2)*unit
        fit=min(1,5.6/max(r['visible_world_size']))
        lines += [f'[node name="Part{i}" parent="." instance=ExtResource("{i}")]',f'position = Vector3({x-cx*fit}, {y-cy*fit}, 0)',
                  f'scale = Vector3({fit}, {fit}, {fit})','freeze = true','collision_layer = 0','collision_mask = 0',
                  f'[node name="Label{i}" type="Label3D" parent="."]',f'position = Vector3({x}, {y-2.2}, 1)',
                  f'text = "{r["role"]}/{r["name"]}"','font_size = 28','pixel_size = 0.006','modulate = Color(0.1, 0.1, 0.1, 1)']
    writer.write_new(OUT/f'Previews/Bird{v}PartsPreview.tscn','\n'.join(lines)+'\n')


def main():
    settings=json.loads((OUT/'Metadata/build_settings.json').read_text(encoding='utf-8')); records=[]
    for item in settings['parts']:
        path=S/item['file']; image=Image.open(path).convert('RGBA')
        bounds=image.getchannel('A').getbbox(); x0,y0,x1,y1=bounds; unit=item['units_per_pixel']
        pivot=item['joint_pixels'][0]; end=item['joint_pixels'][1]; category=item['key']
        texture=OUT/'Textures'/f'{category}.png'; texture.parent.mkdir(parents=True,exist_ok=True); shutil.copyfile(path,texture)
        r=dict(item,source=writer.resource(path),source_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
               texture=writer.resource(texture),texture_size=list(image.size),alpha_bounds=list(bounds),pivot_pixel=pivot,
               units_per_texture_pixel=unit,visible_world_size=[(x1-x0)*unit,(y1-y0)*unit],thickness=settings['thickness'],
               joint_out_local=[(end[0]-pivot[0])*unit,(pivot[1]-end[1])*unit,0],
               glb=writer.resource(OUT/f'Models/{category}.glb'),model_scene=writer.resource(OUT/f'Scenes/{category}.tscn'),
               volume_mesh=f'res://Resources/Meshes/Bird/{category}.res',
               physical_scene=f'res://Scenes/Creatures/Bodyparts/Bird/{category}.tscn')
        r['collision_points']=[(x,y,settings['thickness'] if z>0 else -settings['thickness']) for x,y,z in writer.collision_points(image,pivot,unit)]
        if '--physical' in sys.argv:
            assert (P/r['volume_mesh'].removeprefix('res://')).is_file(),'Bake Bird volumes first'
            physical(r)
        records.append(r)
    (OUT/'Metadata/model_manifest.json').write_text(json.dumps(dict(model_count=len(records),coordinates='XY image plane; +Z front; thickness along Z',outline_resolution=256,models=records),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if '--physical' in sys.argv:
        for v in range(1,4): preview([r for r in records if r['set']==v],v)
    print('PASS:',len(records),'Bird','PhysicalParts and previews' if '--physical' in sys.argv else 'model records prepared')


if __name__=='__main__': main()
