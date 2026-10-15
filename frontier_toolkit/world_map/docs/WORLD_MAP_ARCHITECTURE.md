# WorldMap 架构

```text
Viewport unhandled input (Control UI 优先消费)
    ↓
WorldMapController
    ├─ HexGrid / WorldMapDefinition (有效空间、axial 身份)
    ├─ WorldMapPlayer (CharacterBody2D + NavigationAgent2D)
    │     ├─ WorldMapNavigation (每实例独立 NavigationServer2D map)
    │     ├─ Line2D / 目标 marker (真实剩余路径)
    │     └─ SpeedArea registry (最高 priority 单一区域)
    ├─ WorldMapCameraController (FOLLOW_PLAYER / FREE)
    ├─ WorldMapRoadManager (道路注册表、最近中心线吸附、接路导航)
    │     ├─ WorldMapRoadRouter (中心线路网、交叉点拆分、最短道路路径)
    │     └─ WorldMapRoad : WorldMapSpeedArea (折线视觉、圆角速度区域)
    ├─ WorldMapFog (轨迹数据 → 低分辨率 mask；shader 当前圆形视野)
    ├─ WorldMapLocationManager (稳定 ID、发现、marker hit test)
    │     └─ LocationInteractionController
    │           └─ Definition.PackedScene → 各类型独立 UI
    ├─ WorldMapUI (HUD / Tooltip / 不可取消 modal)
    └─ WorldMapRuntimeState (无节点)
             ↓
       WorldMapSaveService (版本验证、JSON、临时文件替换)

LocationInteractionController → battle_requested(data)
                                   ↓
                             外部 Battle host
                                   ↓
WorldMapController.resolve_location_interaction(id, result)
```

核心不存在 `/root/GameManager` 或 SceneTree 全局暂停依赖。运行时按引用和信号连接子系统。FakeBattleAdapter 在 demo 中接收 battle_requested，展示独立 UI 并回传 victory/defeat/error；不属于地点行为。宿主可替换它，不改变核心。

普通移动目标与地点交互意图分离：点击地点设置两个目标；随后点击地面只改变移动目标；只有所选地点的 interaction_point 距离进入半径才弹 UI。路过仅发现。正式交互时取消路径、模块暂停；UI 返回统一结果，由协调器应用生命周期、清目标、解除暂停并保存。

道路地面点击：原始点通过有效区域/静态障碍检查 → RoadManager 投影到范围内最近的折线中心 → RoadRouter 按交叉点构建路网，验证每段中心线并求道路路径 → 用 Navigation 接入道路 → Player 连续逐段跟随中心线，精确经过拐点。显示的路径是实际接路导航与中心线路线的组合。地点 interaction_point 绕过道路吸附。道路是静态场景配置，路线不进入 RuntimeState；沿线生成速度 Area2D 碰撞，沿用现有最高优先级覆盖规则。道路在地表之上、Fog 之下绘制，不随 Hex 对齐。

静态障碍为可编辑 Polygon2D，加载时生成一次 NavigationPolygon 和物理碰撞。有效 Hex 的联合轮廓参与导航烘焙，disabled Hex 同时被数据、点击、地点放置和玩家下一步有效性检查拒绝。无 Hex Node。TileMapLayer 仅是视觉层，不参与身份或存档。

状态以 map_id + location_id 为持久身份。运行状态保存 JSON 原始值；探索从 capsule 轨迹恢复；永久移除保留墓碑。HIDE_SESSION 在同会话读档保留，新会话恢复 AVAILABLE。移动路径、UI Node、instance_id 不持久化。

战斗前保存 pending_battle 及完整地图状态。场景重建后恢复地图和交互、重发 pending request，外部通过 API 写回；此流程不依赖 Autoload。可选 session adapter 也能用纯 Dictionary 快照保留并恢复会话。

生成器无复杂算法。固定配置输入 → GenerationResult 契约 → manager 注册描述。固定 Hex 数据在地表/导航初始化前覆盖，场景已有固定地点优先。运行时主动 replace 的描述可重建，不扫描全 SceneTree。

性能：固定尺寸 fog mask；直线轨迹合并；不遍历 Hex Node；少量地点使用直接距离检查；registry 的发现/命中算法将来可替换空间索引。核心脚本按职责拆分，最长为约 400 行的协调器。
