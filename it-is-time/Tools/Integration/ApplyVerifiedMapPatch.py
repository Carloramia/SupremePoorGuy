"""Apply only hash-verified payload files to an isolated extracted map delivery."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil

def sha(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024*1024), b''):
            digest.update(block)
    return digest.hexdigest()

def inside(root, name):
    result = (root/name).resolve()
    if not result.is_relative_to(root.resolve()):
        raise ValueError('Path leaves delivery root')
    return result

def apply(base, patch):
    manifest = json.loads((patch/'manifest.json').read_text(encoding='utf-8-sig'))
    changes = []
    for item in manifest['required']:
        path = inside(base, item['path'])
        if not path.is_file() or sha(path) != item['sha256']:
            raise ValueError('Original dependency mismatch: '+item['path'])
    for item in manifest['files']:
        target = inside(base, item['path'])
        source = inside(patch/'payload', item['path'])
        if not source.is_file() or sha(source) != item['sha256']:
            raise ValueError('Payload mismatch: '+item['path'])
        actual = sha(target) if target.is_file() else ''
        if actual == item['sha256']:
            continue
        if actual != item['old_sha256']:
            raise ValueError('Base file conflict: '+item['path'])
        changes.append((source, target, item))
    # All preflight checks complete before the first mutation. The original ZIP
    # remains untouched and this tool writes only the explicit extracted copy.
    for source, target, _ in changes:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    for _, target, item in changes:
        if sha(target) != item['sha256']:
            raise ValueError('Copied file verification failed: '+item['path'])
    receipt = {'patch_id': manifest['id'], 'verified_dependencies': len(manifest['required']), 'applied_files': len(changes), 'files': [i for _, _, i in changes]}
    (base/'event-patch-application-receipt.json').write_text(json.dumps(receipt, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
    print(json.dumps({k:v for k,v in receipt.items() if k!='files'}, ensure_ascii=False))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('base', type=Path)
    parser.add_argument('patch', type=Path)
    args = parser.parse_args()
    apply(args.base.resolve(), args.patch.resolve())
