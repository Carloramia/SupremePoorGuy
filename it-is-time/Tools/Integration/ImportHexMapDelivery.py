"""Import the verified hex delivery as versioned, portable game resources.

Keeps original artwork bytes and authoring coordinates. Does not switch the game
to this map until its runtime bridge and save migration have passed integration.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

PROJECT = Path(__file__).resolve().parents[2]
CONTENT = 'Content/Maps/HexFrontier_20261019'
MODULE = 'Modules/HexFrontier'

def read(path):
    return json.loads(path.read_text(encoding='utf-8-sig'))

def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main(base):
    author = base/'project/frontier_toolkit/editor/hex'
    receipt = read(base/'event-patch-application-receipt.json')
    if receipt.get('patch_id')!='frontier-map-20261019-r1':
        raise ValueError('Verified patch application receipt missing')
    output = PROJECT/CONTENT
    output.mkdir(parents=True,exist_ok=True)
    layout_path = author/'Data/Maps/hex_layout.json'
    battles_path = author/'Data/Maps/hex_battles.json'
    layout = read(layout_path)
    battles = read(battles_path)
    world_spec = read(author/'GodotPreview/scene.json')
    battle_spec = read(author/'GodotBattlePreview/battle_scene.json')
    if world_spec['layout_sha256']!=hashlib.sha256(layout_path.read_bytes()).hexdigest() or battle_spec['layout_sha256']!=hashlib.sha256(battles_path.read_bytes()).hexdigest():
        raise ValueError('Preview constraints do not match authoritative layout')
    files = {}
    registry = {}
    def copy(source):
        source = source.resolve()
        if not source.is_relative_to((base/'project').resolve()) or not source.is_file():
            raise ValueError('Missing or unsafe artwork dependency: '+str(source))
        relative = source.relative_to((base/'project').resolve()).as_posix()
        target = output/'Authoring'/relative
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        if not target.is_file() or hashlib.sha256(target.read_bytes()).hexdigest()!=digest:
            target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(source,target)
        files[relative] = {'sha256':digest,'bytes':source.stat().st_size,'target':target.relative_to(PROJECT).as_posix()}
        return 'res://'+target.relative_to(PROJECT).as_posix()
    for item in layout['assets']:
        registry[item['path']] = copy(author/'Tools/hex-planner'/item['path'])
    background = layout.get('background',{})
    if background.get('asset'):
        registry[background['asset']] = copy(author/'Tools/hex-planner'/background['asset'])
    if background.get('source_tiles',{}).get('clip_asset'):
        clip = background['source_tiles']['clip_asset']
        registry[clip] = copy(author/'Tools/hex-planner'/clip)
    for tile in world_spec['tiles']:
        registry[tile['path']] = copy(author/'Tools/hex-planner'/tile['path'])
    for asset in battle_spec['assets'].values():
        path = asset.get('native_path','')
        if not path:
            continue
        resolved = Path(path) if Path(path).is_absolute() else author/'GodotBattlePreview'/path
        asset['native_path'] = copy(resolved)
    # Authoring JSON remains byte-identical for the visual constraint hash check.
    for source in [layout_path,battles_path]:
        target = output/source.name
        shutil.copyfile(source,target)
    world_spec['layout_path'] = 'res://'+CONTENT+'/hex_layout.json'
    world_spec['asset_root'] = 'res://'+CONTENT+'/Authoring/frontier_toolkit/editor/hex/Tools/hex-planner'
    battle_spec['layout_path'] = 'res://'+CONTENT+'/hex_battles.json'
    write(output/'world_visuals.json',world_spec)
    write(output/'battle_visuals.json',battle_spec)
    write(output/'AssetRegistry.json',registry)
    replacements = {
        'res://HexMapData.gd':'res://'+MODULE+'/HexMapData.gd',
        'res://MapSight.gd':'res://'+MODULE+'/MapSight.gd',
        'res://MapPresentation.gd':'res://'+MODULE+'/MapPresentation.gd',
        'res://MonsterTaxonomy.gd':'res://'+MODULE+'/MonsterTaxonomy.gd',
        'res://scene.json':'res://'+CONTENT+'/world_visuals.json',
        'res://Data/Maps/hex_layout.json':'res://'+CONTENT+'/hex_layout.json',
    }
    for name in ['CurrentMapPreview.gd','HexMapData.gd','MapSight.gd','MapPresentation.gd','MonsterTaxonomy.gd']:
        text = (author/'GodotPreview'/name).read_text(encoding='utf-8-sig')
        for old,new in replacements.items():
            text = text.replace(old,new)
        text = text.replace('\tget_window().title="当前地图 · 图8素材与85%树林 · 柔雾与山后遮挡"\n','')
        if name=='CurrentMapPreview.gd':
            text = text.replace('var image:=Image.load_from_file(str(spec.asset_root).path_join(path))', 'var resolved:=str(spec.asset_root).path_join(path)\n\tif ResourceLoader.exists(resolved):\n\t\tvar imported:=load(resolved) as Texture2D\n\t\tif imported!=null:images[path]=imported;return imported\n\tvar image:=Image.load_from_file(resolved)')
        target = PROJECT/MODULE/name
        target.parent.mkdir(parents=True,exist_ok=True)
        target.write_text(text,encoding='utf-8')
    pose=(base/'project/frontier_toolkit/editor/godot/battle_visual_pose.gd').read_text(encoding='utf-8-sig')
    (PROJECT/MODULE/'BattleVisualPose.gd').write_text(pose,encoding='utf-8')
    visual=(author/'GodotBattlePreview/BattlePreview3D.gd').read_text(encoding='utf-8-sig')
    start=visual.index('func _ready()')
    end=visual.index('func _reset_camera()',start)
    visual=visual[:start]+'func _ready() -> void: pass\n\n'+visual[end:]
    visual=visual.replace('res://battle_visual_pose.gd','res://'+MODULE+'/BattleVisualPose.gd')
    visual+='\nfunc build_geometry(map_id: String) -> Node3D:\n\tspec=JSON.parse_string(FileAccess.get_file_as_string("res://'+CONTENT+'/battle_visuals.json"))\n\tfor entry: Dictionary in spec.maps:\n\t\tif entry.id==map_id:current_map=entry;break\n\tif current_map.is_empty():return null\n\tscenery=Node3D.new();scenery.name="HexBattleEnvironment";add_child(scenery)\n\tground()\n\tfor object: Dictionary in current_map.objects:\n\t\tif object.type not in ["deployment","enemy"] and object.visual.get("visible",true) and not str(object.visual.asset).is_empty():art(object)\n\tremove_child(scenery)\n\treturn scenery\n'
    # Exported textures use imported resources, while raw source remains available in editor.
    visual=visual.replace('var image:=Image.load_from_file(path)','if ResourceLoader.exists(path):\n\t\t\tvar imported:=load(path) as Texture2D\n\t\t\tif imported!=null:textures[path]=imported;return imported\n\t\tvar image:=Image.load_from_file(path)')
    (PROJECT/MODULE/'BattleVisuals.gd').write_text(visual,encoding='utf-8')
    write(output/'ImportReceipt.json',{'source_patch':receipt['patch_id'],'layout_sha256':world_spec['layout_sha256'],'battle_sha256':battle_spec['layout_sha256'],'art_files':files,'map_count':len(battles['maps']),'site_count':len(layout['sites'])})
    print(json.dumps({'art_files':len(files),'bytes':sum(f['bytes'] for f in files.values()),'map_count':len(battles['maps']),'site_count':len(layout['sites'])}))

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base',type=Path)
    args=parser.parse_args()
    main(args.base.resolve())
