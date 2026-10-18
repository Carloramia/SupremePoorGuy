# 专用攻击配置

WolfPounce 与 WolfBite 由 WolfAttackController 的独立子模组执行；RatsBite 与 SnakeBite 使用专用接收器。RatsPounceDisabled 是禁用预设，不表示当前 Rat 开放飞扑。

系统说明：[README.md](../../Docs/Systems/Combat/README.md)。下面记录 2026-10-18 当前工作区的直接引用，未展开所有继承与动态路径。

| 配置文件 | 数据脚本 | 直接引用者（最多两项） |
|---|---|---|
| [RatsBite.tres](RatsBite.tres) | [RatBiteAttackData.gd](../../Scripts/Creatures/RatBiteAttackData.gd) | [RatsBiteAttackController3D.tscn](../../Scenes/Creatures/Components/RatsBiteAttackController3D.tscn) |
| [RatsPounceDisabled.tres](RatsPounceDisabled.tres) | [WolfAttackData.gd](../../Scripts/Creatures/WolfAttackData.gd) | 未发现完整字面路径引用，需结合动态加载/编辑器配置 |
| [SnakeBite.tres](SnakeBite.tres) | [SnakeBiteAttackData.gd](../../Scripts/Creatures/SnakeBiteAttackData.gd) | [SnakeBiteAttackController3D.gd](../../Scripts/Creatures/SnakeBiteAttackController3D.gd)、[SnakeBiteAttackController3D.tscn](../../Scenes/Creatures/Components/SnakeBiteAttackController3D.tscn) |
| [WolfBite.tres](WolfBite.tres) | [WolfAttackData.gd](../../Scripts/Creatures/WolfAttackData.gd) | [WolfAttackController3D.tscn](../../Scenes/Creatures/Components/WolfAttackController3D.tscn) |
| [WolfPounce.tres](WolfPounce.tres) | [WolfAttackData.gd](../../Scripts/Creatures/WolfAttackData.gd) | [WolfAttackController3D.tscn](../../Scenes/Creatures/Components/WolfAttackController3D.tscn) |
