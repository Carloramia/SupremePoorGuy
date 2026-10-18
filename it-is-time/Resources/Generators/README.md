# 生成器默认值与布局

CreatureGeneratorDefaults.parameters 保存每种生成器独立默认值；子类通过 _get_defaults_path() 选择文件。场景里的序列化覆盖与 use_manual_layout 仍会影响最终结果，不会因修改默认文件自动重写所有现有角色。

系统说明：[README.md](../../Docs/Systems/Creatures/README.md)。下面记录 2026-10-18 当前工作区的直接引用，未展开所有继承与动态路径。

| 配置文件 | 数据脚本 | 直接引用者（最多两项） |
|---|---|---|
| [BeastGeneratorDefaults.tres](BeastGeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | [BeastGenerator.gd](../../Scripts/Creatures/Generators/BeastGenerator.gd) |
| [BirdGeneratorDefaults.tres](BirdGeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | [BirdGenerator.gd](../../Scripts/Creatures/Generators/BirdGenerator.gd) |
| [HornedBeastGeneratorDefaults.tres](HornedBeastGeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | [HornedBeastGenerator.gd](../../Scripts/Creatures/Generators/HornedBeastGenerator.gd) |
| [HumanGeneratorDefaults.tres](HumanGeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | [HumanGenerator.gd](../../Scripts/Creatures/Generators/HumanGenerator.gd) |
| [HumanReferenceCalibration.tres](HumanReferenceCalibration.tres) | 内嵌或继承资源 | [HumanGenerator.gd](../../Scripts/Creatures/Generators/HumanGenerator.gd) |
| [RatkinGeneratorDefaults.tres](RatkinGeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | [RatkinGenerator.gd](../../Scripts/Creatures/Generators/RatkinGenerator.gd) |
| [SnakeGeneratorDefaults.tres](SnakeGeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | [SnakeGenerator.gd](../../Scripts/Creatures/Generators/SnakeGenerator.gd) |
| [SpiderGeneratorDefaults.tres](SpiderGeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | [SpiderGenerator.gd](../../Scripts/Creatures/Generators/SpiderGenerator.gd)、[BuildSpiderFrameFittedParts.gd](../../Tools/BuildSpiderFrameFittedParts.gd) 等 3 处 |
| [StumpBeastGeneratorDefaults.tres](StumpBeastGeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | [StumpBeastGenerator.gd](../../Scripts/Creatures/Generators/StumpBeastGenerator.gd) |
| [WolfGeneratorDefaults.tres](WolfGeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | [WolfGenerator.gd](../../Scripts/Creatures/Generators/WolfGenerator.gd) |
| [Rats/Rat1GeneratorDefaults.tres](Rats/Rat1GeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | 未发现完整字面路径引用，需结合动态加载/编辑器配置 |
| [Rats/Rat2GeneratorDefaults.tres](Rats/Rat2GeneratorDefaults.tres) | [CreatureGeneratorDefaults.gd](../../Scripts/Creatures/Generators/CreatureGeneratorDefaults.gd) | 未发现完整字面路径引用，需结合动态加载/编辑器配置 |

[BirdParts](BirdParts) 与 [SpiderParts](SpiderParts) 保存精确 PartSceneRule、布局和内部形状；不要把这些叶资源当成默认值总表。Rats 的 Rat1/Rat2 默认文件独立保存。
