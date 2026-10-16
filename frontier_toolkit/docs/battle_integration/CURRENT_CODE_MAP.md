# 当前代码地图与接口审计

本文件只描述已读代码；设计类见 [实施计划](IMPLEMENTATION_PLAN.md)。上游固定提交、文件哈希和公开声明行号见 [源码索引](SOURCE_INDEX.md)。`host` 指当前根工程；`ui_v2` 指独立新 UI；`combat` 指 it-is-time。以下相对链接定位宿主代码，上游代码使用固定提交链接，避免后续 main 变化使结论失真。

## 1. 模块边界与数据所有权

| 模块 | 现有入口 | 当前拥有的数据 | 实际缺口 |
| --- | --- | --- | --- |
| 大地图 | [WorldMapController](../../world_map/core/world_map_controller.gd) | map_id、地点状态、位置、迷雾、pending_battle | 无 battle_id、结算台账与队伍事务 |
| 地点交互 | [LocationInteractionController](../../world_map/locations/location_interaction_controller.gd) | 当前交互、面板、地点完成策略 | 战斗请求只有三字段；保存结果未传播 |
| 城镇窗口 | [ScenarioOverlay](../../integration/scenario_overlay.gd) | 子视口和窗口节点 | 退出按普通访问处理；不能承载战斗可靠结算 |
| 2.5D 场景 | [ScenarioController](../../scenario_2_5d/core/scenario_controller.gd) | 定义、模式、相机/交互/遮挡引用 | 无战斗生命周期、物理角色注册和胜负 |
| 地编 | [import_level](../../editor/godot/import_level.gd)、[battle_preview](../../editor/godot/battle_preview.gd) | 场景描述、配置 ID、预览节点 | enemy 是描述，部署 Marker 没有运行注册；导航/伤害需接入 |
| 当前宿主 UI | [GameUI](../../ui_module/core/game_ui.gd)、[WorldMapUIBridge](../../ui_module/integration/world_map_ui_bridge.gd) | 旧原型 session、召唤、仓库、队列 | 依赖旧 0.5；没有新版召唤队位和实际战斗写回 |
| 新 UI 0.7.12 | [GameDemo](../../UI跳转原型_20261015/Scripts/GameDemo.gd)、[PrototypeState](../../UI跳转原型_20261015/Scripts/PrototypeState.gd) | 新召唤数据、队位组、原型奖励 | scene_requested 仍伴随本地跳转，跳过战斗仍发测试奖励 |
| it-is-time | [固定版本目录](https://github.com/Carloramia/SupremePoorGuy/tree/e97c6994152301127fd07b779e1dc32fc940b9c4/it-is-time) | 物理角色/部件、武器、AI、控制、运行时装备 | 无地图会话协调器、稳定队伍 ID、正式战后持久化 |

当前并不存在一个同时管理地图、召唤队伍和实际物理战斗的 GameSession。把三个 Dictionary 合并到 UI 层会继续产生多写入者，应由会话服务统一拥有。

## 2. 宿主公开接口：可以直接复用的部分

| 脚本 | 现有方法 / 信号 | 对接注意 |
| --- | --- | --- |
| ScenarioController | `scenario_initialized`、`scenario_ready` | 意味着三个框架控制器完成配置，不代表生成角色或导航已就绪 |
| ScenarioController | `set_scene_mode/get_scene_mode` | COMBAT 模式只改变地面事件分流 |
| ScenarioController | `combat_ground_clicked(Vector3)` | 接指令桥；没有内建攻击或移动逻辑 |
| ScenarioController | `set_camera_input_enabled(bool)` | 只作用于相机 |
| ScenarioController | `set_focus_target/focus_on_target/clear_focus_target` | focus 是一次定位；持续追随需新增桥 |
| ScenarioController | `register_occlusion_target/unregister_occlusion_target` | 按动态躯干 anchor 注册；只注销本适配器拥有的目标 |
| ScenarioController | `request_scenario_exit(reason)` / `scenario_exit_requested` | 战斗下转换为撤退/取消意图，经协调器判定后退出 |
| InteractionController | `click_at(Vector2)`、hover/selection/ground 事件 | `_unhandled_input` 消费左键；pick_mask 默认 1，没有全局输入 enabled |
| ScenarioCameraController | `configure(SceneDefinition)`、`clamp_position` | 正交相机、中键平移、滚轮缩放；ALWAYS 模式 |
| OcclusionController | register/unregister target、enabled | mask 默认 2；视觉淡化，不是攻击碰撞或导航 |
| SpawnPoint3D | `spawn_id`、`metadata`，group `scenario_spawn` | Marker 包装；没有阵营、排队、占用与半径验证 |
| WorldMapController | `battle_requested(Dictionary)` | 实际 BattleHostBridge 的入口候选 |
| WorldMapController | `resolve_location_interaction(id, result)->bool` | 返回路由成功，未返回保存确认；上线前需拆分事务投影与 UI 释放 |
| WorldMapController | `set_world_map_paused(bool)`、`save_world_map(path)->bool` | 前者不是全树暂停；后者 bool 应由协调器处理 |
| WorldMapAutoloadAdapter | retain/restore session、return_battle_result | 可选适配类；当前 project.godot 未配置为 Autoload，不可默认已存在 |

`SceneDefinition` 提供 mode、camera bounds/size、metadata 等场景配置。建议在 metadata 的专用 battle 键保存配置 ID，实际规则和资源由 registry 解析，避免把原始 PackedScene 写入 JSON 存档。

## 3. 请求和返回的真实行为

当前地点请求结构严格说只有：

```json
{"map_id":"地图ID","location_id":"地点ID","encounter_data":{}}
```

`request_battle()` 先写 runtime_state.pending_battle，再调用 save_world_map，但没有判断失败就发事件。重复调用以 pending 非空为保护。没有唯一战斗 ID、队伍版本、场景注册 ID或配置快照。

`resolve()` 顺序：验证 active_location → visits+1 → 合并 custom_data → 写 last_result → 根据 success/complete_location/repeatable 改地点生命周期 → 清空交互和 pending → 关闭面板/解冻 → 调用保存 → 发 completed。它不会发放 rewards，也不会更新怪物仓库。失败时无法把调用者挡在关闭窗口之前。

`world_map/save/world_map_save_service.gd` 支持单文件临时文件替换，pending 校验只要求 map_id/location_id/encounter_data 的基本类型；有附加字段不等于这些字段已被执行或具有幂等语义。

`integration/scenario_overlay.gd` 则在 finish_scenario 先关窗口，再传普通访问结果，保存失败时原运行世界已释放。战斗必须有独立结果路径，保留此城镇行为的兼容测试。

`world_map/demo/WorldMapDemo.tscn` 包含 FakeBattleAdapter 与 ScenarioOverlay；当前 UIWorldMapDemo 继承/组合这一宿主链。移交真实入口前必须禁用 Fake 的信号监听，而非仅把它的按钮隐藏。

## 4. it-is-time 的真实接口与约束

精确签名与行号可在 [SOURCE_INDEX.json](SOURCE_INDEX.json) 搜索声明，或使用固定上游目录中的文件。

| 文件（相对 it-is-time） | 已有接口 / 行为 | 使用方法与限制 |
| --- | --- | --- |
| `Scripts/Creatures/PhysicalCharacterController.gd` | faction_id、get_faction_id、is_combat_alive、get_combat_anchor、get_nearest_combat_torso | 角色加入 physical_characters_3d；anchor 是实际躯干部件；无 DamageController 时 is_combat_alive 会返回真，必须先过 readiness |
| 同上 | get_body_parts_with_tag、get_living_body_mass、get_body_connections、get_physical_body_rids | 用于部件查询、布局和临时碰撞排除；不把 RID 序列化 |
| 同上 | disable_character_controls、临时 ragdoll | 前者为失能，不能作为普通暂停；临时恢复有死亡保护 |
| `Scripts/Creatures/GeneratedCreatureCharacter3D.gd` | `creature_generation_finished(succeeded:bool)`、`generate_creature()->bool` | 连接应早于入树；generate_on_ready 默认为 true；生成器会重建部件和 DamageController |
| 同上 | generated_part_key metadata、manual layout 快照 | part_key 可用于稳定映射；编辑器 capture_manual_layout 不能直接当作运行时整场存档 |
| `Scripts/Creatures/PhysicalBodyParts.gd` | PhysicalBodyPart3D，max_hp/current_hp/armor/is_broken | RigidBody3D；_ready 会初始化 current_hp；初始化属性需考虑生成与 deferred 时机 |
| 同上 | damaged(amount,remaining_hp,source)、broken(source)、apply_damage/break_part | 部件事件非整只角色死亡；伤害数字当前加到 current_scene |
| `Scripts/Creatures/CharacterDamageController3D.gd` | team_id、is_character_disabled、get_parts | team_id 代理父角色 faction_id；维护头/躯干连通和失能；无统一死亡 signal |
| `Scripts/Damage/DamageService.gd` | calculate_raw_damage/apply_armor/calculate_damage；武器专用方法；set/get/reset_active_rules | 根 Autoload；规则是全局状态；临时改规则需快照还原，不能每只怪互相覆盖 |
| `Scripts/Items/SampleWeapon3D.gd` | set_wielder/clear、begin_damage_swing/end_damage_swing、apply_contact_damage | 正式接触伤害入口；过滤自己/友军；主动挥击同目标部件去重，非主动伤害有冷却 |
| `Scripts/Creatures/NPCStateMachine3D.gd` | move_to_node、move_to_position、stop、resume_autonomous、state_changed、set_character_control_enabled | 手动命令与自主模式分开；enabled/attack_execution_enabled 可用于部署门禁；部分方法是控制模式而非冻结物理 |
| `Scripts/Player/PlayerController3D.gd` | attach_character/detach_character、get_controlled_character/get_control_anchor、controlled_character_changed | controller 会重挂到角色；释放时的 level 父节点必须指向本场上下文；camera_rig 要求 follow_target 属性 |
| 同上 | gameplay_input_allowed、set_character_control_enabled | 读 UI/树暂停；false 会关闭轮盘并 detach，true 不对称恢复；不是可逆 pause |
| `Scripts/Player/PlayerControlContext.gd` | controller、controlled_character、input_allowed、character_of | character_of 通过祖先找到物理角色；控制器查找为全树首个 group，无 World3D 限定 |
| `Scripts/Input/TerrainCursor3D.gd` | bind_control_target、set_cursor_world_position、get_ground_position | 使用视口相机，但角色扫描为全树；StaticBody 判地范围与宿主不同 |
| `Scripts/Creatures/NavigationNPCSpawner3D.gd` | spawn_enabled、初始/间隔计时、上限、导航随机落点 | 适合测试/补员；有限波次由新调度器接管，默认定时行为不应直接上线 |

### 实际死亡规则

CharacterDamageController 观察部件与关节图；无有效头/躯干连通的组件会破坏，躯干断裂可引发关联部件破坏，头部全灭或全部部件失效可触发角色控制禁用。角色尸体仍可留在树中。应在其延迟完整性处理完成后读取 `is_character_disabled/is_combat_alive`，并由运行时适配器把 false→true 失能转换成一次 `unit_defeated` 事件。

更理想的实施是在 DamageController 中补一个只发一次的 disabled signal，再由适配器统一订阅；若暂不改上游，则使用仅针对本场注册角色的物理帧观察。不能只订阅第一个 broken 事件，也不能通过队列节点数量判胜。

### 当前主场景不是战斗协调器

`run/main_scene` 的 UID 对应 `Scenes/Levels/TestLevel.tscn`。其中已有导航场地、DragCamera、TerrainCursor、PlayerController、测试 NPC 与关闭的自动 Spawner。它适合保持为物理回归入口；没有完整请求/结果协议、奖励事务或与当前地图的对接。

## 5. UI 版本差异与必须保留的规则

| 项目 | 当前宿主 | 新版独立原型 |
| --- | --- | --- |
| 原型基础 | `ui_module/prototype`，旧 0.5 | `UI跳转原型_20261015`，0.7.12 |
| 常规召唤 | 旧批次数量和旧符文 | 召唤 2.0，常规批次 5，14 符文，扩阵 7/19/37/61 |
| 队列口径 | 旧数量限制 | 最多 6 队位；单位数量不等于队位 |
| 队位规则 | 未实现新模式 | 普通 1、巨化每只 2、超巨化 5、缩小同批整组 1 |
| 对外信号 | blocking_changed、map_command_requested、summon_committed | location_interaction_requested、scene_requested、party_changed 等原型信号 |
| 战斗 | embedded 模式屏蔽跳过战斗入口 | `_location_clicked` 发 scene_requested 后仍 `_show("battle")`；`_skip_battle` 领取固定魔力测试奖励 |

新版 unit 已包含 `part_hp`、`interval`、`visual_scale`、`mode/batch_id/slots/recoverable`、`abilities/effects`、`clone_count/clone_ratio`、source_layout/recipe_id 等；不能在迁移时仅保留旧十个字段。part_hp 使用中文标签“头部/核心/肢体”，需要转换为实际 tag/part_key；`interval` 不叫 attack_interval。`visual_scale` 不能直接赋给物理根 Transform。

新版 scene_requested 是通知信号，没有默认的“被宿主消费后阻止本地路由”协议。适配需要显式 embedded/外部路由模式或派生覆写，并覆盖所有战斗信号发射点；直接 connect 信号会同时出现原型战斗页和真实窗口。

## 6. 地编与 TA 边界

[地编数据契约](../../editor/docs/DATA_CONTRACT.md) 中 battle 地图使用 `[X,Z]` 与独立高度 Y；数据存于 `SceneDefinition.metadata.editor_data`。敌方对象保存 `monster_config_id`，部署对象生成 Slot Marker，web/effect 等区域只提供几何和 metadata。运行适配必须解析 catalogs 中的配置 ID，并执行合法性与可达性检查。

`editor/godot/battle_preview.gd` 自建场景与帮助 UI，未提供实际战斗总线和成体系导航烘焙。预览成功不证明部署合法或 AI 能到达。生产 builder 可以复用几何转换，但应剥离 PreviewHelp 和测试行为。

TA 的 S1/S2/S3 纸质 UI 材质继续在独立工程验证。Shader 的参数动画归 UI 展示；真实伤害、受击次数、角色失能与结算从战斗事件获得，禁止以 Shader 动画结束作为结果确认。
