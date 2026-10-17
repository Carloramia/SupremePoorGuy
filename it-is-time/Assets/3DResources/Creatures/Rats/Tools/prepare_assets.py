"""Package Rats cutouts; original sheets and built-in AI edits remain untouched.
Only approved alpha/fringe cleanup, cropping and uniform resampling are applied.
Run from any working directory with the bundled Python runtime.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter
import hashlib, importlib.util, json, math, shutil, sys
import numpy as np

sys.dont_write_bytecode = True

P = next(p for p in Path(__file__).resolve().parents if (p / 'project.godot').is_file())
OUT = P / 'Assets/3DResources/Creatures/Rats'
SOURCE = P / 'Assets/2DResources/Rats'
spec = importlib.util.spec_from_file_location('human_asset_cleanup', P / 'Assets/3DResources/Creatures/Human/Tools/prepare_assets.py')
cleanup = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cleanup)


def save_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def largest_component(mask):
    parents=[]; areas=[]; runs=[]; previous=[]
    def root(i):
        while parents[i]!=i:
            parents[i]=parents[parents[i]]; i=parents[i]
        return i
    for y,row in enumerate(mask):
        change=np.diff(np.pad(row.astype(np.int8),(1,1)))
        starts=np.flatnonzero(change==1); ends=np.flatnonzero(change==-1)
        current=[]; cursor=0
        for a,b in zip(starts,ends):
            index=len(parents); parents.append(index); areas.append(int(b-a))
            while cursor<len(previous) and previous[cursor][1]<a: cursor+=1
            q=cursor
            while q<len(previous) and previous[q][0]<=b:
                p=root(previous[q][2]); r=root(index)
                if p!=r: parents[p]=r; areas[r]+=areas[p]
                q+=1
            current.append((a,b,index)); runs.append((y,a,b,index))
        previous=current
    best=max(range(len(parents)),key=lambda i:areas[root(i)])
    best=root(best); result=np.zeros_like(mask)
    for y,a,b,index in runs:
        if root(index)==best: result[y,a:b]=True
    return result


def package(image, path):
    data = np.array(image.convert('RGBA'))
    rgb = data[:, :, :3].astype(np.int16)
    matte = (rgb[:, :, 0] > 235) & (rgb[:, :, 2] < 55) & ((rgb[:, :, 1] < 65) | (rgb[:, :, 1] > 205))
    # Edge contamination only: muted pink paws and cream teeth are retained.
    inner = np.array(Image.fromarray((data[:, :, 3] >= 128).astype(np.uint8) * 255).filter(ImageFilter.MinFilter(5))) > 0
    data[matte & ~inner, 3] = 0
    data[data[:, :, 3] < 128, 3] = 0
    keep = largest_component(data[:, :, 3] >= 128)
    data[~keep, 3] = 0
    image = Image.fromarray(data)
    box = image.getchannel('A').getbbox()
    assert box, path
    image = image.crop(box)
    canvas = Image.new('RGBA', (image.width + 24, image.height + 24))
    canvas.alpha_composite(image, (12, 12))
    path.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(path)
    return canvas, box


def isolate(sheet, box, polygon=None, pink=False):
    image = sheet.crop(box)
    if polygon:
        mask = Image.new('L', image.size)
        ImageDraw.Draw(mask).polygon([(x-box[0], y-box[1]) for x, y in polygon], fill=255)
        a = np.array(image)
        a[:, :, 3] = np.minimum(a[:, :, 3], np.array(mask))
        image = Image.fromarray(a)
    if pink:
        a = np.array(image)
        c = a[:, :, :3].astype(float)
        keep = (c[:, :, 0] > c[:, :, 1]*1.15) & (c[:, :, 0] > c[:, :, 2]*1.22)
        a[~keep, 3] = 0
        image = Image.fromarray(a)
    return image


def hole_centers(image):
    # The exterior transparent area is flood-filled away; holes remain zero.
    mask = image.getchannel('A').point(lambda a: 255 if a >= 128 else 0)
    ImageDraw.floodfill(mask, (0, 0), 127)
    pixels = np.array(mask)
    centers = []
    from collections import deque
    for y, x in zip(*np.where(pixels == 0)):
        if pixels[y, x] != 0:
            continue
        queue = deque([(int(x), int(y))]); pixels[y, x] = 126
        points = []
        while queue:
            px, py = queue.popleft(); points.append((px, py))
            for nx, ny in [(px-1, py), (px+1, py), (px, py-1), (px, py+1)]:
                if 0 <= nx < image.width and 0 <= ny < image.height and pixels[ny, nx] == 0:
                    pixels[ny, nx] = 126; queue.append((nx, ny))
        if len(points) >= 30:
            arr = np.array(points)
            centers.append((len(points), arr.mean(axis=0).tolist()))
    return [p for _, p in sorted(centers, reverse=True)[:2]]


def main():
    records = []
    # Pixel regions are source-sheet coordinates, not world dimensions.
    regions = {
        1: [
            ('Torso/TorsoMain', (440, 300, 1007, 722), None, [0.5,0.5], [0.92,0.45], [0]),
            ('Head/HeadMain', (1020, 210, 1445, 470), None, [0.10,0.53], [0.52,0.87], [3]),
            ('Head/LowerJaw', (1173, 440, 1385, 602), None, [0.20,0.25], [0.85,0.78], []),
            ('Head/EarFront', (968, 31, 1205, 227), None, [0.47,0.82], [0.47,0.2], []),
            ('Head/EarBack', (1227, 31, 1334, 218), None, [0.5,0.86], [0.5,0.2], []),
            ('Feet/ForeFoot1', (1213, 609, 1374, 749), None, [0.2,0.16], [0.8,0.84], [4]),
            ('Feet/ForeFoot2', (318, 704, 451, 849), None, [0.20,0.15], [0.8,0.85], [4]),
            ('Feet/HindFoot1', (1125, 886, 1404, 978), None, [0.17,0.49], [0.86,0.55], [1]),
            ('Feet/HindFoot2', (556, 910, 791, 991), None, [0.12,0.45], [0.85,0.55], [1]),
            ('Decorations/NeckPlate1', (20, 57, 357, 437), None, [0.5,0.5], [0.5,0.5], []),
            ('Decorations/NeckPlate2', (294, 36, 640, 397), None, [0.5,0.5], [0.5,0.5], []),
            ('Decorations/NeckPlate3', (528, 29, 799, 269), None, [0.5,0.5], [0.5,0.5], []),
            ('Decorations/NeckPlate4', (714, 48, 1008, 334), None, [0.5,0.5], [0.5,0.5], []),
            ('Decorations/Tooth1', (1318, 398, 1380, 497), None, [0.5,0.15], [0.5,0.85], []),
            ('Decorations/Tooth2', (1363, 397, 1432, 497), None, [0.5,0.15], [0.5,0.85], []),
            ('Decorations/Tongue', (1307, 508, 1422, 590), None, [0.13,0.5], [0.9,0.5], []),
            ('Decorations/Rivet', (321, 997, 377, 1055), None, [0.5,0.5], [0.5,0.5], [0,6]),
        ],
        2: [
            ('Torso/TorsoMain', (207, 15, 964, 580), None, [0.5,0.5], [0.91,0.5], [0]),
            ('Head/HeadMain', (966, 169, 1446, 405), None, [0.09,0.56], [0.54,0.86], [3]),
            ('Head/LowerJaw', (1029, 402, 1299, 536), None, [0.15,0.3], [0.88,0.8], []),
            ('Head/EarFront', (891, 31, 1119, 218), None, [0.70,0.82], [0.5,0.2], []),
            ('Head/EarBack', (1188, 14, 1309, 164), None, [0.67,0.88], [0.5,0.2], []),
            ('Feet/ForeFoot1', (1110, 727, 1215, 931), None, [0.24,0.22], [0.76,0.85], [4]),
            ('Feet/ForeFoot2', (1300, 757, 1443, 958), None, [0.16,0.14], [0.82,0.82], [4]),
            ('Feet/HindFoot1', (233, 853, 421, 995), None, [0.2,0.4], [0.85,0.6], [1]),
            ('Feet/HindFoot2', (600, 875, 859, 982), None, [0.14,0.42], [0.87,0.6], [1]),
            ('Decorations/Tooth1', (1286, 485, 1359, 571), None, [0.5,0.15], [0.5,0.85], []),
            ('Decorations/Tooth2', (1343, 484, 1408, 566), None, [0.5,0.15], [0.5,0.85], []),
            ('Decorations/Nose', (1355, 420, 1444, 478), None, [0.5,0.5], [0.5,0.5], []),
            ('Decorations/Rivet', (271, 999, 338, 1064), None, [0.5,0.5], [0.5,0.5], [0,6]),
        ],
    }
    tails = {
        1: [(33,461,134,594),(32,591,120,696),(43,683,138,776),(81,755,190,850),(133,816,239,910),(198,872,306,944),(280,910,395,960),(365,934,527,980)],
        2: [(76,73,205,193),(33,176,139,321),(33,315,150,457),(79,445,193,562),(126,549,197,663),(121,655,194,761),(16,749,161,914)],
    }
    for variant in [1,2]:
        folder = f'Rat_{variant}'
        original = P / f'Assets/2DResources/AIGenerated/Unprocessed/Rats/{folder}.png'
        dest = SOURCE / 'Originals' / original.name
        dest.parent.mkdir(parents=True, exist_ok=True)
        if not dest.exists(): shutil.copyfile(original, dest)
        assert hashlib.sha256(original.read_bytes()).digest() == hashlib.sha256(dest.read_bytes()).digest()
        sheet = Image.open(original).convert('RGBA')
        entries = list(regions[variant])
        for i, box in enumerate(tails[variant]):
            entries.append((f'Tail/Tail{i+1:02d}', box, None, [0.5,0.12], [0.5,0.88], [10]))
        for category, box, polygon, inlet, outlet, tags in entries:
            image, _ = package(isolate(sheet, box, polygon, pink=category.startswith('Feet/')), SOURCE / 'Separated' / folder / f'{category}.png')
            if category.startswith('Tail/'):
                ys,xs=np.where(np.array(image.getchannel('A'))>=128)
                points=np.column_stack((xs,ys)); center=points.mean(axis=0)
                _,vectors=np.linalg.eigh(np.cov(points.T)); axis=vectors[:,-1]
                if axis[1]<0: axis=-axis
                along=(points-center)@axis
                ends=[center+axis*np.quantile(along,q) for q in [.08,.92]]
                inlet,outlet=[[(point[0]-12)/(image.width-24),(point[1]-12)/(image.height-24)] for point in ends]
            records.append(dict(key=f'{folder}/{category}', file=f'{folder}/{category}.png', category=f'{folder}/{category.rsplit("/",1)[0]}', name=category.rsplit('/',1)[1],
                                joint_in=inlet, joint_out=outlet, tags=tags, units_per_pixel=0.01, origin='original_crop', source_box=list(box)))
        # Four completed templates per preset; both sides retain separate native paws.
        for kind, span in [('fore_upper',165),('fore_lower',125),('hind_upper',180),('hind_lower',205)]:
            raw = SOURCE / 'RawEdits' / folder / f'rat{variant}_{kind}.png'
            image = Image.open(raw).convert('RGBA')
            a = np.array(image)
            a[a[:,:,3]<235,3]=0  # Remove generated exterior glow, retain paper interior.
            temp = OUT / 'Metadata' / f'{folder}_{kind}_cleaning.png'
            temp.parent.mkdir(parents=True, exist_ok=True)
            Image.fromarray(a).save(temp)
            image, _ = cleanup.clean(temp)
            temp.unlink()
            holes = hole_centers(image)
            assert len(holes)==2, (raw,holes)
            holes.sort(key=lambda p: p[1])
            category = 'Legs/' + ''.join(w.title() for w in kind.split('_'))
            final = SOURCE / 'Separated' / folder / f'{category}.png'
            image, crop = package(image, final)
            holes = [[p[0]-crop[0]+12,p[1]-crop[1]+12] for p in holes]
            distance = math.dist(*holes)
            normalized = [[(x-12)/(image.width-24),(y-12)/(image.height-24)] for x,y in holes]
            records.append(dict(key=f'{folder}/{category}',file=f'{folder}/{category}.png',category=f'{folder}/Legs',name=category.split('/')[1],
                                joint_in=normalized[0],joint_out=normalized[1],tags=[5],units_per_pixel=span*.01/distance,
                                origin='AI_occlusion_completion',native_joint_span_pixels=span))
        extra = [('fore_paw','Feet/ForePawCompleted',160,[4])] if variant==1 else [('head','Head/HeadMain',480,[3]),('hind_paw','Feet/HindPawCompleted',220,[1])]
        for kind,category,width,tags in extra:
            raw=SOURCE/'RawEdits'/folder/f'rat{variant}_{kind}.png'
            a=np.array(Image.open(raw).convert('RGBA')); a[a[:,:,3]<235,3]=0
            image,crop=package(Image.fromarray(a),SOURCE/'Separated'/folder/f'{category}.png')
            if kind=='head':
                inlet,outlet=[.1,.57],[.52,.84]
            else:
                holes=hole_centers(image); assert holes,(raw,holes)
                point=holes[0]
                inlet=[(point[0]-12)/(image.width-24),(point[1]-12)/(image.height-24)]
                outlet=[.85,.8]
            records=[r for r in records if r['key']!=f'{folder}/{category}']
            records.append(dict(key=f'{folder}/{category}',file=f'{folder}/{category}.png',category=f'{folder}/{category.rsplit("/",1)[0]}',name=category.rsplit('/',1)[1],
                                joint_in=inlet,joint_out=outlet,tags=tags,units_per_pixel=width*.01/(image.width-24),origin='AI_occlusion_completion'))
    save_json(OUT/'Metadata/build_settings.json',dict(parts=records, thickness=.08))
    save_json(SOURCE/'Separated/asset_manifest.json',dict(count=len(records),parts=records,source_sheets_untouched=True))
    contact = [(r['name'], SOURCE/'Separated'/r['file']) for r in records]
    # A compact overview doubles as a visual QA target.
    cols=7; cw,ch=210,180
    canvas=Image.new('RGB',(cols*cw,math.ceil(len(contact)/cols)*ch),(225,225,225)); draw=ImageDraw.Draw(canvas)
    for i,(name,path) in enumerate(contact):
        im=Image.open(path); im.thumbnail((cw-20,ch-35),Image.Resampling.LANCZOS)
        x=(i%cols)*cw; y=(i//cols)*ch
        canvas.paste(im,(x+(cw-im.width)//2,y+(ch-30-im.height)//2),im)
        draw.text((x+8,y+ch-25),f'{records[i]["file"].split("/")[0]} {name}',fill=(20,20,20))
    canvas.save(SOURCE/'Separated/PartsOverview.png')
    print('PASS: packaged',len(records),'Rats cutouts; originals preserved.')


if __name__ == '__main__': main()
