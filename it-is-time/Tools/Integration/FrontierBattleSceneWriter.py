"""Battle scene writer from the accepted 20261015 delivery; paths are set by BuildHexMapRuntime."""
import json
import math
import xml.etree.ElementTree as ET
from copy import deepcopy
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]


def sprite_pose(o, texture_width, texture_height, default_tilt):
    """The source's bottom-pivot pose, compensated for the object's yaw and X/Z scale."""
    v = o['visual']; mode = v.get('surface_mode', 'auto')
    if mode == 'auto':
        mode = 'ground' if o['type'] in ['mud', 'pit', 'post_battle', 'broken_barricade'] or v['asset'] in ['battle_leaf_litter', 'battle_dry_patch', 'battle_shale_patch', 'demo_wood_fragment'] else 'tilted' if o['type'] in ['tree', 'decoration', 'edge_decoration', 'web', 'thorns', 'indestructible', 'destructible', 'traversable', 'collision_damage'] else 'actor'
    theta = math.radians(max(0, min(90, v.get('tilt_degrees', default_tilt))))
    width, height = v['size'][0]*o['scale'][0], v['size'][1]*o['scale'][1]
    yaw = -math.radians(o['rotation']); c, s = math.cos(yaw), math.sin(yaw)
    # Inverse of the host's rotation*scale, applied to a camera-facing paper basis.
    def inverse(v):
        x, y, z = v
        return [(c*x-s*z)/o['scale'][0], y, (s*x+c*z)/o['scale'][1]]
    lift = max(.015, .035+v.get('z_index', 0)*.0002)
    if mode == 'ground':
        columns = [[width/texture_width,0,0], [0,0,-height/texture_height], [0,1,0]]
        # Ground artwork retains its authored planar yaw.
        columns = [[c*x+s*z,y,-s*x+c*z] for x,y,z in columns]
        origin = [0,lift,0]
    elif mode == 'tilted':
        columns = [[width/texture_width,0,0], [0,height*math.sin(theta)/texture_height,-height*math.cos(theta)/texture_height], [0,math.cos(theta),math.sin(theta)]]
        origin = [0,height*.5*math.sin(theta)+lift,-height*.5*math.cos(theta)]
    else:
        columns = [[width/texture_width,0,0], [0,height/texture_height,0], [0,0,1]]
        origin = [0,height*.5,0]
    local_columns = [inverse(col) for col in columns]
    # TSCN's Transform3D constructor serializes the basis by rows.
    values = [x for row in zip(*local_columns) for x in row] + inverse(origin)
    return 'Transform3D('+', '.join(n(x) for x in values)+')', mode


def scenery_sprite(o, asset, texture, parent, default_tilt):
    """Bake the source preview's Sprite3D pose; no per-frame layout script is needed."""
    pose, mode = sprite_pose(o, asset['width'], asset['height'], default_tilt)
    return ['[node name="Visual" type="Sprite3D" parent='+q(parent)+']',
        'transform = '+pose, 'texture = '+texture, 'pixel_size = 1.0',
        'modulate = Color(1, 1, 1, '+n(o['visual']['opacity'])+')',
        'texture_filter = 3', 'alpha_cut = 2', 'cast_shadow = 0',
        'billboard = '+('2' if mode == 'actor' else '0'),
        'visible = '+str(o['visual'].get('visible', True) and not o.get('layout_review_only', False)).lower(),
        'metadata/surface_mode = '+q(mode),
        'metadata/tilt_from_ground = '+n(max(0, min(90, o['visual'].get('tilt_degrees', default_tilt))) if mode == 'tilted' else 0)]

def q(value):
    return json.dumps(value, ensure_ascii=False)

def n(value):
    return format(float(value), '.9g')

def vec(values, kind='Vector2'):
    return kind + '(' + ', '.join(n(x) for x in values) + ')'

def packed(points, kind='PackedVector2Array'):
    return kind + '(' + ', '.join(n(v) for p in points for v in p) + ')'

def color(value, alpha=1):
    value = value.lstrip('#')
    return 'Color(' + ', '.join(n(int(value[i:i+2], 16)/255) for i in (0, 2, 4)) + ', ' + n(alpha) + ')'

def polygon(m):
    if m['kind'] == 'exploration':
        if m.get('outline'):
            return m['outline']
        x, y = m['bounds']['position']; w, h = m['bounds']['size']
        return [[x,y],[x+w,y],[x+w,y+h],[x,y+h]]
    offset = 0 if m['orientation'] == 'flat' else math.pi/6
    return [[m['radius']*math.cos(i*math.pi/3+offset),m['radius']*math.sin(i*math.pi/3+offset)] for i in range(6)]

def shape_points(shape):
    if shape['shape']=='polygon': return shape['points']
    w,h=shape['size']
    if shape['shape']=='circle': return [[math.cos(i*math.tau/32)*w/2,math.sin(i*math.tau/32)*h/2] for i in range(32)]
    return [[-w/2,-h/2],[w/2,-h/2],[w/2,h/2],[-w/2,h/2]]

def convert_battle_3d(m,assets,object_assets=None):
    """Author native X/Z art planes, separate solid collision/effect areas and hex walls."""
    exts=['[ext_resource type="Script" path="res://Scripts/Map/BattleMap3D.gd" id="BattleScript"]','[ext_resource type="Shader" path="res://Scripts/Map/BattleGround.gdshader" id="GroundShader"]','[ext_resource type="Shader" path="res://Scripts/Map/BattleExterior.gdshader" id="ExteriorShader"]']
    subs=[]; nodes=[]; textures={}
    def tex(a,background=False):
        key=a+(':background' if background else '')
        if key not in textures:
            textures[key]='Texture_'+str(len(textures))
            info=assets[a].get('edge_background',assets[a]) if background else assets[a]
            exts.append('[ext_resource type="Texture2D" path='+q(info.get('render_path',info['path']))+' id='+q(textures[key])+']')
        return 'ExtResource('+q(textures[key])+')'
    def sub(kind,props):
        name='R'+str(len(subs))
        subs.append('[sub_resource type='+q(kind)+' id='+q(name)+']\n'+'\n'.join(props))
        return 'SubResource('+q(name)+')'
    nodes += ['[node name='+q(m['id'])+' type="Node3D"]','script = ExtResource("BattleScript")','map_id = '+q(m['id']), 'data_path = '+q(f"res://Data/Maps/{m['id']}.json")]
    groundmat=sub('StandardMaterial3D',['shading_mode = 0','albedo_color = '+color(m['ground_color'])])
    groundmesh=sub('PrismMesh',['left_to_right = 0.5','size = Vector3(1, 1, 1)']) # Ground polygon authored as a CSGPolygon3D prism.
    # Keep physics at its original hex; use a separate soft visual silhouette.
    nodes += ['[node name="Ground" type="CSGPolygon3D" parent="."]','visible = false','rotation = Vector3(-1.570796327, 0, 0)','polygon = '+packed(polygon(m)), 'depth = 0.15', 'material = '+groundmat,'use_collision = true']
    feather=min(.12,max(0,m.get('edge_feather',0))/m['radius'])*m['radius']*math.sqrt(3)/2
    angle=0 if m['orientation']=='flat' else math.pi/6
    soft=sub('ShaderMaterial',['shader = ExtResource("GroundShader")','shader_parameter/ground_color = '+color(m['ground_color']),'shader_parameter/radius = '+n(m['radius']),'shader_parameter/feather = '+n(feather),'shader_parameter/orientation = '+n(angle)])
    surface=sub('PlaneMesh',['size = '+vec([m['radius']*2.3,m['radius']*2.3])])
    nodes += ['[node name="GroundVisual" type="MeshInstance3D" parent="."]','position = Vector3(0, 0.005, 0)','mesh = '+surface,'material_override = '+soft,'cast_shadow = 0']
    nodes += ['[node name="ExteriorBackground" type="Node3D" parent="."]','metadata/authored_blur = '+n(m.get('background_blur',8))]
    backdrop_mat=sub('StandardMaterial3D',['shading_mode = 0','albedo_color = '+color(m.get('background_color','#344732'))])
    backdrop=sub('PlaneMesh',['size = '+vec([m['radius']*6,m['radius']*6])])
    nodes += ['[node name="Backdrop" type="MeshInstance3D" parent="ExteriorBackground"]','position = Vector3(0,-0.7,0)','mesh = '+backdrop,'material_override = '+backdrop_mat,'cast_shadow = 0']
    shadow=sub('ShaderMaterial',['shader = ExtResource("GroundShader")','shader_parameter/ground_color = '+color('#09160d',.6),'shader_parameter/radius = '+n(m['radius']),'shader_parameter/feather = '+n(feather),'shader_parameter/orientation = '+n(angle),'shader_parameter/halo = true'])
    nodes += ['[node name="Halo" type="MeshInstance3D" parent="ExteriorBackground"]','position = Vector3(0,-0.2,0)','mesh = '+surface,'material_override = '+shadow,'cast_shadow = 0']
    for oi,o in enumerate(m['objects']):
        if o['type']!='edge_decoration' or not o['visual']['asset'] or not o['visual'].get('visible',True):continue
        asset_id=(object_assets or {}).get(o['id'],o['visual']['asset'])
        info=assets[asset_id].get('edge_background',assets[asset_id])
        width,height=o.get('edge_cluster',{}).get('background_size',[s*1.3 for s in o['visual']['size']])
        blur=sub('ShaderMaterial',['shader = ExtResource("ExteriorShader")','shader_parameter/artwork = '+tex(asset_id,True),'shader_parameter/blur_uv = '+vec([m.get('background_blur',8)/info['width'],m.get('background_blur',8)/info['height']]),'shader_parameter/opacity = '+n(.55*o['visual']['opacity'])])
        plane=sub('PlaneMesh',['size = '+vec([width,height])])
        nodes += ['[node name='+q('Edge_'+str(oi))+' type="MeshInstance3D" parent="ExteriorBackground"]','position = '+vec([o['position'][0]*1.23,-.4+oi*.0001,o['position'][1]*1.23],'Vector3'),'rotation = '+vec([0,-math.radians(o['rotation']),0],'Vector3'),'scale = '+vec([o['scale'][0],1,o['scale'][1]],'Vector3'),'mesh = '+plane,'material_override = '+blur,'cast_shadow = 0']
    nodes += ['[node name="Objects" type="Node3D" parent="."]']
    ordered=sorted(m['objects'],key=lambda o:o['visual'].get('z_index',0))
    for order,o in enumerate(ordered):
        oid=o['id'];v={**o['visual'],'asset':(object_assets or {}).get(o['id'],o['visual']['asset'])};p='Objects/'+oid
        nodes += ['[node name='+q(oid)+' type="Node3D" parent="Objects"]','position = '+vec([o['position'][0],o.get('height',0),o['position'][1]],'Vector3'),'rotation = '+vec([0,-math.radians(o['rotation']),0],'Vector3'),'scale = '+vec([o['scale'][0],1,o['scale'][1]],'Vector3'),'metadata/source_id = '+q(oid)]
        if v['asset'] and v.get('visible',True) and o['type'] not in ['deployment','reveal_area']:
            a=assets[v['asset']];w,h=v['size']
            if a.get('demo_art') and 'presentation' not in m:
                f=min(w/a['width'],h/a['height']);w,h=a['width']*f,a['height']*f
            if 'presentation' in m:
                nodes += scenery_sprite({**o, 'visual': v}, a, tex(v['asset']), p, m['presentation'].get('scenery_tilt_degrees',60))
            else:
                mat=sub('StandardMaterial3D',['transparency = 1','shading_mode = 0','cull_mode = 2','albedo_texture = '+tex(v['asset']),'albedo_color = Color(1,1,1,'+n(v['opacity'])+')','texture_filter = 1'])
                mesh=sub('PlaneMesh',['size = '+vec([w,h])]);placement=['position = '+vec([0,.02+order*.003,0],'Vector3')]
                nodes += ['[node name="Visual" type="MeshInstance3D" parent='+q(p)+']',*placement,'mesh = '+mesh,'material_override = '+mat,'cast_shadow = 0','visible = '+str(v['visible'] and not o.get('layout_review_only',False)).lower()]
        for key,body_type in [('collision','StaticBody3D'),('region','Area3D'),('click_area','Area3D')]:
            shape=o.get(key,{})
            if not shape.get('enabled'):continue
            height=shape.get('height',2);points=shape_points(shape)
            verts=[[x,y,z] for x,z in points for y in [0,height]]
            sr=sub('ConvexPolygonShape3D',['points = '+packed(verts,'PackedVector3Array')])
            nodes += ['[node name='+q(key)+' type='+q(body_type)+' parent='+q(p)+']','position = '+vec([shape['offset'][0],0,shape['offset'][1]],'Vector3'),'rotation = '+vec([0,-math.radians(shape['rotation']),0],'Vector3'),'collision_layer = '+str(shape.get('layer',1) if key=='collision' else 0),'collision_mask = '+str(0 if key=='collision' else 1),'[node name="Shape" type="CollisionShape3D" parent='+q(p+'/'+key)+']','shape = '+sr]
    points=polygon(m)
    for i,a in enumerate(points):
        b=points[(i+1)%6]; length=math.dist(a,b);height=m['wall']['height'];thickness=m['wall']['thickness']
        shape=sub('BoxShape3D',['size = '+vec([length,height,thickness],'Vector3')])
        nodes += ['[node name='+q('Boundary'+str(i))+' type="StaticBody3D" parent="."]','position = '+vec([(a[0]+b[0])/2,height/2,(a[1]+b[1])/2],'Vector3'),'rotation = '+vec([0,-math.atan2(b[1]-a[1],b[0]-a[0]),0],'Vector3'),'collision_layer = '+str(m['wall']['layer']),'collision_mask = 0','[node name="Shape" type="CollisionShape3D" parent='+q('Boundary'+str(i))+']','shape = '+shape]
    env=sub('Environment',['background_mode = 1','background_color = '+color(m.get('background_color','#4d5a42')),'ambient_light_source = 3','ambient_light_color = Color(1,1,1,1)','ambient_light_energy = 0.8'])
    nodes += ['[node name="WorldEnvironment" type="WorldEnvironment" parent="."]','environment = '+env,'[node name="Camera" type="Camera3D" parent="."]','position = Vector3(0, 60, 0)','rotation = Vector3(-1.570796327, 0, 0)','projection = 1','size = '+n(m['radius']*2.4),'current = true','[node name="Party" type="Node3D" parent="."]']
    text='[gd_scene load_steps='+str(len(exts)+len(subs)+1)+' format=3]\n\n'+'\n'.join(exts)+'\n\n'+'\n\n'.join(subs)+'\n\n'+'\n'.join(nodes)+'\n'
    (ROOT/f"Scenes/Maps3D/{m['id']}.tscn").write_text(text,encoding='utf-8')


def flatten_svg(blob):
    """Expand SVG symbol instances for Godot's importer, retaining source artwork."""
    root = ET.fromstring(blob)
    if not any(e.tag.endswith('}use') for e in root.iter()): return None
    ET.register_namespace('', 'http://www.w3.org/2000/svg')
    ET.register_namespace('xlink', 'http://www.w3.org/1999/xlink')
    definitions = {e.attrib['id']: e for e in root.iter() if 'id' in e.attrib}
    def expand(element, chain=()):
        tag = element.tag.rsplit('}', 1)[-1]
        if tag == 'use':
            ref = element.get('href', element.get('{http://www.w3.org/1999/xlink}href', '')).lstrip('#')
            assert ref in definitions and ref not in chain, 'Invalid SVG instance: '+ref
            group = ET.Element('{http://www.w3.org/2000/svg}g', {k:v for k,v in element.attrib.items() if k not in ['href','{http://www.w3.org/1999/xlink}href','x','y','width','height']})
            if element.get('x') or element.get('y'):
                group.set('transform', group.get('transform','')+' translate('+element.get('x','0')+' '+element.get('y','0')+')')
            group.append(expand(definitions[ref], (*chain, ref)))
            return group
        if tag == 'defs': return deepcopy(element)
        if tag == 'svg' and element is not root:
            attrs={k:v for k,v in element.attrib.items() if k not in ['id','width','height','viewBox','overflow','x','y']}
            view=[float(x) for x in element.get('viewBox','0 0 '+element.get('width','128')+' '+element.get('height','128')).replace(',',' ').split()]
            sx=float(element.get('width',view[2]))/view[2];sy=float(element.get('height',view[3]))/view[3]
            attrs['transform']=attrs.get('transform','')+f' scale({sx} {sy}) translate({-view[0]} {-view[1]})'
            result=ET.Element('{http://www.w3.org/2000/svg}g',attrs)
        else: result=ET.Element(element.tag,element.attrib)
        result.text=element.text
        for child in element: result.append(expand(child, chain))
        return result
    return ET.tostring(expand(root), encoding='utf-8')
