# 移动配置

LegMovementData 定义通用自动/手动步态，WolfLegMovementData 与 RatsMovementData 扩展专用限制，SnakeMotionData 是独立轨迹参数。资源被直接引用和继承引用的情况不同，最终以运行实例的 slow_gait_data / fast_gait_data / motion_data 等槽位为准。

系统说明：[README.md](../../Docs/Systems/MovementAI/README.md)。下面记录 2026-10-18 当前工作区的直接引用，未展开所有继承与动态路径。

| 配置文件 | 数据脚本 | 直接引用者（最多两项） |
|---|---|---|
| [BirdGroundWalk.tres](BirdGroundWalk.tres) | [LegMovementData.gd](../../Scripts/Creatures/LegMovementData.gd) | [Generate_Bird.tscn](../../Scenes/Creatures/Characters/Generate_Bird.tscn) |
| [DefaultWalk.tres](DefaultWalk.tres) | [LegMovementData.gd](../../Scripts/Creatures/LegMovementData.gd) | 未发现完整字面路径引用，需结合动态加载/编辑器配置 |
| [GeneratedMultiLegWalk.tres](GeneratedMultiLegWalk.tres) | [LegMovementData.gd](../../Scripts/Creatures/LegMovementData.gd) | [_BaseGeneratedCreature.tscn](../../Scenes/Creatures/Characters/_BaseGeneratedCreature.tscn) |
| [GeneratedWalk.tres](GeneratedWalk.tres) | [LegMovementData.gd](../../Scripts/Creatures/LegMovementData.gd) | [GeneratedLegStepMovementController3D.tscn](../../Scenes/Creatures/Components/GeneratedLegStepMovementController3D.tscn) |
| [HornedBeastWalk.tres](HornedBeastWalk.tres) | [LegMovementData.gd](../../Scripts/Creatures/LegMovementData.gd) | [Generate_HornedBeast.tscn](../../Scenes/Creatures/Characters/Generate_HornedBeast.tscn)、[Generate_HornedBeast_SegmentedTail.tscn](../../Scenes/Creatures/Characters/Generate_HornedBeast_SegmentedTail.tscn) |
| [HumanFastWalk.tres](HumanFastWalk.tres) | [LegMovementData.gd](../../Scripts/Creatures/LegMovementData.gd) | [Generate_Human.tscn](../../Scenes/Creatures/Characters/Generate_Human.tscn) |
| [HumanWalk.tres](HumanWalk.tres) | [LegMovementData.gd](../../Scripts/Creatures/LegMovementData.gd) | [Generate_Human.tscn](../../Scenes/Creatures/Characters/Generate_Human.tscn) |
| [RatkinWalk.tres](RatkinWalk.tres) | [LegMovementData.gd](../../Scripts/Creatures/LegMovementData.gd) | [Generate_Ratkin.tscn](../../Scenes/Creatures/Characters/Generate_Ratkin.tscn) |
| [RatsWalk.tres](RatsWalk.tres) | [RatsMovementData.gd](../../Scripts/Creatures/RatsMovementData.gd) | [Generate_Rat_2.tscn](../../Scenes/Creatures/Characters/Generate_Rat_2.tscn)、[_BaseRats.tscn](../../Scenes/Creatures/Characters/_BaseRats.tscn) |
| [SnakeMotion.tres](SnakeMotion.tres) | [SnakeMotionData.gd](../../Scripts/Creatures/SnakeMotionData.gd) | [SnakeMovementController3D.gd](../../Scripts/Creatures/SnakeMovementController3D.gd)、[SnakeMovementController3D.tscn](../../Scenes/Creatures/Components/SnakeMovementController3D.tscn) |
| [SpiderWalk.tres](SpiderWalk.tres) | [LegMovementData.gd](../../Scripts/Creatures/LegMovementData.gd) | [Generate_Spider.tscn](../../Scenes/Creatures/Characters/Generate_Spider.tscn) |
| [WolfWalk.tres](WolfWalk.tres) | [WolfLegMovementData.gd](../../Scripts/Creatures/WolfLegMovementData.gd) | [Generate_Wolf.tscn](../../Scenes/Creatures/Characters/Generate_Wolf.tscn) |
