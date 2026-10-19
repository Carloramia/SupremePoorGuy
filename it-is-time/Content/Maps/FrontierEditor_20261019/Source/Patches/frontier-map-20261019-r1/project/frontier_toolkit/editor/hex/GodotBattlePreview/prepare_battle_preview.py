"""Prepare the current 41-map hex battle work set for the native oblique camera.

Copies scripts and a manifest only; source PNG/SVG assets remain byte-identical.
"""
from pathlib import Path
import argparse,hashlib,json,shutil,sys,os

def prepare(hex_root, output, layout=None, asset_root=None, native_content=None, portable=False):
    source=Path(__file__).resolve().parent
    hex_root=Path(hex_root).resolve();output=Path(output).resolve()
    if output==source:raise ValueError('Choose a separate output directory.')
    layout=Path(layout or hex_root/'Data/Maps/hex_battles.json').resolve()
    raw=layout.read_bytes();doc=json.loads(raw)
    sys.dont_write_bytecode=True;sys.path.insert(0,str(hex_root/'Tools'))
    from battle_layout import validate_battles
    validate_battles(doc)
    repo=hex_root.parents[2]
    web=Path(asset_root).resolve() if asset_root else hex_root/'Tools/hex-planner'
    # Original native asset IDs retained by the editor; newer cutouts are web assets.
    native=Path(native_content).resolve() if native_content else repo/'it-is-time/Content/Maps/FrontierDelivery_20261015'
    assets={}
    for asset in doc['assets']:
        candidates=[web/asset.get('browser_path','__missing__'),web/asset['path']]
        if asset['path'].startswith('res://'):
            candidates.extend([native/asset['path'][6:],repo/'frontier_toolkit'/asset['path'][6:]])
        path=next((p.resolve() for p in candidates if p.is_file()),None)
        if path:assets[asset['id']]={**asset,'native_path':Path(os.path.relpath(path,output)).as_posix() if portable else path.as_posix()}
    required={o['visual']['asset'] for m in doc['maps'] for o in m['objects'] if o['visual'].get('visible',True) and o['visual']['asset'] and o['type'] not in ['enemy','deployment']}
    missing=required-assets.keys()
    if missing:raise ValueError('Missing visible art: '+', '.join(sorted(missing)))
    output.mkdir(parents=True,exist_ok=True)
    spec={'layout_sha256':hashlib.sha256(raw).hexdigest(),'layout_path':Path(os.path.relpath(layout,output)).as_posix() if portable else layout.as_posix(),'assets':{k:v for k,v in assets.items() if k in required},'maps':doc['maps']}
    (output/'battle_scene.json').write_text(json.dumps(spec,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    for name in ['BattlePreview3D.gd','project.godot','BattlePreview.tscn']:
        shutil.copy2(source/name,output/name)
    shutil.copy2(hex_root.parent/'godot/battle_visual_pose.gd',output/'battle_visual_pose.gd')
    if (source/'tests').exists():shutil.copytree(source/'tests',output/'tests',dirs_exist_ok=True)
    print('NATIVE BATTLES',len(doc['maps']),'visible art',len(required),'missing',len(missing),'SHA',spec['layout_sha256'])

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--hex-root',type=Path,default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--layout',type=Path)
    parser.add_argument('--asset-root',type=Path)
    parser.add_argument('--native-content',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--portable',action='store_true',help='Keep generated paths relative to the output project.')
    args=parser.parse_args();prepare(args.hex_root,args.output,args.layout,args.asset_root,args.native_content,args.portable)
