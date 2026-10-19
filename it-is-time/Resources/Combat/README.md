# Arm 与武器攻击配置

LimbSwingPresetBase 提供可复用挥舞参数；ArmSwingBinding 在每个 Arm 上挂载预设并加入控制组。控制组输入由 LimbSwingController 配置。Weapons 下按武器标签映射近战参数，BowAttack 由专用射击控制器使用。

系统说明：[README.md](../../Docs/Systems/EquipmentWorkshop/README.md)。下面记录 2026-10-18 当前工作区的直接引用，未展开所有继承与动态路径。

| 配置文件 | 数据脚本 | 直接引用者（最多两项） |
|---|---|---|
| [HumanArmSwing.tres](HumanArmSwing.tres) | [LimbSwingPresetBase.gd](../../Scripts/Combat/LimbSwingPresetBase.gd) | [GeneratedHumanCharacter3D.gd](../../Scripts/Creatures/GeneratedHumanCharacter3D.gd)、[Generate_Human.tscn](../../Scenes/Creatures/Characters/Generate_Human.tscn) |
| [PrimaryArmSwing.tres](PrimaryArmSwing.tres) | [LimbSwingPresetBase.gd](../../Scripts/Combat/LimbSwingPresetBase.gd) | [Character_Test_2.tscn](../../Scenes/Creatures/Characters/Character_Test_2.tscn)、[Character_Test_NPC.tscn](../../Scenes/Creatures/Characters/Character_Test_NPC.tscn) |
| [Weapons/BluntAttack.tres](Weapons/BluntAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |
| [Weapons/BowAttack.tres](Weapons/BowAttack.tres) | [BowAttackData.gd](../../Scripts/Combat/BowAttackData.gd) | [BowAttackController3D.gd](../../Scripts/Combat/BowAttackController3D.gd)、[BowAttackController3D.tscn](../../Scenes/Creatures/Components/BowAttackController3D.tscn) |
| [Weapons/ClawAttack.tres](Weapons/ClawAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |
| [Weapons/ShieldAttack.tres](Weapons/ShieldAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |
| [Weapons/SpearAttack.tres](Weapons/SpearAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |
| [Weapons/SwordAttack.tres](Weapons/SwordAttack.tres) | [WeaponArmAttackPreset.gd](../../Scripts/Combat/WeaponArmAttackPreset.gd) | [SampleWeapon3D.gd](../../Scripts/Items/SampleWeapon3D.gd) |

`Weapons/SpearAttack.tres` 默认启用 `Hand Driven Thrust / Hand Driven Motion`：主手 Arm 通过位置/速度追踪力带动 ArmLimb，手部扭矩维持武器朝向；ArmLimb 仅保留阻尼和接近伸直/反折时的弱辅助。关闭该开关可恢复原来的整链姿态扭矩；只有一个刚体的旧式 Arm 自动保留原驱动。

| 参数 | 默认值 | 用途 |
|---|---:|---|
| `hand_position_frequency` | 6 Hz | 手部位置追踪响应 |
| `hand_position_damping` | 1.2 | 手部追踪阻尼 |
| `hand_maximum_acceleration` | 120 | 按实际手臂与装备负载换算施力前的加速度上限；攻击蓄力比例仍影响力度 |
| `hand_maximum_force` | 250 | 换算负载后的力上限 |
| `passive_limb_damping` | 4 | ArmLimb 的相对角速度阻尼 |
| `passive_bend_acceleration` | 12 | 接近伸直或反向弯折时的弱辅助；0 可关闭 |

武器朝向仍使用同一资源中的 `pose_frequency`、`pose_damping_ratio`、`maximum_pose_acceleration` 和 `maximum_pose_torque`。手部目标按真实链长和关节角度限位求解，位置施力对躯干施加反作用，防止额外增加整只角色的净推进力。攻击中暂停常态手臂姿态控制，结束、取消或卸下武器时恢复约束和控制权。`trackswing` 同时开关每 0.1 秒的 `[spear_hand_drive]` 追踪误差、力、朝向扭矩和负载日志。

`SpearAttack.tres / Thrust Preparation` 将蓄力收矛和释放后的突刺分开调节：`preparation_speed_ratio = 0.65` 缩放蓄力时的位置与旋转追踪频率；`preparation_force_ratio = 0.5` 缩放蓄力加速度及质量/惯量换算后的驱动力、扭矩上限。默认蓄力主动力上限为 125、主朝向扭矩上限为 750，ArmLimb 的被动阻尼保留。释放后恢复原有突刺响应和上限，伤害数值不变。其他预设两项倍率默认为 1。

Spear 的 `damage_only_during_swing = true`：仅释放后的突刺及跟随阶段结算伤害，待机、蓄力、恢复和取消后均不结算普通碰撞伤害；实体碰撞保持有效。其他武器该开关默认关闭。`trackswing` 中的 `[spear_hand_drive]` 同时显示 `preparing`、当前倍率和施力上限。

`Thrust Preparation / npc_charge_range_multiplier = 1.35` 将 NPC 的开始蓄力范围扩大到实际突刺几何范围的 1.35 倍，随角色及武器尺寸变化。NPC 在蓄力时继续向原有攻击站位接近，只有进入实际突刺范围后才释放；突刺和恢复阶段停止这一接近控制。提前判定仍检查接近后攻击轨迹与地形，不扩大碰撞箱或伤害范围。蓄满后仍在范围外，最多再等待 `LimbSwingController3D / NPC Aiming / npc_maximum_charge_approach_wait`（默认 5 秒），受阻时取消本次攻击；进入范围后的瞄准等待仍单独使用原有 `npc_maximum_aim_wait`。其他武器预设倍率默认 1，保留原来的起手距离与移动规则。`tracknpcstate` 的 `receiver_check` 区分 `maximum`（真实突刺）与 `charge_maximum`（起手范围）；`trackswing` 的 `[npc_swing_aim]` 输出额外范围等待和 `approach_timeout` 原因。
