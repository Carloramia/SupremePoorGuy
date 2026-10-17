"""Import the accepted delivery without replacing the application or paper UI."""
from pathlib import Path
import argparse
import hashlib
import json

PROJECT = Path(__file__).resolve().parents[2]
VERSION = 'FrontierDelivery_20261015'
CONTENT = 'Content/Maps/' + VERSION
MODULE = 'Modules/FrontierDelivery'
PREFIXES = {
    'Scripts/Map/': MODULE + '/Scripts/Map/',
    'Assets/Maps/': CONTENT + '/Assets/Maps/',
    'Data/Maps/': CONTENT + '/Data/Maps/',
    'Scenes/Maps3D/': CONTENT + '/Scenes/Maps3D/',
    'Scenes/Maps/': CONTENT + '/Scenes/Maps/',
    'Assets/UI/': 'Modules/PaperUI/Assets/UI/',
}

def remap(text):
    for old, new in PREFIXES.items():
        text = text.replace('res://' + old, 'res://' + new)
    return text

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('source', type=Path)
    args = parser.parse_args()
    source = args.source.resolve()
    if not (source / 'project.godot').is_file():
        raise SystemExit('Source must be the delivery UI project.')
    if (PROJECT / MODULE).exists() or (PROJECT / CONTENT).exists():
        raise SystemExit('Imported version already exists; do not overwrite adapted files.')
    records = []
    for prefix in list(PREFIXES)[:5]:
        for path in sorted((source / prefix).rglob('*')):
            if not path.is_file():
                continue
            rel = path.relative_to(source).as_posix()
            target = PROJECT / (PREFIXES[prefix] + rel[len(prefix):])
            target.parent.mkdir(parents=True, exist_ok=True)
            data = path.read_bytes()
            if path.suffix in ('.gd', '.gdshader', '.tscn', '.tres', '.json', '.import'):
                data = remap(data.decode('utf-8-sig')).encode('utf-8')
            target.write_bytes(data)
            records.append({'source': rel, 'target': target.relative_to(PROJECT).as_posix(),
                'source_sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'installed_sha256': hashlib.sha256(data).hexdigest()})
    (PROJECT / MODULE / 'sources.json').write_text(json.dumps({'source': str(source), 'files': records},
        ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'files': len(records), 'module': MODULE, 'content': CONTENT}, ensure_ascii=False))

if __name__ == '__main__':
    main()
