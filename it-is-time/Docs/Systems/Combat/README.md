# 攻击、伤害与断裂

## 选择与执行是两层配置

AI 在 [Behavior/NPCAttackData](../../../Resources/AI/README.md) 中选择动作；动作接收器使用 [Actions](../../../Resources/Actions/README.md)、[Attacks](../../../Resources/Attacks/README.md) 或 [Combat](../../../Resources/Combat/README.md) 中的数据实际驱动物理部位。仅把攻击资源放到目录中不会自动让 NPC 使用它。

| 角色 / 方式 | 组件入口 | 主要数据 |
|---|---|---|
| 通用、StumpBeast 踏地 | [CreatureActionController3D](../../../Scripts/Creatures/CreatureActionController3D.gd) | ForeLegStomp、物种踏地数据、StompShockwave |
| HornedBeast 冲锋 | [ChargeAttackController3D](../../../Scripts/Creatures/ChargeAttackController3D.gd) | HornedBeastCharge；物种还可挂载踏地 |
| Wolf 飞扑 / 啃咬 | [WolfAttackController3D](../../../Scripts/Creatures/WolfAttackController3D.gd) 协调 Pounce/Bite 子模组 | WolfPounce、WolfBite；当前没有爪击子模组 |
| Rat 啃咬 | [RatBiteAttackController3D](../../../Scripts/Creatures/RatBiteAttackController3D.gd) | RatsBite；准备时锁定静态目标点，再伸头和合颚 |
| Snake 啃咬 | [SnakeBiteAttackController3D](../../../Scripts/Creatures/SnakeBiteAttackController3D.gd) | SnakeBite；协调抬起躯干和路径控制 |
| Spider 跳跃攻击 | [SpiderPounceController3D](../../../Scripts/Creatures/SpiderPounceController3D.gd) | SpiderPounce；前躯干与前肢动作 |
| Bird 俯冲 | [BirdDiveAttackController3D](../../../Scripts/Creatures/BirdDiveAttackController3D.gd) | BirdDiveAttack；与飞行、翼姿态和临时武器配合 |
| Arm 近战 | [LimbSwingController3D](../../../Scripts/Combat/LimbSwingController3D.gd) | Part 的 ArmSwingBinding、控制组、武器类型预设 |
| Bow 射击 | [BowAttackController3D](../../../Scripts/Combat/BowAttackController3D.gd) | BowAttack、Bow 与 Arrow |

## 接收器接口

NPC 接收器按需实现 `has_npc_attack()`、`predict_npc_attack()`、`try_start_npc_attack()`、`is_npc_attack_active()`、`cancel_npc_attack()`，以及动态距离查询。新增动作时同时检查 `receiver_path`、`action_id`、冷却、最大动作时间、取消和恢复路径。

攻击预测用于决定何时接近或开始动作。动作已经开始后，不应因为一次新的命中预测失败而直接套用旧式中断逻辑；角色死亡、部件 Broken、控制转移或明确取消仍需要处理。目标点是否持续跟踪由具体动作实现决定，Rat 与 Snake 的静态锁点不能当作所有物种的通用规则。

## 伤害链

```text
物理接触或临时攻击体 / 冲击波
  → 冲量与施加者、阵营、挥舞状态
  → DamageService.active_rules
  → 原始伤害与护甲处理
  → PhysicalBodyPart3D.apply_damage
  → HP / 伤害数字 / Broken / 关节移除与控制停用
```

全局服务是 [DamageService](../../../Scripts/Damage/DamageService.gd)，默认数据为 [DefaultDamageRules.tres](../../../Resources/Damage/DefaultDamageRules.tres)。主动攻击原伤害为 `35 × 完整身体基础总质量的立方根 × 动作倍率 × 命中质量`，先应用韧性，再扣固定护甲：`max(raw × 100 / (韧性 + 100) - Armor, 0)`。默认韧性为0，默认固定护甲为10；命中质量来自有效冲量，正常范围0.95～1.05。常态接触保留原有低强度冲量转换、倍率与单次上限，不使用35的主动攻击公式。不要把 UI 中的“护甲 +40%”理解为受到伤害减少 40%。

武器通过 [SampleWeapon3D](../../../Scripts/Items/SampleWeapon3D.gd) 处理施加者、友军排除、同一挥舞对同一 Part 的去重与常态接触冷却。临时命中体见 [TemporaryAttackHitbox3D](../../../Scripts/Items/TemporaryAttackHitbox3D.gd) 及物种派生实现；踏地冲击波使用 [StompShockwave3D](../../../Scripts/VFX/StompShockwave3D.gd)。同动作的多攻击体共享去重记录，但不同受击部位各自承受完整伤害，不设整只目标的总伤害预算。

## 部位和角色死亡

[Part](../../../Scripts/Creatures/PhysicalBodyParts.gd) 持有 `max_hp`、`current_hp`、`armor`、`resilience`、`is_broken`。默认运行时 `max_hp = 裸装部位基础质量 × 40`；Inspector 的 `mass_based_health` 可用于固定血量的特殊部件和测试夹具。攻击者身体质量在初始化时缓存，装备合并质量和后来断肢不会改变该基准。[CharacterDamageController3D](../../../Scripts/Creatures/CharacterDamageController3D.gd) 处理断裂后的连接与连带结果：

- 移除与 Broken Part 连接的 Joint；控制器停止控制 Broken 部件。
- Torso 断裂会使相连且不带 Torso 标签的部件断裂；所有 Head 都 Broken 后，停用角色并使剩余部件 Broken。
- 开启 `require_head_and_torso_connectivity` 时，每个仍存活的连通分量必须同时包含 Head 和 Torso，否则该分量会 Broken。
- Arm 断裂通知物品栏处理装备，不能只删除关节而遗漏装备归属。

阵营由角色 `faction_id` 提供。不同攻击还可能触发质量比较和短暂布娃娃；这与 Broken 的永久失效不是同一状态。

诊断：`trackdamage`、`showattackboxes on`、`trackwolfattacks on 名称`、`tracksnakeattacks on 名称`、`trackcharge`。可视化说明见 [攻击碰撞体可视化](../../Combat/攻击碰撞箱可视化控制台说明_2026-10-16.txt)。

攻击阶段、实际扣血和首次 Broken 也会触发 [战斗音效](../Audio/README.md)，播放配置独立于伤害计算。

已接入 [伤害与耐久方案 V2](../../Combat/伤害与耐久方案_V2_总质量与双护甲_2026-10-18.md)，最终结算顺序按后续要求采用“先韧性、后固定护甲”。旧仓库记录保留姿态与符文倍率并迁移数值，下次保存前保留 `.pre_damage_v2.bak`；不会重新随机生成角色。[第一版方案](../../Combat/伤害与耐久线性化方案_2026-10-18.md) 仅保留设计历史。

配置入口与正式攻击测试见 [伤害V2实施与低矮目标测试](../../Combat/伤害V2实施与低矮目标测试_2026-10-18.md)。测试使用保留正常物理接触回调的被动Rat目标，冻结靶样本已排除。
