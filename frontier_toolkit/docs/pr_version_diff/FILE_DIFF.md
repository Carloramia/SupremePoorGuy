# PR 版本逐文件比较索引

基线：[PR #1](https://github.com/Carloramia/SupremePoorGuy/pull/1) 的 head `a36c06ff1b2313351f85e2d31b4de86d117ab377`，限定 `frontier_toolkit/`。当前目录按相同相对路径映射。

基线 249 个文件；当前核心范围 433 个文件；快照 SHA-256：`579eab0b99f38e5de484a9adafb796be704cc5c0aa6ad145c2a5910f6b7c747b`。

本说明文档、比较工具和输出清单作为本次报告交付单列，不计入待比较版本，避免报告生成改变自身统计。格式变化仅忽略 UTF-8 BOM、CRLF/LF 和文件末尾多余换行；不忽略内部缩进。序列化变化仅指 .tscn 生成的 unique_id 数字。完整文件与哈希见 [FILE_DIFF.json](FILE_DIFF.json) 或 [FILE_DIFF.csv](FILE_DIFF.csv)。

| 模块 | 相同 | 内容修改 | 仅格式 | 仅生成 ID | 当前缺失 | 新增 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| .github | 1 | 0 | 0 | 0 | 0 | 0 |
| docs | 2 | 2 | 0 | 0 | 0 | 12 |
| editor | 50 | 0 | 1 | 2 | 0 | 0 |
| integration | 5 | 1 | 0 | 0 | 0 | 0 |
| root | 4 | 3 | 0 | 0 | 1 | 0 |
| scenario_2_5d | 31 | 0 | 33 | 0 | 0 | 0 |
| tools | 3 | 2 | 0 | 0 | 0 | 4 |
| ui_module | 0 | 0 | 0 | 0 | 0 | 169 |
| world_map | 102 | 1 | 5 | 0 | 0 | 0 |

## 原有文件的内容变更和缺失

| 状态 | 文件 | PR 版本 |
| --- | --- | --- |
| deleted | BUILD.md | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/BUILD.md) |
| modified | [CHANGELOG.md](../../CHANGELOG.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/CHANGELOG.md) |
| modified | [docs/ARCHITECTURE.md](../../docs/ARCHITECTURE.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/docs/ARCHITECTURE.md) |
| modified | [docs/GETTING_STARTED.md](../../docs/GETTING_STARTED.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/docs/GETTING_STARTED.md) |
| serialization_only | [editor/exports/camp_battle_01/camp_battle_01.tscn](../../editor/exports/camp_battle_01/camp_battle_01.tscn) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/editor/exports/camp_battle_01/camp_battle_01.tscn) |
| serialization_only | [editor/exports/frontier/frontier.tscn](../../editor/exports/frontier/frontier.tscn) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/editor/exports/frontier/frontier.tscn) |
| format_only | [editor/地图编辑器需求表.md](../../editor/%E5%9C%B0%E5%9B%BE%E7%BC%96%E8%BE%91%E5%99%A8%E9%9C%80%E6%B1%82%E8%A1%A8.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/editor/%E5%9C%B0%E5%9B%BE%E7%BC%96%E8%BE%91%E5%99%A8%E9%9C%80%E6%B1%82%E8%A1%A8.md) |
| modified | [integration/README.md](../../integration/README.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/integration/README.md) |
| modified | [project.godot](../../project.godot) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/project.godot) |
| modified | [README.md](../../README.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/README.md) |
| format_only | [scenario_2_5d/camera/camera_bounds_3d.gd](../../scenario_2_5d/camera/camera_bounds_3d.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/camera/camera_bounds_3d.gd) |
| format_only | [scenario_2_5d/camera/scenario_camera_controller.gd](../../scenario_2_5d/camera/scenario_camera_controller.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/camera/scenario_camera_controller.gd) |
| format_only | [scenario_2_5d/core/scenario_controller.gd](../../scenario_2_5d/core/scenario_controller.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/core/scenario_controller.gd) |
| format_only | [scenario_2_5d/data/interactable_definition.gd](../../scenario_2_5d/data/interactable_definition.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/data/interactable_definition.gd) |
| format_only | [scenario_2_5d/data/interactable_runtime_state.gd](../../scenario_2_5d/data/interactable_runtime_state.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/data/interactable_runtime_state.gd) |
| format_only | [scenario_2_5d/data/scene_definition.gd](../../scenario_2_5d/data/scene_definition.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/data/scene_definition.gd) |
| format_only | [scenario_2_5d/data/scene_mode.gd](../../scenario_2_5d/data/scene_mode.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/data/scene_mode.gd) |
| format_only | [scenario_2_5d/debug/acceptance_tests.gd](../../scenario_2_5d/debug/acceptance_tests.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/debug/acceptance_tests.gd) |
| format_only | [scenario_2_5d/debug/generate_placeholders.gd](../../scenario_2_5d/debug/generate_placeholders.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/debug/generate_placeholders.gd) |
| format_only | [scenario_2_5d/debug/render_preview.gd](../../scenario_2_5d/debug/render_preview.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/debug/render_preview.gd) |
| format_only | [scenario_2_5d/demo/data/CrateDefinition.tres](../../scenario_2_5d/demo/data/CrateDefinition.tres) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/demo/data/CrateDefinition.tres) |
| format_only | [scenario_2_5d/demo/data/NPCDefinition.tres](../../scenario_2_5d/demo/data/NPCDefinition.tres) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/demo/data/NPCDefinition.tres) |
| format_only | [scenario_2_5d/demo/data/SceneDefinition.tres](../../scenario_2_5d/demo/data/SceneDefinition.tres) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/demo/data/SceneDefinition.tres) |
| format_only | [scenario_2_5d/demo/scenario_demo.gd](../../scenario_2_5d/demo/scenario_demo.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/demo/scenario_demo.gd) |
| format_only | [scenario_2_5d/demo/Scenario25DDemo.tscn](../../scenario_2_5d/demo/Scenario25DDemo.tscn) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/demo/Scenario25DDemo.tscn) |
| format_only | [scenario_2_5d/docs/SCENARIO_25D_ARCHITECTURE.md](../../scenario_2_5d/docs/SCENARIO_25D_ARCHITECTURE.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/docs/SCENARIO_25D_ARCHITECTURE.md) |
| format_only | [scenario_2_5d/docs/SCENARIO_25D_IMPLEMENTATION_PLAN.md](../../scenario_2_5d/docs/SCENARIO_25D_IMPLEMENTATION_PLAN.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/docs/SCENARIO_25D_IMPLEMENTATION_PLAN.md) |
| format_only | [scenario_2_5d/docs/SCENARIO_25D_IMPLEMENTATION_REPORT.md](../../scenario_2_5d/docs/SCENARIO_25D_IMPLEMENTATION_REPORT.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/docs/SCENARIO_25D_IMPLEMENTATION_REPORT.md) |
| format_only | [scenario_2_5d/docs/SCENARIO_25D_LEVEL_DESIGNER_GUIDE.md](../../scenario_2_5d/docs/SCENARIO_25D_LEVEL_DESIGNER_GUIDE.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/docs/SCENARIO_25D_LEVEL_DESIGNER_GUIDE.md) |
| format_only | [scenario_2_5d/docs/SCENARIO_25D_TEST_CHECKLIST.md](../../scenario_2_5d/docs/SCENARIO_25D_TEST_CHECKLIST.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/docs/SCENARIO_25D_TEST_CHECKLIST.md) |
| format_only | [scenario_2_5d/interactables/interactable_3d.gd](../../scenario_2_5d/interactables/interactable_3d.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/interactables/interactable_3d.gd) |
| format_only | [scenario_2_5d/interactables/interaction_controller.gd](../../scenario_2_5d/interactables/interaction_controller.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/interactables/interaction_controller.gd) |
| format_only | [scenario_2_5d/occlusion/occluder_3d.gd](../../scenario_2_5d/occlusion/occluder_3d.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/occlusion/occluder_3d.gd) |
| format_only | [scenario_2_5d/occlusion/occlusion_controller.gd](../../scenario_2_5d/occlusion/occlusion_controller.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/occlusion/occlusion_controller.gd) |
| format_only | [scenario_2_5d/occlusion/occlusion_target.gd](../../scenario_2_5d/occlusion/occlusion_target.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/occlusion/occlusion_target.gd) |
| format_only | [scenario_2_5d/README.md](../../scenario_2_5d/README.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/README.md) |
| format_only | [scenario_2_5d/spawn/spawn_point_3d.gd](../../scenario_2_5d/spawn/spawn_point_3d.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/spawn/spawn_point_3d.gd) |
| format_only | [scenario_2_5d/tools/Run-Demo.ps1](../../scenario_2_5d/tools/Run-Demo.ps1) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/tools/Run-Demo.ps1) |
| format_only | [scenario_2_5d/tools/Run-Tests.ps1](../../scenario_2_5d/tools/Run-Tests.ps1) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/tools/Run-Tests.ps1) |
| format_only | [scenario_2_5d/ui/demo_ui.gd](../../scenario_2_5d/ui/demo_ui.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/ui/demo_ui.gd) |
| format_only | [scenario_2_5d/visuals/billboard_visual_3d.gd](../../scenario_2_5d/visuals/billboard_visual_3d.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/visuals/billboard_visual_3d.gd) |
| format_only | [scenario_2_5d/visuals/blob_shadow.gd](../../scenario_2_5d/visuals/blob_shadow.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/visuals/blob_shadow.gd) |
| format_only | [scenario_2_5d/visuals/paper.gdshader](../../scenario_2_5d/visuals/paper.gdshader) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/scenario_2_5d/visuals/paper.gdshader) |
| modified | [tools/Build-GitHub-Package.ps1](../../tools/Build-GitHub-Package.ps1) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/tools/Build-GitHub-Package.ps1) |
| modified | [tools/Verify-Package.cjs](../../tools/Verify-Package.cjs) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/tools/Verify-Package.cjs) |
| format_only | [world_map/docs/WORLD_MAP_IMPLEMENTATION_REPORT.md](../../world_map/docs/WORLD_MAP_IMPLEMENTATION_REPORT.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/world_map/docs/WORLD_MAP_IMPLEMENTATION_REPORT.md) |
| format_only | [world_map/docs/WORLD_MAP_TEST_CHECKLIST.md](../../world_map/docs/WORLD_MAP_TEST_CHECKLIST.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/world_map/docs/WORLD_MAP_TEST_CHECKLIST.md) |
| format_only | [world_map/README.md](../../world_map/README.md) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/world_map/README.md) |
| format_only | [world_map/tools/Run-Demo.ps1](../../world_map/tools/Run-Demo.ps1) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/world_map/tools/Run-Demo.ps1) |
| format_only | [world_map/tools/Run-Tests.ps1](../../world_map/tools/Run-Tests.ps1) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/world_map/tools/Run-Tests.ps1) |
| modified | [world_map/ui/world_map_ui.gd](../../world_map/ui/world_map_ui.gd) | [固定提交](https://github.com/Carloramia/SupremePoorGuy/blob/a36c06ff1b2313351f85e2d31b4de86d117ab377/frontier_toolkit/world_map/ui/world_map_ui.gd) |

## 当前独立参考工程与需求目录

以下目录不在 PR 的 frontier_toolkit 文件集合内；只记录当前文件清单，不混入核心模块改动统计。

- `UI跳转原型/`：140 个文件。
- `UI跳转原型_20261015/`：312 个文件。
- `shader需求/`：1 个文件。

上级 GitHub 仓库中的 it-is-time、仓库首页与根 CI 不映射成当前工具集根目录文件；不能据此报告为删除。核心行为说明见 [PR_VERSION_DIFFERENCES.md](../PR_VERSION_DIFFERENCES.md)。
