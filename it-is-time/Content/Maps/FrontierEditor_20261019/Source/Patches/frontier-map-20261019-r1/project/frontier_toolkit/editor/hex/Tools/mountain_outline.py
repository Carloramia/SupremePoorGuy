"""Alpha contours for native previews; saved editor rings take precedence."""
from pathlib import Path
import math
import numpy as np
from PIL import Image
import shapely
from shapely.geometry import box
from scipy.ndimage import maximum_filter,minimum_filter

SEAM_WIDTH_WORLD=36.0

def close_seam_mask(mask,rx,ry):
    """Close only narrow alpha seams. Padding preserves opaque pixels at image borders."""
    if rx<=0 or ry<=0:return mask.copy()
    padded=np.pad(mask,((ry*2,ry*2),(rx*2,rx*2)),constant_values=False)
    size=(ry*2+1,rx*2+1)
    expanded=maximum_filter(padded,size=size,mode='constant',cval=0)
    closed=minimum_filter(expanded,size=size,mode='constant',cval=0)
    return closed[ry*2:ry*2+mask.shape[0],rx*2:rx*2+mask.shape[1]]|mask

def alpha_rings(path,threshold=96,max_side=1024,atlas=None,world_size=None):
    with Image.open(path) as source:
        image=source.convert('RGBA')
        if atlas:
            x,y,w,h=atlas;image=image.crop((x,y,x+w,y+h))
        ratio=min(1,max_side/max(image.size))
        image=image.resize(tuple(max(1,round(v*ratio)) for v in image.size),Image.Resampling.LANCZOS)
        mask=np.asarray(image.getchannel('A'))>=threshold
    h,w=mask.shape
    if world_size:
        rx=max(1,round(SEAM_WIDTH_WORLD*.5*w/world_size[0]))
        ry=max(1,round(SEAM_WIDTH_WORLD*.5*h/world_size[1]))
        mask=close_seam_mask(mask,rx,ry)
    runs=[]
    for y,row in enumerate(mask):
        edges=np.diff(np.pad(row.astype(np.int8),(1,1)))
        for start,end in zip(np.flatnonzero(edges==1),np.flatnonzero(edges==-1)):
            runs.append(box(int(start),y,int(end),y+1))
    if not runs:raise ValueError('Mountain image has no opaque pixels: '+str(path))
    geometry=shapely.union_all(runs).simplify(1.25,preserve_topology=True)
    polygons=[geometry] if geometry.geom_type=='Polygon' else list(geometry.geoms)
    rings=[]
    for polygon in polygons:
        if polygon.geom_type!='Polygon' or polygon.area<4:continue
        for ring in [polygon.exterior,*polygon.interiors]:
            if abs(shapely.Polygon(ring).area)<4:continue
            points=[[round(x/w,7),round(y/h,7)] for x,y in list(ring.coords)[:-1]]
            if len(points)>=3:rings.append(points)
    if not rings:raise ValueError('Mountain contours are empty: '+str(path))
    return rings

def world_rings(site,asset,rings):
    visual=site['visual'];w=visual['width'];h=w*asset['height']/asset['width']*visual.get('height_scale',1)
    anchor=visual.get('anchor',asset.get('anchor',[.5,1]));angle=math.radians(visual.get('rotation',0));offset=visual.get('offset',[0,0])
    c,s=math.cos(angle),math.sin(angle)
    result=[]
    for ring in rings:
        transformed=[]
        for u,v in ring:
            x=(u-anchor[0])*w;y=(v-anchor[1])*h
            transformed.append([site['position'][0]+offset[0]+x*c-y*s,site['position'][1]+offset[1]+x*s+y*c])
        result.append(transformed)
    return result

def surface_rings(site,asset,asset_root,assets=None):
    boundary=site.get('terrain',{}).get('boundary',{})
    if boundary.get('mode')=='art_alpha' and boundary.get('asset_id')==asset['id'] and boundary.get('asset_path')==asset['path'] and boundary.get('seam_shadow') is True:
        rings=boundary['rings']
    else:
        width=site['visual']['width'];height=width*asset['height']/asset['width']*site['visual'].get('height_scale',1)
        rings=alpha_rings(Path(asset_root)/asset['path'],atlas=asset.get('atlas_rect'),world_size=(width,height))
    result=world_rings(site,asset,rings)
    additions=[v for v in site['visual'].get('layers',[]) if v.get('role')=='completion_underlay']
    if not additions or not assets:return result
    def shape(source):
        geometry=None
        for ring in source:
            polygon=shapely.make_valid(shapely.Polygon(ring))
            geometry=polygon if geometry is None else geometry.symmetric_difference(polygon)
        return geometry
    geometry=shape(result)
    for visual in additions:
        layer_asset=assets[visual['asset_id']]
        width=visual['width'];height=width*layer_asset['height']/layer_asset['width']*visual.get('height_scale',1)
        layer_rings=alpha_rings(Path(asset_root)/layer_asset['path'],world_size=(width,height))
        geometry=geometry.union(shape(world_rings({'position':site['position'],'visual':visual},layer_asset,layer_rings)))
    polygons=[geometry] if geometry.geom_type=='Polygon' else list(geometry.geoms)
    return [[[float(x),float(y)] for x,y in list(r.coords)[:-1]] for polygon in polygons if polygon.geom_type=='Polygon' for r in [polygon.exterior,*polygon.interiors]]
