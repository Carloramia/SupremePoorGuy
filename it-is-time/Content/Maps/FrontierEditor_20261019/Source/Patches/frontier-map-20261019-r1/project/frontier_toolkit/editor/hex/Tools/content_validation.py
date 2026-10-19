"""Validate image/event extensions before any disk save."""
import math
def validate_content(doc):
 def need(ok,message):
  if not ok:raise ValueError(message)
 def path(value):return isinstance(value,str) and value.startswith('assets/') and '..' not in value.split('/') and not any(c in value for c in '\\?#')
 def num(value):return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value)
 background=doc.get('background')
 if background:need(path(background.get('asset')) and isinstance(background.get('size'),list) and len(background['size'])==2 and all(num(n) and n>0 for n in background['size']),'底图路径或尺寸无效')
 pyramid=background.get('pyramid') if background else None
 if pyramid:
  def pair(v):return isinstance(v,list) and len(v)==2 and all(isinstance(n,int) and not isinstance(n,bool) and 0<n<=131072 for n in v)
  need(isinstance(pyramid,dict),'底图分块参数无效')
  levels=pyramid.get('levels');size=pyramid.get('tile_size');bleed=pyramid.get('bleed')
  need(pyramid.get('version')==1 and isinstance(size,int) and 256<=size<=2048 and isinstance(bleed,int) and 0<=bleed<=8 and pair(pyramid.get('source_pixel_size')) and pair(pyramid.get('native_pixel_size')) and isinstance(levels,list) and 1<=len(levels)<=6 and pyramid.get('format')=='webp','底图分块参数无效')
  prior=1
  for level in levels:
   need(isinstance(level,dict),'底图分级参数无效')
   scale=level.get('scale');pixels=level.get('pixel_size')
   need(isinstance(scale,int) and not isinstance(scale,bool) and prior<scale<=32 and pair(pixels) and all(n==pyramid['source_pixel_size'][i]*scale for i,n in enumerate(pixels)) and path(level.get('path')) and level.get('columns')==math.ceil(pixels[0]/size) and level.get('rows')==math.ceil(pixels[1]/size),'底图分级尺寸或路径无效');prior=scale
  need(pyramid['native_pixel_size']==levels[-1]['pixel_size']==background.get('pixel_size'),'底图母版尺寸不一致')
 hd=background.get('source_tiles') if background else None
 if hd:
  def hd_pair(v):return isinstance(v,list) and len(v)==2 and all(isinstance(n,int) and not isinstance(n,bool) and 0<n<=131072 for n in v)
  def hd_rect(v):return isinstance(v,list) and len(v)==4 and all(num(n) for n in v) and v[0]>=0 and v[1]>=0 and v[2]>0 and v[3]>0
  need(isinstance(hd,dict) and hd.get('version')==1 and hd_pair(hd.get('pixel_size')) and hd['pixel_size']==background.get('pixel_size') and isinstance(hd.get('columns'),int) and isinstance(hd.get('rows'),int) and hd['columns']>0 and hd['rows']>0 and hd['columns']*hd['rows']<=96 and isinstance(hd.get('tiles'),list) and len(hd['tiles'])==hd['columns']*hd['rows'],'高清原块参数无效')
  need(hd.get('clip_asset') is None or path(hd['clip_asset']) and hd['clip_asset'].endswith('.json'),'高清接缝路径无效')
  seen=set()
  for t in hd['tiles']:
   need(isinstance(t,dict) and isinstance(t.get('id'),str) and t['id'] not in seen and path(t.get('path')) and t['path'].endswith('.png') and hd_pair(t.get('source_size')) and hd_rect(t.get('rect')) and hd_rect(t.get('core')),'高清原块位置或路径无效');seen.add(t['id'])
   need(all(t['rect'][i]+t['rect'][i+2]<=hd['pixel_size'][i] and t['core'][i]>=t['rect'][i] and t['core'][i]+t['core'][i+2]<=t['rect'][i]+t['rect'][i+2] for i in range(2)),'高清原块位置或路径无效')
   need(t.get('offset') is None or isinstance(t['offset'],list) and len(t['offset'])==2 and all(num(n) and abs(n)<=640 for n in t['offset']),'高清原块配准偏移无效')
   need(t.get('clip') is None or isinstance(t['clip'],list) and 0<len(t['clip'])<=32 and all(isinstance(ring,list) and 3<=len(ring)<=20000 and all(isinstance(p,list) and len(p)==2 and all(num(n) and 0<=n<=hd['pixel_size'][i] for i,n in enumerate(p)) for p in ring) for ring in t['clip']),'高清原块接缝裁切无效')
 ids=set()
 for a in doc.get('assets',[]):
  need(isinstance(a,dict) and isinstance(a.get('id'),str) and a['id'] and a['id'] not in ids and path(a.get('path')) and (not a.get('preview_path') or path(a['preview_path'])) and num(a.get('width')) and num(a.get('height')) and a['width']>0 and a['height']>0,'素材目录无效');ids.add(a['id'])
 for a in doc.get('assets',[]):
  if a.get('contact_shadow'):
   sh=a['contact_shadow'];color=sh.get('color','');need(isinstance(color,str) and len(color)==7 and color.startswith('#') and all(c in '0123456789abcdefABCDEF' for c in color[1:]) and num(sh.get('opacity')) and 0<=sh['opacity']<=1 and num(sh.get('blur')) and 0<=sh['blur']<=8 and isinstance(sh.get('offset'),list) and len(sh['offset'])==2 and all(num(n) and abs(n)<=16 for n in sh['offset']) and isinstance(sh.get('source_size'),list) and len(sh['source_size'])==2 and all(num(n) and n>0 for n in sh['source_size']),'山石阴影参数无效')
 terrain=doc.get('terrain_artwork',{}).get('mountain')
 if terrain:
  need(isinstance(terrain.get('asset_ids'),list) and len(terrain['asset_ids'])==2 and all(i in ids for i in terrain['asset_ids']) and num(terrain.get('width')) and 0<terrain['width']<=1024,'山体素材规划参数无效')
 for site in doc['sites']:
  layers=site.get('visual',{}).get('layers')
  if layers is None:continue
  need(isinstance(layers,list) and len(layers)<=8,'组合图标图层无效')
  for v in layers:need(isinstance(v,dict) and v.get('asset_id') in ids and num(v.get('width')) and 0<v['width']<=20000 and num(v.get('rotation',0)) and isinstance(v.get('offset'),list) and len(v['offset'])==2 and all(num(n) for n in v['offset']),'组合图标素材或偏移无效')
 def parameters(event):
  rb=event.get('runtime_bindings',{});values=rb.get('parameters');specs=rb.get('parameter_specs')
  if values is None and specs is None:return
  need(isinstance(values,dict) and isinstance(specs,dict) and set(values)==set(specs),'事件数值参数与说明不一致')
  for key,spec in specs.items():
   need(isinstance(spec,dict) and spec.get('type') in ('number','integer','number_array') and num(spec.get('min')) and (spec.get('max') is None or num(spec['max']) and spec['max']>=spec['min']),'事件数值说明无效')
   value=values[key]
   if value is None:
    need(spec.get('allow_unconfigured') is True,'事件数值未配置');continue
   rows=value if spec['type']=='number_array' else [value]
   need(isinstance(rows,list) and bool(rows) and all(num(v) and v>=spec['min'] and (spec.get('max') is None or v<=spec['max']) and (spec['type']!='integer' or float(v).is_integer()) for v in rows),'事件数值无效：'+key)
  if event['id']=='QST_GRASS_020' and values.get('stakes') is not None and values.get('max_settlements') is not None:
   need(len(values['stakes'])==values['max_settlements'] and all(float(v).is_integer() for v in values['stakes']),'赌局轮次数量必须与本金列表一致')
  need(all(k in values for k in rb.get('parameter_bindings',{}).values()),'事件数值引用不存在')
 eids=set()
 for e in doc.get('event_catalog',{}).get('events',[]):
  need(isinstance(e,dict) and isinstance(e.get('id'),str) and e['id'] and e['id'] not in eids and isinstance(e.get('name'),str) and isinstance(e.get('stories'),list) and isinstance(e.get('branches'),list),'事件目录无效');eids.add(e['id']);parameters(e)
 modes={'interact','enter_range','on_discover','on_game_start','on_game_time','battle_won','dialogue_complete'}
 for s in doc['sites']:
  if s.get('visual'):
   v=s['visual'];need(v.get('asset_id') in ids and num(v.get('width')) and 0<v['width']<=20000 and num(v.get('rotation',0)),'素材绑定无效')
 for t in doc['sites']+doc['cells']:
  if t.get('event_trigger'):need(t['event_trigger'].get('mode') in modes,'事件触发方式无效')
  if t.get('event_links') is not None:need(isinstance(t['event_links'],list),'事件关联须为列表')
  for link in t.get('event_links',[]):need(isinstance(link,dict) and link.get('event_id') in eids and isinstance(link.get('entry_role',''),str) and (not link.get('event_trigger') or link['event_trigger'].get('mode') in modes),'共享入口事件关联无效')

 keys={str(c['q'])+','+str(c['r']) for c in doc['cells']}
 obstacles={s['id']:s for s in doc['sites'] if s.get('destruction')}
 for a in doc.get('assets',[]):
  if a.get('atlas_rect') is not None:
   rect=a['atlas_rect'];need(isinstance(rect,list) and len(rect)==4 and all(num(n) and n>=0 for n in rect) and rect[2]==a['width'] and rect[3]==a['height'],'图集裁切矩形无效')
 for s in obstacles.values():
  rule=s['destruction'];steps=rule.get('walk_steps');need(isinstance(steps,int) and not isinstance(steps,bool) and 1<=steps<=100 and isinstance(rule.get('cells'),list) and bool(rule['cells']) and len(set(rule['cells']))==len(rule['cells']) and all(k in keys and s['id'] in next(c for c in doc['cells'] if str(c['q'])+','+str(c['r'])==k).get('obstacle_ids',[]) for k in rule['cells']),'石障破坏时间或占用格无效')
 for c in doc['cells']:
  if c.get('obstacle_ids') is not None:need(isinstance(c['obstacle_ids'],list) and all(i in obstacles and str(c['q'])+','+str(c['r']) in obstacles[i]['destruction']['cells'] for i in c['obstacle_ids']),'石障占用格关联无效')
 if doc.get('destruction_contract',{}).get('version')==1:
  for c in doc['cells']:need(not(c.get('feature')=='breakable' or c.get('control')=='breakable') or bool(c.get('obstacle_ids')),'可破坏区块尚未绑定石头素材')
 mountains={s['id']:s for s in doc['sites'] if s.get('terrain',{}).get('kind')=='mountain'}
 asset_by_id={a['id']:a for a in doc.get('assets',[])}
 for s in doc['sites']:
  boundary=s.get('terrain',{}).get('boundary')
  if boundary is None:continue
  a=asset_by_id.get(s.get('visual',{}).get('asset_id'),{})
  need(isinstance(boundary,dict) and s['id'] in mountains and boundary.get('version')==1 and boundary.get('mode')=='art_alpha' and bool(a) and boundary.get('asset_id')==a['id'] and boundary.get('asset_path')==a['path'],'山体实边与当前素材不匹配')
  rings=boundary.get('rings');threshold=boundary.get('threshold');extent=boundary.get('extent',[0,0,1,1])
  need(isinstance(extent,list) and len(extent)==4 and all(num(n) and -2<=n<=3 for n in extent) and extent[2]>extent[0] and extent[3]>extent[1],'山体实边范围无效')
  need(isinstance(threshold,int) and not isinstance(threshold,bool) and 1<=threshold<=255 and isinstance(rings,list) and 1<=len(rings)<=128 and all(isinstance(r,list) and len(r)>=3 and all(isinstance(p,list) and len(p)==2 and all(num(n) and extent[i]<=n<=extent[i+2] for i,n in enumerate(p)) for p in r) for r in rings) and sum(map(len,rings))<=20000,'山体实边轮廓无效')
 for c in doc['cells']:
  if 'mountain_manual_rule' in c:need(isinstance(c['mountain_manual_rule'],bool),'山体独立阻挡标记无效')
  if c.get('mountain_ids') is not None:need(isinstance(c['mountain_ids'],list) and all(i in mountains and str(c['q'])+','+str(c['r']) in mountains[i]['terrain']['cells'] for i in c['mountain_ids']),'山体占用格关联无效')
 if doc.get('traversal'):need(num(doc['traversal'].get('hex_step_seconds')) and doc['traversal']['hex_step_seconds']>0,'行走耗时无效')
