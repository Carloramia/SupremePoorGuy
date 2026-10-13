"""Create frame-space Spider textures without stretching the shaft's texel scale.

The existing calibrated silhouette and 0.1-unit holes stay fixed. End caps are
sampled isotropically; additional shaft length repeats the source texture at its
original local scale instead of stretching its pixels. Originals are never saved.
"""
from pathlib import Path
import hashlib
import json
import math

import numpy as np
from PIL import Image

PROJECT = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').exists())
META = PROJECT / 'Assets/3DResources/Creatures/Spider/Metadata'


def sample(image, pixels):
    x, y = pixels[..., 0] - .5, pixels[..., 1] - .5
    valid = (x >= 0) & (y >= 0) & (x <= image.shape[1]-1) & (y <= image.shape[0]-1)
    x = np.clip(x, 0, image.shape[1]-1)
    y = np.clip(y, 0, image.shape[0]-1)
    x0, y0 = x.astype(int), y.astype(int)
    x1, y1 = np.minimum(x0+1, image.shape[1]-1), np.minimum(y0+1, image.shape[0]-1)
    fx, fy = (x-x0)[..., None], (y-y0)[..., None]
    result = ((image[y0, x0]*(1-fx)+image[y0, x1]*fx)*(1-fy)
              +(image[y1, x0]*(1-fx)+image[y1, x1]*fx)*fy)
    return np.where(valid[..., None], result, 0)


def warp(pixels, r):
    delta = pixels-np.array(r['origin_pixel'])
    t, x = delta@r['axis_pixel'], delta@r['across_pixel']
    a, b = r['breakpoints'][1:3]
    blend = np.clip((t-a)/(b-a), 0, 1)
    scale = r['scales'][0]*(1-blend)+r['scales'][1]*blend
    y = np.where(t <= a, t*r['scales'][0], np.where(t >= b,
        r['calibrated_span']+(t-r['source_span'])*r['scales'][1],
        r['values'][1]*(1-blend)+r['values'][2]*blend))
    x *= scale*(1-(1-r['shaft_compression'])*np.sin(np.pi*blend))
    band = r['calibrated_width']*.5-.075
    x = np.where(np.abs(x) > .075,
        np.sign(x)*(.075+band*np.tanh((np.abs(x)-.075)/band)), x)
    points = np.stack([x, y-r['calibrated_span']*.5], axis=-1)
    return points if r['name'] == 'UpperLeg' else -points


def build(r):
    r = dict(r)
    source_path = PROJECT / r['source'].removeprefix('res://')
    source_hash = hashlib.sha256(source_path.read_bytes()).hexdigest()
    assert source_hash == r['source_sha256'], 'Source changed: '+r['key']
    image = np.asarray(Image.open(source_path).convert('RGBA'), dtype=float)
    # Three "upper" source files are composite pictures. Use their white upper bar,
    # not the farthest pair of holes belonging to different overlapping pieces.
    composite = r['key'] in ['left_4_upper', 'right_4_upper', 'right_3_upper']
    if composite:
        holes = json.loads((META/'generator_source_holes.json').read_text())[r['volume_mesh']]['holes'][:2]
        start, end = [np.array(h['pixel']) for h in holes]
        diameters = [sum(h['size'])/2 for h in holes]
        axis = (end-start)/np.linalg.norm(end-start)
        across_axis = np.array([axis[1], -axis[0]])
        length = float(np.linalg.norm(end-start))
        buffers = [min(d*1.4, length*.23) for d in diameters]
        scales = [.1/d for d in diameters]
        r.update(origin_pixel=start.tolist(), axis_pixel=axis.tolist(), across_pixel=across_axis.tolist(),
            source_span=length, breakpoints=[0,buffers[0],length-buffers[1],length],
            values=[0,buffers[0]*scales[0],r['calibrated_span']-buffers[1]*scales[1],r['calibrated_span']],
            scales=scales, shaft_compression=1.)
        sy, sx = np.mgrid[:image.shape[0], :image.shape[1]]
        delta = np.stack([sx+.5,sy+.5],axis=-1)-start
        along, across = delta@axis, delta@across_axis
        white = (np.ptp(image[...,:3],axis=-1)<60) & (image[...,:3].min(axis=-1)>100)
        rings = ((along**2+across**2)<diameters[0]**2) | (((along-length)**2+across**2)<diameters[1]**2)
        roi = (along>=-diameters[0]*2) & (along<=length+diameters[1]*2) & (np.abs(across)<max(diameters)*2)
        image[...,3] *= roi & (white | rings)
        yy, xx = np.nonzero(image[...,3]>=128)
        r['silhouette']=np.stack([xx+.5, yy+.5],axis=-1).tolist()
    scale = r['scales'][0]
    ppu = 1/scale
    contour = warp(np.array(r['silhouette'], dtype=float), r)
    low, high = contour.min(axis=0), contour.max(axis=0)
    margin = 4
    origin = np.array([low[0]-margin/ppu, high[1]+margin/ppu])
    size = np.ceil((high-low)*ppu).astype(int)+margin*2
    width, height = map(int, size)
    yy, xx = np.mgrid[:height, :width]
    world = np.stack([origin[0]+(xx+.5)/ppu, origin[1]-(yy+.5)/ppu], axis=-1)
    local = world if r['name'] == 'UpperLeg' else -world
    x, w = local[..., 0], local[..., 1]+r['calibrated_span']*.5
    a, b = r['breakpoints'][1:3]
    va, vb = r['values'][1:3]
    t = np.where(w <= va, w/r['scales'][0], np.where(w >= vb,
        r['source_span']+(w-r['calibrated_span'])/r['scales'][1],
        a+(w-va)/(vb-va)*(b-a)))
    blend = np.clip((t-a)/(b-a), 0, 1)
    local_scale = r['scales'][0]*(1-blend)+r['scales'][1]*blend
    band = r['calibrated_width']*.5-.075
    unclipped = np.where(np.abs(x) > .075,
        np.sign(x)*(.075+band*np.arctanh(np.clip((np.abs(x)-.075)/band, 0, 1-1e-12))), x)
    across = unclipped/(local_scale*(1-(1-r['shaft_compression'])*np.sin(np.pi*blend)))
    axis, perpendicular = np.array(r['axis_pixel']), np.array(r['across_pixel'])
    start = np.array(r['origin_pixel'])
    silhouette = sample(image, start+t[..., None]*axis+across[..., None]*perpendicular)[..., 3]
    silhouette[np.abs(x) >= r['calibrated_width']*.5] = 0

    # Constant axial texel scale; reflect the interior texture to avoid jump seams.
    period = b-a
    phase = np.mod((w-va)/scale, period*2)
    tex_t = a+np.where(phase <= period, phase, period*2-phase)
    interior = (w > va) & (w < vb)
    ysrc, xsrc = np.nonzero(image[..., 3] >= 128)
    pixels = np.stack([xsrc+.5, ysrc+.5], axis=-1)-start
    ts, us = pixels@axis, pixels@perpendicular
    first, last = math.floor(ts.min()), math.ceil(ts.max())
    bins = np.clip(np.floor(ts).astype(int)-first, 0, last-first)
    min_u = np.full(last-first+1, np.inf)
    max_u = np.full(last-first+1, -np.inf)
    np.minimum.at(min_u, bins, us)
    np.maximum.at(max_u, bins, us)
    valid = np.isfinite(min_u)
    rows = np.arange(len(min_u))
    min_u = np.interp(rows, rows[valid], min_u[valid])
    max_u = np.interp(rows, rows[valid], max_u[valid])
    row = np.clip(np.floor(tex_t).astype(int)-first, 0, len(min_u)-1)
    left, right = min_u[row], max_u[row]
    tex_u = np.clip(x/scale+(left+right)*.5, left+1, right-1)
    # Retain the original thin edge finish without compressing the shaft texture.
    mask = silhouette >= 128
    for y in range(height):
        opaque = np.flatnonzero(mask[y])
        if not len(opaque): continue
        lo, hi = opaque[0], opaque[-1]
        distance_l, distance_r = xx[y]-lo, hi-xx[y]
        near_l = (distance_l >= 0) & (distance_l < 6)
        near_r = (distance_r >= 0) & (distance_r < 6)
        if r['name'] == 'UpperLeg':
            tex_u[y] = np.where(near_l, left[y]+distance_l+1, tex_u[y])
            tex_u[y] = np.where(near_r, right[y]-distance_r-1, tex_u[y])
        else:
            tex_u[y] = np.where(near_l, right[y]-distance_l-1, tex_u[y])
            tex_u[y] = np.where(near_r, left[y]+distance_r+1, tex_u[y])
    repeated = sample(image, start+tex_t[..., None]*axis+tex_u[..., None]*perpendicular)
    cap = sample(image, start+t[..., None]*axis+(x/local_scale)[..., None]*perpendicular)
    # Match the last cap with a short crossfade, not a whole-shaft stretch.
    fade = np.clip((vb-w)/(16*scale), 0, 1)
    blend_rgb = repeated[..., :3]*fade[..., None]+cap[..., :3]*(1-fade[..., None])
    rgb = np.where(interior[..., None], blend_rgb, cap[..., :3])
    output = np.concatenate([rgb, silhouette[..., None]], axis=-1)
    output[output[..., 3] < .5] = 0
    output = np.clip(np.rint(output), 0, 255).astype(np.uint8)
    texture = 'res://Assets/2DResources/Spider/FrameFitted/'+r['file']
    destination = PROJECT / texture.removeprefix('res://')
    destination.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(output).save(destination)
    assert hashlib.sha256(source_path.read_bytes()).hexdigest() == source_hash
    # The uncompressed central 0.1-unit hole neighborhood uses only isotropic sampling.
    return dict(key=r['key'], category=r['category'], name=r['name'], source=r['source'],
        source_sha256=source_hash, texture=texture, texture_size=[width, height],
        pixels_per_unit=ppu, top_left_world=origin.tolist(), hole_diameter=.1,
        sampling=dict(origin_pixel=r['origin_pixel'],axis_pixel=r['axis_pixel'],across_pixel=r['across_pixel'],
            scales=r['scales'],source_span=r['source_span'],calibrated_span=r['calibrated_span']),
        original_scene=r['calibrated_scene'], original_mesh=r['calibrated_mesh'],
        mesh=r['calibrated_mesh'].replace('/Calibrated/', '/FrameFitted/'),
        scene=r['calibrated_scene'].replace('/Calibrated/', '/FrameFitted/'),
        glb='res://Assets/3DResources/Creatures/Spider/Models/FrameFitted/'+r['category']+'/'+r['name']+'.glb')


if __name__ == '__main__':
    data = json.loads((META/'generator_calibration.json').read_text(encoding='utf-8'))
    records = []
    for record in data['models']:
        fitted = build(record)
        records.append(fitted)
        print(fitted['key'], fitted['texture_size'], 'pixels/unit=', round(fitted['pixels_per_unit'], 2))
    assert len(records) == 16
    (META/'frame_fitted_manifest.json').write_text(json.dumps({'models': records}, indent=2)+'\n', encoding='utf-8')
    print('PASS: 16 separate frame-space PNGs; original PNG hashes unchanged.')
