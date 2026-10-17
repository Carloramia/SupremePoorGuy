"""Build the two HindClaw alternatives without rewriting the original 55 assets.

Run, import in Godot, bake with BakeRatsVolumes.gd -- --hind-claws-only,
then run this script with --physical.
"""
from pathlib import Path
from PIL import Image
import hashlib
import importlib.util
import json
import shutil
import sys

sys.dont_write_bytecode = True
OUT = Path(__file__).resolve().parent.parent
PROJECT = next(p for p in OUT.parents if (p / 'project.godot').is_file())
SOURCE = PROJECT / 'Assets/2DResources/Rats/Separated'
spec = importlib.util.spec_from_file_location('paper_writer', PROJECT / 'Assets/3DResources/Creatures/Wolf/Tools/build_models.py')
writer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(writer)
writer.OUT = OUT
writer.PROJECT = PROJECT
writer.SOURCE = SOURCE


def main():
    variants = json.loads((SOURCE / 'claw_variants.json').read_text(encoding='utf-8'))
    originals = json.loads((OUT / 'Metadata/model_manifest.json').read_text(encoding='utf-8'))
    records = []
    for variant in variants['parts']:
        source = SOURCE / variant['file']
        previous = next(r for r in originals['models'] if r['source'].removeprefix('res://') == variant['source'])
        image = Image.open(source).convert('RGBA')
        x0, y0, x1, y1 = image.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()
        pivot = variant['joint_in_pixel']
        unit = previous['units_per_texture_pixel']
        key = variant['key']
        record = {
            'key': key, 'name': Path(key).name, 'file': variant['file'],
            'source': writer.resource(source), 'source_sha256': hashlib.sha256(source.read_bytes()).hexdigest(),
            'texture_size': list(image.size), 'alpha_bounds': [x0, y0, x1, y1],
            'pivot_pixel': pivot, 'units_per_texture_pixel': unit,
            'visible_world_size': [(x1 - x0) * unit, (y1 - y0) * unit],
            'joint_out_local': [(x1 - pivot[0]) * unit, 0, 0],
            'mass': .1, 'thickness': previous['thickness'], 'tags': [1],
            'glb': f'Models/{key}.glb', 'scene': f'Scenes/{key}.tscn',
            'volume_mesh': f'res://Resources/Meshes/Rats/{key}.res',
            'physical_scene': f'res://Scenes/Creatures/Bodyparts/Rats/{key}.tscn',
            'joint_in_is_calibrated': True,
        }
        record['collision_points'] = writer.collision_points(image, pivot, unit)
        if '--physical' in sys.argv:
            assert (PROJECT / record['volume_mesh'].removeprefix('res://')).is_file(), 'Bake the paper mesh first'
            target = PROJECT / record['physical_scene'].removeprefix('res://')
            is_new = not target.exists()
            writer.physical_scene(record)
            if is_new:
                text = target.read_text(encoding='utf-8').replace('name="Wolf_', 'name="Rats_Rat_1_')
                text = text.replace('metadata/pivot_is_initial_estimate = true', 'metadata/pivot_is_initial_estimate = false')
                target.write_text(text, encoding='utf-8')
        else:
            glb = OUT / record['glb']
            glb.parent.mkdir(parents=True, exist_ok=True)
            writer.plane_glb(record, source, glb)
            writer.write_new(Path(str(glb) + '.import'), '[remap]\nimporter="scene"\n\n[params]\ngltf/embedded_image_handling=3\n')
            texture = OUT / 'Textures' / f'{key}.png'
            texture.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source, texture)
            wrapper = OUT / record['scene']
            wrapper.parent.mkdir(parents=True, exist_ok=True)
            writer.part_scene(record, image)
        records.append(record)
    (OUT / 'Metadata/hind_claw_model_manifest.json').write_text(json.dumps({'model_count': len(records), 'models': records}, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print('PASS:', len(records), 'HindClaw PhysicalParts' if '--physical' in sys.argv else 'HindClaw models and wrappers')


if __name__ == '__main__':
    main()
