# 地图内容与引用

| 目录 | 地位 |
|---|---|
| [FrontierDelivery_20261015](Maps/FrontierDelivery_20261015) | 当前默认地图包，含运行时 JSON、转换出的场景与素材 |
| [IntegrationFrontier_v1](Maps/IntegrationFrontier_v1) | 保留的 Frontier 集成地图与 SceneDefinition 资源 |
| [Sources](Maps/Sources) | 原始关卡编辑工程及来源资料，不直接等同运行时地图 |

正式地图索引是 [Data/Maps/index.json](Maps/FrontierDelivery_20261015/Data/Maps/index.json)，通过 [MapCatalog](../Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd) 读取其 `.maps[id].data`。地图文件通常位于同目录，Scenes/Maps 与 Scenes/Maps3D 为相应预览/实例化包装。不要只改预览场景而遗漏 JSON。

[FrontierDeliveryBattle.tres](../Resources/Application/FrontierDeliveryBattle.tres) 指定敌方阵容资源和战场适配比例；[EnemyRosters](../Resources/Application/EnemyRosters) 的定义 ID 最终由 CreatureFactory 解析。地图资源 ID、配置 ID、地点 ID 和生物 definition_id 是不同键，应在各自映射处修改。

地图装饰的 3D 物理资源在 [Scenes/Environment](../Scenes/Environment/FrontierBattle)、[3DResources/Environment](../Assets/3DResources/Environment/FrontierBattle) 和 [Meshes/Environment](../Resources/Meshes/Environment)。默认禁用碰撞的装饰仍可显示，实际碰撞以资源和地图策略为准。

重新导入使用 [ImportDeliveryMaps.py](../Tools/Integration/ImportDeliveryMaps.py) 或 [ImportFrontierLevel.ps1](../Tools/Integration/ImportFrontierLevel.ps1)，先阅读参数和来源清单；它们可能重写转换产物，不能把手工场景调整当作唯一源数据。

JSON 是运行时必需的非资源文件，导出时必须显式包含。事件、点击、通行和战斗路由排查用 `trackmap on`、`mapstate`、`trackintegration on`。详见 [地图系统](../Docs/Systems/WorldMapUI/README.md)。
