# 引入模块与适配边界

| 模块 | 用途 | 生产接线 |
|---|---|---|
| [PaperUI](PaperUI) | 纸面 UI、召唤格盘、符文规则、仓库/任务/详情页面和 TA 资源 | GameRoot 创建 GameDemo 场景后改挂 GameUIController，使用统一 GameSession |
| [FrontierDelivery](FrontierDelivery) | 当前地图交付包的 JSON 目录、运行时状态和地图视图 | DeliveryMapBridge、MapCatalog、DeliveryBattleEnvironmentAdapter |
| [Frontier](Frontier) | 保留的世界地图、寻路、交互、存档与 2.5D 场景框架 | 备用世界地图与 SceneDefinition/场景适配；不是另一个正式会话 |

[sources.json](sources.json) 与 [FrontierDelivery/sources.json](FrontierDelivery/sources.json) 保存来源路径和导入哈希，用于比对来源与已安装文件。来源工程目录是制作/同步来源，不是要求玩家机器存在的运行时路径。

主项目适配代码优先在 Scripts/Application；直接运行模块里的 demo 会使用其原型行为。模块原注释中的“仅展示”“跳过战斗”“独立原型存档”不能覆盖 GameUIController/GameSession 的正式行为。

同步工具 [SyncModules.py](../Tools/Integration/SyncModules.py) 可能与本地修改冲突，执行前先检查 source/installed 哈希和差异，不覆盖已经接入的主项目改动。[Frontier 许可说明](Frontier/LICENSE_NOTICE.md)、字体和素材来源说明应保留。

界面资源主要在 Modules/PaperUI/Assets/UI 和 TA，不只在顶层 Assets。正式地图数据在 Content/Maps，模块提供加载和状态逻辑。具体接口见 [地图与 UI](../Docs/Systems/WorldMapUI/README.md)。
