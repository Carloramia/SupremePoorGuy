# 战场适配与敌方编队

FrontierDeliveryBattle 使用 DeliveryBattleSettings，将地图请求中的敌方配置 ID 映射到 EnemyRosterData。每个 roster 的 definitions 是 CreatureFactory 定义 ID 数组，不是 .tscn 路径；实际数量以数组长度为准。

系统说明：[README.md](../../Docs/Systems/WorldMapUI/README.md)。下面记录 2026-10-18 当前工作区的直接引用，未展开所有继承与动态路径。

| 配置文件 | 数据脚本 | 直接引用者（最多两项） |
|---|---|---|
| [EnemyRosters/bandit_clear_team.tres](EnemyRosters/bandit_clear_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/bandit_clear_team_site_2.tres](EnemyRosters/bandit_clear_team_site_2.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/bandit_clear_team_site_3.tres](EnemyRosters/bandit_clear_team_site_3.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/bandit_encounter_team_site_2.tres](EnemyRosters/bandit_encounter_team_site_2.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/bandit_encounter_team_site_3.tres](EnemyRosters/bandit_encounter_team_site_3.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/forest_rat_clear_team.tres](EnemyRosters/forest_rat_clear_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/forest_rat_encounter_team.tres](EnemyRosters/forest_rat_encounter_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/forest_wolf_clear_team.tres](EnemyRosters/forest_wolf_clear_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/forest_wolf_encounter_team.tres](EnemyRosters/forest_wolf_encounter_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/rat_clear_team.tres](EnemyRosters/rat_clear_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/spider_clear_team.tres](EnemyRosters/spider_clear_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/spider_clear_team_site_2.tres](EnemyRosters/spider_clear_team_site_2.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/tree_clear_team.tres](EnemyRosters/tree_clear_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/tree_clear_team_site_2.tres](EnemyRosters/tree_clear_team_site_2.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/wolf_clear_team.tres](EnemyRosters/wolf_clear_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/wolf_clear_team_site_2.tres](EnemyRosters/wolf_clear_team_site_2.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/wolf_encounter_team.tres](EnemyRosters/wolf_encounter_team.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [EnemyRosters/wolf_encounter_team_site_2.tres](EnemyRosters/wolf_encounter_team_site_2.tres) | [EnemyRosterData.gd](../../Scripts/Application/EnemyRosterData.gd) | [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) |
| [FrontierDeliveryBattle.tres](FrontierDeliveryBattle.tres) | [DeliveryBattleSettings.gd](../../Scripts/Application/DeliveryBattleSettings.gd) | [GameRoot.gd](../../Scripts/Application/GameRoot.gd) |

当前地图交付设置引用 human、wolf、snake、spider、stump_beast 等 Factory 类别；地图存在 giant_rat ID 不代表该 NPC 已开放。unit_scale 等适配值影响实际部署尺寸，不能只比较源角色编辑界面的大小。
