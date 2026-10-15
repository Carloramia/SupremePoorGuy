# WorldMap 实施报告

## 道路功能更新

新增 `roads/world_map_road.gd`、`roads/world_map_road_manager.gd`。Demo 原矩形 Road 速度带替换为可编辑中心线主路与南向支路，绘制棕色路面、圆角及中心线，沿同一几何生成速度区域。道路 speed_multiplier=1.5、priority=10，Mud 仍以 priority=20 覆盖减速并绘制在路面上方。

鼠标点击道路或靠近道路的合法地面，目标吸附到所有道路中最近的中心线位置，并生成沿中心线路网的路径。吸附距离为道路半宽 + snap_margin；默认额外范围为 24 世界单位。远处点击保持原坐标，地图外/障碍内点击、不可达的吸附点或中心线路径均拒绝。地点图标优先消费点击，interaction_point 不吸附；普通地面/道路命令仍保留当前地点交互意图。

`set_move_target(point, snap_to_road=false)` 新增可选参数，默认保持原有外部 API 的精确目标语义。道路为静态场景配置，兼容既有存档，无须重置进度。编辑器可修改 center_line、road_width、snap_margin、speed_multiplier、priority 及路面颜色。

道路首次实现验证 17 项全部 PASS；中心线跟随扩展验证包括弯道、支路连接、接路导航、暂停/恢复、反向改目标、取消、段内交叉点和被障碍阻断的道路。结果及截图：`world_map/debug/road_test_results.json`、`preview_roads.png`、`preview_road_snap.png`、`preview_road_bends.png`。Run-Tests 默认包含道路测试，-Render 包含道路和 Hex debug 图形回归。

本次修改：Controller 的地面输入与可选吸附 API、Navigation 的合法地面和直线可通行检查、SpeedArea 的编辑器预览支持、Demo 道路和 Mud 绘制层、Player 连续路线跟随、测试启动脚本及文档。新增 `debug/road_tests.gd`、`debug/road_render_preview.gd`、`roads/world_map_road_router.gd`。道路使用路网最短中心线路线，玩家精确经过拐点，不斜穿弯道；普通地面继续使用 Navigation 最短路径。

## Hex debug 修复记录

开关信号正常，原网格绘制在 TileMapLayer 自身的 `_draw` 中，被内部瓦片绘制层和 Fog 遮挡。改用 `world_map/debug/hex_debug_overlay.gd` 独立 Node2D 覆盖层，z_index=6，在 Fog 之上、路径/玩家/地点之下；逆变换保持逻辑坐标与地表一致。默认隐藏，`terrain.show_hex_debug` 控制显隐。

新增真实 UI 点击与截图像素对比回归 `hex_debug_render_test.gd`。开启有 17,251 个地图像素变化，关闭恢复原图，测试 PASS；原有 28 项验收和 400 组数据验证全部 PASS。`Run-Tests.ps1 -Render` 可复现。

实施日期：2026-10-06。目标及实际验证引擎：Godot 4.7.2 stable official。原目录只有提示词，现已建立可运行的独立 Godot 项目。

## Implemented

- Flat Top axial 坐标、odd-q TileMap 投影、负坐标可逆转换、邻居/距离/范围、独立 Hex 元数据和 disabled 区域。
- TileMapLayer 无美术地表、可切换 Hex overlay、视觉中心与逻辑 Hex 对齐。
- CharacterBody2D + NavigationAgent2D 连续移动，两个不规则编辑器障碍，实际绕行路径、终点 marker、重定向和不可达拒绝。
- CANCEL / PAUSE / resume 和外部 movement blocker；两个重叠 Area2D 的最高 priority 速度覆盖。
- 相机跟随、右键拖动、滚轮缩放、边界、focus、可配置命令恢复跟随。
- 圆形连续实时视野和柔和边缘；UNEXPLORED / EXPLORED / VISIBLE；capsule 探索轨迹、无损直线合并、低分辨率 mask 重建。
- 数据驱动地点、永久发现、视野外低透明度 marker、Tooltip、独立 interaction_point、保留/替换地点意图、仅选中地点自动交互。
- 四个独立正式 UI，模块级暂停，无法直接取消交互，统一结果和生命周期处理。
- KEEP / HIDE_SESSION / REMOVE_PERMANENTLY / RESPAWNABLE；恢复接口、运行时增删替换注册表、重建描述和移除墓碑。
- JSON 单槽手动存读档、自动保存、临时文件替换、版本/字段验证、缺失/损坏/错地图反馈。
- 外部 battle_requested / resolve API，FakeBattle 胜利/失败/错误，pending battle 场景重建及继续请求。
- 多 map_id、多 spawn_id 接口、独立导航 map、固定覆盖生成器契约、可选 Autoload/session adapter。

## Architecture

详见 `WORLD_MAP_ARCHITECTURE.md`。核心以引用、信号、Resource 和纯数据状态连接子系统。没有 Autoload 配置、BattleManager 依赖、全局暂停、Hex 节点或全 SceneTree 地点扫描。普通地面移动与地点交互意图分离；交互完成统一清目标并保存。

## Files Added

项目配置：`project.godot`、`.gitignore`、`Run-Demo.ps1`、`Run-Tests.ps1`。

文档：本报告、`WORLD_MAP_IMPLEMENTATION_PLAN.md`、`WORLD_MAP_ARCHITECTURE.md`、`WORLD_MAP_TEST_CHECKLIST.md`、`world_map/README.md`。

模块源文件及配置详见下方文件清单。Godot 工具位于忽略的 `.tools/godot/`；编辑器缓存 `.godot/` 和测试临时 JSON 不纳入模块。`debug/preview_*.png` 为真实运行截图，并非游戏依赖资源。

## Files Modified

没有修改任何既有项目文件：初始目录没有 Godot 工程。原提示词 Markdown 保持原样。开发过程中修改的文件全部是本次新增文件。

## Public API

详见 `world_map/README.md` 的 External Integration API 表。

集成：实例化 WorldMap 子树并等待 initialized；调用 set_move_target / pause_movement / resume_movement / cancel_movement；通过 add_location / remove_location / replace_location / restore_location / respawn_location 管理地点；通过 save_world_map / load_world_map 或 export_session / import_session 持久化。

战斗：连接 battle_requested，接收 map_id / location_id / encounter_data；外部决定场景切换，返回后调用 resolve_location_interaction。核心不进入战斗场景。正式交互期间只有 WorldMap 暂停，外部系统及 UI 继续执行。

## Demo

运行 `Run-Demo.ps1`，或用 Godot 打开 `project.godot` 按 F5。独立场景入口为 `world_map/demo/WorldMapDemo.tscn`，可按 F6 运行。无需额外 InputMap；使用明确鼠标按钮输入。

初始在 harbor 出生，Test Town 可见。探索发现 Herb Patch、Ancient Monument、Bandit Camp、Wandering Monster。额外 BlockedSite 的 interaction_point 位于山体内，验证不可达地点。Road priority=10 / multiplier=1.5；Mud priority=20 / multiplier=0.5。交互完成后不恢复旧路径。

## Save Format

```json
{
  "save_version": 1,
  "map_id": "frontier",
  "player_position": {"x": 120.0, "y": 220.0},
  "active_spawn_id": "harbor",
  "exploration_samples": [
    {"from": {"x": 120.0, "y": 220.0},
     "position": {"x": 180.0, "y": 220.0}, "radius": 210.0}
  ],
  "location_runtime_states": {
    "town": {"discovered": true, "lifecycle": 0, "visits": 1, "custom_data": {}},
    "herbs": {"discovered": true, "lifecycle": 3, "visits": 1, "custom_data": {"collected": 3}}
  },
  "discovered_locations": ["town", "herbs"],
  "removed_locations": ["herbs"],
  "procedural_seed": 2026,
  "procedural_results": {"hex_overrides": {}, "locations": [], "metadata": {"seed": 2026}},
  "pending_battle": {}
}
```

位置是地图局部坐标，探索记录也是局部坐标。正式存档保存轨迹，不保存 GPU 纹理、Node 或 Navigation path。JSON 生命周期数值对应 AVAILABLE=0、COMPLETED=1、HIDDEN_SESSION=2、REMOVED_PERMANENTLY=3、RESPAWNABLE=4。pending_battle 非空时包含异步外部请求。

## Known Limitations

第一版按需求不实现真正战斗/剧情/商店/库存/时间/任务、LOS、动态障碍重烘焙、联网、角色动画或复杂随机生成。图形为程序占位，UI 为英文 Demo；不可达反馈附带中文。

静态导航在加载时从编辑器轮廓烘焙一次，包含角色半径产生的边缘余量。根节点允许平移，要求单位缩放和零旋转。当前地点数量较少，发现/命中直接遍历 registry。曲线探索保留转折，长时间高度复杂轨迹仍会增长；没有有损历史压缩。

动态地点若要跨场景恢复，Definition 应保存为 Resource 文件。宿主场景切换前必须调用 leave_world_map 或 session adapter；普通地面连续移动没有按帧自动存档。多个地图各自配置 save_path，默认值是单槽 Demo。没有导出 Windows 分发 EXE 或 export templates；交付为可直接运行的 Godot 项目。

## Test Results

Godot headless 导入与主场景运行通过；400 组 Hex world/axial/cell roundtrip 检查通过。28 项 SceneTree 验收全部 PASS，逐项结果见本报告下方及 `WORLD_MAP_TEST_CHECKLIST.md`、`world_map/debug/test_results.json`。

导航测试实际沿路径移动抵达终点，两个不规则障碍都验证绕行；存读档后 fog mask 字节完全一致。额外覆盖了真实 viewport UI/地点输入路由、多实例平移隔离、异步战斗场景重建、动态地点替换及 malformed schema。损坏 JSON 测试产生的 warning 是预期错误处理。

使用 NVIDIA RTX 4070 SUPER / OpenGL Compatibility 实际渲染八张截图并检查地图、柔和迷雾、实际路径、Settlement / Resource / Event / Battle 四种 UI 及 FakeBattle。截图位于 `world_map/debug/preview_*.png`。概览使用调试脚本探索全图，不能代表新存档初始可见状态。

## Recommended Next Steps

接入实际战斗宿主及团队 SaveManager adapter；用正式地表和角色视觉替换占位；依据真实地图大小及地点数量再决定空间索引和探索轨迹压缩。

## 逐项验收结果

| Test | 验收项 | 结果 |
|---|---|---|
| 1 | 普通移动、真实路径与绕山体抵达 | PASS |
| 2 | 移动途中立即改目标 | PASS |
| 3 | 障碍内部、地图外及禁用 Hex 拒绝 | PASS |
| 4 | 连续迷雾及 VISIBLE / EXPLORED 转换 | PASS |
| 5 | 地点按距离发现、持久显示 | PASS |
| 6 | 视野外地点低透明度、Hover 与点击 | PASS |
| 7 | 导航到 interaction_point、自动弹 UI | PASS |
| 8 | 路过未选中地点不打开 UI | PASS |
| 9 | 地面命令保留地点目标，后来接近触发 | PASS |
| 10 | 新地点替换旧地点目标 | PASS |
| 11 | 不可达地点清空交互意图 | PASS |
| 12 | Settlement 完成后保留并可重复访问 | PASS |
| 13 | Resource Collect、永久移除及自动保存 | PASS |
| 14 | Event 两个选项及会话隐藏状态 | PASS |
| 15 | Battle 请求、Victory / Defeat / Error | PASS |
| 16 | Save / Load、玩家与字节一致 Fog、地点生命周期 | PASS |
| 17 | 实际 Area2D 重叠的优先级速度覆盖 | PASS |
| 18 | Camera follow、RMB drag、zoom、focus | PASS |
| 19 | 正式交互模块暂停及恢复，外部 SceneTree 活动 | PASS |
| 20 | 存档缺失与损坏 JSON 容错 | PASS |
| 21 | RESPAWNABLE 与 restore / respawn 接口 | PASS |
| 22 | PAUSE 保留意图、resume、CANCEL 清路径 | PASS |
| 23 | 多地图私有 Navigation 与平移子树 | PASS |
| 24 | 异步战斗场景重建和怪物永久移除 | PASS |
| 25 | 运行时地点增删替换、描述及墓碑重建 | PASS |
| 26 | 损坏字段类型与未知版本验证 | PASS |
| 27 | 真实 viewport GUI 和地图点击分发 | PASS |
| 28 | TileMap 中心精确对齐、绕第二个不规则障碍 | PASS |

## 模块文件清单

- `world_map/camera/world_map_camera_controller.gd`
- `world_map/core/world_map_autoload_adapter.gd`
- `world_map/core/world_map_controller.gd`
- `world_map/data/location_definition.gd`
- `world_map/data/location_runtime_state.gd`
- `world_map/data/world_map_definition.gd`
- `world_map/data/world_map_runtime_state.gd`
- `world_map/debug/acceptance_tests.gd`
- `world_map/debug/data_validation.gd`
- `world_map/debug/navigation_probe.gd`
- `world_map/debug/preview_bandits.png`
- `world_map/debug/preview_fake_battle.png`
- `world_map/debug/preview_herbs.png`
- `world_map/debug/preview_initial.png`
- `world_map/debug/preview_monument.png`
- `world_map/debug/preview_navigation.png`
- `world_map/debug/preview_overview.png`
- `world_map/debug/preview_settlement.png`
- `world_map/debug/render_preview.gd`
- `world_map/debug/test_results.json`
- `world_map/demo/data/battle.tres`
- `world_map/demo/data/event.tres`
- `world_map/demo/data/frontier.tres`
- `world_map/demo/data/monster.tres`
- `world_map/demo/data/resource.tres`
- `world_map/demo/data/settlement.tres`
- `world_map/demo/fake_battle_adapter.gd`
- `world_map/demo/WorldMapDemo.tscn`
- `world_map/fog/fog.gdshader`
- `world_map/fog/world_map_fog.gd`
- `world_map/generation/world_map_generation_result.gd`
- `world_map/generation/world_map_generator.gd`
- `world_map/hex/hex_grid.gd`
- `world_map/hex/hex_math.gd`
- `world_map/hex/terrain_layer.gd`
- `world_map/locations/location_interaction_controller.gd`
- `world_map/locations/world_map_location_manager.gd`
- `world_map/locations/world_map_location.gd`
- `world_map/navigation/world_map_navigation.gd`
- `world_map/player/world_map_player.gd`
- `world_map/player/world_map_speed_area.gd`
- `world_map/README.md`
- `world_map/save/world_map_save_service.gd`
- `world_map/ui/battle_panel.gd`
- `world_map/ui/BattlePanel.tscn`
- `world_map/ui/event_panel.gd`
- `world_map/ui/EventPanel.tscn`
- `world_map/ui/location_interaction_panel.gd`
- `world_map/ui/resource_panel.gd`
- `world_map/ui/ResourcePanel.tscn`
- `world_map/ui/settlement_panel.gd`
- `world_map/ui/SettlementPanel.tscn`
- `world_map/ui/world_map_ui.gd`

## 中心线跟随验收结果

道路 28 项全部 PASS，原 28 项验收和 400 组数据验证全部 PASS。实际弯道轨迹最大中心线偏差报告为 0.0000；主路转支路、段内交叉连接、路外接入、暂停/恢复、反向重定向和取消均验证通过。穿过山体的中心线段被拒绝，未回退到绕山体捷径。OpenGL 实际渲染检查 preview_road_bends.png 的路径经过拐点。
