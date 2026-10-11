"""Register approved AI-extracted Wolf_2 PNGs without replacing Wolf assets."""
from pathlib import Path
from PIL import Image
import hashlib
import html
import json
import shutil

PROJECT = Path(__file__).resolve().parents[5]
SEPARATED = PROJECT / 'Assets/2DResources/Wolf/Separated'
METADATA = PROJECT / 'Assets/3DResources/Creatures/Wolf/Metadata'

def main():
    plan = json.loads((SEPARATED / 'wolf2_generation_prompts.json').read_text(encoding='utf-8'))
    results = {r['key']: r for r in plan['results']}
    assert len(results) == len(plan['specs']) == 34, 'Finish all requested image extractions first'
    source = PROJECT / 'Assets/2DResources/AIGenerated/Unprocessed/Wolf_2.png'
    source_copy = SEPARATED.parent / 'Wolf_2.png'
    if source_copy.exists(): assert source_copy.read_bytes() == source.read_bytes()
    else: shutil.copyfile(source, source_copy)
    assets, settings = [], []
    cards = []
    for key, filename, category, name, size, inlet, outlet, tags, description in plan['specs']:
        generated = Path(results[key]['generated_path'])
        target = SEPARATED / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.exists(): assert target.read_bytes() == generated.read_bytes(), f'Refusing to replace {target}'
        else: shutil.copyfile(generated, target)
        with Image.open(target) as image:
            assert image.mode == 'RGBA'
            alpha = image.getchannel('A')
            bounds = alpha.point(lambda a: 255 if a >= 128 else 0).getbbox()
            assert bounds and alpha.getextrema()[0] == 0, f'Missing silhouette/transparency: {filename}'
            transparent = alpha.histogram()[0] / (image.width * image.height)
            assert transparent > .03, f'Background not removed: {filename}'
            assets.append(dict(key='wolf2_'+key, file=filename, canvas_size=list(image.size),
                alpha_bounds_50_percent=list(bounds), transparent_pixel_ratio=transparent,
                sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                source_sheet='res://Assets/2DResources/Wolf/Wolf_2.png', description=description))
        width_axis = key in ['torso', 'tail', 'mane', 'ornament_flame', 'ornament_curl', 'rivet', 'eye']
        mass = 3.0 if tags == [0] else .6 if tags == [3] else .3 if tags == [5] else .15 if tags == [10] else .12 if tags else .03
        settings.append(dict(key='wolf2_'+key, file=filename, category=category, name=name,
            size_axis='width' if width_axis else 'height', visible_size=size,
            joint_in=inlet, joint_out=outlet, tags=tags, mass=mass, thickness=.08))
        cards.append(f'<article><img src="{html.escape(filename)}"><p>{html.escape(filename)}</p></article>')
    manifest = dict(source='../Wolf_2.png', method='built-in image_gen extraction and occlusion reconstruction; original preserved', assets=assets)
    (SEPARATED / 'wolf2_asset_manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    (SEPARATED / 'Wolf2Preview.html').write_text('<!doctype html><html lang="zh"><meta charset="utf-8"><title>Wolf_2 parts</title><style>body{background:#25272b;color:white;font:14px sans-serif}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:16px}article{padding:12px;background:#35383d}img{width:100%;height:240px;object-fit:contain;background:repeating-conic-gradient(#777 0% 25%,#555 0% 50%) 0 / 20px 20px}p{overflow-wrap:anywhere}</style><h1>Wolf_2 · 34 parts</h1><main>'+''.join(cards)+'</main></html>', encoding='utf-8')
    settings_path = METADATA / 'build_settings.json'
    build = json.loads(settings_path.read_text(encoding='utf-8'))
    existing = {s['key']: s for s in build['parts']}
    for spec in settings:
        if spec['key'] in existing: assert existing[spec['key']] == spec
        else: build['parts'].append(spec)
    settings_path.write_text(json.dumps(build, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    assert len({(s['category'],s['name']) for s in build['parts']}) == len(build['parts'])
    print(f'PASS: registered {len(assets)} Wolf_2 transparent PNGs; {len(build["parts"])} total Wolf model specs.')

if __name__ == '__main__': main()
