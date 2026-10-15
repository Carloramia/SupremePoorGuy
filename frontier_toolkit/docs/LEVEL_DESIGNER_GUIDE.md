# 地编人员场景编辑使用手册

适用项目：克隆或解压后的项目根目录。引擎：Godot 4.7.2。更新日期：2026 年 10 月 7 日。

本手册面向负责地图布局、建筑摆放、地点配置、道路制作和场景验收的地编人员。按本文操作，可以从现有 Demo 复制工作场景，编辑内容并独立运行检查。需要新增游戏逻辑、随机地图生成、角色移动或交互业务时，由程序接入。

## 目录

1. [选择模块与打开项目](#1-选择模块与打开项目)
2. [编辑器操作与资源管理](#2-编辑器操作与资源管理)
3. [大地图制作流程](#3-大地图制作流程)
4. [大地图地点与交互](#4-大地图地点与交互)
5. [大地图道路与速度区域](#5-大地图道路与速度区域)
6. [大地图调试与重置](#6-大地图调试与重置)
7. [25d-场景制作流程](#7-25d-场景制作流程)
8. [25d-建筑立片与交互物件](#8-25d-建筑立片与交互物件)
9. [25d-遮挡摄像机与出生点](#9-25d-遮挡摄像机与出生点)
10. [完整练习与验收](#10-完整练习与验收)
11. [常见问题](#11-常见问题)
12. [交付规范与参考资料](#12-交付规范与参考资料)

## 1 选择模块与打开项目

### 1.1 先确定制作对象

| 制作对象 | 使用模块 | 参考场景 | 当前能力 |
| --- | --- | --- | --- |
| 世界探索、旅行、事件入口 | `world_map` | `world_map/demo/WorldMapDemo.tscn` | 六边形有效区域、障碍导航、发现与迷雾、地点交互、道路吸附和加速、存档 |
| 据点、战场、建筑内部或局部探索空间 | `scenario_2_5d` | `scenario_2_5d/demo/Scenario25DDemo.tscn` | 3D 布局、固定角度正交镜头、纸绘立片、鼠标拾取、遮挡淡化、出生点标记 |

两个模块使用同一个 `project.godot`，内容目录独立。大地图道路具备移动规则；2.5D Demo 的 Road 只是道路视觉。2.5D 框架当前没有角色行走、导航烘焙、战斗或真正开箱对话逻辑，地编应验收画面、碰撞、拾取和接口配置。

### 1.2 打开与运行

1. 启动 Godot 4.7.2。项目管理器选择“导入”，选择 项目根目录的 `project.godot`，再选择“导入并编辑”。
2. 等待资源导入完成，在文件系统面板双击需要编辑的 `.tscn`。
3. 大地图使用顶部“2D”工作区；局部场景使用“3D”工作区。
4. Ctrl+S 保存，F6 运行当前场景，F8 停止。F5 始终运行项目主场景，目前是大地图。

`.godot` 是自动生成的缓存目录，`project.godot` 才是项目入口，`.tscn` 是可编辑场景，`.tres` 是配置资源，`.gd` 是脚本。不要双击缓存目录内的文件来编辑关卡。

引擎不随 GitHub 包分发。安装 Godot 后设置 `GODOT_BIN` 或给脚本传 `-GodotPath`，详见 [首次运行](GETTING_STARTED.md)。可在项目根目录 PowerShell 中打开编辑器：

```powershell
./world_map/tools/Run-Demo.ps1 -Editor
./scenario_2_5d/tools/Run-Demo.ps1 -Editor
```

选择对应的一条命令即可。脚本启动方式与普通 Godot 启动方式使用不同的用户数据目录，详见第 6 节。

## 2 编辑器操作与资源管理

### 2.1 常用操作

| 任务 | 操作 |
| --- | --- |
| 选择整个物件 | 在左侧场景树选物件根节点，避免只移动视觉子节点 |
| 精确摆放 | 右侧检查器展开 Transform，填写 Position；同时核对 Rotation 和 Scale |
| 复制物件 | 场景树中 Ctrl+D，然后改名、改位置，检查资源与 ID |
| 添加节点 | 选中父节点，使用“添加子节点”搜索 Node2D、Area2D、Polygon2D、Node3D 等 |
| 挂载脚本 | 将文件系统中的 `.gd` 拖到节点或检查器 Script 字段 |
| 赋值资源 | 将 `.tres`、`.png` 或 `.tscn` 拖到对应资源字段 |
| 编辑 3D 物件 | 使用移动、旋转、缩放工具；默认 W/E/R，F 聚焦所选物件 |
| 对齐摆放 | 打开工具栏吸附并设置步长；资源中的道路坐标仍需直接填写 |
| 撤销与保存 | Ctrl+Z；Ctrl+S；另存场景使用“场景 → 另存为” |

检查器会把 `interaction_offset` 显示为 `Interaction Offset` 等形式。本文表格保留代码字段名，便于定位。快捷键若被团队修改，以工具栏提示为准。

运行时的 Remote／远程场景树可用于观察实际生成的节点。远程修改用于临时调试，停止运行后通常不保留；正式配置应在 Local／本地场景和资源中修改，再保存重启。

### 2.2 复制场景不等于复制资源

另存 `.tscn` 后，新场景可能仍引用 Demo 的 `.tres`、材质、Mesh 和碰撞 Shape。修改这些共享资源可能同时改变原场景。

制作独立关卡时：

1. 另存工作场景到自己的关卡目录。
2. 在需要独立修改的资源字段菜单中选择 **Make Unique／使唯一**。
3. 再使用资源菜单 **Save As／另存为**，保存到关卡自己的 `data/` 目录。
4. 确认字段引用新路径，改 ID、参数，然后保存场景。

地图／场景 Definition 必须独立。相同类型的地点可以共享 LocationDefinition，但每个地点节点必须有不同的 `location_id`。2.5D 交互物件的 `object_id` 在 Definition 中，复制箱子或 NPC 后需要独立 Definition 和新 ID。贴图可共享；希望独立改变尺寸或颜色的 Mesh、Shape、材质先使唯一。

### 2.3 推荐目录与命名

以下是需要自行创建的目录示例：

```text
world_map/levels/valley_01/
├─ Valley01.tscn
└─ data/
   ├─ ValleyDefinition.tres
   └─ ShrineDefinition.tres

scenario_2_5d/levels/camp_01/
├─ Camp01.tscn
├─ data/
│  ├─ SceneDefinition.tres
│  └─ SupplyCrate01.tres
└─ assets/
```

ID 使用稳定英文，例如 `valley_01`、`valley_shrine_01`、`camp_supply_crate_01`。显示名称可以中文。ID 发布后不要随意更改，大地图存档通过地点 ID 恢复状态。通过 Godot 文件系统面板移动、重命名资源，避免引用丢失。不要编辑 `.godot/` 或将正式内容放进 `debug/`。

## 3 大地图制作流程

### 3.1 建立工作地图

1. 打开 `world_map/demo/WorldMapDemo.tscn`，另存为自己的关卡场景。
2. 选根节点，将 `definition` 使唯一，另存地图 Definition。
3. 改 `map_id` 和 `display_name`。根节点 `save_path` 改为独立路径，例如 `user://valley_01_save.json`，防止读取 Demo 的探索和地点状态。
4. 先保留 Demo 的布局与测试 UI，F6 确认工作场景可以运行。
5. 根据需求修改 Obstacles、Roads、Locations，再逐项验收。

根节点挂载 `world_map/core/world_map_controller.gd`。保留直接子节点 `Obstacles`、`Roads`、`Locations` 的名称与管理脚本，框架按这些入口收集配置。组织节点保持 Scale=(1,1)、Rotation=0。根节点可平移，但初次制作建议保持原点，便于计算位置。

地表、玩家、导航、相机、迷雾和 HUD 主要在运行时创建。编辑器未显示完整地图是当前实现方式，不能据此判断地图损坏。地点和道路提供编辑器占位绘制；最终有效区域与通行效果需要 F6 检查。

### 3.2 地图范围与出生点

选中根节点并展开 Definition：

| 字段 | 意义与编辑规则 |
| --- | --- |
| `map_id` / `display_name` | 地图稳定身份与显示名称 |
| `width` / `height` | 可视矩形的列数、行数，范围 1～100，默认 16×12 |
| `hex_size` | 六边形中心到顶点的距离，默认 64 世界单位 |
| `disabled_hexes` | 禁用六边形的 axial 坐标数组，元素为 Vector2i(q,r) |
| `spawns` | 出生点字典，键为字符串 ID，值为 Vector2 地图局部坐标 |
| `default_spawn_id` | 默认出生点 ID，必须与字典键一致 |
| `discovery_radius` | 首次发现地点的默认半径，默认 240 |
| `interaction_radius` | 到交互点触发交互的默认半径，默认 42 |
| `vision_radius` | 玩家实时视野半径，默认 210 |
| `generator_config` | 生成接口预留配置，当前不能靠填写字典自动生成随机地图 |

大地图坐标为 X 向右、Y 向下，半径与道路宽度使用世界单位。默认出生点为 `harbor → Vector2(120,220)`。根节点 `spawn_id` 可指定某个入口；有效旧存档中的玩家位置会优先于初始出生配置。出生点应放在有效区域内、障碍外，并留出角色通行空间。

调整地图尺寸或 `hex_size` 不会自动缩放已经摆放的地点、道路、障碍或出生点，需要一起重新检查。

根节点 `player_speed` 是基础移动速度，默认 165 世界单位／秒，道路与泥地的倍率以它为基础。`player_visual_scene` 可指定玩家视觉 PackedScene；需要制作新玩家视觉时与美术、程序确认节点约定。运行相机由框架创建，当前 Demo 没有供地编直接拖动的持久相机节点；镜头规则调整需程序配置。

### 3.3 禁用 Hex 与理解坐标

运行后开启 Hex debug，读取格子标注的 `(q,r)`，把要移除的格子填入 `disabled_hexes`。保存并重新运行确认边界。禁用格子会同时影响有效地图、通行和地点注册。

标注是 axial 坐标，不能把普通矩形行列号直接填进去。例如默认 `hex_size=64` 时，Hex `(4,2)` 的中心约为 `(384,443.4)`，其视觉行号为 4。需要精确计算时使用：

```text
x = 1.5 × hex_size × q
y = √3 × hex_size × (r + q/2)
```

通常直接读取运行中的调试标注更方便。大地图连续移动不要求地点或道路点必须位于 Hex 中心。

### 3.4 编辑山体、湖泊与阻挡

1. 选中 `Obstacles/RockRidge` 或 `Obstacles/Lake`。
2. 在 2D 工作区使用 Polygon2D 多边形编辑工具移动顶点；也可展开 Polygon 数组填写精确坐标。
3. 改 Color 以区分山体、水面等占位表现。
4. 新增障碍时，复制一个已有 Polygon2D，或在 `Obstacles` 下直接添加 Polygon2D，绘制闭合、无自交的轮廓。
5. 保存、停止旧运行、F6 重启，从障碍两侧点击测试。

框架启动时从有效 Hex 与 `Obstacles` 下的直接 Polygon2D 子节点生成导航和实体碰撞。改变颜色只改变表现；放在其他容器中的装饰 Polygon2D 不会自动成为导航障碍。当前没有运行时动态重烘焙。

角色碰撞半径约 9，导航留边半径为 10。不要把通道宽度设计成刚好 20；拐角和斜边需要额外空间。地点交互点、出生点及道路中心线都要离障碍边界留出余量。道路视觉不会覆盖或解除障碍阻挡。

## 4 大地图地点与交互

### 4.1 新增地点

1. 在 `Locations` 下复制已有地点，或创建 Node2D 并挂载 `world_map/locations/world_map_location.gd`。地点必须是该容器的直接子节点。
2. 改节点名，例如 Shrine01，并填写唯一 `location_id`，例如 `valley_shrine_01`。
3. 将 Position 设为图标位置。
4. 为 `definition` 赋值 LocationDefinition。需要新名称或独立行为时先使唯一并另存 `.tres`。
5. 调整 `interaction_offset`，检查青色交互点位于合法、可到达区域。
6. 保存并 F6；走进发现范围，悬停、点击，再完成一次交互。

| 节点字段 | 配置方式 |
| --- | --- |
| `location_id` | 地点实例 ID，必须非空且唯一；复制后立即修改 |
| `definition` | 地点静态配置，不能为空 |
| `interaction_offset` | 相对地点节点的交互点偏移，默认 (0,35) |
| `discovery_radius` | -1 使用地图默认值；非负数覆盖默认值 |
| `interaction_radius` | -1 使用地图默认值；非负数覆盖默认值 |
| `completion_behavior_override` | -1 继承 Definition；0～3 覆盖完成行为，见下表 |

**图标位置不是导航目的地。** 例如节点 Position=(350,300)、Offset=(150,0)，玩家要去的是 (500,300)。图标放在可走地面，但交互点落在山体内时，点击仍会报告无法到达。Demo 的 `BlockedSite` 正是这个故意设置的失败用例；它与事件地点使用相同定义名称，制作正式地图时应移除或重新配置，避免误认。

编辑器显示发现圈与交互圈，但继承地图半径的最终效果以运行时为准。部分参数改动后可能需要重新运行才更新绘制。

### 4.2 地点 Definition

| 字段 | 意义 |
| --- | --- |
| `type_id` | 类型标识，例如 settlement、battle、event、resource |
| `display_name` / `short_description` | 悬停面板名称与说明 |
| `icon` | 可选 Texture2D；缺省时显示 `marker_glyph` |
| `marker_color` / `marker_glyph` | 图标颜色及占位字符 |
| `repeatable` | 是否可重复交互 |
| `completion_behavior` | 非重复地点完成后的行为 |
| `interaction_ui_scene` | 正式交互界面的 PackedScene，必须正确配置 |
| `scenario_scene` | 城镇“进入场景”选项打开的 2.5D PackedScene；留空时不显示该入口 |
| `encounter_data` | 交互业务的数据字典，键的约定由接入程序确定 |

`type_id` 不是自动选择界面的开关。应同时指定 `world_map/ui/` 下对应的 `SettlementPanel.tscn`、`BattlePanel.tscn`、`EventPanel.tscn` 或 `ResourcePanel.tscn`。新界面与新业务需程序实现后再配置。

| 完成行为 | 数值 | 非重复地点完成后 |
| --- | --- | --- |
| KEEP | 0 | 图标保留，状态变为已完成，通常不能再次交互 |
| HIDE_SESSION | 1 | 本次场景会话隐藏；本会话 Load 仍隐藏，新会话加载时恢复 |
| REMOVE_PERMANENTLY | 2 | 永久移除状态写入存档，重启不复活 |
| RESPAWNABLE | 3 | 隐藏，等待外部系统显式恢复；当前没有计时刷新 |

`repeatable=true` 的地点完成后保持可交互，例如 Demo 城镇。完成行为配置数值不是运行生命周期状态数值，不要手工混用。

地点首次被发现后可以在视野外保留暗色图标。点击地点会去精确交互点，不执行道路目标吸附。正式交互面板需要完成操作才能退出；Demo 战斗使用测试适配器，不能当作正式战斗内容。

城镇现可通过“进入场景 / Enter town”打开应用内 2.5D 悬浮窗口。进入时地图持续冻结，原弹窗暂时隐藏；点击窗口“返回大地图 / Return”或场景结束后，关闭窗口并结束原交互，恢复地图。城镇保持可再次访问。窗口内的场景每次重新创建，当前不保存其内部状态。目标场景配置与错误处理见 [悬浮场景说明](../integration/README.md)。

## 5 大地图道路与速度区域

### 5.1 新建或修改道路

1. 选中 `Roads/Road` 或 `Roads/SouthRoad`；新增时复制已有道路并改名。
2. 也可在 `Roads` 下创建 Area2D，挂载 `world_map/roads/world_map_road.gd`。
3. 组织节点与道路保持单位缩放、零旋转。初次制作建议道路 Position=(0,0)，使中心线坐标直接对应地图坐标。
4. 在检查器展开 `center_line`，设置数组长度，逐个填写 Vector2 点；至少两个不同的点。
5. 调整宽度、吸附距离、倍率和颜色。保存并运行检查弯道、交叉口、目标 marker 和移动路线。

| 字段 | 默认值 | 意义 |
| --- | --- | --- |
| `center_line` | 两点折线；Demo 使用多点 | 道路局部坐标，按行进顺序连接 |
| `road_width` | 64 | 路面与速度区域总宽度 |
| `snap_margin` | 24 | 路面边缘外额外吸附距离 |
| `speed_multiplier` | Demo 为 1.5 | 道路上的移动速度倍率 |
| `priority` | Demo 为 10 | 重叠速度区域的优先级 |
| `surface_color` / `edge_color` | 棕色／深棕色 | 路面和路边的占位表现 |

当前没有专用道路画笔或可拖拽的中心线控制柄，使用检查器数组编辑点。道路可在编辑器预览，运行时自动生成各段矩形和端点／拐点圆形碰撞区域，无需手工增加 CollisionShape2D。

### 5.2 点击吸附与沿线移动

地面点击距离中心线不超过 `road_width/2 + snap_margin` 时，目标吸附到最近中心线。例如宽 64、Margin 24 时，阈值为 56 世界单位，缩放镜头不会改变阈值。点击更远的普通地面时，目标保留原位置。

玩家在道路外会先通过普通导航接入道路，再逐段经过中心线拐点。道路上移动时沿中心线行进，不在弯道斜切。主路与支路可在公共端点、真正交叉点或 T 形连接处换路；路面看似接触不等于中心线连通，推荐连接处使用完全一致的坐标。互不连通道路间可能通过普通地面导航接入目标道路。

每段中心线必须可以直线通行。穿过山体、湖泊或禁用格的路段不会因为画了道路就可通行。原始点击位于障碍或地图外时也会拒绝；吸附不能把非法点击变成合法移动。地点点击仍使用地点交互点。

制作道路时逐项检查：

- 中心线每个点和连接段都在有效地图内，远离障碍边缘。
- 支路中心线确实接到主路，避免只有路面重叠。
- 弯道每段方向清晰，避免连续重复点或极短折返。
- 门口、地点交互点的偏移符合体验；需要到地点时，普通导航允许离开道路。

### 5.3 泥地与重叠速度

Demo 的 Mud 为 Area2D，挂载 `world_map/player/world_map_speed_area.gd`，使用 CollisionPolygon2D 定义区域。可复制它制作泥地、缓行区，调整碰撞多边形、`speed_multiplier` 和 `tint`。

重叠区域只采用最高 `priority` 的倍率，不叠乘。Demo 道路为 Priority 10、倍率 1.5；Mud 为 Priority 20、倍率 0.5，重叠处表现为减速。避免依赖相同优先级的选择顺序。`priority` 是 Area2D 自带属性，可在检查器搜索。

速度区的占位绘制依据 CollisionPolygon2D。换用其他碰撞形状时，物理效果与占位显示未必一致，应自行提供视觉并运行检查。

## 6 大地图调试与重置

### 6.1 运行检查

| 操作或开关 | 用途 |
| --- | --- |
| 左键地面 | 验证移动、道路吸附和不可达反馈 |
| 右键拖动／滚轮 | 平移、缩放镜头 |
| Focus on traveler | 回到玩家并恢复跟随 |
| Hex debug | 在迷雾上方显示有效格边界与 axial 坐标；关闭后隐藏，不改变探索与通行 |
| Location / nav debug | 辅助检查地点交互点与导航；配合实际路径确认目的地 |
| Save／Load | 验证单槽状态保存与恢复 |

发现范围、视野范围和交互范围是三件事。图标已发现但暗色，不代表地点不可交互；是否可达还取决于交互点和导航。路线上接近某个未选中地点不会自动弹出其界面。

### 6.2 重置世界内容

重置存档会清除旅行位置、探索轨迹、发现状态和地点完成状态，场景文件与静态地图配置仍然保留。

1. F8 停止游戏，防止退出或自动保存再次写入文件。
2. 确认根节点 `save_path`，默认文件名是 `world_map_save.json`；自制地图可能使用另一个名字。
3. 找到本次启动方式实际使用的用户数据目录，将对应 JSON 改名为备份，例如 `world_map_save.backup.json`。
4. F6 重启，检查玩家从配置出生点出现，地点和探索恢复初始状态。

本机默认路径：

| 启动方式 | 默认存档 |
| --- | --- |
| 普通 Godot／项目管理器启动 | `%APPDATA%\Godot\app_userdata\WorldMap · Frontier\world_map_save.json` |
| 本项目 Run-Demo.ps1 启动 | `<项目根目录>\.tools\userdata\Godot\app_userdata\WorldMap · Frontier\world_map_save.json` |

账户名或项目名称变化后路径也会变化。编辑器“项目 → 打开用户数据文件夹”可用于定位当前环境。启动方式不同的两个目录彼此独立，不要只重置其中一个却从另一个启动。

根节点 `auto_load=false` 可跳过初始读档，但后续保存仍可能写入 `save_path`。调试新关卡优先使用独立测试文件；交付前核对加载设置。不要用删除 `.godot` 缓存来重置世界。

## 7 2.5D 场景制作流程

### 7.1 建立新关卡

1. 打开 `scenario_2_5d/demo/Scenario25DDemo.tscn`，另存为自己的 `.tscn`。
2. 保留测试 Hero、DemoUI、CameraRig、InteractionController、OcclusionController。
3. 根节点 `definition` 使唯一，另存 SceneDefinition，修改 `scene_id` 与 `display_name`。
4. 根节点及 Geometry、Actors 等组织节点保持原点、零旋转、单位缩放。
5. 先摆地面与建筑，再摆树木、交互物件和出生点，最后调整镜头、光照与淡化。
6. 保存、F6，用测试 UI 检查拾取、遮挡与画面。F5 会进入大地图。

更详细的逐物件操作与参考截图见 [2.5D 场景地编使用手册](../scenario_2_5d/docs/SCENARIO_25D_LEVEL_DESIGNER_GUIDE.md)。

### 7.2 场景树职责

| 节点 | 地编操作 |
| --- | --- |
| Geometry/Ground、Road、Plaza | 修改地面、道路、广场布局 |
| Geometry/Building、BackWall、Obstacle | 摆放建筑、墙、普通阻挡，核对碰撞 |
| Actors/Hero、NPC、Crate、Tree | 摆放角色参考、NPC、箱子、树与立片 |
| CameraBounds | 设置手工镜头边界 |
| CameraRig/CameraPivot/Camera3D | 固定角度镜头，保留控制器引用 |
| Lighting | 环境与主光源 |
| SpawnRoot/Arrival | 提供出生点位置与朝向 |
| NavigationRoot | 后续导航接入位置，当前为空 |
| DemoUI | 运行测试面板；正式集成时由程序替换 |

坐标 X 为左右，Z 为前后，Y 为高度，平地表面为 Y=0。编辑器视角可自由旋转，运行镜头保持固定角度。移动建筑或箱子时选择整个根节点，使 Mesh、碰撞和视觉一起移动。

### 7.3 编辑地面与道路

Demo 地面 Ground 是 StaticBody3D，下面包含 MeshInstance3D 和 CollisionShape3D，加入 `scenario_ground` 组。地面顶部应对齐 Y=0。扩大地面时同时修改 Mesh 与碰撞尺寸，确保光标看到的地面都有对应碰撞。

新增地面推荐复制 Ground，保留组和碰撞。射线只有命中带 `scenario_ground` 组的实体才发出地面点击事件。组在节点面板的 Groups／组标签配置。

Road 与 Plaza 是稍高于地面的视觉 Mesh，适当保持很小高度差以避免闪烁。它们没有大地图道路的加速、中心线吸附或行走逻辑。场地扩大后还要同步修改镜头边界。

## 8 2.5D 建筑立片与交互物件

### 8.1 建筑与碰撞

复制 Building 后移动根节点，再修改墙体、屋顶 Mesh 和 CollisionShape3D。独立改 Mesh/Shape 尺寸前先使唯一。碰撞体应覆盖实际可见建筑，而不是整个庭院；过大碰撞会挡住背后的地面与物件点击，过小碰撞会漏过可见墙体。

普通 StaticBody3D 障碍可以挡住拾取射线。需要建筑或树遮挡玩家时变透明，必须再配置 Occluder 脚本与层，见第 9 节。导入模型可用于视觉，但不会自动生成正确碰撞、交互或淡化接口，应另外配置对应节点。

### 8.2 纸绘立片

角色、树、箱子的 Billboard 节点挂载 `scenario_2_5d/visuals/billboard_visual_3d.gd`。内部 QuadMesh 在运行时生成，编辑器没有立片实时预览，改参数后必须 F6 看最终效果。

| 字段 | 用途 |
| --- | --- |
| `texture` | 带透明背景的 Texture2D，建议 PNG |
| `visual_height` | 世界空间中的立片高度 |
| `visual_scale` | X/Y 视觉比例 |
| `ground_offset` | 脚底相对物件地面的偏移 |
| `pivot_offset` | 立片视觉偏移 |
| `linear_filter` | true 平滑过滤；false 用于像素风近邻过滤 |

立片自动计算底部锚点，只绕 Y 轴朝向运行摄像机。脚底漂浮时先检查物件根节点 Y、PNG 底部透明留白和 `ground_offset`；不要靠移动运行生成的 QuadMesh 解决。PNG 导入保持透明边缘修正，缩放较多的贴图保留 mipmaps。

BlobShadow 为地面的软阴影，`shadow_size` 控制尺寸、`opacity` 控制透明度。立片不投真实 Quad 阴影。视觉高度变化不会自动调整实体碰撞体，应同步调整。坡地、跨层阴影贴合需额外系统支持，当前优先制作水平场地。

### 8.3 新增箱子或 NPC

1. 复制 `Actors/Crate` 或 `Actors/NPC`，修改节点名与位置。
2. 将 `definition` 使唯一并另存，改为新 `object_id`。
3. 设置显示名称、描述、类型与贴图。
4. 核对物件的视觉引用指向自己的 Billboard，检查 CollisionShape3D 的位置和尺寸。
5. 保存、运行，悬停和点击，确认选择的是新物件与新 ID。

| InteractableDefinition 字段 | 规则 |
| --- | --- |
| `object_id` | 稳定、唯一身份，不能用运行时 instance_id；复制后修改 |
| `display_name` / `description` | 面板文字 |
| `interaction_type` | 交互业务标识，默认 inspect；填写类型不会自动实现业务 |
| `icon` | 可选面板图标 |
| `tags` / `metadata` | 分类与外部业务数据，按程序约定填写 |

运行状态的 enabled、selected、custom_state 由每个实例独立维护。地编配置静态 Definition；业务运行状态交给程序管理。

拾取使用最近命中的碰撞体，不是逐像素检测 PNG。透明区域也可能落在矩形碰撞范围内，因此需要认真调整 Shape。没有 Definition 的物件交互会禁用，但其碰撞仍能挡住射线。

## 9 2.5D 遮挡摄像机与出生点

### 9.1 配置遮挡淡化

需要淡化的物件采用 StaticBody3D，挂载 `scenario_2_5d/occlusion/occluder_3d.gd`，添加对应 Collider 与 Mesh。Collision Layer 勾选第 1、第 2 层，数值为 3；第 1 层用于拾取，第 2 层用于遮挡检测。

目标在角色或重要物件下添加 Marker3D，挂载 `scenario_2_5d/occlusion/occlusion_target.gd`，位置放到胸口或可见中心。脚本类名是 OcclusionTarget，运行时加入的组名为 `scenario_occlusion_target`。默认选中物件也会获得临时选择目标，但高度不一定适合所有尺寸的物件。

运行中将目标置于建筑前后，检查遮挡时淡化、移开后恢复。普通 StandardMaterial3D 与默认纸绘 Shader 支持淡化；自定义 Shader 需程序适配。碰撞体过大会导致“没有挡住也透明”，过小会导致漏检。Blob Shadow 不参与树木淡化。

### 9.2 镜头参数与边界

在根节点 Definition 中编辑：

| 字段 | 默认值 | 含义 |
| --- | --- | --- |
| `camera_bounds` | Rect2(-18,-14,36,28) | X/Z 平面边界，Rect2 的 Y 对应世界 Z |
| `default_camera_size` | 20 | 初始正交观察范围，越大看得越远 |
| `min_camera_size` / `max_camera_size` | 10 / 26 | 缩放范围，均须大于 0，min 不大于 max |
| `camera_drag_smoothing` / `camera_zoom_smoothing` | 20 / 12 | 平移与缩放平滑频率，使用正值 |
| `camera_margin` | 2 | 镜头边界余量 |
| `zoom_step` | 1.5 | 滚轮步长 |
| `default_scene_mode` | EXPLORE | 初始探索或战斗事件模式 |

CameraRig 上 `yaw_degrees`、`pitch_degrees`、`distance` 控制固定视角。默认 Pitch=-50°，初次制作保留原角度，先完成布局。直接修改运行 Camera3D 的姿态可能被控制器覆盖，应改持久配置。

绑定 CameraBounds 节点时，它的 `bounds` 会覆盖 Definition 的边界，优先修改该节点，并同步 Definition 作为备用配置。边界为世界 X/Z 坐标，不会因给 CameraBounds 节点拖动位置而自动得到新的 Rect2。

运行时按住中键拖动，滚轮缩放。检查所有边缘与窗口比例；正交镜头视野随缩放和宽高比变化。场地比镜头视野小的轴会锁在中心，仍露出空白时需要扩大场地或减小最大镜头 Size。

### 9.3 光照与出生点

Lighting 下环境光和主光源共同决定建筑的明暗。纸绘 Shader 保留较多贴图原色，与普通 3D 材质的受光表现不同。调整灯光后同时观察建筑、立片与地面，避免只凭编辑器预览判断效果。

在 SpawnRoot 下复制 Arrival 或创建 Marker3D，挂载 `scenario_2_5d/spawn/spawn_point_3d.gd`，设置唯一 `spawn_id`、位置、朝向和可选 metadata。出生点仅提供真实 3D Transform，当前不会自行生成角色，也不会让 Demo Hero 自动移动到它。

NavigationRoot 当前只是接入位置。不要把“物件有碰撞”当作“已经有单位寻路”；需要导航、坡地、高低差行走或战斗规则时，在交付说明中给程序明确需求。

## 10 完整练习与验收

### 10.1 大地图练习

1. 将 Demo 另存为 Valley01，独立保存 Definition，设置 `map_id=valley_01` 与 `save_path=user://valley_01_save.json`。
2. 暂时保持默认范围与障碍，出生点保留 (120,220)。
3. 在 Roads 下新增一条道路，Position=(0,0)，中心线为 (120,220) → (200,340) → (200,490)，宽 64、吸附 24、倍率 1.5、优先级 10。这是 Demo 已有道路的前段，可先替换原道路，避免重复重叠。
4. 在 Locations 下复制城镇到 (200,490)，新 ID 为 `valley_town_01`，交互偏移 (0,35)，其余先继承。
5. F6 后点击拐角前后的道路，观察目标吸附和依次过弯；再点击城镇，确认角色离开中心线到精确交互点并打开界面。
6. Save、重启，确认状态恢复；备份测试存档后再次启动，确认初始出生与发现流程。

### 10.2 2.5D 练习

1. 将 Demo 另存为 Camp01，独立保存 SceneDefinition，改 `scene_id=camp_01`。
2. 复制 Crate，向场地空旷处移动 2 个 X 单位，Definition 使唯一另存，填写 `object_id=camp_supply_crate_02`。
3. 复制 Building 并整体移动，先保持原尺寸与碰撞，确保没有完全覆盖箱子或地面入口。
4. F6，点击两个箱子确认 ID 不同；在建筑前后测试 Hero 遮挡，用中键拖动和滚轮检查布局。
5. 改一处 Billboard 的 visual_height，运行确认，再调整碰撞高度以匹配视觉。

Demo 的 Hero 前后切换按钮使用原 Demo 的固定坐标。新布局中按钮位置可能不再适合，需通过本地场景调整测试 Hero 位置，或让程序调整测试工具。

### 10.3 每轮编辑的人工验收

| 验收项 | 大地图 | 2.5D |
| --- | --- | --- |
| 打开与运行 | F6 无脚本报错，正确读取独立配置 | F6 无脚本报错，控制器引用完整 |
| 布局 | 出生、地点、道路均位于有效区 | 物件根节点位置正确，地面高度一致 |
| 障碍 | 从两侧寻路，窄通道可通行，无穿山 | Mesh 与 Shape 匹配，拾取不会穿墙 |
| 道路 | 吸附阈值合理，弯道沿线，支路连通 | 视觉不闪烁，不误当作寻路功能 |
| 交互 | 每个 ID 唯一，交互点可达，面板正确 | 每个 ID 唯一，悬停、选择与请求正确 |
| 范围 | 发现、视野、交互分别符合需求 | 镜头最大／最小缩放与四边符合需求 |
| 状态 | 完成行为、读档、重置符合配置 | 淡化恢复，运行状态不污染资源 |
| 表现 | 图标、颜色、道路与阻挡易于辨认 | 贴图脚底、阴影、遮挡与光照协调 |

框架回归测试可在项目根目录执行：

```powershell
./world_map/tools/Run-Tests.ps1 -Render
./scenario_2_5d/tools/Run-Tests.ps1 -Render
```

这些脚本检查框架与参考 Demo，不会自动遍历或验收新建关卡。新关卡仍需完成上述人工检查；新业务规则由程序添加相应验证。

## 11 常见问题

| 现象 | 检查顺序与处理 |
| --- | --- |
| 改了场景但运行内容没变 | Ctrl+S；确认当前标签与 F6；F5 可能启动另一场景；不要只改 Remote 节点 |
| 复制场景后 Demo 也变了 | 外部资源仍共享；还原误改，然后 Make Unique、Save As，再编辑 |
| 大地图编辑器没有玩家或完整地表 | 这些节点运行时创建，F6 看最终画面 |
| 图标看着可达，点击却失败 | 开地点调试，检查真正 interaction_point；再查障碍、禁用 Hex、导航留边 |
| 地点不出现 | ID 非空且唯一、Definition 非空、节点是 Locations 直接子节点、图标在有效区；再查发现距离与旧存档生命周期 |
| 改出生点没有变化 | 有效存档恢复位置优先；停止运行，备份对应存档，再试 |
| 道路不吸附 | 确认 WorldMapRoad 脚本、至少两个不同点、点击距离与有效地面；点击地点不会吸附 |
| 支路无法沿路连接 | 核对中心线连接而非路面相接；连接点使用一致坐标，检查整段有无障碍 |
| 路上没有加速或反而减速 | 检查 speed_multiplier、优先级；高优先级 Mud 会覆盖道路倍率 |
| Hex debug 没看到网格 | 确认运行最新保存场景并打开开关；检查有效范围；输出若有脚本错误先处理错误 |
| 2.5D 编辑器没有树或人物贴片 | 当前运行时生成 QuadMesh，F6 查看；检查 texture 与高度 |
| 2.5D 物件点不到／点到旁边 | 查 Collider、Layer 1、前方挡住射线的实体及物件 Definition；不是按 PNG 不透明像素拾取 |
| 2.5D 地面没有点击反馈 | 地面须有 Collider、Layer 1 与 scenario_ground 组；查上方实体及全屏 UI 是否阻止输入 |
| 建筑没有淡化 | 查 Occluder 脚本、Layer 2、目标 Marker、Collider、材质支持和 Fade 开关 |
| 物件未挡住也淡化 | Collider 过大或目标位置不合适，核对实际射线遮挡 |
| 拖镜头后露空／不能拖 | 核对 CameraBounds 的覆盖值、真实地面范围、最大 Size、输入锁定状态 |
| 点击地面角色不走 | 2.5D 当前只发地面事件，行走需外部系统接入 |
| 出生点没有生成角色 | SpawnPoint 是位置接口，需要外部生成器使用 |

发现报错时记录：场景路径、节点路径、操作步骤、Output／Debugger 中完整报错、使用哪个启动脚本、是否清过存档，并附上失败位置截图。不要通过增大所有交互半径、关闭碰撞等方式掩盖布局错误。

## 12 交付规范与参考资料

### 12.1 交付文件

- 关卡 `.tscn` 与独立 Definition `.tres`，引用完整且位于对应模块目录。
- 新增贴图、模型、材质及其必要导入配置；运行时测试存档和 `.godot` 缓存不作为关卡内容交付。
- 地图／场景 ID、所有地点／交互物件／出生点 ID 清单。
- 一张总览与关键入口、交互点、道路连接处截图。
- 人工验收结果、已知问题、需要程序接入的交互／战斗／导航需求。
- 大地图完成行为与测试存档路径；2.5D 摄像机边界、初始模式与出生点说明。

多人协作尽量按关卡或独立物件场景分工，避免同时编辑同一个 `.tscn`。复用组件可以另存独立场景再实例化；需要调整内部资源时仍遵循共享资源规则。

2.5D 正式集成时，由程序将根节点从 Demo 脚本改为 `scenario_2_5d/core/scenario_controller.gd`，核对三个控制器引用，替换 DemoUI 并接入业务系统。地编验收阶段保留测试入口；不要删除测试 UI 后误以为开箱、战斗或角色移动已经接入。

### 12.2 项目内参考

- [项目入口与启动命令](../README.md)
- [世界地图配置及接口说明](../world_map/README.md)
- [世界地图测试清单](../world_map/docs/WORLD_MAP_TEST_CHECKLIST.md)
- [2.5D 地编详细手册与截图](../scenario_2_5d/docs/SCENARIO_25D_LEVEL_DESIGNER_GUIDE.md)
- [2.5D 框架说明](../scenario_2_5d/README.md)
- [2.5D 测试清单](../scenario_2_5d/docs/SCENARIO_25D_TEST_CHECKLIST.md)

遇到需要调整底层坐标、路网算法、摄像机投影、交互信号或自定义 Shader 的问题，结合模块 README 与架构文档交给程序处理；地编继续在已支持的节点、资源和布局范围内制作。
