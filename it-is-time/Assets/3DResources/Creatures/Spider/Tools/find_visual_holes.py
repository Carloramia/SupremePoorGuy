import json
from pathlib import Path
import numpy as np
from PIL import Image
root=next(p for p in Path(__file__).resolve().parents if (p/'project.godot').exists())
manifest=json.loads((root/'Assets/3DResources/Creatures/Spider/Metadata/model_manifest.json').read_text(encoding='utf-8'))
result={}
for r in manifest['models']:
    p=root/r['source'].removeprefix('res://')
    im=np.array(Image.open(p).convert('RGBA'))

    mask=im[:,:,3]<128
    parents=[]; runs=[]; previous=[]
    def find(i):
        while parents[i]!=i:
            parents[i]=parents[parents[i]]; i=parents[i]
        return i
    for y,row in enumerate(mask):
        changes=np.diff(np.pad(row.astype(np.int8),(1,1)))
        starts=np.flatnonzero(changes==1); ends=np.flatnonzero(changes==-1)-1
        current=[]; cursor=0
        for x0,x1 in zip(starts,ends):
            idx=len(parents); parents.append(idx); runs.append((y,int(x0),int(x1))); current.append((int(x0),int(x1),idx))
            while cursor<len(previous) and previous[cursor][1]<x0: cursor+=1
            k=cursor
            while k<len(previous) and previous[k][0]<=x1:
                a,b=find(idx),find(previous[k][2]); parents[a]=b; k+=1
        previous=current
    groups={}
    for i,(y,x0,x1) in enumerate(runs):
        g=groups.setdefault(find(i),[0,0.,0.,10**9,10**9,0,0,False]); n=x1-x0+1
        g[0]+=n; g[1]+=(x0+x1)*n*.5; g[2]+=y*n
        g[3]=min(g[3],x0); g[4]=min(g[4],y); g[5]=max(g[5],x1); g[6]=max(g[6],y)
        g[7]|=x0==0 or x1==mask.shape[1]-1 or y==0 or y==mask.shape[0]-1
    holes=[]
    for area,sx,sy,x0,y0,x1,y1,border in groups.values():
        w,h=x1-x0+1,y1-y0+1
        if border or area<100 or min(w,h)/max(w,h)<.5: continue
        holes.append({'pixel':[sx/area,sy/area],'area':area,'size':[w,h]})
    result[r['volume_mesh']]={'image':r['source'],'dimensions':[im.shape[1],im.shape[0]],'holes':holes}
(root/'Assets/3DResources/Creatures/Spider/Metadata/generator_source_holes.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
for k,v in result.items():
    if '/Legs/' in k: print(k,v['holes'])

