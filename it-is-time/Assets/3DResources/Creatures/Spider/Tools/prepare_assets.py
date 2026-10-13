"""Register the approved imagegen extractions; never replace existing artwork."""
from pathlib import Path
import hashlib
import html
import json
import shutil
from PIL import Image

OUT = Path(__file__).resolve().parent.parent
PROJECT = next(p for p in OUT.parents if (p / 'project.godot').is_file())
SOURCE = PROJECT / 'Assets/2DResources/Spider'

def main():
    plan = json.loads((OUT / 'Metadata/final_extraction.json').read_text(encoding='utf-8'))
    results = {r['key']: r for r in plan['results']}
    assert len(results) == len(plan['specs']) == 22
    SOURCE.mkdir(parents=True, exist_ok=True)
    original = PROJECT / 'Assets/2DResources/AIGenerated/Unprocessed/Spider/Spider.png'
    saved = SOURCE / 'Spider.png'
    if not saved.exists(): shutil.copyfile(original, saved)
    assert saved.read_bytes() == original.read_bytes()
    settings, assets = [], []
    for key, filename, category, name, box, description, size, inlet, outlet, tags, mass in plan['specs']:
        generated = Path(results[key]['generated_path'])
        target = SOURCE / 'Separated' / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists(): assert target.read_bytes() == generated.read_bytes(), f'Refusing to overwrite {target}'
        else: shutil.copyfile(generated, target)
        with Image.open(target) as image:
            assert image.mode == 'RGBA', key
            alpha = image.getchannel('A')
            bounds = alpha.point(lambda a: 255 if a >= 128 else 0).getbbox()
            clear = alpha.histogram()[0] / (image.width * image.height)
            assert bounds and clear > .05, f'Missing transparent silhouette: {key}'
            assert bounds[0] > 0 and bounds[1] > 0 and bounds[2] < image.width and bounds[3] < image.height, f'Clipped: {key}'
            assets.append(dict(key=key, file=filename, canvas_size=list(image.size), alpha_bounds_50_percent=list(bounds), transparent_pixel_ratio=clear, sha256=hashlib.sha256(target.read_bytes()).hexdigest(), source_region=box, description=description))
        axis = 'width' if key in ['rear_torso', 'front_torso', 'joint_rivet'] else 'height'
        if key.endswith('_upper'):
            number = int(key.split('_')[1])
            axis = 'width' if number == 1 else 'height'
            size = {1: 1.45, 2: 1.5, 3: 1.5, 4: 2.2}[number]
            inlet = [.2, .25] if key.startswith('right') else [.8, .25]
            outlet = [.8, .8] if key.startswith('right') else [.2, .8]
        elif key.endswith('_lower'):
            number = int(key.split('_')[1])
            size = {1: 4.15, 2: 4.6, 3: 3.9, 4: 2.8}[number]
            inlet = [.5, .12]
            outlet = [.5, .98]
        settings.append(dict(key=key, file=filename, category=category, name=name, size_axis=axis, visible_size=size, joint_in=inlet, joint_out=outlet, tags=tags, mass=mass, thickness=.08))
    metadata = dict(source='../Spider.png', method='built-in imagegen individual extraction and occlusion reconstruction; source preserved', assets=assets)
    (SOURCE / 'Separated/asset_manifest.json').write_text(json.dumps(metadata, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    cards = ''.join(f'<article><img src="{html.escape(a["file"])}"><p>{html.escape(a["key"])}</p></article>' for a in assets)
    (SOURCE / 'Separated/Preview.html').write_text('<!doctype html><html lang="zh"><meta charset="utf-8"><title>Spider Parts</title><style>body{background:#25272b;color:white;font:16px sans-serif}main{display:grid;grid-template-columns:repeat(4,1fr);gap:16px}article{padding:12px;background:#35383d}img{width:100%;height:260px;object-fit:contain;background:repeating-conic-gradient(#777 0% 25%,#555 0% 50%) 0 / 20px 20px}</style><h1>Spider · 22 independent parts</h1><main>'+cards+'</main></html>', encoding='utf-8')
    build = dict(description='Spider paper parts. XY visual plane, thickness on Z. Reference proportions approximate original sheet at 0.01 units/pixel; markers initially estimated and editable. Mouth/rivet are untagged attachments, not gameplay weapons.', parts=settings)
    (OUT / 'Metadata/build_settings.json').write_text(json.dumps(build, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print('PASS: registered 22 transparent Spider assets; source preserved.')

if __name__ == '__main__': main()
