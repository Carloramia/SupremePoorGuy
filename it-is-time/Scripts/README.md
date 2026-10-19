# 脚本职责导航

| 目录 | 主要职责 | 系统说明 |
|---|---|---|
| [Application](Application) | 应用宿主、会话、Factory、头像、地图/战斗适配、部署、新手待办 | [应用](../Docs/Systems/Application/README.md) |
| [Events](Events) | 剧情目录、纯逻辑事务和现有UI适配；不另建玩家槽位 | [剧情事件](../Docs/Systems/StoryEvents/README.md) |
| [Creatures](Creatures) | 身体、生成、密度、连接、物种控制、AI、恢复与攻击 | [生物](../Docs/Systems/Creatures/README.md)、[运动与 AI](../Docs/Systems/MovementAI/README.md) |
| [Combat](Combat) | Arm 控制组、挥舞、持武器姿态与 Bow 射击 | [战斗](../Docs/Systems/Combat/README.md) |
| [Damage](Damage) | 全局伤害数据与 Autoload 服务 | [伤害链](../Docs/Systems/Combat/README.md) |
| [Audio](Audio) | 战斗音效配置、空间播放、冷却和生命周期 | [音效](../Docs/Systems/Audio/README.md) |
| [Items](Items) | 物品、武器、装备、辅助持握、箭矢、临时攻击体 | [装备](../Docs/Systems/EquipmentWorkshop/README.md) |
| [Materials](Materials) | 材料 Resource 基类与 TestMaterial | [材料](../Docs/Systems/EquipmentWorkshop/README.md) |
| [Workshop](Workshop)、[UI](UI) | 材料网格、连接点、面板、构建与界面遮罩 | [工坊](../Docs/Systems/EquipmentWorkshop/README.md) |
| [Input](Input)、[Player](Player)、[Camera](Camera) | 输入接收、控制对象、光标、轮盘、摄像机 | [输入与摄像机](../Docs/Systems/InputCamera/README.md) |
| [Geometry](Geometry) | 地形查询、纸片厚度 Mesh 与静态环境 Part | [资源链](../Assets/README.md) |
| [VFX](VFX)、[Shaders](../Shaders/README.md) | 描边、伤害数字、弧线与冲击波 | [伤害与特效](../Docs/Systems/Combat/README.md) |
| [Debug](Debug)、[Performance](Performance) | 控制台、诊断、可视化、按需统计与性能开关 | [日志与性能](../Docs/Systems/DebugExport/README.md) |
| [Localization](Localization) | 文本键、回退、语言设置与绑定 | [本地化](../Localization/README.md) |
| [Quests](Quests) | 独立通用任务 Resource/服务，当前未接入会话 | [任务接线边界](../Resources/Quests/README.md) |

Autoload 仅以 [project.godot](../project.godot) 为准：GameLocalization、DamageService、CombatAudio、WorkshopUIController、RuntimeConsole。其他脚本不会仅因位于 Scripts 自动运行。

共享方法优先放到已有父类/服务；物种差异保留在专用子类。编辑器工具脚本需要 `@tool`；正式运行脚本不能直接依赖模板里不存在的 EditorInterface 等编辑器类，编辑器分支采用动态单例访问。
