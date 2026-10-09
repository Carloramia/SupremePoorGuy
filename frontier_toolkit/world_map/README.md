# WorldMap / Frontier

独立 Godot 4.7.2、GDScript、2D Windows 大地图模块。无外部美术、插件、Autoload 或其他游戏系统依赖。

内容制作见 [地编人员场景编辑使用手册](../docs/LEVEL_DESIGNER_GUIDE.md)，包含地图范围、障碍、地点、道路、存档重置与验收步骤。

Demo 城镇已接入 [2.5D 悬浮场景](../integration/README.md)：弹窗选择 Enter town，返回时结束交互并恢复冻结的大地图。

## 运行 Demo

打开项目根目录的 `project.godot`，F6 运行 `world_map/demo/WorldMapDemo.tscn`，或 F5 运行项目。

GitHub 包不包含 Godot 引擎。先按 [首次运行](../docs/GETTING_STARTED.md) 安装并配置 Godot 4.7.2，再运行：

```powershell
./world_map/tools/Run-Demo.ps1
./world_map/tools/Run-Demo.ps1 -Editor
./world_map/tools/Run-Tests.ps1
./world_map/tools/Run-Tests.ps1 -Render  # 额外验证实际 UI 开关与 Hex debug 图形渲染
```

工具不随 Git 分发；其他成员可传入 `-GodotPath C:\path\Godot.exe`。直接用 Godot 打开时使用标准 user:// 路径；启动脚本将 APPDATA 临时指向项目 `.tools/userdata`，存档因此在 `.tools/userdata/Godot/app_userdata/WorldMap · Frontier/world_map_save.json`。两种启动方式的存档各自独立。

左键点击地面连续移动，包括未探索区域；道路及附近地面点击会吸附到最近的道路中心线。右键按住拖动地图；滚轮缩放；Focus 恢复玩家跟随。地点第一次进入发现范围后显示图标。悬停显示 Tooltip，点击选中地点，然后自动导航并弹出正式 UI。正式 UI 必须完成操作，无法直接取消。Save / Load 提供单槽手动存读档。

Hex debug 使用独立覆盖层，显示有效 Hex 的边界和 `(q, r)` 坐标，位于地表和迷雾之上、玩家/地点及 UI 之下。调试模式可查看迷雾内的逻辑网格；关闭后覆盖层完全隐藏，不改变探索状态或寻路规则。

首次出生只发现 Test Town。向东探索 Bandit Camp、Wandering Monster；向东南探索 Herb Patch；向南探索 Ancient Monument。靠近出生地的问号地点使用山体内的 interaction_point，用于验证不可达地点反馈。棕色带为 Road，深棕色重叠区域为 Mud。Hex debug 默认关闭。

## 目录及职责

| 目录 | 职责 |
|---|---|
| core | 协調模块、对外 API、可选 session adapter |
| data | 地图/地点 Resource，独立运行状态，生命周期 |
| hex | Flat Top axial 公式、有效区域、TileMapLayer 占位地表 |
| navigation | 独立 NavigationServer2D map、静态导航与障碍 |
| player | CharacterBody2D + NavigationAgent2D、速度区域、真实路径 |
| roads | 可编辑道路中心线、道路绘制、速度带和地面点击吸附 |
| camera | FOLLOW_PLAYER / FREE、拖拽、缩放、边界 |
| fog | 512px 宽探索 mask、shader 连续实时视野、轨迹重建 |
| locations | 稳定 ID 注册表、发现、交互协调与生命周期 |
| ui | Tooltip、HUD、四种独立 PackedScene 交互界面 |
| save | JSON 原子替换、验证、版本迁移入口 |
| generation | 固定覆盖优先的生成契约，第一版不做随机算法 |
| demo | 编辑器可调障碍/地点/速度区域及 FakeBattleAdapter |
| debug | 数据验证、28 项运行验收、渲染截图及结果 JSON |

## 地图与导航配置

`demo/data/frontier.tres` 是 Map Definition 示例：width、height、hex_size、disabled_hexes、spawns、发现/交互/视野默认半径均可修改。逻辑使用 axial `(q,r)`；width/height 以 odd-q 视觉矩形投影计数，禁止把 TileMap cell 当持久身份。负坐标转换同样可逆。HexGrid 保存元数据，不创建每格节点。

TileMapLayer 的整数纹理尺寸经过原点和平面比例校正，所有 cell 的视觉中心与 Hex 精确浮点坐标一致，但 TileMap 不持有逻辑身份。Hex border 和坐标只在 debug 下绘制。地图坐标以 WorldMap 根节点为原点；可以平移根节点，核心的两个实例使用独立 Navigation map。根节点和 Locations 容器保持单位缩放及零旋转；这使半径、速度、碰撞和保存位置的含义一致。

Demo 的 Obstacles 子节点是编辑器可调整的 Polygon2D：RockRidge、Lake。加载时根据 enabled Hex 联合集和障碍轮廓静态烘焙一次 NavigationPolygon，创建 NavigationRegion2D 及 StaticBody2D。agent_radius=10、角色碰撞半径=9；导航不会把不可达目标吸附到网格边界。道路的主动点击吸附在寻路之前处理，吸附后的中心线目标仍须完全可达。没有动态烘焙。接入已有手工 NavigationPolygon 时可替换 `WorldMapNavigation.build` 内的静态来源，保持 legal_path 契约。

## 道路配置与点击规则

Demo 的 `Roads/Road` 是主路，`Roads/SouthRoad` 是通往南方事件的支路。每条道路是挂载 `roads/world_map_road.gd` 的 Area2D，继承现有 WorldMapSpeedArea；中心线、路面和加速区域统一从同一组点生成。编辑器中也会显示道路占位视觉。

在 Inspector 配置：

| 属性 | 作用 | Demo 主路默认值 |
|---|---|---|
| center_line | 道路局部坐标折线，至少两个不同的点 | 出生点 → 南绕山体 → 向东延伸 |
| road_width | 路面及速度区域的宽度 | 64 世界单位 |
| snap_margin | 路面边缘外额外的点击吸附距离 | 24 世界单位 |
| speed_multiplier | 道路上的速度倍率 | 1.5 |
| priority | 与其他速度区域重叠时的优先级 | 10 |
| surface_color / edge_color | 路面、边缘占位颜色 | 棕色 |

新增道路：在 `Roads` 下创建 Area2D 并挂载 WorldMapRoad，配置中心线。无需手动创建 CollisionShape2D，加载时生成各段矩形和拐点/端点圆形速度区域。道路为地图静态配置，重启和读档自动加载，不需要修改存档格式。运行时新增时调用 `world_map.roads.register_road(road)`，移除时 unregister_road。

地面点击按如下顺序处理：地点图标优先；合法地面查询最近的中心线投影；距离不超过 `road_width/2 + snap_margin` 时吸附；生成接路导航和沿中心线的路径；最后检查每段是否可通行。远离道路的点击保持原点；原始点击在山体或地图外仍然拒绝；吸附后的点或中心线路径不可达也拒绝，不换用其他目标。目标 marker 和路径都反映实际吸附后的目标。地面点击保持既有地点交互意图，地点点击始终保留其精确 interaction_point。

沿道路移动时，玩家逐段经过中心线的拐点，再进入下一段；主路和支路在公共端点、交叉点或 T 形连接处切换。不会在弯道斜穿地面。道路范围内采用最高 priority 的速度区域，倍率不叠乘。Demo Mud priority=20，会覆盖道路的加速。

`WorldMapRoadRouter` 将折线按连接点拆成路网，选取可通行中心线上的最短道路路径。玩家已在道路上时从当前位置的中心线投影进入路网；道路外使用普通 Navigation 到接路点，然后沿中心线移动。互不连通的道路通过普通 Navigation 接入目标道路。点击远离道路的普通地面或地点交互点，则使用普通 Navigation 离开道路。

中心线每段通过 Navigation 检查；若必须绕障碍才能连接该段，则不允许把该段作为道路捷径。Player 的 `set_move_route` 保存已验证的连续空间路线，精确经过拐点，并显示实际剩余路径；暂停保留路线，改目标替换路线，取消和交互完成清空路线。道路路径不写入存档。

## 增加地点与地点类型

1. 创建 LocationDefinition `.tres`：type_id、名称、描述、颜色/占位 glyph 或 icon、repeatable、completion_behavior、interaction_ui_scene、encounter_data。
2. 在 Locations 下摆放挂载 `world_map_location.gd` 的 Node2D，指定稳定 location_id 和 Definition。
3. position 是图标位置；interaction_offset 是单独的交互点。发现/交互半径为 -1 时取地图默认值。completion_behavior_override 为 -1 时取 Definition，0/1/2/3 分别 KEEP/HIDE_SESSION/REMOVE_PERMANENTLY/RESPAWNABLE。
4. 动态调用 `add_location` 时给出无父节点的 WorldMapLocation；Definition 必须保存为 `.tres` 才能在场景重建后从资源路径恢复。

新增类型时创建继承 LocationInteractionPanel 的脚本和独立 PackedScene，并配置 Definition。UI 通过 `interaction_completed(result)` 返回结果，不直接改玩家或存档。LocationManager 无需增加类型分支。`battle_start_requested` 是异步外部流程的专用信号；其他类型可按同样方式扩展适配器。

统一结果示例：

```gdscript
{"success": true, "action": "collect", "complete_location": true,
 "custom_data": {"collected": 3}}
```

Settlement 的 repeatable=true，始终 AVAILABLE。非重复地点完成时，InteractionController 统一应用生命周期：KEEP→COMPLETED、HIDE_SESSION→HIDDEN_SESSION、REMOVE_PERMANENTLY→REMOVED_PERMANENTLY、RESPAWNABLE→RESPAWNABLE。后三者不显示；永久移除保留状态墓碑以防重建复活。restore/respawn 显式恢复 AVAILABLE；没有时间系统。HIDE_SESSION 只在新场景会话加载时重置；本会话手动 Load 保留隐藏状态。

## External Integration API

将 WorldMapDemo 作为普通子树实例化，或创建使用 WorldMapController 的 Node2D，并注入 WorldMapDefinition。可选直系节点 `Obstacles`、`Locations`；若没有则创建最小空实现。等待 `initialized` 或检查 `is_initialized` 后调用移动/存读档 API。核心不需要 FakeBattleAdapter，集成时可移除 Demo 适配器节点。

| API | 说明 |
|---|---|
| set_move_target(world_position, snap_to_road=false) -> bool | 默认精确目的地；鼠标地面点击传 true 进行道路吸附；普通地面不清除地点意图 |
| select_location(location_id) -> bool | 选择发现且可交互地点；不可达则清空意图 |
| clear_interaction_target() | 显式清除地点意图 |
| pause_movement(reason) / resume_movement() | 保留移动意图的暂停/恢复 |
| cancel_movement(reason) | 停止并清空路径，不自动清除地点意图 |
| set_movement_blocker(reason, blocked) | 外部阻止命令，并暂停移动；多个 blocker 全部释放才恢复 |
| set_world_map_paused(bool) | 暂停整个模块的动态逻辑、输入、移动、相机、迷雾；UI 保持活动 |
| focus_on_player() | 恢复跟随；相机 follow_on_move_command 控制移动命令是否自动恢复跟随 |
| add_location(location) / replace_location(id, replacement) -> bool | 注册或替换；资源路径、空间配置和运行状态可恢复 |
| remove_location(id, permanently=true) -> bool | 生命周期墓碑；false 为本会话隐藏 |
| get_location(id) / has_location(id) | 稳定注册表查询 |
| restore_location(id) / respawn_location(id) -> bool | 恢复 AVAILABLE 并自动保存 |
| resolve_location_interaction(id, result) -> bool | 统一结果回传；只接受对应的活动交互 |
| save_world_map(path="") / load_world_map(path="", new_session=false) -> bool | 单槽 JSON；显式 path 可注入既有存档适配器 |
| export_session() / import_session(data, new_session=false) | 无节点的会话快照/重建 |
| leave_world_map() -> bool | 清理移动并保存；场景宿主切换前调用 |

Controller signals：battle_requested、location_discovered、location_selected、location_interaction_started、location_interaction_completed、invalid_destination、world_map_paused、world_map_resumed、save_completed、load_completed、initialized。player 的移动 signals：movement_started、movement_cancelled、movement_paused、movement_resumed、movement_finished。

模块暂停独立于 SceneTree.paused。交互正式开始时取消路径并暂停模块；完成后清空两个目标、保持当前位置、恢复模块、自动保存。外部系统不应在交互中强制 unpause；应通过统一结果完成交互。

## 外部战斗接入

```gdscript
world_map.battle_requested.connect(func(request: Dictionary):
    # request: map_id, location_id, encounter_data
    # 宿主可导出 session、切换战斗场景；WorldMap 本身不切场景。
    battle_host.start(request))

# 胜利后由外部系统回传；失败/错误使用 success=false，地点保持可用。
world_map.resolve_location_interaction(&"bandits", {
    "success": true, "result_type": "victory",
    "rewards": {}, "custom_data": {}})
```

Start Battle 前保存 player/fog/location/seed 及 pending_battle。重建 Demo 时自动读档，重开对应交互并发出未完成战斗请求。也可关闭 auto_load，再等待 initialized，import_session 后回传结果。宿主应先连接 battle_requested 再添加子树，以接收恢复时发出的请求。可选 WorldMapAutoloadAdapter 提供 retain_session/restore_session/return_battle_result，但项目未注册任何 Autoload。

## 存档与迷雾

单槽 JSON save_version=1。FileAccess 写临时文件，关闭后重命名替换。缺失、JSON 损坏、无效字段类型、版本不支持、map_id 不匹配均返回 false/空状态并给出反馈。migrate_save_data 是版本升级入口。Load 清理移动与交互意图，恢复生命周期和发现状态，从轨迹重建 fog mask，然后重新计算当前可见圆。

探索样本包含 position、radius，移动样本额外包含 from。from→position 代表该段连续移动扫过的圆形视野，即 capsule。直线相邻段合并，重复样本去重；不靠丢弃距离阈值内的圆改变探索区域。曲线路径保留实际转折，因此复杂探索仍可能增长；纹理固定为低分辨率，数据不绑定 shader/image。当前视野每帧由 shader 更新，边缘 smoothstep；无 LOS。

## Spawn、视觉与生成器

新增地图：建立新的 WorldMapDefinition，使用新的 map_id 和独立 save_path，复制/实例化场景并配置地点/障碍。spawns 为 spawn_id→Vector2，首次入图取 root.spawn_id 或 default_spawn_id，存档存在时优先保存位置；无效入口警告并回退默认入口。返回战斗不恢复旧路径。

根节点导出 player_speed 和 player_visual_scene，替换美术只需注入视觉 PackedScene，移动接口无需改变。LocationDefinition.icon 可替换 marker fallback。地表替换 terrain_layer，fog 及数据无需改动。

WorldMapGenerator.generate(definition, seed, fixed_overrides) 返回 WorldMapGenerationResult：hex_overrides、locations、metadata。第一版仅返回固定配置；hex_overrides 的键为 `"q,r"`，值为 enabled/terrain/custom，locations 描述包含 id、Definition 资源路径、位置和 interaction_offset。定义中的 disabled Hex 及已摆放的固定地点优先；未来随机实现不得覆盖它们。替换生成器应在场景入树前设置 `world_map.generator`。固定 Hex 覆盖在一次静态烘焙前应用，生成地点通过 manager 注册。运行时显式 replace 的描述另有 overrides_scene=true，允许还原用户主动替换的定义。

## 验证

`Run-Tests.ps1` 运行 400 组坐标可逆检查及 28 项真实 SceneTree 验收；结果位于 `debug/test_results.json`。`render_preview.gd` 使用真实 OpenGL 渲染并保存 8 张 UI/地图截图。概览图是调试脚本探索全图后的状态，首次启动仍只有出生点附近可见。详见本模块 docs/ 中的测试清单及实施报告。

道路验收：`road_tests.gd` 的 28 项结果保存为 `debug/road_test_results.json`，Run-Tests 默认运行，包含弯道实际轨迹、支路连接、接路、反向移动及中断接口。`Run-Tests.ps1 -Render` 额外验证 Hex debug 显隐以及道路实际渲染、鼠标吸附和中心线拐点路径，保存 `debug/preview_roads.png`、`debug/preview_road_snap.png` 和 `debug/preview_road_bends.png`。
