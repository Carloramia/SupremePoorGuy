# 编辑器插件

启用列表以 [project.godot 的 editor_plugins](../project.godot) 为准，插件用于编辑器，不作为玩家运行时 UI。

| 插件 | 入口与作用 |
|---|---|
| [weapon_workshop](weapon_workshop/plugin.cfg) | 武器画布编辑、多持握点 Marker、将 Marker 姿态读回装备设置 |
| [creature_part_editor](creature_part_editor/plugin.cfg) | 选中生成的基础物理部件后便捷修改源 Part 和等比尺寸，协调快照、关节与撤销 |
| [runtime_log_archive](runtime_log_archive/plugin.cfg) | 编辑器断点与运行日志自动归档桥 |
| [localization_export](localization_export/plugin.cfg) | 依据本地化配置把语言 JSON 加入导出包 |

编辑器执行 Resource 方法时，被调用脚本也需支持 tool 模式；否则会遇到 placeholder instance 错误。不要简单通过在游戏控制器上调用运行时方法来实现编辑器按钮，先区分编辑器与游戏分支。

`creature_part_editor` 当前面向基础生成器部件，模组内部部件按模组模板/布局捕获流程处理。插件启用不代表这些节点会进入正式导出，相关运行时功能应在 Scripts 与组件里实现。

更多操作：[部件编辑](../Docs/Creatures/生成部件便捷编辑说明_2026-10-14.txt)、[持握点](../Docs/Combat/武器多持握点编辑说明_2026-10-15.txt)、[日志桥](../Docs/Integration/运行时断点自动日志导出_2026-10-16.txt)。
