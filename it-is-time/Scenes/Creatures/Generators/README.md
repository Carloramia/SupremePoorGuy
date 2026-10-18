# 生物生成器

[_BaseCreatureGenerator](_BaseCreatureGenerator.tscn) 挂载 [BaseCreatureGenerator.gd](../../../Scripts/Creatures/Generators/BaseCreatureGenerator.gd)。物种脚本负责结构差异，共用 PartSceneRule、手动布局、框架展示与默认预设读写。`CreatureGenerator` 是保留的 Beast 兼容入口，不是所有物种共同的场景父节点。

## 调整入口

- `overall_scale` 控制整体比例；`part_width` 控制生成框架的 Z 厚度。
- Beast 有后腿/前腿数量、体长、Torso 数量与轮廓曲线；Bird、Human、Spider、Snake、Rats 使用专门的结构参数。
- `part_scene_rules` 指定后续物理部件。匹配优先级为非空 `part_key` 精确匹配，其次精确 `part_name`，最后 `part_type`；同层级取首个匹配。PartKey 可在生成部件 Metadata 的 `generated_part_key` 查看。
- `size_mode` 管理模型与框架的匹配；`use_joint_markers` 和 `align_connectors_to_frame` 需要先校准 Marker，不能用来补偿错误图片原点。
- `use_manual_layout=true` 时使用捕获布局，不再由随机参数重新决定姿态。修改参数后看不到布局变化时先检查此开关。

“将当前参数保存为默认值”通过物种 `_get_defaults_path()` 写入独立 [默认 `.tres`](../../../Resources/Generators/README.md)，不修改共同父类源码。已有场景实例的序列化覆盖值仍会优先于初始化默认值；要变更现有角色，还要保存相应场景。

角色根节点的“生成框架与物理角色”“将当前部件姿态写入生成器”和“自动对齐连接点”不是同一个按钮。前者装配物理角色，捕获用于持久化，自动对齐处理锚点；执行后检查日志和保存结果。

详细使用：[手动布局](手动布局使用说明.txt)、[Spider](SpiderGenerator使用说明.txt)、[Snake](SnakeGenerator使用说明.txt)、[StumpBeast](StumpBeastGenerator使用说明.txt)。

## 当前生成器场景

| 场景 | 挂载脚本或直接父场景 |
|---|---|
| [_BaseCreatureGenerator.tscn](_BaseCreatureGenerator.tscn) | [BaseCreatureGenerator.gd](../../../Scripts/Creatures/Generators/BaseCreatureGenerator.gd) |
| [BeastGenerator.tscn](BeastGenerator.tscn) | [BeastGenerator.gd](../../../Scripts/Creatures/Generators/BeastGenerator.gd) |
| [BirdGenerator.tscn](BirdGenerator.tscn) | [BirdGenerator.gd](../../../Scripts/Creatures/Generators/BirdGenerator.gd) |
| [CreatureGenerator.tscn](CreatureGenerator.tscn) | [CreatureGenerator.gd](../../../Scripts/Creatures/CreatureGenerator.gd) |
| [HornedBeastGenerator.tscn](HornedBeastGenerator.tscn) | [HornedBeastGenerator.gd](../../../Scripts/Creatures/Generators/HornedBeastGenerator.gd) |
| [HumanGenerator.tscn](HumanGenerator.tscn) | [HumanGenerator.gd](../../../Scripts/Creatures/Generators/HumanGenerator.gd) |
| [RatkinGenerator.tscn](RatkinGenerator.tscn) | [RatkinGenerator.gd](../../../Scripts/Creatures/Generators/RatkinGenerator.gd) |
| [RatsGenerator.tscn](RatsGenerator.tscn) | [RatsGenerator.gd](../../../Scripts/Creatures/Generators/RatsGenerator.gd) |
| [RatsGenerator_Rat1.tscn](RatsGenerator_Rat1.tscn) | [RatsGenerator.tscn](RatsGenerator.tscn) |
| [RatsGenerator_Rat2.tscn](RatsGenerator_Rat2.tscn) | [RatsGenerator.tscn](RatsGenerator.tscn) |
| [SnakeGenerator.tscn](SnakeGenerator.tscn) | [SnakeGenerator.gd](../../../Scripts/Creatures/Generators/SnakeGenerator.gd) |
| [SpiderGenerator.tscn](SpiderGenerator.tscn) | [SpiderGenerator.gd](../../../Scripts/Creatures/Generators/SpiderGenerator.gd) |
| [StumpBeastGenerator.tscn](StumpBeastGenerator.tscn) | [StumpBeastGenerator.gd](../../../Scripts/Creatures/Generators/StumpBeastGenerator.gd) |
| [WolfGenerator.tscn](WolfGenerator.tscn) | [WolfGenerator.gd](../../../Scripts/Creatures/Generators/WolfGenerator.gd) |
