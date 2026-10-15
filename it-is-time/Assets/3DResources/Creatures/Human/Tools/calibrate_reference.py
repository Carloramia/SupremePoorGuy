"""Calibrate generated Human sizes without changing textures, meshes or source Parts."""
from pathlib import Path
import json
import math
import sys
import numpy as np
from PIL import Image

ROOT = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').is_file())
RESOURCE = ROOT / 'Resources/Generators/HumanReferenceCalibration.tres'
META = ROOT / 'Assets/3DResources/Creatures/Human/Metadata'

# Body silhouettes exclude synthetic mounting tabs and the duplicate chest on the third skirt.
# These ranges measure the artwork only; all mounting geometry and ports remain intact.
BODY_Y = {
    'human1_torso': (156, 854), 'human1_pelvis': (101, None),
    'human1_hand_left': (390, None),
    'human1_foot_left': (300, None), 'human1_foot_right': (240, None),
    'human2_foot_left': (180, None), 'human2_foot_right': (170, None),
    'human3_pelvis': (280, None),
    'human3_foot_left': (225, None), 'human3_foot_right': (245, None),
    'human5_hand_left': (260, None),
}
SOURCE_FOOT_TOP = {
    'human1_foot_left': 980, 'human1_foot_right': 950,
    'human2_foot_left': 994, 'human2_foot_right': 990,
    'human3_foot_left': 944, 'human3_foot_right': 968,
}


def main_component_bounds(image):
    """Ignore isolated neighboring fragments and saturated source matte contamination."""
    pixels = np.asarray(image.convert('RGBA'))
    rgb = pixels[:, :, :3].astype(np.int16)
    vivid = (rgb[:, :, 0] > 240) & (rgb[:, :, 2] < 35) & ((rgb[:, :, 1] < 38) | (rgb[:, :, 1] > 225))
    mask = (pixels[:, :, 3] >= 128) & ~vivid
    parents, runs, previous = [], [], []

    def find(i):
        while parents[i] != i:
            parents[i] = parents[parents[i]]
            i = parents[i]
        return i

    for y, row in enumerate(mask):
        changes = np.diff(np.pad(row.astype(np.int8), (1, 1)))
        current, cursor = [], 0
        for left, right in zip(np.flatnonzero(changes == 1), np.flatnonzero(changes == -1)):
            n = len(parents)
            parents.append(n)
            while cursor < len(previous) and previous[cursor][1] < left:
                cursor += 1
            q = cursor
            while q < len(previous) and previous[q][0] <= right:
                a, b = find(previous[q][2]), find(n)
                if a != b:
                    parents[a] = b
                q += 1
            current.append((left, right, n))
            runs.append((y, left, right, n))
        previous = current
    areas = {}
    for _, left, right, n in runs:
        key = find(n)
        areas[key] = areas.get(key, 0) + int(right - left)
    if not areas:
        raise ValueError('Empty original body silhouette')
    largest = max(areas, key=areas.get)
    chosen = [(y, int(a), int(b)) for y, a, b, n in runs if find(n) == largest]
    return [min(a for _, a, _ in chosen), min(y for y, _, _ in chosen),
            max(b for _, _, b in chosen), max(y for y, _, _ in chosen) + 1]


def main():
    header, payload = RESOURCE.read_text(encoding='utf-8').split('metadata/calibration = ', 1)
    data = json.loads(payload)
    models = {m['physical_scene']: m for m in json.loads((META / 'model_manifest.json').read_text())['models']}
    unit = float(json.loads((META / 'build_settings.json').read_text())['source_pixel_to_world_reference'])
    assert math.isfinite(unit) and unit > 0
    selected = next((set(arg.partition('=')[2].split(',')) for arg in sys.argv if arg.startswith('--sets=')), None)
    count = 0
    for number, source_set in data['sets'].items():
        if selected is not None and number not in selected: continue
        source_set['source_units_x'] = source_set['source_units_y'] = unit
        for name, part in source_set['parts'].items():
            count += 1
            model = models[part['asset']]
            if part['source_joints']:
                part['target'] = math.dist(*part['source_joints']) * unit
                native = math.dist(part['ports']['in'], part['ports']['out']) * part['pixel_unit']
                part['scale'] = part['target'] / native
                part['fit'] = 'joint_span'
                continue
            original_box = part.setdefault('source_search_bounds', list(part['source_bounds']))
            search = list(original_box)
            if model['key'] in SOURCE_FOOT_TOP:
                search[1] = SOURCE_FOOT_TOP[model['key']]
            source = Image.open(ROOT / part['source_image']).convert('RGBA').crop(tuple(search))
            tight = main_component_bounds(source)
            part['source_bounds'] = [tight[0] + search[0], tight[1] + search[1], tight[2] + search[0], tight[3] + search[1]]
            visual = list(model['alpha_bounds'])
            if model['key'] in BODY_Y:
                top, bottom = BODY_Y[model['key']]
                visual[1], visual[3] = top, bottom if bottom is not None else visual[3]
            assert 0 <= visual[0] < visual[2] <= model['texture_size'][0]
            assert 0 <= visual[1] < visual[3] <= model['texture_size'][1]
            alpha = Image.open(ROOT / model['source'].removeprefix('res://')).getchannel('A').crop(tuple(visual))
            visible = alpha.getbbox()
            assert visible
            visual = [visible[0] + visual[0], visible[1] + visual[1], visible[2] + visual[0], visible[3] + visual[1]]
            bounds = part['source_bounds']
            target = [(bounds[2] - bounds[0]) * unit, (bounds[3] - bounds[1]) * unit]
            native = [(visual[2] - visual[0]) * part['pixel_unit'], (visual[3] - visual[1]) * part['pixel_unit']]
            # One uniform factor minimizes the worst relative width/height error.
            part['scale'] = 2.0 / (native[0] / target[0] + native[1] / target[1])
            part['fit'] = 'outline'
            part['visual_bounds'] = visual
            part['target_size'] = target
            part['target'] = math.sqrt(target[0] * target[1])
            print(name, model['key'], f'scale={part["scale"]:.4f}',
                  f'body error X/Y={native[0]*part["scale"]/target[0]-1:+.1%}/{native[1]*part["scale"]/target[1]-1:+.1%}')
    data['version'] = 2
    data['source_pixel_unit'] = unit
    data['policy'] = 'One source pixel unit for all sets and axes. Preserve uniform XY texture scale; fit original joint spans or measured body outlines, excluding added connector tabs. One outline scale minimizes maximum relative width/height error without warping the image.'
    text = header + 'metadata/calibration = ' + json.dumps(data, ensure_ascii=False, indent=2) + '\n'
    RESOURCE.write_text(text, encoding='utf-8')
    print('PASS: Calibrated',count,'Human body sizes at one source pixel unit; source artwork unchanged.')


if __name__ == '__main__':
    main()
