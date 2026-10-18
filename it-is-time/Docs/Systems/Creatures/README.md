# 生物生成、部件与模组

## 资源如何组成角色

```text
源图与拆分 PNG
  → GLB / 带厚度 ArrayMesh
  → 继承 _PhysicalSampleBodyParts 的 Part 场景
  → Generator.part_scene_rules
  → 框架蓝图 parts/connections 或捕获的 manual_layout
  → GeneratedParts 下的刚体、Joints 下的连接
  → 移动、AI、攻击、伤害和装备组件
```

相关目录：[资产链](../../../Assets/README.md)、[Part](../../../Scenes/Creatures/Bodyparts/README.md)、[Generator](../../../Scenes/Creatures/Generators/README.md)、[角色引用索引](../../../Scenes/Creatures/Characters/README.md)。

## 两种继承要分别检查

场景继承与 GDScript 继承不是同一条链。通用生成脚本 [GeneratedCreatureCharacter3D](../../../Scripts/Creatures/GeneratedCreatureCharacter3D.gd) 继承 [PhysicalCharacterController](../../../Scripts/Creatures/PhysicalCharacterController.gd)。多数角色场景继承 `_BaseGeneratedCreature.tscn`，但 Snake 的场景直接继承 `_SampleCharacter.tscn`，再挂载专用生成脚本。不要根据场景名字推断实际根脚本。

`GeneratedCreatureCharacter3D` 负责框架装配、部件密度、内部碰撞忽略、连接、模组与运行时激活；物种脚本可以覆盖局部关节、支撑、头部、翅膀或肢体处理。

## 物理标签与生成类型

| 物理标签 | 主要用途 |
|---|---|
| Torso | 躯干、重心、移动推进、存活与断裂判定 |
| SubTorso | 体节分配、腿根及辅助支撑；可与 Torso 共存 |
| Leg / ForeLeg | 接地脚、吸附、滑步状态、迈步及前肢动作 |
| LegLimb | 脚与腿根之间的中间肢体、连接与关节姿态 |
| Arm / ArmLimb | 持握、挥舞和人形手臂链 |
| Head | 头部支撑、攻击相关部位及存活条件 |
| Wing / WingLimb / Feather | 翼段、展开、收拢及羽毛姿态 |
| Tail / Horn | 尾部、角的生成分类与物种附属结构 |

完整枚举以 [PhysicalBodyParts.gd](../../../Scripts/Creatures/PhysicalBodyParts.gd) 为准。已有枚举按整数保存，新增应追加，不能重排旧值。`Neck`、`WingRoot` 等是生成类型/密度键，不代表存在同名的物理标签。

## 尺寸、厚度和质量

- `GeneratedPartSceneRule` 的 `KEEP_SIZE`、`FIT_UNIFORM`、`FIT_BOX` 决定素材与框架的尺寸匹配；连接孔对齐是独立设置，不会自动等同于碰撞箱对齐。
- 生成的纸片自定义 Part 厚度由 `Part Width × Overall Scale` 统一决定。单独编辑源 Part 时可使用 `paper_volume_thickness`，但装配的生成规则可能再次覆盖厚度。
- 身体部件碰撞深度使用视觉厚度的 2 倍机制；不要把它照搬到使用另一脚本的地表静态装饰。
- 密度按生成类型匹配 [Density 资源](../../../Resources/Creatures/README.md)，质量计算再受角色 `mass_limits_enabled` 及上下限影响。物理体根节点保持单位缩放。

## 手工姿态的持久化

1. 在生成角色场景调整部件、内部模型、碰撞或 Marker；先确认正在编辑正确的继承层级。
2. 必要时使用“自动对齐连接点”，检查实际关节锚点和视觉孔洞。
3. 使用“将当前部件姿态写入生成器”，然后保存场景。捕获包括部件内部快照和连接信息。
4. 再次“生成框架与物理角色”并对照姿态。源 Part 版本变化时快照可能被跳过；看 `[manual_layout]` 日志，不把警告当成保存成功。

捕获的 `use_manual_layout=true` 时，布局优先于随机构造。生成器“保存当前参数为默认值”保存物种参数，不代替角色的手动姿态捕获。详见 [手动布局原说明](../../../Scenes/Creatures/Generators/手动布局使用说明.txt)。

## 独立挂件模组

[_SampleModule](../../../Scenes/Creatures/Modules/_SampleModule.tscn) 的 `Parts` 和 `Joints` 可以为空，可承载逻辑、视觉、单个物理件或多段肢体。通过角色的 `module_attachments` 数组挂载 [CreatureModuleAttachment](../../../Scripts/Creatures/Modules/CreatureModuleAttachment.gd)，指定唯一 `instance_id`、宿主 `host_part_key`、可选插槽、偏移与缩放。

物理模组需要指定 `root_part_path`，其内部物理件必须连通。装配后 Part 和 Joint 并入宿主结构，原模板根节点保留视觉/逻辑；使用 `get_host_character()`、`get_host_part()`、`get_module_part()` 获取对象，不依赖直接父节点。

此系统用于生成阶段装配和保存重建，不自动赋予飞行、攻击或 AI，也不等同于运行时肢体移植。详见 [模组模板](../../../Scenes/Creatures/Modules/README.md) 与 [完整接口说明](../../Integration/CreatureModules_2026-10-18.txt)。
