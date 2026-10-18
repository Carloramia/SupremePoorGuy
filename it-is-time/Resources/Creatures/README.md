# 密度、物理和视觉配置

GeneratedCreatureDensityData 按生成部位类型匹配密度，最终质量还受体积和角色质量限制开关影响。WolfPhysics / HornedBeastPhysics 是物种关节、自然姿态等专用配置，不是单纯的质量表。

系统说明：[README.md](../../Docs/Systems/Creatures/README.md)。下面记录 2026-10-18 当前工作区的直接引用，未展开所有继承与动态路径。

| 配置文件 | 数据脚本 | 直接引用者（最多两项） |
|---|---|---|
| [BeastDensity.tres](BeastDensity.tres) | [GeneratedCreatureDensityData.gd](../../Scripts/Creatures/GeneratedCreatureDensityData.gd) | [Generate_Beast.tscn](../../Scenes/Creatures/Characters/Generate_Beast.tscn)、[Generate_StumpBeast.tscn](../../Scenes/Creatures/Characters/Generate_StumpBeast.tscn) |
| [BirdDensity.tres](BirdDensity.tres) | [GeneratedCreatureDensityData.gd](../../Scripts/Creatures/GeneratedCreatureDensityData.gd) | [Generate_Bird.tscn](../../Scenes/Creatures/Characters/Generate_Bird.tscn) |
| [HornedBeastDensity.tres](HornedBeastDensity.tres) | [GeneratedCreatureDensityData.gd](../../Scripts/Creatures/GeneratedCreatureDensityData.gd) | [Generate_HornedBeast.tscn](../../Scenes/Creatures/Characters/Generate_HornedBeast.tscn)、[Generate_HornedBeast_SegmentedTail.tscn](../../Scenes/Creatures/Characters/Generate_HornedBeast_SegmentedTail.tscn) |
| [HornedBeastPhysics.tres](HornedBeastPhysics.tres) | [HornedBeastPhysicsData.gd](../../Scripts/Creatures/HornedBeastPhysicsData.gd) | [HornedBeastCharacter3D.gd](../../Scripts/Creatures/HornedBeastCharacter3D.gd)、[Generate_HornedBeast.tscn](../../Scenes/Creatures/Characters/Generate_HornedBeast.tscn) |
| [HumanDensity.tres](HumanDensity.tres) | [GeneratedCreatureDensityData.gd](../../Scripts/Creatures/GeneratedCreatureDensityData.gd) | [Generate_Human.tscn](../../Scenes/Creatures/Characters/Generate_Human.tscn) |
| [RatkinDensity.tres](RatkinDensity.tres) | [GeneratedCreatureDensityData.gd](../../Scripts/Creatures/GeneratedCreatureDensityData.gd) | [Generate_Ratkin.tscn](../../Scenes/Creatures/Characters/Generate_Ratkin.tscn) |
| [RatsDensity.tres](RatsDensity.tres) | [GeneratedCreatureDensityData.gd](../../Scripts/Creatures/GeneratedCreatureDensityData.gd) | [Generate_Rat_2.tscn](../../Scenes/Creatures/Characters/Generate_Rat_2.tscn)、[_BaseRats.tscn](../../Scenes/Creatures/Characters/_BaseRats.tscn) |
| [SpiderDensity.tres](SpiderDensity.tres) | [GeneratedCreatureDensityData.gd](../../Scripts/Creatures/GeneratedCreatureDensityData.gd) | [Generate_Spider.tscn](../../Scenes/Creatures/Characters/Generate_Spider.tscn) |
| [WolfDensity.tres](WolfDensity.tres) | [GeneratedCreatureDensityData.gd](../../Scripts/Creatures/GeneratedCreatureDensityData.gd) | [Generate_Wolf.tscn](../../Scenes/Creatures/Characters/Generate_Wolf.tscn) |
| [WolfPhysics.tres](WolfPhysics.tres) | [WolfPhysicsData.gd](../../Scripts/Creatures/WolfPhysicsData.gd) | [WolfCharacter3D.gd](../../Scripts/Creatures/WolfCharacter3D.gd)、[Generate_Wolf.tscn](../../Scenes/Creatures/Characters/Generate_Wolf.tscn) |

[VisualStates/Human](VisualStates/Human) 保存 Human 多套 Open/Grip 视觉资源；对应 BodyPartVisualState3D，在 Part.visual_states 中引用。[Wolf/ManualLayouts](Wolf/ManualLayouts) 保存版本化布局与碰撞快照，修改前确认当前 WolfGenerator 选用的具体版本。
