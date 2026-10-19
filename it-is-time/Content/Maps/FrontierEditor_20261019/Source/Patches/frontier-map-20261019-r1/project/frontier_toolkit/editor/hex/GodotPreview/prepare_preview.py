from pathlib import Path
import base64,hashlib,io,json,math,shutil
import numpy as np
from PIL import Image,ImageDraw
from scipy.ndimage import distance_transform_edt
import sys
import shapely
from shapely.geometry import Polygon
from shapely.ops import triangulate

import argparse,os
parser=argparse.ArgumentParser(description='Read the saved editor map and original HD art into a native visual preview.')
parser.add_argument('--hex-root',type=Path,default=Path(__file__).resolve().parent.parent)
parser.add_argument('--output',type=Path,required=True)
parser.add_argument('--layout',type=Path)
parser.add_argument('--portable',action='store_true',help='Use paths relative to the output project; keep it beside Data and Tools when distributing.')
args=parser.parse_args()
HEX=args.hex_root.resolve();WEB=HEX/'Tools/hex-planner'
sys.dont_write_bytecode=True;sys.path.insert(0,str(HEX/'Tools'))
from mountain_outline import surface_rings
ROOT=Path(__file__).resolve().parent
PREVIEW=args.output.resolve()
if PREVIEW==ROOT:raise SystemExit('Use a separate output directory, not the formal source folder.')
PREVIEW.mkdir(parents=True,exist_ok=True)
layout_file=(args.layout or HEX/'Data/Maps/hex_layout.json').resolve()
raw=layout_file.read_bytes();doc=json.loads(raw);bg=doc['background'];spec=bg['source_tiles'];clips=json.loads((WEB/spec['clip_asset']).read_text('utf-8'))
tiles=[]
for tile in spec['tiles']:
 geom=None
 for ring in clips['tiles'][tile['id']]['clip']:
  p=Polygon(ring)
  if not p.is_valid:p=shapely.make_valid(p)
  geom=p if geom is None else geom.symmetric_difference(p)
 if hasattr(shapely,'constrained_delaunay_triangles'):
  triangles=shapely.constrained_delaunay_triangles(geom).geoms
 else:triangles=[t for t in triangulate(geom) if geom.covers(t)]
 points=[];area=0
 for tri in triangles:
  area+=tri.area
  for p in list(tri.exterior.coords)[:3]:points.extend([round(p[0],4),round(p[1],4)])
 assert abs(area-geom.area)<max(1,geom.area*1e-9),tile['id']
 tiles.append({**tile,'triangles':points,'clip_bounds':list(geom.bounds)})
assets={a['id']:a for a in doc['assets']};surfaces=[]

def rear_edge_mask(rings):
 # Signed distance to the sealed art silhouette, not the coarse hex/ray boundary.
 points=np.array([p for ring in rings for p in ring]);lo=points.min(axis=0)-96;hi=points.max(axis=0)+96
 unit=max(1.5,float(max(hi-lo))/1024)
 size=np.ceil((hi-lo)/unit).astype(int)
 mask=np.zeros((size[1],size[0]),dtype=bool)
 for ring in rings:
  layer=Image.new('1',tuple(size));ImageDraw.Draw(layer).polygon([tuple((np.array(p)-lo)/unit) for p in ring],fill=1)
  mask^=np.asarray(layer,dtype=bool)
 distance=(distance_transform_edt(mask)-distance_transform_edt(~mask))*unit
 encoded=np.clip(np.rint(127.5+distance*(127.5/64)),0,255).astype(np.uint8)
 buffer=io.BytesIO();Image.fromarray(encoded).save(buffer,format='PNG')
 return {'bounds':[float(lo[0]),float(lo[1]),float(size[0]*unit),float(size[1]*unit)],'distance_scale':64.0,'png':base64.b64encode(buffer.getvalue()).decode('ascii')}

for site in doc['sites']:
 if site.get('terrain',{}).get('kind')!='mountain':continue
 v=site.get('visual');a=assets.get(v.get('asset_id')) if v else None
 if not a:continue
 rings=surface_rings(site,a,WEB,assets)
 geometry=None
 for ring in rings:
  polygon=shapely.make_valid(Polygon(ring))
  geometry=polygon if geometry is None else geometry.symmetric_difference(polygon)
 seam_triangles=[]
 for triangle in shapely.constrained_delaunay_triangles(geometry).geoms:
  for x,y in list(triangle.exterior.coords)[:3]:seam_triangles.extend([round(x,4),round(y,4)])
 surfaces.append({'id':site['id'],'polygon':rings[0],'rings':rings,'rear_edge_mask':rear_edge_mask(rings),'seam_shadow':{'color':'#171b19','triangles':seam_triangles},'cells':site.get('terrain',{}).get('cells',[]),'asset_id':a['id'],'asset_sha256':hashlib.sha256((WEB/a['path']).read_bytes()).hexdigest()})
scene={'format':'current_hex_visual_scene','version':2,'layout_sha256':hashlib.sha256(raw).hexdigest(),'asset_root':Path(os.path.relpath(WEB,PREVIEW)).as_posix() if args.portable else WEB.as_posix(),'layout_path':Path(os.path.relpath(layout_file,PREVIEW)).as_posix() if args.portable else layout_file.as_posix(),'tiles':tiles,'mountain_surfaces':surfaces,'source_note':'Direct current canonical layout and original PNGs; no old Demo asset table, no re-encoding.'}
(PREVIEW/'scene.json').write_text(json.dumps(scene,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
for name in ['CurrentMapPreview.gd','MapSight.gd','MapPresentation.gd','HexMapData.gd','MonsterTaxonomy.gd','project.godot','Preview.tscn']:
 shutil.copy2(ROOT/name,PREVIEW/name)
if (ROOT/'tests').exists():shutil.copytree(ROOT/'tests',PREVIEW/'tests',dirs_exist_ok=True)
print('CURRENT',len(doc['sites']),'sites',len(doc['assets']),'assets',len(tiles),'original HD tiles',len(surfaces),'art-derived mountain surfaces',scene['layout_sha256'],flush=True)
