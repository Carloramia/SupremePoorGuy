"""Prepare connector calibration data without resampling or overwriting source PNGs.

Run the bundled Python, then Tools/BuildSpiderCalibratedParts.gd in Godot.
The mesh UVs retain the original art; only the shaft between the end rings stretches.
"""
from pathlib import Path
import json, math
import numpy as np
from PIL import Image
import find_visual_holes

PROJECT = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').exists())
ART = PROJECT / 'Assets/3DResources/Creatures/Spider'
manifest = json.loads((ART / 'Metadata/model_manifest.json').read_text(encoding='utf-8'))
holes = json.loads((ART/'Metadata/generator_source_holes.json').read_text())
records = []
for record in manifest['models']:
    if not record['category'].startswith('Legs/'):
        continue
    found = holes[record['volume_mesh']]['holes']
    assert found, record['key']
    image = Image.open(PROJECT / record['source'].removeprefix('res://')).convert('RGBA')
    alpha = np.asarray(image)[:, :, 3] >= 128
    yy, xx = np.nonzero(alpha)
    pixels = np.stack([xx + .5, yy + .5], axis=1)
    upper = record['name'] == 'UpperLeg'
    if upper:
        a, b = max(((a,b) for a in found for b in found), key=lambda pair: math.dist(pair[0]['pixel'],pair[1]['pixel']))
        if a['pixel'][1] > b['pixel'][1]: a,b = b,a
        start, end = np.array(a['pixel']), np.array(b['pixel'])
        diameters = [sum(h['size']) / 2 for h in [a,b]]
    else:
        a = max(found, key=lambda h: h['area'])
        start = np.array(a['pixel'])
        end = pixels[np.argmax(np.sum((pixels-start)**2,axis=1))]
        diameters = [sum(a['size']) / 2] * 2
    axis = (end-start) / np.linalg.norm(end-start)
    across = np.array([axis[1],-axis[0]])
    length = float(np.linalg.norm(end-start))
    # Half a ring's surrounding paper also retains the local isotropic scale.
    buffers = [min(d * 1.4, length * .23) for d in diameters]
    span, width = (2.0,.25) if upper else (2.8,.3)
    scales = [.1 / d for d in diameters]
    breakpoints = [0,buffers[0],length-buffers[1],length]
    values = [0,buffers[0]*scales[0],span-buffers[1]*scales[1],span]
    assert values[2] > values[1]
    def warp(points):
        delta = points-start
        t = delta@axis
        x = delta@across
        s = np.interp(t,breakpoints,[scales[0],scales[0],scales[1],scales[1]])
        y = np.interp(t,breakpoints,values)
        y = np.where(t<0,t*scales[0],np.where(t>length,span+(t-length)*scales[1],y))
        return np.stack([x*s,y-span/2],axis=1)
    # Bound the shaft width but leave the ring neighborhoods isotropic.
    mapped = warp(pixels)
    shaft = (pixels-start)@axis
    interior = (shaft>buffers[0]) & (shaft<length-buffers[1])
    max_width = float(np.max(np.abs(mapped[interior,0]))) if np.any(interior) else width/2
    compression = min(1.0, width / (2*max_width))
    # Sample the silhouette densely for a new convex hull after deformation.
    outline=[]
    for y in range(alpha.shape[0]):
        xs=np.flatnonzero(alpha[y])
        if len(xs): outline.extend([[float(xs[0]),float(y)],[float(xs[-1]+1),float(y+1)]])
    records.append(dict(record, calibrated_span=span, calibrated_width=width, calibrated_hole_diameter=.1,
        origin_pixel=start.tolist(), axis_pixel=axis.tolist(), across_pixel=across.tolist(),
        source_span=length, breakpoints=breakpoints, values=values, scales=scales,
        shaft_compression=compression, silhouette=outline,
        calibrated_mesh='res://Resources/Meshes/Spider/Calibrated/'+record['category']+'/'+record['name']+'.res',
        calibrated_scene='res://Scenes/Creatures/Bodyparts/Spider/Calibrated/'+record['category']+'/'+record['name']+'.tscn'))
out=ART/'Metadata/generator_calibration.json'
out.write_text(json.dumps({'hole_diameter':.1,'models':records},indent=2)+'\n',encoding='utf-8')
assert len(records)==16
print('PASS: 16 connector-calibrated mesh specifications; all source PNGs unchanged.')
