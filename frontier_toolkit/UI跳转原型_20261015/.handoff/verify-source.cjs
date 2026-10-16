const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const root = path.resolve(__dirname, '..');
const manifest = JSON.parse(fs.readFileSync(path.join(__dirname, 'source-manifest.json'), 'utf8'));
const changes = [];
const generated = [];
const adaptationFile=path.join(__dirname,'source-adaptations.json');
const accepted=fs.existsSync(adaptationFile)?JSON.parse(fs.readFileSync(adaptationFile,'utf8')).files:[];
const adaptations=[];
for (const file of manifest.files) {
  const target = path.join(root, file.path);
  if (!fs.existsSync(target)) { changes.push({path: file.path, status: 'missing'}); continue; }
  const data = fs.readFileSync(target);
  const hash = crypto.createHash('sha1').update('blob ' + data.length + '\0').update(data).digest('hex');
  if (hash !== file.sha) {
    const allowed=accepted.find(a=>a.path===file.path&&a.upstream_blob===file.sha&&a.current_blob===hash);
    if(allowed)adaptations.push(allowed);
    else (file.path.endsWith('.import') ? generated : changes).push({path: file.path, status: 'changed'});
  }
}
const report = {repository: manifest.repository, commit: manifest.commit, sourceFiles: manifest.files.length, unchangedSource: manifest.files.length - changes.length - generated.length - adaptations.length, recognizedAdaptations:adaptations, generatedImportChanges: generated, sourceChanges: changes};
fs.writeFileSync(path.join(__dirname, 'source-verification.json'), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({commit: report.commit, sourceFiles: report.sourceFiles, sourceChanges: changes.length, recognizedAdaptations:adaptations.length, generatedImportChanges: generated.length}));
if (changes.length) process.exitCode = 1;
