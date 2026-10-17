"""New Rat 1 hind claws: keep the distal pixels and transplant each native joint ring.

No resampling, existing texture replacement, model rebuild or scene reassignment.
"""
from pathlib import Path
from collections import deque
import hashlib
import json

import numpy as np
from PIL import Image, ImageDraw, ImageFont

PROJECT = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').is_file())
ROOT = PROJECT / 'Assets/2DResources/Rats'
FEET = ROOT / 'Separated/Rat_1/Feet'
REPORT = PROJECT.parents[1] / 'Reports/RatClawVariants_2026-10-17'
SPECS = [
    dict(index=1, source='HindFoot1.png', cut=145, source_center=(61, 61),
         destination_center=(145, 60), radius=30.5, preserved_from_x=177),
    dict(index=2, source='HindFoot2.png', cut=126, source_center=(47, 38),
         destination_center=(126, 48), radius=29.0, preserved_from_x=157),
]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hole_pixels(rgba, seed):
    height, width = rgba.shape[:2]
    todo = deque([seed])
    visited = set()
    while todo:
        x, y = todo.popleft()
        if not 0 <= x < width or not 0 <= y < height or (x, y) in visited:
            continue
        if rgba[y, x, 3] >= 128:
            continue
        visited.add((x, y))
        todo.extend([(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)])
    assert visited and all(0 < x < width - 1 and 0 < y < height - 1 for x, y in visited)
    return np.array(sorted(visited), dtype=int)


def create(spec):
    source = FEET / spec['source']
    source_hash = sha(source)
    image = Image.open(source).convert('RGBA')
    original = np.array(image)
    output = original.copy()
    output[:, :spec['cut']] = 0
    sx, sy = spec['source_center']
    cx, cy = spec['destination_center']
    dx, dy = cx - sx, cy - sy
    yy, xx = np.indices(original.shape[:2])
    disc = (xx - cx) ** 2 + (yy - cy) ** 2 <= spec['radius'] ** 2
    y, x = np.where(disc)
    # Replace RGBA, including the transparent hole: alpha-compositing would fill it.
    output[y, x] = original[y - dy, x - dx]
    assert np.array_equal(output[:, spec['preserved_from_x']:], original[:, spec['preserved_from_x']:])
    hole = hole_pixels(original, (sx, sy))
    transferred_hole = hole + (dx, dy)
    assert np.all(output[transferred_hole[:, 1], transferred_hole[:, 0], 3] < 128)
    edited = Image.fromarray(output)
    bounds = edited.getbbox()
    assert bounds and bounds[0] > 0
    # Reframe only; original texture pixels and their scale are unchanged.
    crop = (bounds[0] - 12, bounds[1] - 12, bounds[2] + 12, bounds[3] + 12)
    cropped = edited.crop(crop)
    key = 'HindClaw%d' % spec['index']
    raw = ROOT / 'RawEdits/Rat_1' / ('rat1_hind_claw%d.png' % spec['index'])
    destination = FEET / (key + '.png')
    raw.parent.mkdir(parents=True, exist_ok=True)
    cropped.save(raw)
    cropped.save(destination)
    normalized = np.array(cropped)
    # Verify every retained claw pixel after the canvas translation.
    kept = np.argwhere((original[:, :, 3] > 0) & (xx >= spec['preserved_from_x']))
    assert np.array_equal(normalized[kept[:, 0] - crop[1], kept[:, 1] - crop[0]], original[kept[:, 0], kept[:, 1]])
    root = transferred_hole.mean(axis=0) - np.array(crop[:2])
    new_hole = hole_pixels(normalized, tuple(np.rint(root).astype(int)))
    assert len(new_hole) == len(hole), 'Connection hole must preserve its original pixel size'
    assert source_hash == sha(source), 'Original source must never be modified'
    return {
        'key': 'Rat_1/Feet/' + key,
        'source': source.relative_to(PROJECT).as_posix(),
        'source_sha256': source_hash,
        'raw_edit': raw.relative_to(PROJECT).as_posix(),
        'file': destination.relative_to(ROOT / 'Separated').as_posix(),
        'sha256': sha(destination),
        'canvas_size': list(cropped.size),
        'source_cut_x': spec['cut'],
        'source_crop': list(crop),
        'ring_translation': [dx, dy],
        'joint_in_pixel': root.tolist(),
        'joint_in': [float(root[0] / cropped.width), float(root[1] / cropped.height)],
        'hole_pixels': len(hole),
        'unchanged_claw_pixels': len(kept),
        'preserved_source_from_x': spec['preserved_from_x'],
        'resampled': False,
        'used_by_existing_models': (PROJECT / ('Assets/3DResources/Creatures/Rats/Models/Rat_1/Feet/' + key + '.glb')).is_file(),
    }


def preview(records):
    canvas = Image.new('RGB', (1000, 480), '#e8e8e8')
    draw = ImageDraw.Draw(canvas)
    font = ImageFont.truetype('C:/Windows/Fonts/arial.ttf', 19)
    for row, record in enumerate(records):
        y = row * 240
        draw.text((20, y + 15), 'HindFoot%d - original' % (row + 1), font=font, fill='#303030')
        draw.text((590, y + 15), 'HindClaw%d - new joint root' % (row + 1), font=font, fill='#303030')
        for column, path in enumerate([PROJECT / record['source'], FEET / ('HindClaw%d.png' % (row + 1))]):
            im = Image.open(path).convert('RGBA')
            im = im.resize((im.width * 2, im.height * 2), Image.Resampling.NEAREST)
            canvas.paste(im, (20 if column == 0 else 590, y + 45), im)
    canvas.save(ROOT / 'Separated/ClawVariantsOverview.png')
    REPORT.mkdir(parents=True, exist_ok=True)
    canvas.save(REPORT / 'claw_variants_preview.png')


def main():
    records = [create(spec) for spec in SPECS]
    document = {'count': len(records), 'note': 'Independent claw alternatives. Optional 3D chains are recorded in hind_claw_model_manifest.json.', 'parts': records}
    (ROOT / 'Separated/claw_variants.json').write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    preview(records)
    (REPORT / 'validation.json').write_text(json.dumps(document, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    for record in records:
        print('PASS:', record['file'], 'size=', record['canvas_size'], 'hole=', record['joint_in_pixel'], 'preserved claw pixels=', record['unchanged_claw_pixels'])


if __name__ == '__main__':
    main()
