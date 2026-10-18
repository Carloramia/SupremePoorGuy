# 大地图、UI 与战斗部署

## 正式路径与保留路径

[GameRoot](../../../Scripts/Application/GameRoot.gd) 默认 `use_delivery_map=true`，通过 [DeliveryMapBridge](../../../Scripts/Application/DeliveryMapBridge.gd) 接入 [FrontierDelivery](../../../Modules/FrontierDelivery)。保留的 [Frontier 世界地图](../../../Modules/Frontier/world_map) 用于备用集成与原型验证，不应再同时创建另一个独立存档会话。

界面从 [GameDemo.tscn](../../../Modules/PaperUI/Scenes/GameDemo.tscn) 实例化后改挂 [GameUIController](../../../Scripts/Application/GameUIController.gd)，用真实会话替换原型行为。直接单独运行 GameDemo 的展示、战斗跳过和独立存档，不等于正式流程行为。

## 内容和配置

| 入口 | 内容 |
|---|---|
| [index.json](../../../Content/Maps/FrontierDelivery_20261015/Data/Maps/index.json) | 地图、资源 ID 与美术策略索引 |
| [MapCatalog](../../../Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd) | 按 ID 读取运行时地图 JSON 并缓存 |
| [WorldMapRuntime](../../../Modules/FrontierDelivery/Scripts/Map/WorldMapRuntime.gd) | 路径、地点、交互与事件状态 |
| [FrontierDeliveryBattle.tres](../../../Resources/Application/FrontierDeliveryBattle.tres) | 战场适配、比例与敌方阵容表 |
| [DeliveryBattleEnvironmentAdapter](../../../Scripts/Application/DeliveryBattleEnvironmentAdapter.gd) | 把战斗地图环境和部署区接到 BattleHost |
| [BattleHost](../../../Scripts/Application/BattleHost.gd) | 独立 3D 世界、导航、部署、实际生物与结果 |
| [BattleDeployment3D](../../../Scripts/Application/BattleDeployment3D.gd) | 友军部署区、位置合法性与拖动 |

地图 JSON、场景资源和原始关卡工程的分工见 [Content](../../../Content/README.md)。地图/阵容 ID 是接口，不随显示名称翻译。巨鼠地图保留配置入口，不代表巨鼠 NPC 已开放。

## UI 资源

[Screens](../../../Modules/PaperUI/Scenes/UI/Screens) 放主菜单、任务、仓库、召唤、结果与详情界面。[UI 资源](../../../Modules/PaperUI/Assets/UI) 与 [TA](../../../Modules/PaperUI/TA) 放字体、纸面、墨迹、贴图和材质绑定。GameRoot 的 `ui_skin_preset` 默认引用 [medium.tres](../../../Modules/PaperUI/TA/Presets/medium.tres)；替换资源时也检查 light/strong 的共享引用。

`Localization` 负责可见文本，字体与中文形状渲染仍依赖资源正确导出。不要编辑图片上的字来替代文本键，也不要在来源工程改完后假设主项目会自动同步。

## 部署、暂停与设置

战斗加载后先进入 deployment。友方在左、敌方在右；仅友军可在允许部署区内移动，禁止与其他生物或启用碰撞的障碍重叠，不开放旋转，只影响本场战斗。部署确认后才开始物理战斗。

应用使用带 reason 的暂停管理：设置、界面、工坊或手动暂停可以叠加，关闭其中一个界面不应释放其他原因的暂停。部署的停驻逻辑也不能当作运行时攻击故障处理。

Esc 在开始后的各阶段打开设置；设置可调整分辨率、全屏、语言并返回主菜单。正式战斗 Space 暂停/继续，Q 切换自由系统鼠标。默认自由地形光标与“没有玩家 Controller”是明确设计，不是漏生成角色控制器。

运行时地图摆放物通过 [静态物理装饰](../../../Scenes/Environment/FrontierBattle) 与 `BattleEnvironmentPhysicalPart3D` 显示；是否碰撞由 `collision_enabled` 和地图策略决定，不能依据可见性推断碰撞已启用。

排查命令：`trackmap on`、`mapstate`、`trackintegration on`。既有说明：[部署](../../Integration/战斗前部署阶段_2026-10-16.txt)、[设置与返回](../../Integration/全阶段ESC与返回主菜单_2026-10-16.txt)、[地图接入](../../Integration/地图与UI交付包接入实施记录_2026-10-16.txt)。
