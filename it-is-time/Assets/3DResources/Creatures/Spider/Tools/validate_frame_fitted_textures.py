"""Check original hashes, hole sizes and unchanged isotropic ring texture samples."""
from collections import deque
import hashlib
import json

import numpy as np
from PIL import Image
from build_frame_fitted_textures import META, PROJECT, sample

manifest = json.loads((META/'frame_fitted_manifest.json').read_text())
calibration = {r['key']: r for r in json.loads((META/'generator_calibration.json').read_text())['models']}
count = 0
for record in manifest['models']:
    r = calibration[record['key']]
    r = dict(r, **record['sampling'])
    source = PROJECT/record['source'].removeprefix('res://')
    assert hashlib.sha256(source.read_bytes()).hexdigest() == record['source_sha256']
    original = np.asarray(Image.open(source).convert('RGBA'), dtype=float)
    image = np.asarray(Image.open(PROJECT/record['texture'].removeprefix('res://')).convert('RGBA'))
    assert [image.shape[1], image.shape[0]] == record['texture_size']
    ppu = record['pixels_per_unit']
    top = np.array(record['top_left_world'])
    for endpoint in range(2 if r['name'] == 'UpperLeg' else 1):
        along = -r['calibrated_span']/2 if endpoint == 0 else r['calibrated_span']/2
        center = np.array([0., along])*(1 if r['name'] == 'UpperLeg' else -1)
        px = (center-top)*np.array([ppu, -ppu])
        start = tuple(np.floor(px).astype(int))
        visited, queue = {start}, deque([start])
        while queue:
            x, y = queue.popleft()
            assert 0 < x < image.shape[1]-1 and 0 < y < image.shape[0]-1, 'Hole connects to outer boundary'
            assert image[y, x, 3] < 128
            for point in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)]:
                xx, yy = point
                if point not in visited and image[yy, xx, 3] < 128:
                    visited.add(point)
                    queue.append(point)
        coordinates = np.array(list(visited))
        diameter = (coordinates.max(axis=0)-coordinates.min(axis=0)+1).mean()/ppu
        assert abs(diameter-.1) < 3/ppu, (record['key'], diameter)
        # The ring at the joint uses source pixels with isotropic scaling, not shaft stretching.
        yy, xx = np.mgrid[:image.shape[0], :image.shape[1]]
        world = np.stack([top[0]+(xx+.5)/ppu, top[1]-(yy+.5)/ppu], axis=-1)
        local = world*(1 if r['name']=='UpperLeg' else -1)
        radius = np.linalg.norm(local-np.array([0.,along]), axis=-1)
        ring = (radius < .07) & (image[...,3] >= 128)
        src_center = np.array(r['origin_pixel'])+np.array(r['axis_pixel'])*(0 if endpoint==0 else r['source_span'])
        delta = (local[ring]-np.array([0.,along]))/r['scales'][endpoint]
        pixels = src_center+delta[:,0,None]*r['across_pixel']+delta[:,1,None]*r['axis_pixel']
        expected = sample(original,pixels)
        assert np.max(np.abs(image[ring,:3].astype(float)-expected[:,:3])) <= .501, record['key']+' ring texture changed'
        count += 1
print(f'PASS: 16 originals unchanged; {count} holes retain 0.1-unit size and isotropic source ring textures.')
