const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const required = ['project.godot', 'README.md', '.gitignore', '.gitattributes', '.github/workflows/editor-checks.yml', 'docs/GETTING_STARTED.md', 'docs/ARCHITECTURE.md', 'docs/GITHUB_UPLOAD.md', 'world_map/demo/WorldMapDemo.tscn', 'scenario_2_5d/demo/Scenario25DDemo.tscn', 'integration/scenario_overlay.gd', 'editor/index.html', 'editor/README.md', 'editor/examples/Frontier.mapproject.json', 'editor/examples/FrontierImported.mapproject.json'];
const errors = required.filter(file => !fs.existsSync(path.join(root, file))).map(file => 'Missing: ' + file);
function walk(folder) { return fs.readdirSync(folder, { withFileTypes: true }).flatMap(entry => {
  if (['.git', '.godot', '.tools', 'dist', 'node_modules'].includes(entry.name)) return [];
  const file = path.join(folder, entry.name); return entry.isDirectory() ? walk(file) : [file];
}); }
let references = 0;
for (const file of walk(root).filter(file => /\.(tscn|tres)$/.test(file))) {
  const text = fs.readFileSync(file, 'utf8');
  for (const match of text.matchAll(/path="res:\/\/([^"\r\n]+)"/g)) {
    references++;
    if (!fs.existsSync(path.join(root, match[1]))) errors.push(`${path.relative(root, file)}: unresolved resource res://${match[1]}`);
  }
}
if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
else console.log(`Package structure OK; ${required.length} required entries, ${references} Godot resource references resolved.`);
