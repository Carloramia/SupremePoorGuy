# 源码定位索引（自动生成）

审计日期：2026-10-15；上游提交：`e97c6994152301127fd07b779e1dc32fc940b9c4`。

由 `node tools/Build-Battle-Integration-Index.cjs [缓存仓库路径]` 重建。JSON 包含文件 SHA-256、公开方法/信号/导出字段行号及字面量资源引用。行号仅对应本次审计快照。

此索引是静态定位工具，不代表完整资源导入或战斗运行通过。缓存缺少的已跟踪资源归类为 `tracked_not_checked_out`；`not_in_git_tree` 还可能是动态模板或运行时生成文件，需逐项判断。

it-is-time 跟踪文件 4469 个，Tests 下 GDScript 261 个，跟踪 C# 源文件 0 个。

字面量资源去重：本地可用 497；上游已跟踪但未检出 893；未匹配 Git tree 27。扫描范围仅为已检出的文本资源。

| 范围 | 文件 | 行数 | 公开声明数 |
| --- | --- | ---: | ---: |
| host | [project.godot](../../project.godot) | 28 | 0 |
| host | [world_map/core/world_map_controller.gd](../../world_map/core/world_map_controller.gd) | 415 | 41 |
| host | [world_map/core/world_map_autoload_adapter.gd](../../world_map/core/world_map_autoload_adapter.gd) | 21 | 6 |
| host | [world_map/locations/location_interaction_controller.gd](../../world_map/locations/location_interaction_controller.gd) | 73 | 10 |
| host | [world_map/data/location_definition.gd](../../world_map/data/location_definition.gd) | 17 | 13 |
| host | [world_map/data/world_map_runtime_state.gd](../../world_map/data/world_map_runtime_state.gd) | 41 | 4 |
| host | [world_map/save/world_map_save_service.gd](../../world_map/save/world_map_save_service.gd) | 86 | 6 |
| host | [world_map/demo/fake_battle_adapter.gd](../../world_map/demo/fake_battle_adapter.gd) | 48 | 4 |
| host | [world_map/demo/WorldMapDemo.tscn](../../world_map/demo/WorldMapDemo.tscn) | 105 | 0 |
| host | [integration/scenario_overlay.gd](../../integration/scenario_overlay.gd) | 127 | 4 |
| host | [integration/scenario_overlay_tests.gd](../../integration/scenario_overlay_tests.gd) | 114 | 5 |
| host | [scenario_2_5d/core/scenario_controller.gd](../../scenario_2_5d/core/scenario_controller.gd) | 92 | 25 |
| host | [scenario_2_5d/data/scene_definition.gd](../../scenario_2_5d/data/scene_definition.gd) | 16 | 14 |
| host | [scenario_2_5d/camera/scenario_camera_controller.gd](../../scenario_2_5d/camera/scenario_camera_controller.gd) | 119 | 15 |
| host | [scenario_2_5d/interactables/interaction_controller.gd](../../scenario_2_5d/interactables/interaction_controller.gd) | 67 | 12 |
| host | [scenario_2_5d/occlusion/occlusion_controller.gd](../../scenario_2_5d/occlusion/occlusion_controller.gd) | 52 | 8 |
| host | [scenario_2_5d/spawn/spawn_point_3d.gd](../../scenario_2_5d/spawn/spawn_point_3d.gd) | 9 | 4 |
| host | [scenario_2_5d/visuals/billboard_visual_3d.gd](../../scenario_2_5d/visuals/billboard_visual_3d.gd) | 61 | 13 |
| host | [scenario_2_5d/demo/Scenario25DDemo.tscn](../../scenario_2_5d/demo/Scenario25DDemo.tscn) | 213 | 0 |
| host | [editor/godot/import_level.gd](../../editor/godot/import_level.gd) | 267 | 12 |
| host | [editor/godot/battle_preview.gd](../../editor/godot/battle_preview.gd) | 296 | 8 |
| host | [editor/docs/DATA_CONTRACT.md](../../editor/docs/DATA_CONTRACT.md) | 45 | 0 |
| host | [ui_module/core/game_ui.gd](../../ui_module/core/game_ui.gd) | 179 | 13 |
| host | [ui_module/integration/world_map_ui_bridge.gd](../../ui_module/integration/world_map_ui_bridge.gd) | 100 | 5 |
| ui_v2 | [UI跳转原型_20261015/Scripts/GameDemo.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/UI%E8%B7%B3%E8%BD%AC%E5%8E%9F%E5%9E%8B/Scripts/GameDemo.gd) | 1029 | 5 |
| ui_v2 | [UI跳转原型_20261015/Scripts/PrototypeState.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/UI%E8%B7%B3%E8%BD%AC%E5%8E%9F%E5%9E%8B/Scripts/PrototypeState.gd) | 363 | 21 |
| ui_v2 | [UI跳转原型_20261015/Scripts/SummonExperiment.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/UI%E8%B7%B3%E8%BD%AC%E5%8E%9F%E5%9E%8B/Scripts/SummonExperiment.gd) | 217 | 5 |
| ui_v2 | [UI跳转原型_20261015/docs/07_系统接入适配与联调协议.md](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/UI%E8%B7%B3%E8%BD%AC%E5%8E%9F%E5%9E%8B/docs/07_%E7%B3%BB%E7%BB%9F%E6%8E%A5%E5%85%A5%E9%80%82%E9%85%8D%E4%B8%8E%E8%81%94%E8%B0%83%E5%8D%8F%E8%AE%AE.md) | 188 | 0 |
| ui_v2 | [UI跳转原型_20261015/docs/08_召唤2.0接入与边界.md](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/UI%E8%B7%B3%E8%BD%AC%E5%8E%9F%E5%9E%8B/docs/08_%E5%8F%AC%E5%94%A42.0%E6%8E%A5%E5%85%A5%E4%B8%8E%E8%BE%B9%E7%95%8C.md) | 62 | 0 |
| combat | [it-is-time/project.godot](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/project.godot) | 136 | 0 |
| combat | [it-is-time/ItIsTime.csproj](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/ItIsTime.csproj) | 313 | 0 |
| combat | [it-is-time/Scripts/Creatures/PhysicalCharacterController.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Creatures/PhysicalCharacterController.gd) | 282 | 25 |
| combat | [it-is-time/Scripts/Creatures/GeneratedCreatureCharacter3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Creatures/GeneratedCreatureCharacter3D.gd) | 1271 | 68 |
| combat | [it-is-time/Scripts/Creatures/GeneratedHumanNPCCharacter3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Creatures/GeneratedHumanNPCCharacter3D.gd) | 3 | 1 |
| combat | [it-is-time/Scripts/Creatures/PhysicalBodyParts.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Creatures/PhysicalBodyParts.gd) | 663 | 73 |
| combat | [it-is-time/Scripts/Creatures/CharacterDamageController3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Creatures/CharacterDamageController3D.gd) | 211 | 7 |
| combat | [it-is-time/Scripts/Creatures/NPCStateMachine3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Creatures/NPCStateMachine3D.gd) | 934 | 59 |
| combat | [it-is-time/Scripts/Creatures/NavigationNPCSpawner3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Creatures/NavigationNPCSpawner3D.gd) | 118 | 20 |
| combat | [it-is-time/Scripts/Creatures/CreatureActionController3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Creatures/CreatureActionController3D.gd) | 450 | 18 |
| combat | [it-is-time/Scripts/Player/PlayerControlContext.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Player/PlayerControlContext.gd) | 36 | 7 |
| combat | [it-is-time/Scripts/Player/PlayerController3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Player/PlayerController3D.gd) | 422 | 36 |
| combat | [it-is-time/Scripts/Input/TerrainCursor3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Input/TerrainCursor3D.gd) | 494 | 40 |
| combat | [it-is-time/Scripts/Camera/DragCamera3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Camera/DragCamera3D.gd) | 101 | 19 |
| combat | [it-is-time/Scripts/Damage/DamageService.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Damage/DamageService.gd) | 52 | 11 |
| combat | [it-is-time/Scripts/Damage/DamageRules.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Damage/DamageRules.gd) | 45 | 19 |
| combat | [it-is-time/Scripts/Items/SampleWeapon3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Items/SampleWeapon3D.gd) | 119 | 19 |
| combat | [it-is-time/Scripts/Items/InventoryController3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/Items/InventoryController3D.gd) | 490 | 22 |
| combat | [it-is-time/Scripts/VFX/StompShockwave3D.gd](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scripts/VFX/StompShockwave3D.gd) | 131 | 2 |
| combat | [it-is-time/Scenes/Creatures/Characters/Generate_Human_NPC.tscn](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scenes/Creatures/Characters/Generate_Human_NPC.tscn) | 27 | 0 |
| combat | [it-is-time/Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn) | 16 | 0 |
| combat | [it-is-time/Scenes/Levels/TestLevel.tscn](https://github.com/Carloramia/SupremePoorGuy/blob/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time/Scenes/Levels/TestLevel.tscn) | 63 | 0 |

完整机器索引：[SOURCE_INDEX.json](SOURCE_INDEX.json)。当前代码解释：[CURRENT_CODE_MAP.md](CURRENT_CODE_MAP.md)。
