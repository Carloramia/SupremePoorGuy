from pathlib import Path
import hashlib,json,sys
root=Path(__file__).resolve().parent
manifest_path=root/'补丁后文件清单_SHA256.json'
if not manifest_path.is_file():manifest_path=root/'文件清单_SHA256.json'
manifest=json.loads(manifest_path.read_text('utf-8'))
errors=[]
for item in manifest['files']:
 p=root/item['path'];h=hashlib.sha256()
 if not p.is_file():errors.append('Missing: '+item['path']);continue
 with p.open('rb') as f:
  for b in iter(lambda:f.read(4*1024*1024),b''):h.update(b)
 if p.stat().st_size!=item['bytes'] or h.hexdigest()!=item['sha256']:errors.append('Changed: '+item['path'])
print('PASS' if not errors else 'FAIL',len(manifest['files']),'files')
for e in errors:print(e)
sys.exit(bool(errors))
