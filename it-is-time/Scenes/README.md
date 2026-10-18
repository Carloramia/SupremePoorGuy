# 场景导航

| 目录 | 入口和用途 |
|---|---|
| [Application/GameRoot](Application/GameRoot.tscn) | F5 正式流程 |
| [Levels](Levels) | 独立测试关卡与调试宿主，不自动等同正式游戏入口 |
| [Creatures/Characters](Creatures/Characters/README.md) | 角色模板、NPC 与武器人形变体 |
| [Creatures/Generators](Creatures/Generators/README.md) | 框架参数、Part 映射和生成预览 |
| [Creatures/Bodyparts](Creatures/Bodyparts/README.md) | 物理身体部件与源模型 |
| [Creatures/Components](Creatures/Components) | 可挂载的移动、AI、伤害、攻击、装备和支撑组件 |
| [Creatures/Modules](Creatures/Modules/README.md) | 可装配的空/视觉/物理模组模板 |
| [Items](Items) | SampleItem、SampleWeapon、实体武器与临时攻击体 |
| [Environment/FrontierBattle](Environment/FrontierBattle) | 静态厚度环境件，碰撞使用独立开关 |
| [Camera/DragCamera3D](Camera/DragCamera3D.tscn) | 右键环绕、缩放与 Follow Target |
| [Input](Input)、[Player](Player) | 输入接收、地形光标、可挂接 Controller 与轮盘 |
| [Workshop](Workshop)、[Masks](Masks) | 材料网格工坊、右侧选项、构建按钮和模糊遮罩 |
| [Debug](Debug)、[VFX](VFX) | 控制台、输出、描边、伤害数字、方向弧和冲击波 |

继承场景修改会被实例自己的导出值、根节点脚本、子节点覆盖和手动布局快照再次覆盖。调试前先确认实际实例的 Scene File Path、Script 和 `.tres` 引用，尤其是 `_NPC` 对基础角色的覆盖。

不要把可运行的预览场景、模型包装场景和 PhysicalBodyPart3D 场景混用。新 Part 应从身体基类继承，新武器应从物品/武器基类继承，新生物则接入生成角色与 NPC 的结构。
