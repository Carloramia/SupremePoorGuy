# 大地图、UI 与战斗部署

## 正式路径与保留路径

[GameRoot](../../../Scripts/Application/GameRoot.gd) 默认 `use_delivery_map=true`，通过 [DeliveryMapBridge](../../../Scripts/Application/DeliveryMapBridge.gd) 接入 [FrontierDelivery](../../../Modules/FrontierDelivery)。保留的 [Frontier 世界地图](../../../Modules/Frontier/world_map) 用于备用集成与原型验证，不应再同时创建另一个独立存档会话。

界面从 [GameDemo.tscn](../../../Modules/PaperUI/Scenes/GameDemo.tscn) 实例化后改挂 [GameUIController](../../../Scripts/Application/GameUIController.gd)，用真实会话替换原型行为。直接单独运行 GameDemo 的展示、战斗跳过和独立存档，不等于正式流程行为。

## 内容和配置

2026-10-19 六边形地图已成为新游戏默认地图，旧档继续绑定原版。新版索引为 [Runtime/index.json](../../../Content/Maps/FrontierEditor_20261019/Runtime/index.json)，已接通 31 处营地，8 处因缺少物种绑定保留禁用；完整行为、日志、生成工具及验证见 [实际接入记录](新版六边形地图接入_2026-10-19.md)。原始资源对应关系仍见 [更新方案](地图交接包资源对应与更新方案_2026-10-19.md)。

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

## 游戏时间与旅行速度

大地图左上角的 [WorldTimeHUD.tscn](../../../Scenes/Application/WorldTimeHUD.tscn) 显示天数、时分和玩家旅行速度。新游戏默认第 1 天 08:00、旅行速度 600 地图单位/游戏小时。

```text
旅途耗时（游戏分钟）= 实际走过的地图距离 / 玩家旅行速度 × 60
```

逐段累计实际移动距离，绕路也计入，保留不足一分钟的小数；瞬移、镜头拖动、缩放和被拒绝的目的地不计路程。速度翻倍，同路程的游戏耗时减半。画面移动沿用地图现有节奏。停留、浏览菜单和暂停不推进时间。

[GameRoot](../../../Scripts/Application/GameRoot.gd) 根节点的 `World Time Settings` 引用 [DefaultWorldTime.tres](../../../Resources/Application/DefaultWorldTime.tres)，数据类型为 [WorldTimeSettings](../../../Scripts/Application/WorldTimeSettings.gd)。可在 Inspector 调整 `Starting Hour`、`Starting Travel Speed` 和 `Interaction Minutes`：

| 交互键 | 默认耗时（分钟） | 结算时机 |
|---|---:|---|
| `visit` | 5 | 实际抵达并成功访问地点，每次访问结算一次 |
| `clear_obstacle` | 15 | 成功清除路障 |
| `summon` | 30 | 大地图召唤交易成功提交，即使本批没有成功召唤结果 |
| `study` / `collect` | 15 / 10 | 保留地图中的研读/收集成功提交 |
| `battle` | 20 | 战斗结果首次成功结算，撤退也算一次；取消载入不计 |

旅行速度只影响旅途耗时，交互耗时独立配置，设为 0 即不消耗时间。仅打开仓库、调整队伍或取消操作不额外耗时。战斗不按现实秒数推进游戏时间。

时间和速度保存在同一游戏槽位的 `world_time.total_minutes`、`world_time.travel_speed`，`day` 同步跨天。旧存档保留原天数并补上默认时刻和速度，不会清空角色、地图或任务。移动沿用每秒/到达保存，并在菜单阻止地图输入时补存未满一秒的旅程；保存失败时正式地图的位置和时间一起回滚。初始设置用于新游戏和没有时钟字段的旧存档，已有时间/速度的存档继续使用保存值。

运行时修改玩家旅行速度使用 `GameRoot.set_world_travel_speed(1200.0)`，它先提交当前旅程，再保存新属性；返回 `false` 时读取 `session.last_error`。扩展成功交互时在原交易的保存前调用 `session.spend_world_action("交互键")`，失败时随该交易一起回滚数据。自定义等待可调用 `advance_world_minutes()` 并通过 `GameRoot.save_session()` 保存。

素材替换：打开 `WorldTimeHUD.tscn`，选根节点，在 Inspector 设置 `Background Texture`、`Time Icon`、`Travel Icon`、`Display Font`、`Font Size`、`Text Color`；面板框样式可在 Theme Overrides 中替换。空贴图自动隐藏对应图标，不影响文本。整体替换可创建继承该 UI 的场景并指定到 GameRoot 的 `World Time Hud Scene`，保留 `bind_session()` 接口。面板及子控件均忽略鼠标，不遮挡地图点击，界面随现有 UI 缩放，文案已加入中英文本地化。

`mapstate` 和 `trackmap on` 的地图事件包含 `world_time` 快照。验证入口：[ValidateWorldTime](../../../Tests/Integration/ValidateWorldTime.gd)，含时间计算、存档兼容、失败回滚、实际地图移动/交互及素材接口检查。

## 部署、暂停与设置

战斗加载后先进入 deployment。友方在左、敌方在右；仅友军可在允许部署区内移动，禁止与其他生物或启用碰撞的障碍重叠，不开放旋转，只影响本场战斗。部署确认后才开始物理战斗。

应用使用带 reason 的暂停管理：设置、界面、工坊或手动暂停可以叠加，关闭其中一个界面不应释放其他原因的暂停。部署的停驻逻辑也不能当作运行时攻击故障处理。

Esc 在开始后的各阶段打开设置；设置可调整分辨率、全屏、语言并返回主菜单。正式战斗 Space 暂停/继续，Q 切换自由系统鼠标。默认自由地形光标与“没有玩家 Controller”是明确设计，不是漏生成角色控制器。

运行时地图摆放物通过 [静态物理装饰](../../../Scenes/Environment/FrontierBattle) 与 `BattleEnvironmentPhysicalPart3D` 显示；是否碰撞由 `collision_enabled` 和地图策略决定，不能依据可见性推断碰撞已启用。

排查命令：`trackmap on`、`mapstate`、`trackintegration on`。既有说明：[部署](../../Integration/战斗前部署阶段_2026-10-16.txt)、[设置与返回](../../Integration/全阶段ESC与返回主菜单_2026-10-16.txt)、[地图接入](../../Integration/地图与UI交付包接入实施记录_2026-10-16.txt)。
