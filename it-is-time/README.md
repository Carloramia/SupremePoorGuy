# ItIsTime

Godot 4.7.2 的物理生物战斗项目。正式流程为主菜单、大地图、符文召唤、仓库与编队、战斗部署、物理战斗和结算。角色的身体由独立刚体和关节构成，移动与攻击由控制器施加物理作用完成。

## 打开与运行

1. 用 Godot 4.7.2 打开 [工程配置](project.godot)，首次打开等待模型、贴图和全局脚本导入完成。
2. F6 运行当前场景用于单独调试；F5 从 [正式入口 GameRoot](Scenes/Application/GameRoot.tscn) 启动完整流程。
3. 当前玩家版目标是 Windows x86_64，使用 Forward+、Direct3D 12 和 Jolt。项目运行代码为 GDScript，导出使用标准版引擎；遗留 `.csproj/.sln` 不参与该导出流程。
4. 新游戏初始没有赠送角色；完成召唤并编入出战队伍后才能进入战斗。第一次从新游戏进入大地图会打开新手待办。

## 从哪里查找

| 内容 | README |
|---|---|
| 系统入口、依赖和运行流程 | [系统总览](Docs/Systems/README.md) |
| 图片、模型、网格与物理部件的引用链 | [美术资源与引用](Assets/README.md) |
| 步态、AI、攻击、密度和生成器预设 | [配置资源](Resources/README.md) |
| 角色、生成器和可挂载组件场景 | [场景结构](Scenes/README.md) |
| 脚本目录与职责 | [代码导航](Scripts/README.md) |
| 地图配置与敌方编队 | [地图内容](Content/README.md) |
| 引入的 UI、地图与场景框架 | [模块边界](Modules/README.md) |
| 中文、英文与文本键 | [本地化](Localization/README.md) |
| 资源构建、导出与测试工具 | [工具入口](Tools/README.md)、[测试入口](Tests/README.md) |
| 编辑器插件 | [插件说明](addons/README.md) |
| 增量交付包与来源归档 | [交付归档](Deliveries/README.md) |
| 既有实施报告与技术文档 | [文档索引](Docs/README.md) |

## 正式游戏的常用输入

| 输入 | 正式入口中的作用 |
|---|---|
| Esc | 打开或切换设置界面，可返回主菜单 |
| Space | 战斗开始后暂停、继续战斗 |
| QPressed（Q） | 部署和战斗中切换系统鼠标与自由地形光标操作 |
| 鼠标左键 | 界面交互；部署时拾取、放置友军 |
| CallConsole（反引号） | 开关运行时控制台，输入 `help` 查看指令 |

独立测试角色仍可能使用方向键、WASD、Shift、Space、MouseLeft、EPressed 和数字槽位。正式战斗默认不生成玩家 Controller，不启用 Q 接入轮盘，也不通过 BPressed 打开工坊。详见 [输入与摄像机](Docs/Systems/InputCamera/README.md)。

## 保存和导出

存档为 `user://saves/slot_01.json`，显示和语言设置分别位于 `user://settings/display.cfg`、`user://settings/language.cfg`。不要把运行时数据写入资源包或安装目录。

在工程根目录执行：

```powershell
& .\Tools\Export\Build-Windows.ps1
```

构建输出可直接运行的 `Windows-x86_64/` 文件夹、独立 `ResourcePack/ItIsTime.pck`、日志及哈希清单，不生成可运行包 ZIP。引擎和模板位置见 [导出说明](Docs/Integration/Windows导出与资源包_2026-10-18.txt)。

## 修改约定

- 在 Godot 文件系统面板移动或重命名资源，同时检查脚本字符串、JSON 清单和导出过滤器。不要只改文件名或手工重建 `.uid`。
- 先确认修改的是共享 `.tres`、继承场景覆盖，还是生成器的手动布局。修改共享资源可能影响多种角色。
- 调整生成角色后，执行“将当前部件姿态写入生成器”并保存场景；只移动预览节点不能保证重生成后保留。
- 带日期的实施说明记录当时状态。README 的接线说明对应 2026-10-18 的工作区，具体参数与引用以当前代码、场景和 Inspector 为准。
- 通用任务资源框架与正在运行的新手待办是两条不同路径；当前接入差异见 [任务与符文](Docs/Systems/QuestsRunes/README.md)。

目前的包体启动验证不等于所有物理布局、长期混战或 50 NPC 性能已达标。已知范围和诊断方法见 [调试与导出](Docs/Systems/DebugExport/README.md)。
