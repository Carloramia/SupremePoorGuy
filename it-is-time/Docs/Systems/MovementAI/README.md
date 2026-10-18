# 移动、朝向与 NPC AI

## 控制器继承与职责

| 控制器 | 父类与用途 |
|---|---|
| [LegStepMovementControllerBase3D](../../../Scripts/Creatures/LegStepMovementControllerBase3D.gd) | 通用脚部发现、落点、迈步、接地与推进基础 |
| [LegStepMovementController3D](../../../Scripts/Creatures/LegStepMovementController3D.gd) | 基础角色输入适配，继承 Base |
| [NPCLegStepMovementController3D](../../../Scripts/Creatures/NPCLegStepMovementController3D.gd) | Character_Test_NPC 的状态机输入适配，继承 Base |
| [GeneratedLegStepMovementController3D](../../../Scripts/Creatures/GeneratedLegStepMovementController3D.gd) | 继承 Base；多腿、体节、恢复和动作接管 |
| [Wolf](../../../Scripts/Creatures/WolfLegStepMovementController3D.gd)、[Spider](../../../Scripts/Creatures/SpiderLegStepMovementController3D.gd)、[Human](../../../Scripts/Creatures/HumanLegStepMovementController3D.gd) | 继承 Generated，分别实现结构可达性、肢体或人形姿态特例 |
| [Rats](../../../Scripts/Creatures/RatsLegStepMovementController3D.gd) | 继承 Wolf 控制器，配合独立 Rats 数据 |
| [SnakeMovementController3D](../../../Scripts/Creatures/SnakeMovementController3D.gd) | 独立控制器，使用 S 形路径与躯干轨迹跟随，不走 Leg 迈步继承链 |
| [BirdFlightController3D](../../../Scripts/Creatures/BirdFlightController3D.gd) | 飞行/落地交接；与地面迈步、翼姿态协调 |

实际引用见 [移动预设](../../../Resources/Movement/README.md) 与 [角色场景索引](../../../Scenes/Creatures/Characters/README.md)。修改父类会影响继承它的多种角色，物种专用参数应优先放在专用资源或子类。

## 步态调参

[LegMovementData](../../../Scripts/Creatures/LegMovementData.gd) 的 `automatic_motion` 开启时，`target_speed`、`turning_speed_degrees`、`maximum_step_frequency` 参与步幅、时序、抬高和力的计算。速度不是刚体位置直接赋值；接触、结构、制动和动作接管仍会影响实际速度。某些专用控制器将步频用于参考计算，而非固定换步许可，应检查对应子类。

手动模式使用 `step_distance`、`step_height`、`step_frequency`、`swing_duration` 等。`maximum_stepping_ratio`、`maximum_simultaneous_steps`、`minimum_support_feet` 决定支撑与迈步名额。飞奔由 `gallop_enabled`、腾空支撑、落地制动及同时迈步设置共同控制；仅提高目标速度不保证自动得到稳定飞奔。

角色的 PlanarConstraints 是一套不同的运动、约束与支撑分支，不能把该分支的测试结论直接用于普通物理模式。朝向还受 [PhysicalFacingController3D](../../../Scripts/Creatures/PhysicalFacingController3D.gd)、角色关节和专用控制器共同影响。

## NPC 状态机

[NPCStateMachine3D](../../../Scripts/Creatures/NPCStateMachine3D.gd) 提供 `IDLE`、`MOVE_TO_TARGET`、`ATTACK`、`WAITING`。Bird、Human、Snake、Spider 使用专用子类；通用 NPC 挂载 Behavior，读取 NavigationAgent3D 的路径，并向移动组件输出方向。

- `enabled` 控制 AI；`attack_execution_enabled` 可停用攻击执行但保留靠近目标。
- [NPCBehaviorData](../../../Scripts/Creatures/NPCBehaviorData.gd) 负责索敌、切敌冷却和攻击选项数组。当前敌人感知遍及同一物理世界的角色，旧的 detection/disengage 半径不是当前索敌距离开关；感知到目标仍不代表有合法路径或可攻击。
- 左右朝向和 Z 轴对位由 `generated_x_axis_facing`、`humanoid_xz_positioning` 及子类配置共同决定。友军避让有独立扫描间隔、范围和权重。
- [NPCAttackData](../../../Scripts/Creatures/NPCAttackData.gd) 的 `receiver_path` 相对角色根节点，`action_id` 必须被接收器支持；不是相对状态机节点。
- 动作接收器可以提供动态距离、预测与执行接口，AI 选择距离不应与物理攻击范围分别任意设置。

## 运动与攻击所有权

Generated 控制器通过 `begin_action_control()`、`end_action_control()` 等接口让指定脚和身体进入动作接管，其余可用部位可继续响应行走。Snake 使用专用 `set_attack_control()` 协调路径和抬起部分。不能只停用整个移动节点再直接驱动部位，否则可能同时移除姿态支撑或造成恢复时跳变。

Broken、短暂布娃娃、飞行和倒地恢复也会改变控制权。记录目标速度时同时检查实际速度、接地状态、动作 owner 和姿态恢复状态。

诊断建议：`tracknpcstate on 名称`、`tracknpcmotion on 名称`、`trackjoints on 名称`、`showsteptargets on`；大量 NPC 时保持 `motiondetail summary`。历史运动报告见 [运动修正与性能边界](../../Physics/生成生物运动修正实施与回归报告_2026-10-12.txt)。
