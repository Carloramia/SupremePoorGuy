"""Build Rats GLBs, frozen wrappers and inherited PhysicalParts.
Run once, bake with Tools/BakeRatsVolumes.gd, then run with --physical.
Reuses the project's tested paper-model writer; existing physical scenes are kept.
"""
from pathlib import Path
from PIL import Image
import hashlib, importlib.util, json, shutil, sys

sys.dont_write_bytecode = True

OUT=Path(__file__).resolve().parent.parent
P=next(p for p in OUT.parents if (p/'project.godot').is_file())
S=P/'Assets/2DResources/Rats/Separated'
spec=importlib.util.spec_from_file_location('paper_model_writer',P/'Assets/3DResources/Creatures/Wolf/Tools/build_models.py')
writer=importlib.util.module_from_spec(spec); spec.loader.exec_module(writer)
writer.OUT=OUT; writer.PROJECT=P; writer.SOURCE=S


def main():
    settings=json.loads((OUT/'Metadata/build_settings.json').read_text(encoding='utf-8'))
    fixed_file=OUT/'Metadata/fixed_geometry.json'
    fixed=json.loads(fixed_file.read_text(encoding='utf-8')) if fixed_file.exists() else {}
    records=[]
    for part in settings['parts']:
        source=S/part['file']; image=Image.open(source).convert('RGBA')
        bounds=image.getchannel('A').point(lambda a:255 if a>=128 else 0).getbbox()
        x0,y0,x1,y1=bounds; unit=part['units_per_pixel']
        pivot=[x0+part['joint_in'][0]*(x1-x0),y0+part['joint_in'][1]*(y1-y0)]
        end=[x0+part['joint_out'][0]*(x1-x0),y0+part['joint_out'][1]*(y1-y0)]
        category=part['key']
        record=dict(part,source=writer.resource(source),source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                    texture_size=list(image.size),alpha_bounds=list(bounds),pivot_pixel=pivot,
                    units_per_texture_pixel=unit,visible_world_size=[(x1-x0)*unit,(y1-y0)*unit],
                    joint_out_local=[(end[0]-pivot[0])*unit,(pivot[1]-end[1])*unit,0],mass=.1,thickness=settings['thickness'],
                    glb=f'Models/{category}.glb',scene=f'Scenes/{category}.tscn',
                    volume_mesh=f'res://Resources/Meshes/Rats/{category}.res',
                    physical_scene=f'res://Scenes/Creatures/Bodyparts/Rats/{category}.tscn')
        if category in fixed:
            frame=fixed[category]
            assert list(image.size)==frame['texture_size'],'Completed foot canvas must not change'
            record.update({k:v for k,v in frame.items() if k!='repair_source'})
            record['origin']='pixel_ankle_completion'
            record['repair_source']=frame['repair_source']
        else:
            record['collision_points']=writer.collision_points(image,pivot,unit)
        if '--physical' in sys.argv:
            assert (P/record['volume_mesh'].removeprefix('res://')).is_file(),'Bake volumes first'
            target=P/record['physical_scene'].removeprefix('res://')
            was_new=not target.exists()
            if '--refresh' in sys.argv and not was_new:
                target.unlink()  # Only this builder's explicit manifest outputs.
            writer.physical_scene(record)
            if was_new or '--refresh' in sys.argv:
                content=target.read_text(encoding='utf-8').replace('name="Wolf_',f'name="Rats_{category.split("/")[0]}_')
                target.write_text(content,encoding='utf-8')
        else:
            model=OUT/record['glb']; model.parent.mkdir(parents=True,exist_ok=True)
            if not model.exists() or '--refresh' in sys.argv or category in fixed: writer.plane_glb(record,source,model)
            writer.write_new(Path(str(model)+'.import'),'[remap]\nimporter="scene"\n\n[params]\ngltf/embedded_image_handling=3\n')
            texture=OUT/'Textures'/f'{category}.png'; texture.parent.mkdir(parents=True,exist_ok=True)
            if not texture.exists() or '--refresh' in sys.argv or category in fixed: shutil.copyfile(source,texture)
            wrapper=OUT/record['scene']; wrapper.parent.mkdir(parents=True,exist_ok=True)
            if not wrapper.exists() or '--refresh' in sys.argv: writer.part_scene(record,image)
        records.append(record)
    (OUT/'Metadata/model_manifest.json').write_text(json.dumps({'model_count':len(records),'models':records,'coordinates':'XY paper plane; Z thickness; +X forward'},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    if '--physical' in sys.argv: preview(records)
    print('PASS: built',len(records),'Rats', 'PhysicalParts' if '--physical' in sys.argv else 'models and wrappers')


def preview(records):
    lines=['[gd_scene format=3]']
    for i,r in enumerate(records): lines.append(f'[ext_resource type="PackedScene" path="{r["physical_scene"]}" id="{i}"]')
    rows=(len(records)+6)//7
    lines.extend(['[sub_resource type="Environment" id="Env"]','background_mode = 1','background_color = Color(0.92, 0.92, 0.92, 1)',
                  '[node name="RatsPartsPreview" type="Node3D"]','[node name="Camera3D" type="Camera3D" parent="."]','position = Vector3(0, 0, 80)',
                  'projection = 1',f'size = {max(rows*6,54)}','current = true','[node name="WorldEnvironment" type="WorldEnvironment" parent="."]','environment = SubResource("Env")'])
    for i,r in enumerate(records):
        x=(i%7-3)*8; y=((rows-1)*.5-i//7)*6
        x0,y0,x1,y1=r['alpha_bounds']; px,py=r['pivot_pixel']; unit=r['units_per_texture_pixel']
        cx=((x0+x1)*.5-px)*unit; cy=(py-(y0+y1)*.5)*unit
        lines.extend([f'[node name="Part{i}" parent="." instance=ExtResource("{i}")]',f'position = Vector3({x-cx},{y-cy},0)',
                      'freeze = true','collision_layer = 0','collision_mask = 0',f'[node name="Label{i}" type="Label3D" parent="."]',
                      f'position = Vector3({x},{y-2.6},1)',f'text = "{r["key"]}"','font_size = 28','pixel_size = 0.007','modulate = Color(0.1,0.1,0.1,1)'])
    writer.write_new(OUT/'Previews/RatsPartsPreview.tscn','\n'.join(lines)+'\n')


if __name__=='__main__': main()
