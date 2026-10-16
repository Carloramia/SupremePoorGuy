# 当前代码与 GitHub PR 版本差异说明

本文保留 GitHub 打包整理之前的工作区审计快照。后续交付已补 BUILD.md 并纳入新版 UI/TA；最新包结构与范围见 [RELEASE_CONTENTS.md](RELEASE_CONTENTS.md)。下面的数量、哈希和旧打包范围对应当时快照，不表示整理后最新版本。

当前版本在 PR #1 的大地图、2.5D 场景和地编工具集上，新增了原生 UI 模块、独立 Shader 材质实验台、新版 UI Shader 测试工程，以及 it-is-time 战斗对接设计。**实际战斗仍由 FakeBattleAdapter 占位；新版 UI 0.7.12 尚未替换宿主正在使用的 0.5 UI。**

PR 原有的大地图寻路、迷雾、道路、地点存档及 2.5D 场景交互逻辑保持原有实现。核心目录按相同相对路径比较后，原有 249 个文件中只有 9 个存在内容变更；另有 39 个仅格式变化、2 个仅导出节点 ID 变化、1 个当前缺失。当前核心范围新增 185 个文件，其中 169 个位于 ui_module。

## 比较版本与范围

| 项目 | 版本依据 |
| --- | --- |
| GitHub 仓库 | [Carloramia/SupremePoorGuy](https://github.com/Carloramia/SupremePoorGuy) |
| 历史 PR | [#1 新增独立大地图、2.5D 场景与地编工具集及构建指南](https://github.com/Carloramia/SupremePoorGuy/pull/1) |
| PR 提交 | [`a36c06ff1b2313351f85e2d31b4de86d117ab377`](https://github.com/Carloramia/SupremePoorGuy/commit/a36c06ff1b2313351f85e2d31b4de86d117ab377) |
| PR 基础提交 | `1295c61f672ca80f1856ad25ea413efef34bbc5f` |
| PR 合并状态 | 已合并；北京时间 2026-10-15 19:45:31；merge commit 为 `5c6568c144d7c38665f6735574bdc9192df57d77` |
| 当前比较对象 | 2026-10-15 的当前工作目录文件快照，核心根为 `E:/gamejam` |
| 比较路径 | PR 的 `frontier_toolkit/<相对路径>` ↔ 当前 `<相对路径>` |

PR 的代码基线采用其 head 提交，不采用 PR 最初的 base，也不采用后续 main。这避免把主仓库后续的召唤、美术、怪物等变更误算成当前工具集的改动。PR 本身共有 251 个变更文件，其中工具集目录 249 个，另两个是上级仓库 README 和 `.github/workflows/frontier-toolkit.yml`。

当前根仓库分支 `codex/map-toolkit` 尚无 HEAD 提交，源文件在 Git 状态中显示为 untracked；因此本比较直接读取 PR 的 Git blob 与当前文件，不使用 `git diff HEAD`。**这里记录的是文件差异，不能将其理解为这些差异已提交或已上传 GitHub。** PR 已合并只确认历史 PR 的内容进入主分支。

元数据快照见 [PR_BASELINE.json](pr_version_diff/PR_BASELINE.json)，逐文件数据见 [FILE_DIFF.json](pr_version_diff/FILE_DIFF.json)、[CSV 清单](pr_version_diff/FILE_DIFF.csv) 和 [分类索引](pr_version_diff/FILE_DIFF.md)。

### 文件计数口径

核心范围包括 PR 已有的根配置、world_map、scenario_2_5d、editor、integration、docs、tools、.github，以及新 ui_module。引擎、缓存、Git 目录、dist、导入记录、日志、临时文件、存档及测试结果输出不计入。保留运行素材、脚本 UID、已有截图、来源清单和交接验证记录。

`UI跳转原型/`、`UI跳转原型_20261015/` 和 `shader需求/` 另列当前清单，不混入核心 185 个新增文件。它们不在历史 PR 的 frontier_toolkit 文件集合内。`.tools` 下的 it-is-time 稀疏审计缓存、历史下载包和提示词草稿也不算正式源码增量。

本次说明文档、比较工具和 `docs/pr_version_diff/` 输出作为本次交付单列，不计入被比较快照；README 中新增的文档导航仍计入 README 内容变更。

## 文件差异统计

| 模块 | 完全相同 | 内容修改 | 仅格式 | 仅生成 ID | 当前缺失 | 新增 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 根配置与说明 | 4 | 3 | 0 | 0 | 1 | 0 |
| world_map | 102 | 1 | 5 | 0 | 0 | 0 |
| scenario_2_5d | 31 | 0 | 33 | 0 | 0 | 0 |
| editor | 50 | 0 | 1 | 2 | 0 | 0 |
| integration | 5 | 1 | 0 | 0 | 0 | 0 |
| docs | 2 | 2 | 0 | 0 | 0 | 12 |
| tools | 3 | 2 | 0 | 0 | 0 | 4 |
| .github | 1 | 0 | 0 | 0 | 0 | 0 |
| ui_module | 0 | 0 | 0 | 0 | 0 | 169 |
| 合计 | **198** | **9** | **39** | **2** | **1** | **185** |

当前核心范围共 433 个文件，计算为 `249 - 1 + 185`。9 个内容修改由 5 个说明文档、2 个运行入口/界面文件和 2 个交付工具组成；不能把文件数量直接当作玩法改动数量。

“仅格式”只归一化 UTF-8 BOM、CRLF/LF 和文件末尾多余换行，不忽略代码内部缩进。“仅生成 ID”仅指 `.tscn` 的数字 `unique_id`。详细哈希保留原始字节，仍能看到这两类变化。

## 运行行为差异

| 能力 | PR #1 版本 | 当前版本 | 对使用者的影响 |
| --- | --- | --- | --- |
| F5 默认入口 | WorldMapDemo | UIWorldMapDemo | 默认进入带召唤、仓库、队列入口的真实大地图 |
| 地图 UI | 原调试栏、反馈与地点面板 | GameUI + WorldMapUIBridge 包装 | 原调试栏在嵌入模式隐藏，地图命令由新界面转发 |
| 召唤与库存 | 工具集无独立召唤 UI 模块 | 基于 UI 0.5 的原生召唤、仓库、详情、队列 | 新增独立 UI session；与地图存档仍分开 |
| 地图寻路与道路 | 已实现并有回归 | 核心未改 | 仍由 WorldMapController 和原道路系统负责 |
| 城镇 2.5D 进入与返回 | 已有 SubViewport 悬浮场景 | 原实现保留 | UI 模块配合原暂停状态；没有替换城镇业务 |
| 2.5D 相机与遮挡 | 正交、拖动缩放、拾取、淡化 | 逻辑未改，仅格式差异 | 没有新增自动战斗或实际导航烘焙 |
| 地编编辑与转换 | 已有工具和预览转换 | 实现未改 | 两份导出示例仅重生成节点 ID |
| UI Shader | 无本轮 UI 材质库 | S1/S2/S3 实验台及新版插槽适配 | 独立场景可验证，正式页面尚未批量启用 |
| 实际战斗 | FakeBattleAdapter | 仍为 FakeBattleAdapter | it-is-time 接入目前是技术设计，非运行功能 |
| 战斗存档与奖励 | 外部适配的占位结果 | 当前接口保持占位行为 | 新 BattleRequest/Result 和台账只在文档中定义 |

### 默认启动入口

[project.godot](../project.godot) 的唯一内容变化是：

```diff
-run/main_scene="res://world_map/demo/WorldMapDemo.tscn"
+run/main_scene="res://ui_module/demo/UIWorldMapDemo.tscn"
```

新 [UIWorldMapDemo.tscn](../ui_module/demo/UIWorldMapDemo.tscn) 继续实例化原 WorldMapDemo，并增加 GameUILayer。地图主控制器、玩家、道路、迷雾、地点、FakeBattleAdapter 和 ScenarioOverlay 继续使用原节点。

仍依赖项目默认入口的启动脚本会随此配置进入新 UI。要单独验证 PR 风格的大地图，可显式指定旧场景：

```powershell
& $env:GODOT_BIN --path . res://world_map/demo/WorldMapDemo.tscn
```

Godot 版本特性、GL Compatibility、窗口基准尺寸及拉伸配置没有由本次入口变化而改变。当前工程也未因此转为 it-is-time 的 Jolt/Forward Plus 工程。

## 原有文件的内容修改说明

| 文件 | 具体变化 | 影响 |
| --- | --- | --- |
| [project.godot](../project.godot) | F5 入口切换到 UIWorldMapDemo | 改变默认运行场景 |
| [world_map/ui/world_map_ui.gd](../world_map/ui/world_map_ui.gd) | 为动态 UI 增加 Root、MapHeader、MapToolbar、MapFeedback 四个固定节点名 | 供 UI bridge 查找和隐藏旧界面；没有修改寻路、地点或存档逻辑 |
| [tools/Build-GitHub-Package.ps1](../tools/Build-GitHub-Package.ps1) | 白名单增加 ui_module，移除 BUILD.md | 新 UI 模块进入工具集源码包；旧统一构建指南不再被打包 |
| [tools/Verify-Package.cjs](../tools/Verify-Package.cjs) | 必需入口从 15 个增至 18 个；增加 `.gd` 的 preload/load/extends 资源扫描；跳过独立 project.godot 和 .gdignore 目录 | 验证新 UI 引用，避免将独立原型工程当宿主路径解析 |
| [README.md](../README.md) | 新 UI/Shader 入口、运行与测试命令、战斗文档导航 | 面向当前根目录组织；不再含历史 BUILD.md 入口 |
| [CHANGELOG.md](../CHANGELOG.md) | 增加 2026-10-13 UI 模块交付记录 | 记录来源版本、组合方式与测试范围 |
| [docs/GETTING_STARTED.md](GETTING_STARTED.md) | 补 UI 默认入口、运行与验证命令 | 新克隆的操作说明变化 |
| [docs/ARCHITECTURE.md](ARCHITECTURE.md) | 增加 GameUI/WorldMapUIBridge 依赖和真实战斗设计入口 | 明确 UI 接入与尚未实现的战斗边界 |
| [integration/README.md](../integration/README.md) | 增加 it-is-time 技术对接文档链接，说明城镇窗口边界 | 只有说明修改，scenario_overlay.gd 运行代码保持原版 |

### 格式与导出数据差异

scenario_2_5d 的 64 个原有文件中，31 个字节一致、33 个仅格式变化，没有内容逻辑新增。相机、纸片 Shader、遮挡脚本和 Demo 中看到的部分增行是文件末尾空行。

world_map 的 108 个原有文件中，102 个字节一致、5 个仅末尾空行等格式变化，只有 world_map_ui.gd 增加上述节点名。`WorldMapController`、地点交互、FakeBattleAdapter、保存服务和地图数据类均未因 UI 接入而改写。

editor 的两个导出 `.tscn` 内容差异均为生成节点 `unique_id`：`editor/exports/frontier/frontier.tscn` 与 `editor/exports/camp_battle_01/camp_battle_01.tscn`。地图对象、位置、碰撞、道路和 encounter 数据保持原配置；这不构成新增玩法。

### 当前缺失文件

历史 [`frontier_toolkit/BUILD.md`](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/BUILD.md) 在当前工具集根目录缺失。其构建步骤部分分散在 GETTING_STARTED、模块 README 和 GITHUB_UPLOAD 中；新版独立 UI 内的 BUILD.md 只覆盖该独立工程，不能替代工具集总指南。

下一次提交应明确选择：恢复并更新根 BUILD.md，或同步修改上级仓库首页及 PR 后续说明，避免已合并版本入口仍指向旧指南。本次只记录差异，未自动恢复或删除其他文件。

## 新增原生 UI 模块

ui_module 是 PR 中完全没有的模块，核心比较口径下包含 169 个文件：

| 范围 | 文件数 | 作用 |
| --- | ---: | --- |
| prototype | 98 | 迁移后的 UI 0.5 脚本、场景、素材、主题和原型测试 |
| shader_lab | 53 | 本轮 S1/S2/S3 材质、组件、预设、独立场景及截图 |
| core / demo / integration | 6 | GameUI 门面、两个 Demo、WorldMapUIBridge 及 UID |
| tests | 7 | 宿主集成测试、UID、4 张截图及扫描隔离文件 |
| tools | 2 | 独立/嵌入运行与测试脚本 |
| README、UPSTREAM、source-manifest | 3 | 使用说明及来源追溯 |

### 运行组合

[GameUI](../ui_module/core/game_ui.gd) 继承迁移后的 GameDemo，提供 `open_summon/open_warehouse/open_party`、`is_blocking`、`set_external_blocked` 等入口，以及 blocking_changed、map_command_requested、summon_committed 信号。

[WorldMapUIBridge](../ui_module/integration/world_map_ui_bridge.gd) 在地图上组合 UI，通过现有 API 保存/读取地图、跟随玩家和切换调试显示。打开阻挡 UI 时取得地图暂停所有权，关闭时只释放自己取得的暂停；已有地点交互继续持有其原有流程。空白 UI 区域允许地图接收鼠标。

嵌入模式屏蔽原型自己的地点点击与跳过战斗路径，避免其测试地点和测试奖励覆盖真实地图入口。召唤提交信号发生在原型保存成功之后，外部监听不能再次扣费或生成一份怪物。

### 数据和版本边界

当前宿主 UI 来源为固定上游提交 `43f4e54f9beaa0341f7dc58a0e35680b27c513de`，原型 0.5；完整原始清单为 171 个文件，独立参考副本在 `UI跳转原型/`。运行副本重写 res 路径到 `ui_module/prototype/`，并增加宿主上下文和独立存档。

当前宿主采用旧规则：7 枚符文、常规召唤 3 个实例、6 只队列上限。UI 存档为 `user://ui_module_session.json`，地图仍使用自己的存档。这里新增的是原型 UI 事务与界面组合，尚未接入正式怪物生成服务、物理模型、战斗能力或统一库存。

## 两套 Shader 工程的区别

### 宿主内 Shader 实验台

新增 [ui_module/shader_lab](../ui_module/shader_lab/README.md)，入口为 `ShaderLab.tscn` 和 `ComponentWorkshop.tscn`。内容包括：

- S1 手绘墨线与九宫格边框，支持纹理笔触、粗细、偏折、复笔和断墨。
- S2 基于 Alpha 剪影的连续剪纸白底与内孔填白。
- S3 纸面颗粒、局部毛边与底纸效果。
- 轻、中、强与分项预设，原始/S1/S2/S3/组合五组对照，组件状态与多分辨率验证。

这套 UI 材质与 PR 已有的 `scenario_2_5d/visuals/paper.gdshader` 不同：后者是 3D 纸片深度/透明视觉，当前逻辑未变。新 UI Shader 不负责物理碰撞、角色受伤或结算，尚未批量替换宿主全部 UI 页面。

### 新版 UI 独立适配工程

`UI跳转原型_20261015/` 来源固定为上游提交 `e97c6994152301127fd07b779e1dc32fc940b9c4` 的 UI 0.7.12，287 个上游文件保持原始字节。新增内容单列在 TA、测试、Tools 和 .handoff 中，详见 [该工程 BUILD.md](../UI跳转原型_20261015/BUILD.md)。

新增 TA 适配复用新版 UISkinPreset 插槽，提供 ShaderComparison 和 NativeSkinPreview 两个独立场景；ShaderSkinBinding 负责准备剪影和装饰绘制锚点，保持原控件布局与输入。原型默认主场景没有批量启用新材质。

| 项目 | 当前宿主 UI | 新版独立 UI |
| --- | --- | --- |
| 基础版本 | 0.5 | 0.7.12 |
| 常规召唤与符文 | 3 个实例、7 符文 | 5 个实例、14 符文，召唤 2.0 |
| 队列 | 旧 6 只限制 | 6 队位；普通 1、巨化每只 2、超巨化 5、缩小同批整组 1 |
| 地图接入 | 已通过 WorldMapUIBridge 组合真实地图 | 独立原型；没有自动升级宿主 |
| Shader | 独立 shader_lab | TA 插槽独立预览/应用/撤回 |
| 默认状态 | 宿主 F5 | 导入该独立 project.godot 后 F5/F6 |

比较清单按过滤后的文件计数记录旧参考目录 140 个、新独立目录 312 个和 shader需求 1 个。它们与来源清单的 171/287 不同，是因为本比较排除了 `.import`、Tests/.runtime 中的运行时存档/测试结果和缓存；不能把这组过滤后数量当作“上游原文件未完整获取”。

## 战斗对接部分的新增内容

PR 已明确将正式伤害、控制、自动部署与奖励留给外部游戏系统。当前版本进一步确认外部系统为 it-is-time，并新增 12 个文档/契约文件和两个审计校验工具：

- [战斗技术主文档](BATTLE_INTEGRATION_GUIDE.md)、代码地图、实施步骤与验收矩阵。
- 拟定 BattleRequest/BattleResult 的 JSON Schema、示例和跨字段检查。
- 51 个关键源文件的公开接口、行号、哈希和固定上游链接。
- 跨 World3D 的特效/掉落/目标查询、Input 门禁、可逆暂停、部件失能、有限波次和幂等存档方案。

这些交付把“外部游戏接入”细化为可实施工作清单，尚未创建运行时 BattleHostBridge、BattleSessionCoordinator 或 SessionStore。当前 `integration/scenario_overlay.gd` 仍按城镇访问返回，`LocationInteractionController.resolve()` 仍会在保存确认前清理/解冻。文档中提出的修复不能列为已经完成的代码功能。

it-is-time 脚本只在 `.tools` 稀疏缓存中用于审计，不是宿主新的运行依赖；本次差异统计不将其上游演进计为当前新增战斗代码。固定战斗审计版本 e97c699 与历史 PR head a36c06f 用途不同，后续实施还需完整导入资源并确定正式工程基线。

## 构建和 GitHub 交付差异

### 默认源码包

当前 Build-GitHub-Package 增加 ui_module，因此新 GameUI、宿主 Shader 实验台、文档和工具可以进入工具集包。**默认白名单未包含 `UI跳转原型_20261015/`、旧参考目录和 shader需求**；运行脚本生成的常规工具集 ZIP 不等于包含全部本次独立工程成果。

如果下一次交付需要新版 TA 工程，应单独打包或明确扩展交付清单；不能仅检查宿主 Verify-Package 通过就宣称它也已打包。新 battle 索引重建工具依赖本地审计缓存，缓存不入包；交接方可读现有索引，需要重建时另行准备固定提交仓库。

### 上传路径与 CI

当前目录是工具集根；回到 SupremePoorGuy 完整仓库时，保持 `frontier_toolkit/` 一层映射，不要把当前 project.godot 覆盖到 it-is-time 的 project.godot，也不要把全部 .tools、dist、github_pull 和用户存档上传。

历史 PR 的上级 `.github/workflows/frontier-toolkit.yml` 在 `frontier_toolkit` 工作目录执行 Node 检查；当前工具集内部 `.github/workflows/editor-checks.yml` 内容未改。下一次合并应保留上级 CI 的工作目录配置。把工作流放在 `frontier_toolkit/.github/` 下不会使它自动成为上级仓库根 Actions 工作流。

新增旧/新 UI 双版本与 Shader 素材时，应保留来源清单和独立 project.godot 的边界。不能把新版 Scripts/Scenes 直接覆盖 ui_module/prototype：两者规则、路径、存档和 TA 插槽均不同。

## 验证结果与比较方式

| 范围 | PR 记录 | 当前可追溯结果 | 解读 |
| --- | --- | --- | --- |
| 资源引用 | PR 说明记录 80 条 | 当前 Verify-Package 277 条、18 个必需项通过 | 增加 UI，同时扫描由 tscn/tres 扩展到 gd；两数字不是同一口径的功能数量 |
| 大地图/道路/2.5D/城镇窗口 | 已有回归 | 28/28、28/28、42/42、14/14，共 112 项通过；另有数据校验 | 核心基础设施回归；不包含真实物理战斗 |
| 宿主 UI | 无该模块 | 保存结果为 257 规则、436 布局、43 美术、50 宿主集成，均 0 失败 | 结果文件为当前已有记录，本轮文档比较未重跑图形测试 |
| 旧 Shader 实验台 | 无该实验台 | 记录为 headless 51、GPU 77，0 失败 | 两种模式有重叠，不相加当独立用例 |
| 新版 UI 与 TA | 不含新版工程 | [TA 记录](../UI跳转原型_20261015/TA/VALIDATION.json)：上游 1789、Shader headless 82、GPU 118，通过 | 同样不把重叠 Shader 检查相加；未验证移动性能 |
| 战斗协议文档 | 无 | 25 个契约检查、64 个本地链接、51 个源码哈希通过 | 文档和数据检查，不证明实际战斗已接入 |

基础回归与战斗文档检查见 [战斗验收记录](battle_integration/VALIDATION.json)；旧 Shader 记录见 [VERIFICATION.md](../ui_module/shader_lab/VERIFICATION.md)。本轮只读比较和文档检查不重复声称这些历史 GPU 测试是本轮新执行结果。

重建比较数据：

```powershell
node tools/Compare-PR-Workspace.cjs
node tools/Compare-PR-Workspace.cjs --check
node tools/Verify-Package.cjs
node tools/Verify-Battle-Integration-Docs.cjs
```

Compare 工具读取本地历史 PR Git 对象，优先使用 `.tools/frontier-pr/frontier_toolkit` 中可校验的基线文件；如字节不匹配则从 Git blob 读取。它不 checkout、reset、commit 或 push，不修改被比较源码。输出 SHA-256、CSV 和分类索引；`--check` 仅核对现有快照和文档链接，不重写文件。当前源码再次改动后需要重建，不能继续沿用旧快照统计。

## 下一次 PR 应明确说明的范围

下一次 PR 的可交付范围应分成：原生 UI 与地图组合、宿主 Shader 实验台、新版独立 TA 工程、战斗接入设计。标题和说明应覆盖最终实际提交内容，并明确正式战斗仍待实施。

提交前处理根 BUILD.md 的入口一致性，确认新版独立工程是否纳入交付，保留上级 CI 路径，排除缓存/存档，并在固定目录映射后复核文件差异。39 个纯格式变化和 2 个生成 ID 变化可在后续提交整理时独立处理，避免干扰代码评审；本次没有替用户撤销这些文件变化。
