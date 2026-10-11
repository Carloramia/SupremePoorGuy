"""Keep connector pixels unchanged; extend only the shaft along its joint axis."""
from pathlib import Path
import hashlib
import json
import numpy as np
from PIL import Image

PROJECT = Path(__file__).resolve().parents[5]
BASE = PROJECT / 'Assets/3DResources/Creatures/Wolf'
BACKUP = PROJECT / 'Assets/2DResources/Wolf/Backups/ForelimbsBeforeElongation_20261009'

def main():
    old = json.loads((BACKUP/'model_manifest.json').read_text(encoding='utf-8'))
    settings_path = BASE/'Metadata/build_settings.json'
    settings = json.loads(settings_path.read_text(encoding='utf-8'))
    originals = {r['key']: r for r in old['models']}
    results = []
    for pair, desired in [(1,3.52097964286804),(2,4.05663919448853)]:
        keys = [f'leg{pair}_upper',f'leg{pair}_lower']
        native = sum(np.linalg.norm(originals[k]['joint_out_local']) for k in keys)
        factor = desired/native
        for key in keys:
            record = originals[key]
            source = BACKUP/Path(record['file']).name
            image = Image.open(source).convert('RGBA')
            pixels = np.asarray(image)
            inlet = np.array(record['pivot_pixel'])
            # Stored GLB marker uses image +Y flipped.
            unit = record['units_per_texture_pixel']
            outlet = inlet+np.array(record['joint_out_local'][:2])*[1,-1]/unit
            span = outlet-inlet
            length = np.linalg.norm(span)
            axis = span/length
            delta = np.rint(span*(factor-1)).astype(int)
            extension = delta@axis
            cut_a,cut_b = ((.50,.87) if key.endswith('upper') else (.18,.82))
            cut_a *= length
            cut_b *= length
            offset = np.maximum(-delta,0)+2
            w,h = image.size
            ow,oh = np.array([w,h])+np.abs(delta)+4
            yy,xx = np.mgrid[:oh,:ow]
            px,py = xx-offset[0],yy-offset[1]
            t = (px-inlet[0])*axis[0]+(py-inlet[1])*axis[1]
            denominator = cut_b+extension-cut_a
            constant = axis@(offset+inlet)+cut_a
            affine = (1-delta[0]*axis[0]/denominator,-delta[0]*axis[1]/denominator,
                -offset[0]+delta[0]*constant/denominator,
                -delta[1]*axis[0]/denominator,1-delta[1]*axis[1]/denominator,
                -offset[1]+delta[1]*constant/denominator)
            warped = image.convert('RGBa').transform((int(ow),int(oh)),Image.Transform.AFFINE,affine,Image.Resampling.BICUBIC).convert('RGBA')
            output = np.array(warped)
            output[(t<=cut_a)|(t>=cut_b+extension)] = 0
            # Copy protected pixels directly; they never pass through interpolation.
            iy,ix = np.mgrid[:h,:w]
            old_t = (ix-inlet[0])*axis[0]+(iy-inlet[1])*axis[1]
            for mask,shift in [(old_t<=cut_a,offset),(old_t>=cut_b,offset+delta)]:
                output[(iy+shift[1])[mask],(ix+shift[0])[mask]] = pixels[mask]
                assert np.array_equal(output[(iy+shift[1])[mask],(ix+shift[0])[mask]],pixels[mask])
            target = PROJECT/record['source'].removeprefix('res://')
            Image.fromarray(output).save(target)
            alpha = output[:,:,3]
            by,bx = np.where(alpha>=128)
            low = np.array([bx.min(),by.min()])
            extent = np.array([bx.max()+1,by.max()+1])-low
            new_in = inlet+offset
            new_out = outlet+offset+delta
            spec = next(r for r in settings['parts'] if r['key']==key)
            spec['visible_size'] = float(extent[1]*unit)
            spec['joint_in'] = ((new_in-low)/extent).tolist()
            spec['joint_out'] = ((new_out-low)/extent).tolist()
            results.append(dict(key=key,source=str(source),output=str(target),factor=factor,
                protected_axis_range=[float(cut_a),float(cut_b)],pixel_translation=delta.tolist(),
                original_units_per_pixel=unit,original_connector_span=float(length*unit),
                new_connector_span=float(np.linalg.norm(span+delta)*unit),
                original_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                output_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                protected_pixels_exact=True))
    settings_path.write_text(json.dumps(settings,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (BASE/'Metadata/forelimb_elongation.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print('PASS: 4 shafts extended; protected end pixels identical; original world pixel scale retained.')
    for r in results: print(r['key'],r['original_connector_span'],'->',r['new_connector_span'])

if __name__=='__main__': main()
