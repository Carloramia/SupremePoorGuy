# 2026-10-19 地图资源迁入快照

来源：`D:/GameJamWorkspace/地图编辑器系统合并完整交接包_20261019`。

当前状态为 **运行时已接入，新游戏默认使用新版；旧存档继续使用旧版**。新适配输出在 `Runtime`，通过现有 GameRoot / MapCatalog 按存档版本加载。旧 `FrontierDelivery_20261015` 内容与旧阵容保留，生物与召唤池未改动。详见 [实际接入记录](../../../Docs/Systems/WorldMapUI/新版六边形地图接入_2026-10-19.md)。

已接入 `frontier-map-20261019-r1` 增量补丁。`Source/hex_layout.json` 和 `Source/hex_battles.json` 现为补丁后的权威副本；原始补丁与预览源码保存在 `Source/Patches/frontier-map-20261019-r1`，资料脚本不参与游戏执行。`Migration/patch.json` 记录本次校验与测试，初次迁入的对应表仍保留历史对照。素材路径别名现为 2,643 个，唯一素材文件为 2,225 个。

本轮同步 10,877 格、631 点位与 41 张战场，补入小屋岩石底层；游戏适配器使用精确山体轮廓、像素柔雾、完整近侧岩面和城镇/小屋地面衬底。出生点和小屋交互入口共用美术归一化坐标。战场装饰按新字段抬起 60°，地表贴片保持贴地，摄像机初始俯角为 -50°，独立碰撞/效果区不随美术倾斜。现有容量检查、友左敌右的安全部署、暂停、事件和存档接口继续使用原实现；未绑定的 8 处营地保持禁用。

接入前备份和原始日志位于 `D:/GameJamWorkspace/RuntimeChecks/MapPatch_20261019`；工程内记录见 `Reports/MapPatch_20261019/增量地图补丁接入记录.txt`。重新启动游戏后生效，已运行的游戏不会热替换已加载的地图。

| 目录 | 内容 |
|---|---|
| `Runtime` | 实际游戏使用的索引、42 份地图数据、41 个战场环境、39 份阵容配置、高清分块与 50 份厚片装饰模型 |
| `Source/hex_layout.json`、`Source/hex_battles.json` | 两个唯一源数据的逐字节副本，保留来源路径和指纹，仅供编辑/追溯 |
| `Source/Exports` | 交付的关联表、素材解析、事件参数等派生资料 |
| `Data/hex_layout.json`、`Data/hex_battles.json` | 保留全部数据，只将素材 URI 改为本项目 `res://` 路径的副本 |
| `Data/BattleLevels` | 41 份逐场接入配置，含编译后的真实六边形多边形；素材路径已迁移 |
| `Assets/HexPlanner` | 浏览器地图资产，包括 48 张高清分块、裁切 JSON、85% 树木版本、图标及预览纹理 |
| `Assets/LegacyMaps` | 战场原 `res://Assets/Maps/...` 及嵌套围边引用的原始美术 |
| `Migration/asset_paths.json` | 2,643 条旧 URI → 新 URI；别名合并到 2,225 个资源文件 |
| `Migration/asset_correspondence.json` | 1,753 条素材记录按 `scope + asset_id` 对照现有工程，区分同字节候选、同 ID 内容变化、新素材 |
| `Migration/map_correspondence.json` | 全部 41 张战场的旧/新名称、当前场景、迁入文件、关联点与阵容 ID |
| `Migration/site_correspondence.json` | 631 个点位与当前地点的 ID、坐标、关联战场对照 |
| `Migration/enemy_bindings.json` | 39 处营地的完整敌群、数量、现有阵容文件情况与未绑定物种 |
| `Migration/files.json` | 复制文件 SHA256、逐场派生来源、18 个受保护的现行文件指纹 |
| `Migration/validation.json` | 本次迁移检查结果 |
| `Documentation` | 原对接文档、原始测试结果、缺件与限制记录 |

所有贴图保持原文件字节、透明通道与分辨率。保留 `anchor / width / size / rect / core / offset / clip_asset` 等数据；不重绘、不合并高清分块，不改地图位置、敌群或事件内容。迁移同时覆盖素材记录内部的 `edge_background` 依赖，不能只复制顶层素材列表。

未迁入编辑器、UI 和应用脚本的历史副本，也未将未使用的 TIFF 母版、过期方案、缓存和原工程导入记录复制成运行时资产。原包保留完整原件。新路径由 Godot 自行生成 `.import`，避免复制旧导入 UID 与现有资源冲突；`Source/Documentation/Migration` 使用 `.gdignore` 作为资料目录。

原迁入快照约 419 MiB，保留作追溯资料。导出预设现仅排除 Source/Data/Documentation/Migration/原始 Assets，Runtime 参与导出。源 Assets 不再自动导入重复或隐藏的历史资源，实际使用的贴图已复制到 Runtime/Textures，原图不变。

完整对应关系和下一步见 [资源对应与更新方案](../../../Docs/Systems/WorldMapUI/地图交接包资源对应与更新方案_2026-10-19.md)。

只读复核（在项目根目录执行，Python 需 Pillow）：

```powershell
python Tools/Integration/ImportHexMapHandoff.py --verify
python Tools/Integration/test_import_hex_map_handoff.py
Godot_v4.7.2-stable_win64_console.exe --headless --path . --log-file D:/GameJamWorkspace/RuntimeChecks/HexMapHandoff/godot_validation.log --script res://Tests/Integration/ValidateHexMapHandoff.gd
```

初次迁入使用 `ImportHexMapHandoff.py <交付包目录>`；目标存在时拒绝覆盖，以保护后续手工编辑。再次复核使用 `--verify`。
