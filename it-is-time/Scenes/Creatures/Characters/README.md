# 角色场景与直接引用

`Generate_*` 保存可编辑的生成器、角色组件与物理装配。`*_NPC` 一般继承基础角色并挂载 AI，但根脚本、组件与资源也可能在子场景中被覆盖。下表取当前文件的直接场景继承，不将脚本继承混入该列。

正式召唤/部署的入口是 [CreatureFactory.DEFINITIONS](../../../Scripts/Application/CreatureFactory.gd)，当前池为 StumpBeast、Wolf、Snake、HornedBeast、Spider。其他场景属于可用资产或测试角色，不自动进入随机池。

| 场景 | 直接继承的场景 | 当前 Factory |
|---|---|---|
| [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | [_SampleCharacter.tscn](_SampleCharacter.tscn) | 未直接登记 |
| [_BaseRats.tscn](_BaseRats.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [_SampleCharacter.tscn](_SampleCharacter.tscn) | 无场景继承 | 未直接登记 |
| [Character_Test_2.tscn](Character_Test_2.tscn) | [_SampleCharacter.tscn](_SampleCharacter.tscn) | 未直接登记 |
| [Character_Test_NPC.tscn](Character_Test_NPC.tscn) | 无场景继承 | 未直接登记 |
| [Generate_Beast.tscn](Generate_Beast.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_Bird.tscn](Generate_Bird.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_Bird_NPC.tscn](Generate_Bird_NPC.tscn) | [Generate_Bird.tscn](Generate_Bird.tscn) | 未直接登记 |
| [Generate_Creature_NPC.tscn](Generate_Creature_NPC.tscn) | [Generate_Beast.tscn](Generate_Beast.tscn) | 未直接登记 |
| [Generate_Creature_Test.tscn](Generate_Creature_Test.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_HornedBeast.tscn](Generate_HornedBeast.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_HornedBeast_NPC.tscn](Generate_HornedBeast_NPC.tscn) | [Generate_HornedBeast.tscn](Generate_HornedBeast.tscn) | horned_beast / 召唤池 |
| [Generate_HornedBeast_SegmentedTail.tscn](Generate_HornedBeast_SegmentedTail.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_Human.tscn](Generate_Human.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_Human_NPC.tscn](Generate_Human_NPC.tscn) | [Generate_Human.tscn](Generate_Human.tscn) | 未直接登记 |
| [Generate_Rat_1.tscn](Generate_Rat_1.tscn) | [_BaseRats.tscn](_BaseRats.tscn) | 未直接登记 |
| [Generate_Rat_1_NPC.tscn](Generate_Rat_1_NPC.tscn) | [Generate_Rat_1.tscn](Generate_Rat_1.tscn) | 未直接登记 |
| [Generate_Rat_2.tscn](Generate_Rat_2.tscn) | [_BaseRats.tscn](_BaseRats.tscn) | 未直接登记 |
| [Generate_Rat_2_NPC.tscn](Generate_Rat_2_NPC.tscn) | [Generate_Rat_2.tscn](Generate_Rat_2.tscn) | 未直接登记 |
| [Generate_Ratkin.tscn](Generate_Ratkin.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_Snake.tscn](Generate_Snake.tscn) | [_SampleCharacter.tscn](_SampleCharacter.tscn) | 未直接登记 |
| [Generate_Snake_NPC.tscn](Generate_Snake_NPC.tscn) | [Generate_Snake.tscn](Generate_Snake.tscn) | snake / 召唤池 |
| [Generate_Spider.tscn](Generate_Spider.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_Spider_NPC.tscn](Generate_Spider_NPC.tscn) | [Generate_Spider.tscn](Generate_Spider.tscn) | spider / 召唤池 |
| [Generate_StumpBeast.tscn](Generate_StumpBeast.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_StumpBeast_NPC.tscn](Generate_StumpBeast_NPC.tscn) | [Generate_StumpBeast.tscn](Generate_StumpBeast.tscn) | stump_beast / 召唤池 |
| [Generate_Wolf.tscn](Generate_Wolf.tscn) | [_BaseGeneratedCreature.tscn](_BaseGeneratedCreature.tscn) | 未直接登记 |
| [Generate_Wolf_NPC.tscn](Generate_Wolf_NPC.tscn) | [Generate_Wolf.tscn](Generate_Wolf.tscn) | wolf / 召唤池 |

## Human 武器变体

[Human/Armed](Human/Armed) 有 Spear1、Spear5、ClawGauntlet、CurvedSword、Flail、Shield、Bow 及对应 NPC；[variants.json](Human/Armed/variants.json) 记录变体。Human 的素材预设切换和物种生成参数是另外的配置，不等于只更换武器。

## 编辑与部署的区别

正式 Factory 使用保存的部件姿态进行部署，不重复随机生成；编辑时应先捕获手动布局并保存基础角色，再检查 NPC 的覆盖。只改基础角色不保证旧 NPC 子场景的覆盖会消失。

`_SampleCharacter` 是物理角色基类；`_BaseGeneratedCreature` 是通用生成场景；`Generate_Creature_Test` / `Generate_Beast` 是保留的生成入口；`Character_Test_2` / `Character_Test_NPC` 是早期物理测试角色，仍有引用，不应因名称含 Test 就直接删除。

资产和参数入口见 [生成系统](../../../Docs/Systems/Creatures/README.md)、[移动](../../../Resources/Movement/README.md)、[AI](../../../Resources/AI/README.md) 与 [密度/物理](../../../Resources/Creatures/README.md)。既有 [Wolf 批次说明](Wolf_README.md) 仅用于追溯历史调整。
