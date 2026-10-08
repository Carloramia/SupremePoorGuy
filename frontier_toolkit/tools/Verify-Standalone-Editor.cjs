const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const required = ['README.md', '使用说明.html', '启动编辑器.cmd', 'editor/index.html', 'editor/README.md', 'editor/app.js', 'editor/model.js', 'editor/renderer.js', 'editor/styles.css', 'editor/examples/Frontier.mapproject.json', 'editor/examples/FrontierImported.mapproject.json'];
const errors = required.filter(file => !fs.existsSync(path.join(root, file))).map(file => 'Missing: ' + file);
if (!errors.length) {
  const M = require(path.join(root, 'editor/model.js'));
  const project = M.createProject();
  for (const asset of project.assets) {
    if (!asset.data && !fs.existsSync(path.join(root, asset.path.replace(/^res:\/\//, '')))) errors.push('Missing asset: ' + asset.path);
  }
  for (const issue of M.validate(project)) if (issue.severity === 'error') errors.push(issue.message);
  const source = M.parseDocument(fs.readFileSync(path.join(root, 'editor/examples/Frontier.mapproject.json'), 'utf8'));
  if (M.serialize(M.parseDocument(M.serialize(source))) !== M.serialize(source)) errors.push('Document roundtrip failed');
  const index = fs.readFileSync(path.join(root, 'editor/index.html'), 'utf8');
  for (const match of index.matchAll(/(?:src|href)="([^"#]+)"/g)) {
    if (/^(https?:|data:)/.test(match[1])) continue;
    if (!fs.existsSync(path.resolve(root, 'editor', match[1]))) errors.push('Missing page dependency: ' + match[1]);
  }
  for (const folder of ['world_map', 'scenario_2_5d', '.godot', '.tools']) if (fs.existsSync(path.join(root, folder))) errors.push('Unexpected game/runtime folder: ' + folder);
}
if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
else console.log('Standalone editor OK: entry points, page dependencies, built-in assets, example validation and document roundtrip.');
