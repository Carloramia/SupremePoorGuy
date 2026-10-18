# NPC 行为配置

大部分资源使用 NPCBehaviorData，并以内嵌 NPCAttackData 指向动作接收器；BirdDiveAttack.tres 等也可能直接是攻击选项。调整 enabled、receiver_path、action_id、预测、冷却和距离时，需要同时核对接收器支持的方法。

系统说明：[README.md](../../Docs/Systems/MovementAI/README.md)。下面记录 2026-10-18 当前工作区的直接引用，未展开所有继承与动态路径。

| 配置文件 | 数据脚本 | 直接引用者（最多两项） |
|---|---|---|
| [BirdDiveAttack.tres](BirdDiveAttack.tres) | [NPCAttackData.gd](../../Scripts/Creatures/NPCAttackData.gd) | [BirdDiveBehavior.tres](BirdDiveBehavior.tres) |
| [BirdDiveBehavior.tres](BirdDiveBehavior.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Generate_Bird.tscn](../../Scenes/Creatures/Characters/Generate_Bird.tscn) |
| [DefaultArmNPC.tres](DefaultArmNPC.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Character_Test_NPC.tscn](../../Scenes/Creatures/Characters/Character_Test_NPC.tscn) |
| [GeneratedStompAI.tres](GeneratedStompAI.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Generate_Creature_NPC.tscn](../../Scenes/Creatures/Characters/Generate_Creature_NPC.tscn)、[Generate_StumpBeast_NPC.tscn](../../Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn) |
| [HornedBeastChargeAI.tres](HornedBeastChargeAI.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Generate_HornedBeast_NPC.tscn](../../Scenes/Creatures/Characters/Generate_HornedBeast_NPC.tscn) |
| [HumanBowAI.tres](HumanBowAI.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Generate_Human_Bow_NPC.tscn](../../Scenes/Creatures/Characters/Human/Armed/Generate_Human_Bow_NPC.tscn) |
| [HumanMeleeAI.tres](HumanMeleeAI.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Generate_Human_NPC.tscn](../../Scenes/Creatures/Characters/Generate_Human_NPC.tscn) |
| [RatsAI.tres](RatsAI.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Generate_Rat_1_NPC.tscn](../../Scenes/Creatures/Characters/Generate_Rat_1_NPC.tscn)、[Generate_Rat_2_NPC.tscn](../../Scenes/Creatures/Characters/Generate_Rat_2_NPC.tscn) |
| [SnakeNavigation.tres](SnakeNavigation.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Generate_Snake_NPC.tscn](../../Scenes/Creatures/Characters/Generate_Snake_NPC.tscn) |
| [SpiderAI.tres](SpiderAI.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Generate_Spider_NPC.tscn](../../Scenes/Creatures/Characters/Generate_Spider_NPC.tscn) |
| [WolfAI.tres](WolfAI.tres) | [NPCBehaviorData.gd](../../Scripts/Creatures/NPCBehaviorData.gd) | [Generate_Wolf_NPC.tscn](../../Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn) |
