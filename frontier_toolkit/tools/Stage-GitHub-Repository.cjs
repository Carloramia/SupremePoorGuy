// Builds a new repository tree. No Git mutation, network, move, overwrite or deletion.
const fs=require('node:fs'), path=require('node:path'), crypto=require('node:crypto');
const root=path.resolve(__dirname,'..');
const config=JSON.parse(fs.readFileSync(path.join(__dirname,'github-package.config.json'),'utf8'));
const destination=path.resolve(process.argv[2] || '');
const dist=path.join(root,'dist');
const contained=(parent,child)=>{const rel=path.relative(parent,child);return rel!==''&&!rel.startsWith('..'+path.sep)&&rel!=='..'&&!path.isAbsolute(rel);};
if (!process.argv[2] || !contained(dist,destination)) throw new Error('Destination must be a new directory inside this workspace dist/.');
if (fs.existsSync(destination)) throw new Error('Destination exists; choose a new package name.');
if (config.schema_version!==1 || config.toolkit_directory!=='frontier_toolkit') throw new Error('Unsupported release layout');
const sha256=b=>crypto.createHash('sha256').update(b).digest('hex');
const blobHash=b=>crypto.createHash('sha1').update(Buffer.from(`blob ${b.length}\0`)).update(b).digest('hex');
const pinned=new Map();
const adaptations=new Map();
for(const spec of config.source_adaptation_manifests||[]) {
  const m=JSON.parse(fs.readFileSync(path.join(root,spec.manifest),'utf8'));
  for(const entry of m.files) adaptations.set(spec.prefix+entry.path,entry);
}
for(const spec of config.source_manifests) {
  const manifest=JSON.parse(fs.readFileSync(path.join(root,spec.manifest),'utf8'));
  for(const entry of manifest.files) pinned.set(spec.prefix+entry.path,{...entry,commit:manifest.commit});
}
const selected=[], excluded=[];
function allowed(p) {
  if(p.split('/').some(s=>config.excluded_directories.includes(s))) return false;
  if(pinned.has(p)&&config.preserve_pinned_extensions.includes(path.extname(p).toLowerCase())) return true;
  if(config.excluded_extensions.includes(path.extname(p).toLowerCase())) return false;
  if(p.endsWith('.import')) return pinned.has(p);
  return !/(?:_save|_test_results|test_results|-results)\.json$/.test(path.basename(p)) && !['.DS_Store','Thumbs.db'].includes(path.basename(p));
}
function collect(relative) {
  const absolute=path.resolve(root,relative);
  if(!contained(root,absolute)) throw new Error('Source path escapes workspace: '+relative);
  const stat=fs.lstatSync(absolute);
  if(stat.isSymbolicLink()) throw new Error('Release does not dereference symlinks: '+relative);
  if(!allowed(relative)) {excluded.push(relative);return;}
  if(stat.isDirectory()) for(const name of fs.readdirSync(absolute).sort()) collect(relative+'/'+name);
  else {
    if(stat.size>=100*1024*1024) throw new Error('File exceeds release size limit: '+relative);
    const bytes=fs.readFileSync(absolute);
    const entry=pinned.get(relative);
    if(entry && blobHash(bytes)!==entry.sha) {
      const adaptation=adaptations.get(relative);
      if(!adaptation || adaptation.upstream_blob!==entry.sha || adaptation.current_blob!==blobHash(bytes)) throw new Error('Pinned source changed; preserve or explicitly revise source adaptation manifest: '+relative);
    }
    selected.push({source:relative,target:config.toolkit_directory+'/'+relative,bytes,hash:sha256(bytes)});
  }
}
for(const entry of config.entries) collect(entry);
const templateRoot=path.resolve(root,config.templates_directory);
function templates(folder,relative='') {
  for(const entry of fs.readdirSync(folder,{withFileTypes:true})) {
    const name=relative?relative+'/'+entry.name:entry.name;
    if(entry.name==='.gdignore') continue;
    if(entry.isSymbolicLink()) throw new Error('Template symlink unsupported');
    if(entry.isDirectory()) templates(path.join(folder,entry.name),name);
    else {const bytes=fs.readFileSync(path.join(folder,entry.name));selected.push({source:config.templates_directory+'/'+name,target:name,bytes,hash:sha256(bytes)});}
  }
}
templates(templateRoot);
const targets=new Set(selected.map(f=>f.target));
if(targets.size!==selected.length) throw new Error('Duplicate release destination');
for(const p of pinned.keys()) if(!targets.has(config.toolkit_directory+'/'+p)) throw new Error('Pinned source omitted: '+p);
fs.mkdirSync(destination,{recursive:true});
for(const file of selected) {
  const target=path.resolve(destination,file.target);
  if(!contained(destination,target)) throw new Error('Output path escapes release root');
  fs.mkdirSync(path.dirname(target),{recursive:true});
  fs.writeFileSync(target,file.bytes,{flag:'wx'});
  if(sha256(fs.readFileSync(target))!==file.hash) throw new Error('Copy integrity failed: '+file.target);
}
const provenance={
  schema_version:1,
  prepared_date:new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Shanghai',year:'numeric',month:'2-digit',day:'2-digit'}).format(new Date()),
  source_snapshot_date:'2026-10-15',
  layout:'repository wrapper with frontier_toolkit payload',toolkit_directory:config.toolkit_directory,
  original_pr:'https://github.com/Carloramia/SupremePoorGuy/pull/1',original_pr_head:'a36c06ff1b2313351f85e2d31b4de86d117ab377',
  pinned_source_files:pinned.size,source_adaptations:[...adaptations].map(([p,a])=>({...a,path:p})),
  source_manifests:config.source_manifests.map(s=>config.toolkit_directory+'/'+s.manifest),
  excluded_directories:config.excluded_directories,
  generated_import_policy:'Only upstream-manifest-tracked .import metadata is preserved.',
  runtime_boundary:'FakeBattleAdapter remains; actual it-is-time integration is a documented future change.',
  copy_files:selected.length,excluded_entries:excluded.length
};
fs.writeFileSync(path.join(destination,'RELEASE_CONTENTS.json'),JSON.stringify(provenance,null,2)+'\n');
const manifest=selected.map(f=>({path:f.target,bytes:f.bytes.length,sha256:f.hash}));
const releaseBytes=fs.readFileSync(path.join(destination,'RELEASE_CONTENTS.json'));
manifest.push({path:'RELEASE_CONTENTS.json',bytes:releaseBytes.length,sha256:sha256(releaseBytes)});
manifest.sort((a,b)=>a.path.localeCompare(b.path,'en'));
fs.writeFileSync(path.join(destination,'PACKAGE_MANIFEST.json'),JSON.stringify(manifest,null,2)+'\n');
console.log(JSON.stringify({repository:destination,files:manifest.length,pinned_source_files:pinned.size,total_bytes:manifest.reduce((n,f)=>n+f.bytes,0),excluded_entries:excluded.length},null,2));
