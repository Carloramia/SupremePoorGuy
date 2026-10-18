# 应用、存档与生物实例

## 主入口

| 文件 | 职责 |
|---|---|
| [GameRoot.tscn](../../../Scenes/Application/GameRoot.tscn)、[GameRoot.gd](../../../Scripts/Application/GameRoot.gd) | 主菜单、地图、部署、战斗、结算及设置的宿主 |
| [GameSession.gd](../../../Scripts/Application/GameSession.gd) | 统一存档、交易、召唤、编队、新手待办和战斗结算 |
| [GameUIController.gd](../../../Scripts/Application/GameUIController.gd) | 在 PaperUI 上接入真实游戏会话与界面操作 |
| [CreatureFactory.gd](../../../Scripts/Application/CreatureFactory.gd) | 读取保存的 NPC 场景，生成可存档的姿态与部件记录，部署真实角色 |
| [CreaturePortraitRenderer.gd](../../../Scripts/Application/CreaturePortraitRenderer.gd) | 角色实际视觉的正交截图、白底头像与缓存 |
| [DeliveryMapBridge.gd](../../../Scripts/Application/DeliveryMapBridge.gd) | 正式地图模块与统一存档、界面的适配 |
| [WorldMapSessionSave.gd](../../../Scripts/Application/WorldMapSessionSave.gd) | 保留的 Frontier 地图存档适配 |

## 存档边界

GameSession 继承 [PrototypeState](../../../Modules/PaperUI/Scripts/PrototypeState.gd)，扩展真实角色、地图状态和战斗回执。正式路径是 `user://saves/slot_01.json`，不是原型类默认的 `user://prototype_session.json`。当前游戏只能由同一会话协调经济、队伍和战斗结算；失败时保留可重试状态，不能在 UI 内绕过会话直接重复发奖励。

地图与战斗结果通过 `battle_id/request_id` 和回执避免重复提交。修改存档结构前同时检查 `_valid_save()`、读档恢复、结算和备份处理。不要把测试临时存档写进真实槽位。

## 角色定义与召唤池

`CreatureFactory.DEFINITIONS` 当前登记 `human`、`stump_beast`、`wolf`、`snake`、`horned_beast`、`spider`；其中 `human` 指向持矛人形 NPC。当前随机召唤池仅为：

```text
stump_beast, wolf, snake, horned_beast, spider
```

Bird、Rat、Ratkin 和其他武器人形已有测试资源，但不会因场景存在就自动加入该池。敌方编队通过 [敌方阵容配置](../../../Resources/Application/README.md) 另行指定。

Factory 读取已经保存的角色姿态进行部署，不在每场战斗重新随机生成框架。它保存 NodePath 对应的变换、部件标识、HP、护甲和模板场景哈希；修改模板后，旧记录可能因哈希或结构不匹配而被拒绝。引用路径和保存布局都属于生物数据的一部分。

头像来自角色视觉渲染，不是模型文件的静态缩略图。无图形模式使用占位图；图形模式负责截图、缓存与请求失效处理。详见 [头像说明](../../Creatures/生物头像生成说明_2026-10-16.txt)。

## 常见扩展

- 新增可召唤物种：先完成 Part、Generator、角色、NPC 与攻击接线，再登记 Factory 定义；需要随机抽取时才改 `SUMMON_POOL`。
- 调整地图敌人：改敌方 `.tres` 与对应地图的配置 ID，不通过修改召唤池实现。
- 修改玩家初始数据：检查 `GameSession.reset()`、继承的 PrototypeState 与新手进度，不只改 UI 展示文字。

相关验证：[会话](../../../Tests/Integration/ValidateGameSession.gd)、[完整宿主](../../../Tests/Integration/ValidateGameRoot.gd)、[恢复与结算](../../../Tests/Integration/ValidateApplicationRecovery.gd)。
