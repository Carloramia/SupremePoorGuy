"""Non-destructive model pipeline for four AI-reconstructed tail segments.
Read original PNGs unchanged. Reuse the project's existing paper model builder.
Run normally, import in Godot, bake volumes, then run with --physical.
Existing GLBs, wrappers and Parts are never overwritten.
"""
from pathlib import Path
from PIL import Image
from collections import deque
import hashlib, importlib.util, json, shutil, sys

OUT = Path(__file__).resolve().parent.parent
PROJECT = next(p for p in OUT.parents if (p / 'project.godot').is_file())
SOURCE = PROJECT / 'Assets/2DResources/HornedBeast/SegmentedTail_v1'
spec = importlib.util.spec_from_file_location('paper_builder', OUT.parent / 'Tools/build_models.py')
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)
builder.OUT = OUT


def connector_holes(image):
    """Measure hole centers without editing the image, first at reduced resolution."""
    small = image.getchannel('A').copy()
    small.thumbnail((320, 320))
    width, height = small.size
    alpha = small.tobytes()
    seen = bytearray(width * height)
    centers = []
    for seed in range(width * height):
        if seen[seed] or alpha[seed] >= 128:
            continue
        pending = deque([seed])
        seen[seed] = 1
        points, border = [], False
        while pending:
            index = pending.popleft()
            x, y = index % width, index // width
            points.append((x, y))
            border |= x == 0 or x == width - 1 or y == 0 or y == height - 1
            for nx, ny in ((x-1, y), (x+1, y), (x, y-1), (x, y+1)):
                if 0 <= nx < width and 0 <= ny < height:
                    neighbor = ny * width + nx
                    if not seen[neighbor] and alpha[neighbor] < 128:
                        seen[neighbor] = 1
                        pending.append(neighbor)
        if not border and len(points) >= 12:
            centers.append([sum(x for x, _ in points)/len(points)*image.width/width,
                            sum(y for _, y in points)/len(points)*image.height/height])
    return sorted(centers)


def main():
    names = ['TailRoot', 'TailTransition', 'TailMiddle', 'TailTip']
    files = ['01_tail_root.png', '02_tail_transition.png', '03_tail_middle.png', '04_tail_tip.png']
    records = []
    for name, filename in zip(names, files):
        source = SOURCE / filename
        with Image.open(source) as image:
            assert image.mode == 'RGBA' and image.getchannel('A').getextrema()[0] == 0
            bounds = image.getchannel('A').point(lambda a: 255 if a >= 128 else 0).getbbox()
            holes = connector_holes(image)
            assert len(holes) >= (1 if name == 'TailTip' else 2), (name, holes)
            x0, y0, x1, y1 = bounds
            unit = 1.0 / (x1-x0)
            inlet = holes[-1]
            outlet = holes[0] if len(holes) >= 2 else [x0+(x1-x0)*0.56, y0+(y1-y0)*0.88]
            record = dict(name=name, category='TailSegments', file=filename,
                          source=builder.resource(source), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                          texture_size=list(image.size), alpha_bounds=list(bounds), pivot_pixel=inlet,
                          units_per_texture_pixel=unit, visible_world_size=[1.0,(y1-y0)*unit],
                          joint_out_local=[(outlet[0]-inlet[0])*unit,(inlet[1]-outlet[1])*unit,0],
                          connector_hole_pixels=holes, tags=[10], mass=0.05, thickness=0.08,
                          glb=f'Models/{name}.glb', scene=f'Scenes/{name}.tscn',
                          volume_mesh=f'res://Resources/Meshes/HornedBeast/SegmentedTail_v1/{name}.res',
                          physical_scene=f'res://Scenes/Creatures/Bodyparts/HornedBeast/SegmentedTail_v1/{name}.tscn')
            record['collision_points'] = builder.collision_points(image, inlet, unit)
            if '--physical' in sys.argv:
                assert (PROJECT / record['volume_mesh'].removeprefix('res://')).is_file()
                builder.physical_scene(record)
            else:
                model = OUT / record['glb']
                model.parent.mkdir(parents=True, exist_ok=True)
                if not model.exists():
                    builder.plane_glb(record, source, model)
                builder.write_new(Path(str(model)+'.import'), '[remap]\nimporter="scene"\n\n[params]\ngltf/embedded_image_handling=3\n')
                if not (OUT / record['scene']).exists():
                    (OUT / record['scene']).parent.mkdir(parents=True, exist_ok=True)
                    builder.part_scene(record, image)
                texture = OUT / 'Textures' / filename
                texture.parent.mkdir(parents=True, exist_ok=True)
                if not texture.exists():
                    shutil.copyfile(source, texture)
            records.append(record)
    manifest = OUT / 'Metadata/model_manifest.json'
    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(dict(model_count=4, models=records), ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('PASS: four segmented tail', 'Parts' if '--physical' in sys.argv else 'GLBs/wrappers', 'prepared without overwriting existing assets.')
    for record in records:
        print(record['name'], 'holes=', record['connector_hole_pixels'], 'endpoint=', record['joint_out_local'])


if __name__ == '__main__':
    main()
