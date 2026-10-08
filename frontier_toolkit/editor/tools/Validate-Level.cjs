const fs = require('node:fs');
const path = require('node:path');
const model = require('../model.js');
try {
  const source = path.resolve(process.argv[2] || path.join(__dirname, '../examples/Frontier.mapproject.json'));
  const project = model.parseDocument(fs.readFileSync(source, 'utf8'));
  const issues = model.validate(project);
  for (const issue of issues) console.log(`${issue.severity.toUpperCase()} ${issue.map_id}/${issue.object_id || '(map)'}: ${issue.message}`);
  const errors = issues.filter(issue => issue.severity === 'error').length;
  console.log(`${project.maps.length} maps, ${project.maps.reduce((sum, map) => sum + map.objects.length, 0)} objects, ${errors} errors`);
  process.exitCode = errors ? 1 : 0;
} catch (error) { console.error(error.message); process.exitCode = 1; }
