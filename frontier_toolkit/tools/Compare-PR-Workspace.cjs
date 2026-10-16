// Read-only source comparison against PR #1; writes only its documentation artifacts.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const root = path.resolve(__dirname,'..');
const output = path.join(root,'docs/pr_version_diff');
const checkOnly = process.argv.includes('--check');
function emit(name, content) {
  const target=path.join(output,name);
  if (checkOnly) {
    if (!fs.existsSync(target) || fs.readFileSync(target,'utf8') !== content) throw new Error(`Comparison snapshot is stale: ${name}; run without --check to rebuild.`);
  } else fs.writeFileSync(target,content);
}
const metadata = JSON.parse(fs.readFileSync(path.join(output,'PR_BASELINE.json'),'utf8'));
const baseline = metadata.head_sha;
const baselineRoot = path.join(root,'.tools/frontier-pr/frontier_toolkit');
const git = args => cp.execFileSync('git',['-c','core.quotepath=false',...args],{cwd:root,maxBuffer:64*1024*1024});
const sha256 = b => crypto.createHash('sha256').update(b).digest('hex');
const blobHash = b => crypto.createHash('sha1').update(Buffer.from(`blob ${b.length}\0`)).update(b).digest('hex');
const generated = p => p === 'docs/PR_VERSION_DIFFERENCES.md' || p.startsWith('docs/pr_version_diff/') || p === 'tools/Compare-PR-Workspace.cjs';
const excludedDir = new Set(['.git','.godot','.tools','.runtime','dist','node_modules']);
function excluded(p) {
  return p.split('/').some(x=>excludedDir.has(x)) || /\.(import|log|tmp)$/.test(p) || /(?:_save|_test_results|test_results|-results)\.json$/.test(path.basename(p)) || ['.DS_Store','Thumbs.db'].includes(path.basename(p));
}
function walk(dir,relative='') {
  return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>{
    const p = relative ? `${relative}/${e.name}` : e.name;
    if (excluded(p) || generated(p)) return [];
    return e.isDirectory() ? walk(path.join(dir,e.name),p) : [p];
  });
}
const tree = git(['ls-tree','-r','-z',baseline,'--','frontier_toolkit']).toString('utf8').split('\0').filter(Boolean).map(row=>{
  const [header,repoPath] = row.split('\t');
  return {path:repoPath.slice('frontier_toolkit/'.length),blob:header.split(' ')[2]};
});
const coreRoots = new Set([...tree.map(e=>e.path.split('/')[0]),'ui_module']);
const current = walk(root).filter(p=>coreRoots.has(p.split('/')[0]));
const currentSet = new Set(current), baselineSet = new Set(tree.map(e=>e.path));
function textValue(buf) {
  if (buf.includes(0)) return null;
  const s=buf.toString('utf8');
  return Buffer.from(s,'utf8').equals(buf) ? s : null;
}
const normalize = s => s.replace(/^\uFEFF/,'').replaceAll('\r\n','\n').replace(/\n+$/,'\n');
const entries = [];
for (const entry of tree) {
  const fromDisk = path.join(baselineRoot,entry.path);
  let old = fs.existsSync(fromDisk) ? fs.readFileSync(fromDisk) : null;
  if (!old || blobHash(old) !== entry.blob) old=git(['cat-file','blob',entry.blob]);
  const now = currentSet.has(entry.path) ? fs.readFileSync(path.join(root,entry.path)) : null;
  let status = now === null ? 'deleted' : old.equals(now) ? 'unchanged' : 'modified';
  if (status === 'modified') {
    const a=textValue(old), b=textValue(now);
    if (a!==null && b!==null) {
      if (normalize(a) === normalize(b)) status='format_only';
      else if (entry.path.endsWith('.tscn') && normalize(a).replace(/\bunique_id=\d+/g,'unique_id=<generated>') === normalize(b).replace(/\bunique_id=\d+/g,'unique_id=<generated>')) status='serialization_only';
    }
  }
  entries.push({path:entry.path,module:entry.path.includes('/')?entry.path.split('/')[0]:'root',status,baseline_blob:entry.blob,baseline_sha256:sha256(old),current_sha256:now===null?null:sha256(now),baseline_bytes:old.length,current_bytes:now?.length??null});
}
for (const p of current.filter(p=>!baselineSet.has(p))) {
  const now=fs.readFileSync(path.join(root,p));
  entries.push({path:p,module:p.includes('/')?p.split('/')[0]:'root',status:'added',baseline_blob:null,baseline_sha256:null,current_sha256:sha256(now),baseline_bytes:null,current_bytes:now.length});
}
entries.sort((a,b)=>a.path.localeCompare(b.path,'en'));
const statusCounts = list => Object.fromEntries(['unchanged','modified','format_only','serialization_only','deleted','added'].map(s=>[s,list.filter(e=>e.status===s).length]));
const modules = [...new Set(entries.map(e=>e.module))].sort().map(module=>({module,...statusCounts(entries.filter(e=>e.module===module))}));
const independentRoots = ['UI跳转原型','UI跳转原型_20261015','shader需求'];
const independent = independentRoots.filter(p=>fs.existsSync(path.join(root,p))).map(folder=>({folder,files:walk(path.join(root,folder)).map(p=>{const b=fs.readFileSync(path.join(root,folder,p));return {path:p,bytes:b.length,sha256:sha256(b)};})}));
const fingerprint = sha256(Buffer.from(entries.map(e=>`${e.path}\0${e.status}\0${e.current_sha256||'-'}\n`).join('')));
const comparison = {comparison_date:'2026-10-15',baseline:metadata,scope:{baseline_prefix:'frontier_toolkit/',workspace_prefix:'./',core_roots:[...coreRoots].sort(),self_artifacts_excluded:['docs/PR_VERSION_DIFFERENCES.md','docs/pr_version_diff/','tools/Compare-PR-Workspace.cjs'],exclusions:'Engine/cache/Git/import/log/temp/save/test-result outputs; dist, github_pull, prompt drafts and exports outside core scope. Independent projects inventoried separately.',format_only_definition:'Equal after UTF-8 BOM removal, CRLF-to-LF normalization and collapsing trailing newlines only; internal whitespace is preserved.',serialization_only_definition:'TSCN files differ only by generated unique_id numeric values after format normalization.',current_workspace_has_no_head_commit:true},baseline_files:tree.length,current_core_files:current.length,counts:statusCounts(entries),modules,core_snapshot_sha256:fingerprint,entries,independent:independent.map(x=>({folder:x.folder,file_count:x.files.length,files:x.files}))};
emit('FILE_DIFF.json',JSON.stringify(comparison,null,2)+'\n');
const csv = [['status','module','path','baseline_sha256','current_sha256','baseline_bytes','current_bytes'],...entries.map(e=>[e.status,e.module,e.path,e.baseline_sha256,e.current_sha256,e.baseline_bytes,e.current_bytes])].map(row=>row.map(v=>'"'+String(v??'').replaceAll('"','""')+'"').join(',')).join('\n');
emit('FILE_DIFF.csv','\ufeff'+csv+'\n');
const report = ['# PR 版本逐文件比较索引','',`基线：[PR #1](${metadata.url}) 的 head \`${baseline}\`，限定 \`frontier_toolkit/\`。当前目录按相同相对路径映射。`, '',`基线 ${tree.length} 个文件；当前核心范围 ${current.length} 个文件；快照 SHA-256：\`${fingerprint}\`。`,'','本说明文档、比较工具和输出清单作为本次报告交付单列，不计入待比较版本，避免报告生成改变自身统计。格式变化仅忽略 UTF-8 BOM、CRLF/LF 和文件末尾多余换行；不忽略内部缩进。序列化变化仅指 .tscn 生成的 unique_id 数字。完整文件与哈希见 [FILE_DIFF.json](FILE_DIFF.json) 或 [FILE_DIFF.csv](FILE_DIFF.csv)。','','| 模块 | 相同 | 内容修改 | 仅格式 | 仅生成 ID | 当前缺失 | 新增 |','| --- | ---: | ---: | ---: | ---: | ---: | ---: |'];
for (const m of modules) report.push(`| ${m.module} | ${m.unchanged} | ${m.modified} | ${m.format_only} | ${m.serialization_only} | ${m.deleted} | ${m.added} |`);
report.push('','## 原有文件的内容变更和缺失','','| 状态 | 文件 | PR 版本 |','| --- | --- | --- |');
for (const e of entries.filter(e=>!['unchanged','added'].includes(e.status))) {
 const upstream=`https://github.com/Carloramia/SupremePoorGuy/blob/${baseline}/frontier_toolkit/${e.path.split('/').map(encodeURIComponent).join('/')}`;
 const local=e.status==='deleted'?e.path:`[${e.path}](../../${e.path.split('/').map(encodeURIComponent).join('/')})`;
 report.push(`| ${e.status} | ${local} | [固定提交](${upstream}) |`);
}
report.push('','## 当前独立参考工程与需求目录','','以下目录不在 PR 的 frontier_toolkit 文件集合内；只记录当前文件清单，不混入核心模块改动统计。','');
for(const i of independent) report.push(`- \`${i.folder}/\`：${i.files.length} 个文件。`);
report.push('','上级 GitHub 仓库中的 it-is-time、仓库首页与根 CI 不映射成当前工具集根目录文件；不能据此报告为删除。核心行为说明见 [PR_VERSION_DIFFERENCES.md](../PR_VERSION_DIFFERENCES.md)。');
emit('FILE_DIFF.md',report.join('\n')+'\n');
if (tree.length !== entries.filter(e=>e.status!=='added').length || current.length !== entries.filter(e=>e.status!=='deleted').length) throw new Error('File count invariant failed');
if (checkOnly) {
  let links=0;
  for (const file of [path.join(root,'docs/PR_VERSION_DIFFERENCES.md'),path.join(output,'FILE_DIFF.md')]) {
    for (const match of fs.readFileSync(file,'utf8').matchAll(/\[[^\]\n]+\]\(([^)]+)\)/g)) {
      const href=match[1]; if (/^(https?:|#)/.test(href)) continue;
      const target=path.resolve(path.dirname(file),decodeURIComponent(href.split('#')[0]));
      if (!fs.existsSync(target)) throw new Error(`Missing documentation link: ${href}`);
      links++;
    }
  }
  console.log(`Comparison snapshot and ${links} local documentation links verified.`);
}
console.log(JSON.stringify({baseline_files:tree.length,current_core_files:current.length,counts:comparison.counts,modules,independent:comparison.independent.map(i=>({folder:i.folder,count:i.file_count})),core_snapshot_sha256:fingerprint},null,2));
