# 地图内容与引用

| 目录 | 地位 |
|---|---|
| [Events/Current](Events/README.md) | 正式剧情正文、原生执行图与实际读取的事件参数；独立于地图Source快照 |
| [FrontierDelivery_20261015](Maps/FrontierDelivery_20261015) | 旧档兼容地图包，含原运行时 JSON、转换出的场景与素材 |
| [FrontierEditor_20261019](Maps/FrontierEditor_20261019/README.md) | 新游戏默认地图；Runtime 为实际接入产物，其余为资源快照与对应表；[接入记录](../Docs/Systems/WorldMapUI/新版六边形地图接入_2026-10-19.md) |
| [IntegrationFrontier_v1](Maps/IntegrationFrontier_v1) | 保留的 Frontier 集成地图与 SceneDefinition 资源 |
| [Sources](Maps/Sources) | 原始关卡编辑工程及来源资料，不直接等同运行时地图 |

新游戏索引为 [Runtime/index.json](Maps/FrontierEditor_20261019/Runtime/index.json)；旧档索引是 [Data/Maps/index.json](Maps/FrontierDelivery_20261015/Data/Maps/index.json)。[MapCatalog](../Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd) 按显式版本读取 `.maps[id].data`，同 ID 的两版内容不混用。不要只改场景而遗漏 JSON。

[FrontierDeliveryBattle.tres](../Resources/Application/FrontierDeliveryBattle.tres) 指定敌方阵容资源和战场适配比例；[EnemyRosters](../Resources/Application/EnemyRosters) 的定义 ID 最终由 CreatureFactory 解析。地图资源 ID、配置 ID、地点 ID 和生物 definition_id 是不同键，应在各自映射处修改。

地图装饰的 3D 物理资源在 [Scenes/Environment](../Scenes/Environment/FrontierBattle)、[3DResources/Environment](../Assets/3DResources/Environment/FrontierBattle) 和 [Meshes/Environment](../Resources/Meshes/Environment)。默认禁用碰撞的装饰仍可显示，实际碰撞以资源和地图策略为准。

重新导入使用 [ImportDeliveryMaps.py](../Tools/Integration/ImportDeliveryMaps.py) 或 [ImportFrontierLevel.ps1](../Tools/Integration/ImportFrontierLevel.ps1)，先阅读参数和来源清单；它们可能重写转换产物，不能把手工场景调整当作唯一源数据。

JSON 是运行时必需的非资源文件，导出时必须显式包含。事件、点击、通行和战斗路由排查用 `trackmap on`、`mapstate`、`trackintegration on`。详见 [地图系统](../Docs/Systems/WorldMapUI/README.md)。
