// Prepare a namespaced, editable runtime copy; leave the upstream snapshot intact.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const source = JSON.parse(fs.readFileSync(path.join(root, 'ui_module/upstream/source-manifest.json'), 'utf8'));
const targetRoot = path.join(root, 'ui_module/prototype');
if (fs.existsSync(targetRoot)) throw new Error('Runtime already exists. Local edits will not be overwritten.');
let count = 0;
for (const entry of source.files) {
  const relative = entry.path.slice('UI跳转原型/'.length);
  if (!/^(Assets|Scenes|Scripts|Tests)\//.test(relative) || /\.(import|uid)$/.test(relative) || /^(Tests\/(screenshots|previews)\/)/.test(relative) || relative.endsWith('.ps1') || relative.endsWith('.json') && relative.startsWith('Tests/')) continue;
  let data = fs.readFileSync(path.join(root, entry.path));
  const hash = crypto.createHash('sha1').update(`blob ${data.length}\0`).update(data).digest('hex');
  if (hash !== entry.sha) throw new Error(`Upstream snapshot modified: ${entry.path}`);
  if (/\.(gd|tscn|tres|json|md)$/.test(relative)) {
    data = Buffer.from(data.toString('utf8').replaceAll('res://', 'res://ui_module/prototype/').replaceAll('user://prototype_session.json', 'user://ui_module_session.json'));
  }
  const target = path.join(targetRoot, relative);
  fs.mkdirSync(path.dirname(target), {recursive: true});
  fs.writeFileSync(target, data);
  count++;
}
fs.mkdirSync(path.join(targetRoot, 'Tests/screenshots'), {recursive: true});
fs.writeFileSync(path.join(root, 'ui_module/UPSTREAM.json'), JSON.stringify({repository:source.repository,commit:source.commit,sourceDirectory:'UI跳转原型',files:count,adaptations:['res:// -> res://ui_module/prototype/', 'isolated user://ui_module_session.json', 'hosted WorldView rendering switch; see README.md']}, null, 2) + '\n');
console.log(`Imported ${count} UI runtime files. Upstream preserved.`);
