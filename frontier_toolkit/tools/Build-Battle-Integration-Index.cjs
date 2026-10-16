// Source audit only. Does not import or execute either Godot project.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const cp = require('node:child_process');
const root = path.resolve(__dirname, '..');
const cache = path.resolve(root, process.argv[2] || '.tools/upstream-ui-20261015');
const out = path.join(root, 'docs/battle_integration');
const git = (...args) => cp.execFileSync('git', ['-c', 'core.quotepath=false', '-C', cache, ...args], {encoding:'utf8'}).trim();
const commit = git('rev-parse', 'HEAD');
const expectedCommit = 'e97c6994152301127fd07b779e1dc32fc940b9c4';
if (commit !== expectedCommit) throw new Error(`Audit is pinned to ${expectedCommit}; review documentation before changing the upstream baseline.`);
const tree = git('ls-tree', '-r', '--name-only', 'HEAD', 'it-is-time').split('\n');
const tracked = new Set(tree);
const groups = {
  host: ['project.godot', 'world_map/core/world_map_controller.gd', 'world_map/core/world_map_autoload_adapter.gd', 'world_map/locations/location_interaction_controller.gd', 'world_map/data/location_definition.gd', 'world_map/data/world_map_runtime_state.gd', 'world_map/save/world_map_save_service.gd', 'world_map/demo/fake_battle_adapter.gd', 'world_map/demo/WorldMapDemo.tscn', 'integration/scenario_overlay.gd', 'integration/scenario_overlay_tests.gd', 'scenario_2_5d/core/scenario_controller.gd', 'scenario_2_5d/data/scene_definition.gd', 'scenario_2_5d/camera/scenario_camera_controller.gd', 'scenario_2_5d/interactables/interaction_controller.gd', 'scenario_2_5d/occlusion/occlusion_controller.gd', 'scenario_2_5d/spawn/spawn_point_3d.gd', 'scenario_2_5d/visuals/billboard_visual_3d.gd', 'scenario_2_5d/demo/Scenario25DDemo.tscn', 'editor/godot/import_level.gd', 'editor/godot/battle_preview.gd', 'editor/docs/DATA_CONTRACT.md', 'ui_module/core/game_ui.gd', 'ui_module/integration/world_map_ui_bridge.gd'],
  ui_v2: ['Scripts/GameDemo.gd', 'Scripts/PrototypeState.gd', 'Scripts/SummonExperiment.gd', 'docs/07_系统接入适配与联调协议.md', 'docs/08_召唤2.0接入与边界.md'],
  combat: ['project.godot', 'ItIsTime.csproj', 'Scripts/Creatures/PhysicalCharacterController.gd', 'Scripts/Creatures/GeneratedCreatureCharacter3D.gd', 'Scripts/Creatures/GeneratedHumanNPCCharacter3D.gd', 'Scripts/Creatures/PhysicalBodyParts.gd', 'Scripts/Creatures/CharacterDamageController3D.gd', 'Scripts/Creatures/NPCStateMachine3D.gd', 'Scripts/Creatures/NavigationNPCSpawner3D.gd', 'Scripts/Creatures/CreatureActionController3D.gd', 'Scripts/Player/PlayerControlContext.gd', 'Scripts/Player/PlayerController3D.gd', 'Scripts/Input/TerrainCursor3D.gd', 'Scripts/Camera/DragCamera3D.gd', 'Scripts/Damage/DamageService.gd', 'Scripts/Damage/DamageRules.gd', 'Scripts/Items/SampleWeapon3D.gd', 'Scripts/Items/InventoryController3D.gd', 'Scripts/VFX/StompShockwave3D.gd', 'Scenes/Creatures/Characters/Generate_Human_NPC.tscn', 'Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn', 'Scenes/Levels/TestLevel.tscn']
};
const entries = [];
for (const [group, files] of Object.entries(groups)) for (const file of files) {
  const relative = group === 'combat' ? `it-is-time/${file}` : group === 'ui_v2' ? `UI跳转原型_20261015/${file}` : file;
  const absolute = path.join(group === 'combat' ? cache : root, relative);
  if (!fs.existsSync(absolute)) throw new Error(`Missing indexed source: ${absolute}`);
  const bytes = fs.readFileSync(absolute), content = bytes.toString('utf8');
  const lines = content.split(/\r?\n/);
  const repoPath = group === 'ui_v2' ? `UI跳转原型/${file}` : relative;
  if (group !== 'host') {
    const blob = crypto.createHash('sha1').update(Buffer.from(`blob ${bytes.length}\0`)).update(bytes).digest('hex');
    if (blob !== git('rev-parse', `HEAD:${repoPath}`)) throw new Error(`Source differs from pinned upstream: ${absolute}`);
  }
  const url = group === 'host' ? null : `https://github.com/Carloramia/SupremePoorGuy/blob/${commit}/${repoPath.split('/').map(encodeURIComponent).join('/')}`;
  const symbols = [];
  lines.forEach((line, i) => {
    if (/^(?:class_name |extends |signal |(?:static )?func [^_]|@export)/.test(line))
      symbols.push({line:i+1, declaration:line.trim(), url:url ? `${url}#L${i+1}` : null});
  });
  entries.push({group, path:relative, workspace_path:path.relative(root, absolute).replaceAll('\\','/'), sha256:crypto.createHash('sha256').update(bytes).digest('hex'), lines:lines.length, url, symbols});
}
// Transitive closure cannot be proven from literals alone: dynamic paths and uid:// need an actual import.
const refs = new Map();
for (const repoPath of tree.filter(p => /\.(gd|tscn|tres|godot)$/.test(p))) {
  const absolute = path.join(cache, repoPath);
  if (!fs.existsSync(absolute)) continue;
  const content = fs.readFileSync(absolute, 'utf8');
  for (const match of content.matchAll(/res:\/\/([^"'\s)\r\n]+)/g)) {
    const resource = match[1], key = `it-is-time/${resource}`;
    if (!refs.has(resource)) refs.set(resource, {resource, status:tracked.has(key) ? fs.existsSync(path.join(cache,key)) ? 'available' : 'tracked_not_checked_out' : 'not_in_git_tree', referenced_by:[]});
    if (!refs.get(resource).referenced_by.includes(repoPath)) refs.get(resource).referenced_by.push(repoPath);
  }
}
const dependencies = [...refs.values()].sort((a,b) => a.resource.localeCompare(b.resource));
const statusCounts = Object.fromEntries(['available','tracked_not_checked_out','not_in_git_tree'].map(s => [s,dependencies.filter(d => d.status === s).length]));
const result = {audit_date:'2026-10-15', upstream_commit:commit, upstream_repository:'https://github.com/Carloramia/SupremePoorGuy', scope:'Static audit; combat checkout is sparse. No import, gameplay or full dependency-closure guarantee.', combat_tracked_files:tree.length, combat_tracked_cs_files:tree.filter(p=>p.endsWith('.cs')), combat_tracked_test_scripts:tree.filter(p=>p.startsWith('it-is-time/Tests/') && p.endsWith('.gd')).length, dependency_counts:statusCounts, entries, dependencies};
fs.mkdirSync(out,{recursive:true});
fs.writeFileSync(path.join(out,'SOURCE_INDEX.json'), JSON.stringify(result,null,2)+'\n');
const md = ['# 源码定位索引（自动生成）','',`审计日期：2026-10-15；上游提交：\`${commit}\`。`, '', '由 `node tools/Build-Battle-Integration-Index.cjs [缓存仓库路径]` 重建。JSON 包含文件 SHA-256、公开方法/信号/导出字段行号及字面量资源引用。行号仅对应本次审计快照。', '', '此索引是静态定位工具，不代表完整资源导入或战斗运行通过。缓存缺少的已跟踪资源归类为 `tracked_not_checked_out`；`not_in_git_tree` 还可能是动态模板或运行时生成文件，需逐项判断。', '', `it-is-time 跟踪文件 ${tree.length} 个，Tests 下 GDScript ${result.combat_tracked_test_scripts} 个，跟踪 C# 源文件 ${result.combat_tracked_cs_files.length} 个。`, '', `字面量资源去重：本地可用 ${statusCounts.available}；上游已跟踪但未检出 ${statusCounts.tracked_not_checked_out}；未匹配 Git tree ${statusCounts.not_in_git_tree}。扫描范围仅为已检出的文本资源。`, '', '| 范围 | 文件 | 行数 | 公开声明数 |','| --- | --- | ---: | ---: |'];
for (const e of entries) {
  const href = e.url || '../../'+e.workspace_path.split('/').map(encodeURIComponent).join('/');
  md.push(`| ${e.group} | [${e.path}](${href}) | ${e.lines} | ${e.symbols.length} |`);
}
md.push('', '完整机器索引：[SOURCE_INDEX.json](SOURCE_INDEX.json)。当前代码解释：[CURRENT_CODE_MAP.md](CURRENT_CODE_MAP.md)。');
fs.writeFileSync(path.join(out,'SOURCE_INDEX.md'),md.join('\n')+'\n');
console.log(JSON.stringify({indexed_files:entries.length, commit, dependency_counts:statusCounts, combat_cs:result.combat_tracked_cs_files.length, combat_tests:result.combat_tracked_test_scripts},null,2));
