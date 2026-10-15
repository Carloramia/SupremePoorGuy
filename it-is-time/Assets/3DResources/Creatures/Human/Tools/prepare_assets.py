"""Clean approved alpha/fringe artifacts and package the Human cutouts.
Preserves originals and RawEdits; only the final Separated outputs are rewritten.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import numpy as np
import hashlib, html, json, shutil, sys
P=next(p for p in Path(__file__).resolve().parents if (p/'project.godot').is_file())
OUT=P/'Assets/3DResources/Creatures/Human'
S=P/'Assets/2DResources/Human/Separated'

def digest(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def read_json(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def write_json(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def large_components(mask):
    # Row runs avoid a per-pixel Python flood fill on the high-resolution edits.
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
            n=len(parents); parents.append(n); areas.append(int(b-a))
            while cursor<len(previous) and previous[cursor][1]<a: cursor+=1
            q=cursor
            while q<len(previous) and previous[q][0]<=b:
                p=root(previous[q][2]); r=root(n)
                if p!=r: parents[p]=r; areas[r]+=areas[p]
                q+=1
            current.append((a,b,n)); runs.append((y,a,b,n))
        previous=current
    minimum=max(80,int(max(areas)*.003))
    result=np.zeros_like(mask)
    for y,a,b,n in runs:
        if areas[root(n)]>=minimum: result[y,a:b]=True
    return result

def clean(raw):
    pixels=np.array(Image.open(raw).convert('RGBA'))
    alpha=pixels[:,:,3].copy()
    rgb=pixels[:,:,:3].astype(np.int16)
    # Source matte contamination is saturated red/yellow, unlike the muted motifs.
    vivid=(rgb[:,:,0]>240)&(rgb[:,:,2]<35)&((rgb[:,:,1]<38)|(rgb[:,:,1]>225))
    eroded=Image.fromarray((alpha>=128).astype(np.uint8)*255)
    for _ in range(5): eroded=eroded.filter(ImageFilter.MinFilter(3))
    border=np.array(eroded)==0
    artifact=vivid&border
    alpha[artifact]=0
    mask=large_components(alpha>=128)
    allowed=np.array(Image.fromarray(mask.astype(np.uint8)*255).filter(ImageFilter.MaxFilter(3)))>0
    alpha[~allowed]=0
    alpha[alpha<64]=0
    pixels[:,:,3]=alpha
    pixels[alpha==0,:3]=0
    image=Image.fromarray(pixels)
    bounds=image.getchannel('A').point(lambda v:255 if v>=128 else 0).getbbox()
    assert bounds and mask.sum()>100
    image=image.crop(bounds)
    # Retain aspect ratio; runtime textures need no oversized transparent canvas.
    image.thumbnail((1024,1024),Image.Resampling.LANCZOS)
    canvas=Image.new('RGBA',(image.width+32,image.height+32))
    canvas.alpha_composite(image,(16,16))
    return canvas,dict(raw_size=list(pixels.shape[1::-1]),raw_crop=list(bounds),
                       removed_fringe_pixels=int(artifact.sum()),opaque_pixels=int(mask.sum()),
                       max_content_side=1024,padding=16)

def contact_sheet(parts,filename,cols=5):
    cell_w,cell_h=320,278
    rows=(len(parts)+cols-1)//cols
    canvas=Image.new('RGB',(cols*cell_w,rows*cell_h),(43,48,56))
    d=ImageDraw.Draw(canvas)
    try: font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',15)
    except OSError: font=ImageFont.load_default()
    for i,s in enumerate(parts):
        x=(i%cols)*cell_w;y=(i//cols)*cell_h
        for cy in range(y,y+236,16):
            for cx in range(x,x+cell_w,16):
                shade=210 if ((cx-x)//16+(cy-y)//16)%2==0 else 230
                d.rectangle((cx,cy,cx+15,cy+15),fill=(shade,shade,shade))
        im=Image.open(S/s['file']).convert('RGBA'); im.thumbnail((cell_w-20,226))
        canvas.paste(im,(x+(cell_w-im.width)//2,y+(236-im.height)//2),im)
        d.text((x+8,y+244),s['name'],font=font,fill='white')
        d.text((x+8,y+263),s['file'].split('/')[0]+' / '+s['role'],fill=(185,194,208))
    canvas.save(S/filename,quality=92)

def main():
    jobs=read_json(S/'generation_jobs.json')['specs']+read_json(S/'extra_specs.json')
    additions=S/'generation_jobs_4_5.json'
    if additions.exists(): jobs+=read_json(additions)['specs']
    outputs={r['key']:r for r in read_json(S/'imagegen_final_paths.json')}
    extra_outputs=S/'imagegen_paths_4_5.json'
    if extra_outputs.exists(): outputs.update({r['key']:r for r in read_json(extra_outputs)})
    selected=next((set(map(int,arg.partition('=')[2].split(','))) for arg in sys.argv if arg.startswith('--sets=')),None)
    previous_assets=read_json(S/'asset_manifest.json') if (S/'asset_manifest.json').exists() else {'parts':[]}
    previous_settings=read_json(OUT/'Metadata/build_settings.json') if (OUT/'Metadata/build_settings.json').exists() else {'parts':[]}
    old_assets={r['key']:r for r in previous_assets['parts']}
    old_settings={r['key']:r for r in previous_settings['parts']}
    assert len({s['key'] for s in jobs})==len(jobs)
    (S/'RawEdits/.gdignore').write_text('',encoding='utf-8')
    (S/'SourceCrops/.gdignore').write_text('',encoding='utf-8')
    sets=sorted({s['set'] for s in jobs})
    for i in sets:
        src=P/f'Assets/2DResources/AIGenerated/Unprocessed/Human/Humanoid_{i}.png'
        dest=S.parent/src.name
        if not dest.exists(): shutil.copyfile(src,dest)
        assert digest(src)==digest(dest)
    # Coordinates refer to visible alpha bounds, not transparent padding.
    anchors={
        'human1_forearm_left':([.60,.25],[.63,.72]),
        'human1_forearm_right':([.24,.30],[.74,.73]),
        'human1_hand_right':([.14,.54],[.78,.57]),
        'human2_hand_left':([.43,.04],[.52,.83]),
        'human2_hand_right':([.19,.08],[.68,.79]),
        'human2_upper_leg_right':([.80,.24],[.10,.83]),
        'human3_forearm_left':([.68,.09],[.44,.91]),
        'human3_forearm_right':([.20,.14],[.84,.87]),
        'human3_lower_leg_left':([.23,.09],[.46,.93]),
        'human3_curved_sword':([.21,.04],[.20,.97]),
        'human2_leaf_branch_left':([.43,.97],[.63,.06]),
        'human2_leaf_branch_right':([.76,.96],[.49,.08]),
    }
    records=[]; settings=[]
    for spec in jobs:
        dest=S/spec['file']
        if (selected is not None and spec['set'] not in selected) or (dest.exists() and '--reclean' not in sys.argv):
            assert spec['key'] in old_assets and spec['key'] in old_settings, 'Existing outputs require matching metadata'
            records.append(old_assets[spec['key']]); settings.append(old_settings[spec['key']])
            continue
        assert spec['key'] in outputs, 'Missing image generation output: '+spec['key']
        raw=S/'RawEdits'/f"{spec['key']}.png"
        im,cleanup=clean(raw)
        dest=S/spec['file']; dest.parent.mkdir(parents=True,exist_ok=True); im.save(dest)
        assert im.getpixel((0,0))[3]==0
        spec=dict(spec)
        if spec['key'] in anchors: spec['joint_in'],spec['joint_out']=anchors[spec['key']]
        spec['original_image']=f"Assets/2DResources/Human/{spec['source']}"
        settings.append({k:v for k,v in spec.items() if k not in ('prompt','source')})
        records.append(dict(key=spec['key'],name=spec['name'],role=spec['role'],set=spec['set'],
                            file=spec['file'],original_image=spec['original_image'],source_sha256=digest(P/spec['original_image']),
                            raw_edit=f"RawEdits/{spec['key']}.png",raw_sha256=digest(raw),sha256=digest(dest),
                            image_size=list(im.size),cleanup=cleanup))
    write_json(OUT/'Metadata/build_settings.json',dict(parts=settings,source_pixel_to_world_reference=.01,
         size_note='Visible height calibrated to the corresponding source-sheet part; AI completion may slightly change the contour.',
         joint_note='Initial mounting marker estimates; confirm exact holes when assembling a character.'))
    write_json(S/'asset_manifest.json',dict(part_count=len(records),source_count=len(sets),parts=records,
          method='AI isolated cutouts and occlusion completion, followed by approved pixel alpha/fringe cleanup',
          naming='Left/Right mean source image left/right, not anatomical left/right',
          reference_pixel_unit=.01))
    contact_sheet(jobs,'ContactSheet.jpg',6)
    for i in sets:
        if selected is None or i in selected: contact_sheet([s for s in jobs if s['set']==i],f'Human{i}ContactSheet.jpg')
    cards=''.join(f'<figure><img loading="lazy" src="{html.escape(s["file"])}"><figcaption>{html.escape(s["name"])}</figcaption></figure>' for s in jobs)
    page='<!doctype html><html lang="zh"><meta charset="utf-8"><title>Human parts</title><style>body{background:#252a32;color:#edf1f6;font:16px sans-serif;margin:24px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(220px,1fr));gap:16px}figure{margin:0;background:#373e49;border-radius:8px;padding:12px}img{width:100%;height:230px;object-fit:contain;background:repeating-conic-gradient(#ddd 0% 25%,#eee 0% 50%) 0/24px 24px}figcaption{margin-top:8px}</style><h1>Human — '+str(len(jobs))+' parts</h1><p>Left/Right 按原图画面左右命名；所有原图均保留。透明 PNG、双面薄片模型和物理部件一一对应。</p><div class="grid">'+cards+'</div></html>'
    (S/'Preview.html').write_text(page,encoding='utf-8')
    print('PASS:',len(records),'transparent Human parts, source copies, manifests and contact sheets')
if __name__=='__main__': main()

