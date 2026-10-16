// Verifies the staged/checked-out repository layout without Git or network access.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.resolve(process.argv[2]||'.');
const toolkit=path.join(root,'frontier_toolkit');
const errors=[], warnings=[];
const required=['README.md','BUILD.md','CONTRIBUTING.md','LICENSE_NOTICE.md','.gitignore','.gitattributes','.github/workflows/frontier-toolkit.yml','docs/REPOSITORY_LAYOUT.md','docs/INTEGRATING_IN_SUPREMEPOORGUY.md','RELEASE_CONTENTS.json','PACKAGE_MANIFEST.json','frontier_toolkit/project.godot','frontier_toolkit/BUILD.md','frontier_toolkit/docs/INTEGRATION_AND_EXTENSION.md','frontier_toolkit/docs/RELEASE_CONTENTS.md','frontier_toolkit/UI跳转原型/project.godot','frontier_toolkit/UI跳转原型_20261015/project.godot','frontier_toolkit/UI跳转原型_20261015/TA/Scenes/ShaderComparison.tscn','frontier_toolkit/UI跳转原型_20261015/TA/Scenes/NativeSkinPreview.tscn'];
for(const p of required)if(!fs.existsSync(path.join(root,p)))errors.push('Missing: '+p);
if(errors.length){console.error(errors.join('\n'));process.exit(1);}
const config=JSON.parse(fs.readFileSync(path.join(toolkit,'tools/github-package.config.json'),'utf8'));
const pinned=new Map();
const adaptations=new Map();
for(const spec of config.source_adaptation_manifests||[]){
 const m=JSON.parse(fs.readFileSync(path.join(toolkit,spec.manifest),'utf8'));
 for(const entry of m.files)adaptations.set('frontier_toolkit/'+spec.prefix+entry.path,entry);
}
for(const spec of config.source_manifests){
 const m=JSON.parse(fs.readFileSync(path.join(toolkit,spec.manifest),'utf8'));
 for(const entry of m.files)pinned.set('frontier_toolkit/'+spec.prefix+entry.path,entry.sha);
}
const digest=(b,type='sha256')=>crypto.createHash(type).update(b).digest('hex');
const blob=b=>crypto.createHash('sha1').update(Buffer.from(`blob ${b.length}\0`)).update(b).digest('hex');
let sourceChecked=0,generatedImports=0,recognizedAdaptations=0;
for(const [p,sha]of pinned){
 if(!fs.existsSync(path.join(root,p))){errors.push('Missing pinned source: '+p);continue;}
 if(blob(fs.readFileSync(path.join(root,p)))!==sha){
  const a=adaptations.get(p);
  if(a && a.upstream_blob===sha && a.current_blob===blob(fs.readFileSync(path.join(root,p))))recognizedAdaptations++;
  else if(p.endsWith('.import')&&!process.argv.includes('--manifest'))generatedImports++;
  else errors.push('Pinned source drift: '+p);
 }
 sourceChecked++;
}
if(generatedImports)warnings.push(`${generatedImports} tracked .import files regenerated; canonical source remains checked.`);
function walk(folder,relative=''){
 return fs.readdirSync(folder,{withFileTypes:true}).flatMap(e=>{
  const p=relative?relative+'/'+e.name:e.name;
  if(config.excluded_directories.includes(e.name))return [];
  if(e.isSymbolicLink()){errors.push('Symlink in release: '+p);return [];}
  return e.isDirectory()?walk(path.join(folder,e.name),p):[p];
 });
}
// In the shared game repository, unrelated it-is-time/reference files are outside
// this delivery. Validate only the toolkit plus the configured root scaffold.
const scaffold=walk(path.join(toolkit,config.templates_directory)).filter(p=>p!=='.gdignore');
const rootFiles=[...scaffold,'RELEASE_CONTENTS.json','PACKAGE_MANIFEST.json'];
const files=[...walk(toolkit).map(p=>'frontier_toolkit/'+p),...rootFiles.filter(p=>fs.existsSync(path.join(root,p)))];
for(const p of files){
 const ext=path.extname(p).toLowerCase();
 if(config.excluded_extensions.includes(ext)&&!(pinned.has(p)&&config.preserve_pinned_extensions.includes(ext)))errors.push('Unexpected release file: '+p);
 if(/^\.env(?:\.|$)/.test(path.basename(p))&&path.basename(p)!=='.env.example')errors.push('Environment file in release: '+p);
 if(fs.statSync(path.join(root,p)).size>=100*1024*1024)errors.push('Oversized release file: '+p);
}
let references=0;
function verifyProject(project){
 function scan(folder){
  if(folder!==project&&(fs.existsSync(path.join(folder,'.gdignore'))||fs.existsSync(path.join(folder,'project.godot'))))return;
  for(const entry of fs.readdirSync(folder,{withFileTypes:true})){
   if(config.excluded_directories.includes(entry.name))continue;
   const absolute=path.join(folder,entry.name);
   if(entry.isDirectory()){scan(absolute);continue;}
   if(!/\.(gd|tscn|tres)$/.test(entry.name))continue;
   const content=fs.readFileSync(absolute,'utf8');
   for(const m of content.matchAll(/(?:path=|preload\(|load\(|extends )"res:\/\/([^"\r\n]+)"/g)){
    // Dynamic resource expressions need runtime validation.
    if(/[%{}]/.test(m[1]))continue;
    const target=path.resolve(project,m[1]), rel=path.relative(project,target);
    references++;
    if(rel.startsWith('..'+path.sep)||path.isAbsolute(rel)||!fs.existsSync(target))errors.push(`Resource unresolved: ${path.relative(root,absolute)} -> res://${m[1]}`);
   }
  }
 }
 scan(project);
}
for(const project of [toolkit,path.join(toolkit,'UI跳转原型'),path.join(toolkit,'UI跳转原型_20261015')])verifyProject(project);
const ci=fs.readFileSync(path.join(root,'.github/workflows/frontier-toolkit.yml'),'utf8');
if(!ci.includes('working-directory: frontier_toolkit')||!ci.includes('Verify-GitHub-Repository.cjs'))errors.push('Root CI does not validate the toolkit layout.');
const docFiles=['README.md','BUILD.md','CONTRIBUTING.md','docs/REPOSITORY_LAYOUT.md','docs/INTEGRATING_IN_SUPREMEPOORGUY.md','frontier_toolkit/README.md','frontier_toolkit/BUILD.md','frontier_toolkit/docs/GITHUB_UPLOAD.md','frontier_toolkit/docs/INTEGRATION_AND_EXTENSION.md','frontier_toolkit/docs/RELEASE_CONTENTS.md','frontier_toolkit/docs/PR_VERSION_DIFFERENCES.md','frontier_toolkit/docs/battle_integration/ACCEPTANCE.md'];
let links=0;
for(const p of docFiles){
 if(!fs.existsSync(path.join(root,p))){errors.push('Missing documentation: '+p);continue;}
 for(const m of fs.readFileSync(path.join(root,p),'utf8').matchAll(/\[[^\]\n]+\]\(([^)]+)\)/g)){
  const href=m[1];if(/^(?:[a-z]+:|#)/i.test(href))continue;
  const target=path.resolve(path.dirname(path.join(root,p)),decodeURIComponent(href.split('#')[0]));
  links++;
  if(!fs.existsSync(target))errors.push(`Missing local link: ${p} -> ${href}`);
 }
}
let manifestFiles=0;
if(process.argv.includes('--manifest')){
 const manifest=JSON.parse(fs.readFileSync(path.join(root,'PACKAGE_MANIFEST.json'),'utf8'));
 const expected=new Set(['PACKAGE_MANIFEST.json']);
 for(const entry of manifest){
  const absolute=path.resolve(root,entry.path),rel=path.relative(root,absolute);
  if(rel.startsWith('..'+path.sep)||path.isAbsolute(rel)){errors.push('Manifest escapes repository: '+entry.path);continue;}
  if(expected.has(entry.path)){errors.push('Duplicate manifest path: '+entry.path);continue;}expected.add(entry.path);
  if(!fs.existsSync(absolute)){errors.push('Manifest missing file: '+entry.path);continue;}
  const bytes=fs.readFileSync(absolute);
  if(bytes.length!==entry.bytes||digest(bytes)!==entry.sha256)errors.push('Manifest hash mismatch: '+entry.path);
  manifestFiles++;
 }
 for(const p of files)if(!expected.has(p))errors.push('Unlisted release file: '+p);
}
if(errors.length){console.error(errors.join('\n'));process.exitCode=1;}
else console.log(JSON.stringify({status:'passed',projects:3,pinned_source_files:sourceChecked,recognized_source_adaptations:recognizedAdaptations,resource_references:references,documentation_links:links,manifest_files_checked:manifestFiles,warnings,scope:'Toolkit and configured root integration files only; existing it-is-time and other projects are outside this validation. Run Godot and GPU acceptance separately.'},null,2));
