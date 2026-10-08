# 数据与游戏程序接入

## 文件组织

`index.html`、`styles.css`、`app.js` 为界面和交互；`renderer.js` 为俯视画布；`model.js` 为浏览器/Node 共用模型、几何、引用校验、历史与只读预览状态。`godot/import_world.gd` 读取现有场景，`import_level.gd` 转换初始配置，`battle_preview.gd` 生成预览几何。`examples/` 是地编源文件，`exports/` 是转换输出，`tests/` 是测试与证据。

## 文档版本 1

根对象：`format: "frontier-map-editor"`、`version: 1`、`name`、`assets`、`catalogs`、`maps`。保存和导出都使用这份结构。未识别的扩展字段在序列化往返中保留；不支持的版本或损坏的结构不替换当前工作集。

探索地图 `kind: exploration` 包含 `bounds`、可选 `outline`、`native`、`spawn`、`fog`、`objects`。`native` 保存现有 WorldMapDefinition 参数，地图轮廓与后台 Hex 元数据分开。

战斗地图 `kind: battle` 包含 `radius`、`orientation`、`ground_asset`、`background_asset`、`background_blur`、`edge_feather`、`wall`、`natural_border`、`objects`。平面位置使用 `[X,Z]`。

对象共用 `id,type,name,position,height,rotation,scale,layer,visual`。角度为度；`position` 是世界平面坐标，`points`、`slots` 和范围多边形是对象局部坐标。`visual.size` 不隐式改变碰撞；碰撞、效果、点击区域分别保存在 `collision`、`region`、`click_area`。范围记录 `enabled,shape,offset,size,rotation,points,height,depth`；矩形 size 为宽高，圆形 size[0] 为直径，多边形用 points。对象缩放和旋转再作用于局部范围。物理层是 Godot 位掩码。

`catalogs` 包含 conditions、events、effects、monster_configs、enemy_configs、deployment_rules、options。引用按字符串 ID 关联，不嵌入运行时实例。条件模拟支持 `kind: monster_count,minimum`，其他条件作为外部开关。正式游戏解释规则内容。

## Godot 接口

探索配置完整写入 `WorldMapDefinition.editor_data = { map, assets, catalogs }`；战场完整配置写入 `SceneDefinition.metadata.editor_data`。全工作集另存为 `initial_configuration.json`，适合一个系统集中加载地图关联。

战场每个对象节点带 `editor_object` 元数据；敌方节点另带 monster_config_id。显式实体碰撞生成 `StaticBody3D`，触发范围生成 `Area3D`，部署槽位为 `Marker3D`。碰撞多边形进行凸分解；蛛网 Area 的高度范围按 min/max 导出。空气墙为六个独立 StaticBody3D，与自然装饰分离。

玩法系统读取元数据后连接 Area 信号、按间隔施加效果、按 targets 过滤单位、执行条件、部署和奖励。编辑器不会按渲染帧调用伤害，也不包含正式战斗模拟。深度和体积是配置，不默认生成可跌落的导航洞。

## 初始配置和玩家状态

`History.document` 是唯一可导出的初始配置；FogPreview 的 samples、discovered、destroyed、crossed、rewards、won、fullReveal 独立存放。导出仅序列化 document。游戏存档加载仅替换预览位置、探索记录、发现集合；永不回写文件。

游戏实际存档应分别保存探索轨迹、地标发现、破障、跨越和奖励领取状态。当前已有 Godot 存档的胶囊探索段会在编辑器中采样以复现视野；仅支持已有版本 1 和相同 map_id，其他状态由后续玩法存档扩展。

## 需求覆盖与边界

| 需求 | 编辑器交付 |
| --- | --- |
| S01–S06 | 连续探索 / 独立可调六边形、自然边缘、背景模糊、入口残骸、独立辅助图层 |
| E01–E10 | 道路与所有探索类型的摆放、范围、引用、视觉和参数；破障跨越与营地关联模拟 |
| F01–F10 | 独立迷雾配置、初始区域、路径揭示、渐变、发现分离、隐藏命中策略、全揭示/重置、只读存档预览 |
| B01–B12 | 尺寸与物理边界、碰撞/陷阱体积参数、显式区域、部署槽位、可变数量敌方 |
| 战后交互 | 条件、事件、召唤/升级引用、预览胜利及重复领取检查 |
| 编辑与交付操作 | 放置/选择/变换/复制/删除、节点编辑、撤销重做、预览、保存重开、校验定位、Godot 转换 |

原需求中的“运行时行为”由游戏负责。浏览器场景预览用于验证空间和关联；它不是完整战斗运行器。当前 Godot 大地图的迷雾呈现仍由旧核心执行，新配置完整保存在 editor_data 等待接入。现有 WorldMapDefinition 的导航范围仍由 Hex 核心解释，自定义连续轮廓只作为编辑器布局及新配置传递，未改写核心寻路。正式美术可替换内置占位 SVG。
