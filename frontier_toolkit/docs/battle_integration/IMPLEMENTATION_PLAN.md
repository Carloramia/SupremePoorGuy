# 实施步骤、文件修改清单与回退

本文是待实施工作清单；本次只新增文档、索引和契约校验工具。未修改角色物理、UI 原型布局、地图业务或战斗入口。总设计见 [主文档](../BATTLE_INTEGRATION_GUIDE.md)。

## 1. 接入前置问题

| 优先级 | 问题与证据 | 必须完成的改动 | 通过条件 |
| --- | --- | --- | --- |
| P0 | 宿主与上游资源路径/配置不同；缓存不完整 | 确定唯一正式 project.godot；导入完整依赖；合并 Jolt、Autoload、InputMap | 无加载错误，一个真实角色可生成和受伤 |
| P0 | FakeBattleAdapter 与原型跳过战斗仍是入口 | 在独占功能开关下替换监听；新版 UI 外部路由模式 | 一次点击只有一个请求和窗口，没有测试奖励 |
| P0 | 缺少 battle_id 和 readiness | 会话协调器、注册表、生成/导航屏障、超时处理 | 生成失败不判胜；迟到回调无效 |
| P0 | Fx/掉落使用 current_scene | 注入 FxRoot/DropsRoot；限制 World3D | 所有新物体和作用目标均属本场 |
| P0 | Shockwave、控制器、光标有全树查询 | BattleContext 注入 + 同 World3D + 本会话 ID | 第二个世界角色不受伤、不被选中 |
| P0 | UI 遮挡不能禁用 Input 全局轮询 | 单一输入桥与门禁；暂停快照/物理冻结 | 点 UI、焦点丢失、暂停时无角色动作 |
| P0 | 当前退出先关窗再保存；save bool 被忽略 | 结果冻结、幂等 SessionStore、提交后返回 | 保存失败留在结果页；重试/重启不重复领奖 |
| P0 | 部件破坏不等于角色死亡 | disabled 一次性事件或延迟状态观察；有限波次判定 | 断手不结束，头部失能正确结束，不重复结算 |
| P1 | 新召唤规则尚未映射物理原型 | 版本化原型/能力/StatProfileResolver | 巨化/缩小生成合法，队位组一致，能力有实际行为 |
| P1 | 地编只有预览描述 | 生产 builder、SpawnRegistry、导航资产 | 敌人配置可解析，部署无穿透且路径可达 |
| P1 | 构建包含缓存引用/可疑原型资源 | csproj 整理、资源补全、目标渲染验证 | 干净工作目录可导入和导出 |

P0 是首个可验收真实闭环的必要条件。P1 中不启用的原型或能力可以标为“不支持”并在准备阶段阻止使用，不能静默降级成另一种怪物。

## 2. 拟新增目录（实施时创建）

```text
integration/battle/
  battle_host_bridge.gd           world_map 入口与 UI 适配
  battle_session_coordinator.gd   生命周期、一次性终止、事务协调
  battle_context.gd               battle_id/world_3d/节点所有权/注册表
  battle_request_validator.gd     Schema 对应的运行时业务校验
  battle_result_projector.gd     纯数据结算投影、兼容地图 result
  battle_input_gate.gd            焦点、模态窗、暂停令牌
  battle_pause_controller.gd      物理/逻辑暂停快照
  battle_camera_bridge.gd         受控角色 anchor 与正交相机
  battle_runtime_adapter.gd       生成器、角色、死亡事件封装
  battle_unit_registry.gd         actor_id -> 节点、monster_id/part_key
  battle_wave_scheduler.gd        有限波次及未就绪计数
  battle_spawn_registry.gd        地编 Marker -> 部署数据
  battle_ui_adapter.gd            UI 展示与队伍快照
  battle_config_registry.gd       ID -> 受控资源、蓝图、数值版本
  session_store.gd                统一快照/迁移/结算台账
  scenes/BattleScenario.tscn      无 DemoUI 的生产场景
  tests/                         真正运行这些组件的集成测试
```

这些是职责划分；实施时可合并小文件，但保持方向：地图/场景模块不 preload 战斗内部脚本；战斗内部不 import UI 原型；适配层负责跨模块调用。不要为了整理代码改名上游核心物理脚本和 body tag 枚举，这会扩大资源迁移范围。

## 3. 现有文件的精确改动范围

| 文件 | 拟变更 | 保留的行为 |
| --- | --- | --- |
| 正式 `project.godot` | 合并运行入口、Autoload、输入和物理/渲染基线 | 原物理回归场景单独可运行 |
| `world_map/locations/location_interaction_controller.gd` | battle 请求先经协调器验证/持久化；失败不 emit；拆分结果数据投影与交互释放 | 非战斗地点 begin/resolve 兼容 |
| `world_map/core/world_map_controller.gd` | 公开可区分存储失败的提交接口；接入暂停所有权 | 地图状态导入导出与地点完成策略 |
| `world_map/data/world_map_runtime_state.gd` | pending 包含版本、battle_id 和阶段；迁移旧三字段请求 | 旧地图存档可恢复 |
| `world_map/save/world_map_save_service.gd` | 校验新版 pending；统一存储适配或事务日志 | 单文件替换与错误返回 |
| `world_map/demo/WorldMapDemo.tscn` / FakeBattleAdapter | 真实模式断开 Fake 信号；测试模式保留 | 旧 Demo 可测，不与真实模式并行 |
| `integration/scenario_overlay.gd` | 必要时抽出通用 ViewportHost；战斗结果不走 finish_scenario | 城镇返回行为与现有测试 |
| `scenario_2_5d/interactables/interaction_controller.gd` | 总体 input_enabled 或门禁注入；单一点击入口 | 探索物件点击、遮挡与地面事件 |
| `scenario_2_5d/camera/scenario_camera_controller.gd` | 可选平滑追随目标接口，门禁 | 正交边界、中键释放防粘滞 |
| `editor/godot/battle_preview.gd` | 抽可复用几何构建器，生产路径独立 | 浏览器/引擎预览不依赖战斗运行 |
| `ui_module/core/game_ui.gd` / UIBridge | 升级至新版基础前先做迁移适配；暂停归协调器；只读展示结果 | 已确认布局、召唤入库/队位规则 |
| 新 UI `Scripts/GameDemo.gd`（正式集成副本） | 显式外部路由模式；跳过战斗与奖励测试路径退出正式运行 | 独立原型测试可保留测试模式 |
| it-is-time `PhysicalBodyParts.gd` | FxRoot 注入；可选部件事件关联 actor_id | 唯一伤害入口及部件物理 |
| it-is-time `CharacterDamageController3D.gd` | 可选一次性 disabled 事件 | 原连通图、破坏传播逻辑 |
| it-is-time `CreatureActionController3D.gd` | 冲击波 parent 使用上下文 | 原动作计算与冲量 |
| it-is-time `InventoryController3D.gd` | DropsRoot 注入；运行装备与永久背包的边界 | 握持/拾取机制 |
| it-is-time `StompShockwave3D.gd` | World3D/会话角色过滤 | 距离、视线、护甲与击退计算 |
| it-is-time `PlayerControlContext.gd` | 先解析指定上下文，再允许兼容独立 Demo fallback | 独立测试场景不失效 |
| it-is-time `PlayerController3D.gd` | 明确 runtime level、全局 Input 门禁、局部指示器；camera_rig 留空或显式适配 | attach/detach 的 AI 状态恢复 |
| it-is-time `TerrainCursor3D.gd` | 世界内角色选择、地面语义统一、门禁 | 光标/蓄力跟随计算 |
| 其他 AI、LimbSwing、Facing、Arc 等组查询 | 逐项扫描并判定是否需上下文 | 已有同 World3D 的路径不重复改逻辑 |

文档中的新版 UI 原始副本保留为参考；实施应在正式集成副本修改并通过其原测试。若需改变已确认布局，属于另一个明确需求，不应夹带在适配工作内。

## 4. 里程碑与负责人职责

| 阶段 | 可 review 的交付 | 负责人职责 | 放行门槛 |
| --- | --- | --- | --- |
| M0：基线确定 | 目标工程、完整资源清单、ID 注册表示例、首期规则记录 | 主程 + 战斗 + 策划确定控制/健康/撤退/奖励政策 | 目标渲染/物理可运行；不支持的能力明确 |
| M1：独立真战斗 | BattleScenario，双方各一只，生成/导航屏障，实际死亡 | 战斗程序提供 readiness/disabled 语义；场景程序提供导航 | 真实接触伤害到失能；加载错误不判胜 |
| M2：地图入口与隔离 | BattleHostBridge、ViewportHost、InputGate、Fx/DropsRoot、CameraBridge | 客户端/场景程序 | 地图冻结、两世界隔离、可逆暂停、没有双入口 |
| M3：持久化闭环 | request/result 运行校验、SessionStore、迁移、台账、故障恢复 | 客户端/存档程序 | 保存失败不退出；任意重试/重启只领奖一次 |
| M4：队伍与新版 UI | PartyProvider/StatProfileResolver、0.7.12 外部路由、多单位和队位 | UI + 战斗 + 策划 | 6 队位语义、中文部件映射、原数据不丢失 |
| M5：生产地编与扩展 | 配置表、部署/波次、能力/分身、性能报告、打包 | 地编工具 + 战斗 + TA + QA | 完整验收矩阵通过；独立 Demo 与 Shader 回归通过 |

并行实施时，可在 M0 后并行完成场景生产 builder、UI 只读适配与存档纯数据投影；共同协议先固定，再对接。物理伤害与数值映射改动须分开评审，便于定位行为变化。

## 5. M0 必须记录的产品决策

建议首期默认：固定遭遇战；手操一只、其余自主 AI；战后部件损伤 session_only；撤退不奖励、不完成地点；加载失败不消耗队伍。它们是设计建议，不是已获确认的产品规则。

实施前需要记录：全员失能是否永久损失、缩小体 recoverable 的战后语义、增殖分身是否可操作、召唤 hp/attack 到物理规则的公式、失败/撤退的货币和装备处理、是否允许战中开仓库、战斗崩溃后重开还是取消。决策写入 ruleset_id/balance_version，不在 UI 回调中散写判断。

## 6. 回退、兼容与发布

1. 新桥先由 `real_battle_enabled` 等显式配置启用，同一时刻只注册一个战斗入口。回退只影响新会话，已产生 result 的会话必须完成持久化或恢复处理。
2. 保存升级保留旧文件备份。新协议无法解析时提示迁移失败并保留原数据，不用空队伍覆盖。
3. 老 `pending_battle` 没有 battle_id，不得每次启动随机生成不同 ID。迁移第一次生成并持久化映射后才启动；也可按明确政策取消旧测试请求。
4. 回退到旧版本前，若有 PREPARED/未提交结果，先由新版本提交或导出恢复包。禁止旧 UI 的 claim_once 再发同一奖励。
5. 每阶段提交独立变更，保留测试记录和固定资源版本。最后在干净目录导入与导出，再替换 F5 入口；不要把 `.tools` 审计缓存当作正式游戏依赖。
