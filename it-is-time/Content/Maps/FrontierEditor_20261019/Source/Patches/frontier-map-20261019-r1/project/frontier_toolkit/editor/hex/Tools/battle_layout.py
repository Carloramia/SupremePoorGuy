"""Structural validation for saved hex battle drafts. Business diagnostics stay in the editor."""
import math,re

TYPES={'indestructible','destructible','traversable','collision_damage','pit','thorns','mud','web','deployment','enemy','post_battle','tree','decoration','edge_decoration','broken_barricade'}
FAMILIES={'unassigned','snake','humanoid','beast','spider','flying'}
SIZES={'','tiny','small','medium','large','huge'}

def number(value,minimum,maximum):
    return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value) and minimum<=value<=maximum

def vector(value):return isinstance(value,list) and len(value)==2 and all(number(n,-100000,100000) for n in value)

def validate_battles(doc):
    def need(condition,message):
        if not condition:raise ValueError(message)
    need(isinstance(doc,dict) and doc.get('format')=='frontier_hex_battles' and type(doc.get('version')) is int and doc.get('version')==1,'不兼容的蜂窝战场工作集')
    need(isinstance(doc.get('maps'),list) and 1<=len(doc['maps'])<=100 and isinstance(doc.get('assets'),list) and isinstance(doc.get('catalogs'),dict) and isinstance(doc.get('source_maps'),dict) and isinstance(doc.get('source_sha256'),str),'战场工作集结构无效')
    ids=set()
    for m in doc['maps']:
        need(isinstance(m,dict),'战场须为对象')
        ident=m.get('id');need(isinstance(ident,str) and re.fullmatch(r'[A-Za-z0-9_-]{1,80}',ident) and ident not in ids,'战场 ID 无效或重复');ids.add(ident)
        need(m.get('kind')=='battle' and isinstance(m.get('name'),str) and number(m.get('radius'),3,200) and m.get('orientation') in ['flat','pointy'],'战场尺寸或朝向无效')
        wall=m.get('wall',{});grid=m.get('hex_grid',{})
        need(isinstance(wall,dict) and isinstance(grid,dict),'空气墙或网格结构无效')
        need(number(wall.get('thickness'),.05,10) and number(wall.get('height'),.1,1000) and type(wall.get('layer')) is int and 1<=wall['layer']<=1048575,'空气墙配置无效')
        need(number(m.get('background_blur'),0,30) and number(m.get('edge_feather'),0,10),'光晕配置无效')
        need(number(grid.get('cell_width'),1,10) and vector(grid.get('origin')) and m['radius']/grid['cell_width']<=100,'蜂窝尺寸或密度无效')
        need(isinstance(m.get('objects'),list) and len(m['objects'])<=10000 and isinstance(m.get('hex_cells'),list) and len(m['hex_cells'])<=100000,'对象或网格数量无效')
        cells=set()
        for c in m['hex_cells']:
            need(isinstance(c,dict),'蜂窝须为对象')
            need(type(c.get('q')) is int and type(c.get('r')) is int and abs(c['q'])<=1000 and abs(c['r'])<=1000,'蜂窝坐标无效')
            k=(c['q'],c['r']);need(k not in cells,'重复蜂窝');cells.add(k)
            need(not c.get('ground') or c['ground'] in ['plain','grass','soil','stone','sand','water'],'地面涂色无效')
            need(not c.get('control') or c['control'] in ['allowed','outside','breakable'],'控制层无效')
            for f in ['condition_ref','event_id']:need(f not in c or isinstance(c[f],str),'控制引用须为文本')
        for o in m['objects']:
            need(isinstance(o,dict),'点位须为对象')
            need(o.get('type') in TYPES and isinstance(o.get('id'),str) and bool(o['id']) and o['id'] not in ids and isinstance(o.get('name'),str),'对象 ID 或类型无效');ids.add(o['id'])
            need(vector(o.get('position')) and vector(o.get('scale')) and min(o['scale'])>0 and number(o.get('height'),-1000,1000) and number(o.get('rotation'),-360,360),'对象坐标或缩放无效')
            v=o.get('visual',{});need(isinstance(v,dict),'视觉配置须为对象');need(vector(v.get('size')) and min(v['size'])>0 and number(v.get('opacity'),0,1),'视觉参数无效')
            need(v.get('surface_mode','auto') in ['auto','tilted','ground'] and ('tilt_degrees' not in v or number(v['tilt_degrees'],0,90)),'美术摆放模式或倾角无效')
            for field in ['region','collision','click_area']:
                if field not in o:continue
                s=o[field];need(isinstance(s,dict),'范围须为对象');need(s.get('shape') in ['rect','circle','polygon'] and vector(s.get('offset')) and vector(s.get('size')) and min(s['size'])>0 and isinstance(s.get('points'),list) and all(vector(p) for p in s['points']) and number(s.get('rotation'),-360,360) and number(s.get('height'),.01,10000) and number(s.get('depth'),0,10000),'碰撞或效果范围无效：'+o['id'])
            if 'hex_footprint' in o:need(isinstance(o['hex_footprint'],list) and 1<=len(o['hex_footprint'])<=10000 and all(vector(p) for p in o['hex_footprint']),'蜂窝占地无效')
            if 'slots' in o:need(isinstance(o['slots'],list) and all(vector(p) for p in o['slots']),'槽位无效')
            if o['type']=='enemy':
                need(not o.get('monster_type') or o['monster_type'] in FAMILIES,'怪物形态无效');need(not o.get('monster_size') or o['monster_size'] in SIZES,'怪物尺寸无效')
                need('count' not in o or type(o['count']) is int and 1<=o['count']<=999,'怪物数量无效')
    for m in doc['maps']:
        if not m.get('encounter'):continue
        p=m['encounter'];enemies=[o for o in m['objects'] if o['type']=='enemy'];total=sum(o.get('count',1) for o in enemies);groups={}
        need(type(p.get('minimum_count')) is int and type(p.get('maximum_count')) is int and 1<=p['minimum_count']<=p['maximum_count']<=10 and p['minimum_count']<=total<=p['maximum_count'],'此战场敌军总数不符合点位规则')
        for o in enemies:
            need(not(o.get('monster_type')=='spider' or o.get('monster_species')=='spider') or p.get('region')=='spider','蜘蛛仅允许部署在蜘蛛森林')
            need(bool(o.get('monster_config_id')) and o.get('monster_type') in FAMILIES-{'unassigned'},'敌军配置或形态未完成')
            signature=(o.get('monster_type'),o.get('monster_size'),o.get('grouped'));g=o.get('team_group')
            need(g not in groups or groups[g]==signature,'同组怪物属性须一致');groups[g]=signature
        need(len(groups)<=2 and (len(groups)<=1 or p.get('difficulty')==3 or p.get('difficulty')==2 and p.get('sublevel')=='upper'),'复合敌群仅在二级高段或三级开放')
        need(len(groups)!=2 or len(set(groups.values()))==2,'主副组不能完全相同')
    return doc
