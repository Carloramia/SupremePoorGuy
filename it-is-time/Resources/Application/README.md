# 应用、地图与战场配置

FrontierDeliveryBattle 使用 DeliveryBattleSettings，将地图请求中的敌方配置 ID 映射到 EnemyRosterData。每个 roster 的 definitions 是 CreatureFactory 定义 ID 数组，不是 .tscn 路径；实际数量以数组长度为准。

2026-10-19 起，新游戏使用 [Runtime/BattleSettings.tres](../../Content/Maps/FrontierEditor_20261019/Runtime/BattleSettings.tres) 和同目录生成的 EnemyRosters；此处原配置继续服务旧档。两版均由 GameRoot.get_delivery_battle_settings() 选择，不能只改旧的 FrontierDeliveryBattle.tres 来调整新版敌群。新版实际接入及生成流程见 [接入记录](../../Docs/Systems/WorldMapUI/新版六边形地图接入_2026-10-19.md)。

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
| [DefaultWorldTime.tres](DefaultWorldTime.tres) | [WorldTimeSettings.gd](../../Scripts/Application/WorldTimeSettings.gd) | [GameRoot.gd](../../Scripts/Application/GameRoot.gd)、[GameSession.gd](../../Scripts/Application/GameSession.gd) |
| [DefaultSummonAnimation.tres](DefaultSummonAnimation.tres) | [SummonAnimationSettings.gd](../../Scripts/Application/SummonAnimationSettings.gd) | [GameRoot.gd](../../Scripts/Application/GameRoot.gd)、[GameWorldView.gd](../../Scripts/Application/GameWorldView.gd) |

当前地图交付设置引用 human、wolf、snake、spider、stump_beast 等 Factory 类别；地图存在 giant_rat ID 不代表该 NPC 已开放。unit_scale 等适配值影响实际部署尺寸，不能只比较源角色编辑界面的大小。

召唤演出入口为 [SummonBattleStage3D.tscn](../../Scenes/Application/SummonBattleStage3D.tscn)，通过 `DefaultSummonAnimation.tres / stage_scene` 引用。生物部件在组装点附近随机喷出，`part_spawn_radius` 默认 2，`part_interval` 默认 0.1 秒。`creature_start_interval` 默认 1 秒，多只生物并行召唤。两类部件向上喷发速度均为 10–14，真实部件水平速度上限 `part_horizontal_speed` 默认 1.5；真实部件完全出地后开启地形碰撞并自由运动，至少 `part_free_motion_duration`（默认 1 秒）且真实接地后才关闭碰撞并吸附。连接在组装期间隔离，完成后展示保存姿态。视觉散件按 `decoration_interval`（默认 0.12 秒）持续喷发，复用有上限的池，直到所有生物完成后停止新增并淡出。观察、暂停和跳过保持生效，不回写存档。完整参数见[应用系统说明](../../Docs/Systems/Application/README.md)。

召唤场景初始俯角为 35°，镜头按活动圆和完整生物取景；黑色环境与暗色地面通过 [SummonGroundFade.gdshader](../../Shaders/SummonGroundFade.gdshader) 衔接。地面材质的 `ground_color`、`fade_start`、`fade_end` 控制颜色与边缘渐黑；碰撞和空气墙保持完整。此设置仅作用于召唤演出。
