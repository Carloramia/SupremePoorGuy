# 动作与冲击波配置

这些资源分别由动作控制器、冲锋、俯冲、Spider 跳跃或冲击波使用。文件存在不代表角色当前已经挂载；物种子场景可覆盖组件默认值。

系统说明：[README.md](../../Docs/Systems/Combat/README.md)。下面记录 2026-10-18 当前工作区的直接引用，未展开所有继承与动态路径。

| 配置文件 | 数据脚本 | 直接引用者（最多两项） |
|---|---|---|
| [BirdDiveAttack.tres](BirdDiveAttack.tres) | [BirdDiveAttackData.gd](../../Scripts/Creatures/BirdDiveAttackData.gd) | [BirdDiveAttackController3D.gd](../../Scripts/Creatures/BirdDiveAttackController3D.gd) |
| [ForeLegStomp.tres](ForeLegStomp.tres) | [CreatureActionData.gd](../../Scripts/Creatures/CreatureActionData.gd) | [CreatureActionController3D.tscn](../../Scenes/Creatures/Components/CreatureActionController3D.tscn) |
| [ForeLegStompShockwave.tres](ForeLegStompShockwave.tres) | [StompShockwaveData.gd](../../Scripts/VFX/StompShockwaveData.gd) | [CreatureActionData.gd](../../Scripts/Creatures/CreatureActionData.gd)、[ForeLegStomp.tres](ForeLegStomp.tres) 等 4 处 |
| [GroundCharge.tres](GroundCharge.tres) | [ChargeAttackData.gd](../../Scripts/Creatures/ChargeAttackData.gd) | [ChargeAttackController3D.gd](../../Scripts/Creatures/ChargeAttackController3D.gd) |
| [HornedBeastCharge.tres](HornedBeastCharge.tres) | [ChargeAttackData.gd](../../Scripts/Creatures/ChargeAttackData.gd) | [Generate_HornedBeast_NPC.tscn](../../Scenes/Creatures/Characters/Generate_HornedBeast_NPC.tscn) |
| [HornedBeastForeLegStomp.tres](HornedBeastForeLegStomp.tres) | [CreatureActionData.gd](../../Scripts/Creatures/CreatureActionData.gd) | [Generate_HornedBeast.tscn](../../Scenes/Creatures/Characters/Generate_HornedBeast.tscn)、[Generate_HornedBeast_SegmentedTail.tscn](../../Scenes/Creatures/Characters/Generate_HornedBeast_SegmentedTail.tscn) |
| [SpiderPounce.tres](SpiderPounce.tres) | [SpiderPounceData.gd](../../Scripts/Creatures/SpiderPounceData.gd) | [SpiderPounceController3D.gd](../../Scripts/Creatures/SpiderPounceController3D.gd)、[SpiderPounceController3D.tscn](../../Scenes/Creatures/Components/SpiderPounceController3D.tscn) |
| [StumpBeastForeLegStomp.tres](StumpBeastForeLegStomp.tres) | [CreatureActionData.gd](../../Scripts/Creatures/CreatureActionData.gd) | [Generate_StumpBeast.tscn](../../Scenes/Creatures/Characters/Generate_StumpBeast.tscn) |
| [WolfForeLegStomp.tres](WolfForeLegStomp.tres) | [CreatureActionData.gd](../../Scripts/Creatures/CreatureActionData.gd) | 未发现完整字面路径引用，需结合动态加载/编辑器配置 |
