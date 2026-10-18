# 调试、性能与导出

## 控制台

[RuntimeConsole](../../../Scenes/Debug/RuntimeConsole.tscn) 是 Autoload，使用 CallConsole 开关。完整命令及参数以 [COMMAND_HELP](../../../Scripts/Debug/RuntimeConsole.gd) 和游戏内 `help` 为准。

| 用途 | 常用命令 |
|---|---|
| 全部指令、压缩运行日志 | `help`、`getlogs` |
| 错误/断点自动归档 | `autogetlogs on` / `off` / `status` |
| NPC 状态与选敌 | `tracknpcstate on 名称`、`npcstates 名称` |
| NPC 步态与部件运动 | `tracknpcmotion on 名称`、`motiondetail summary` 或 `full` |
| 控制角色、生成移动、寻路 | `trackmotion`、`trackgenerated`、`tracknpc` |
| 关节与落点 | `trackjoints on 名称`、`jointstates 名称`、`showsteptargets on` |
| 伤害与碰撞体 | `trackdamage`、`trackcollision`、`showattackboxes on` |
| Wolf/Rat、Snake、冲锋、飞行 | `trackwolfattacks on 名称`、`tracksnakeattacks on 名称`、`trackcharge`、`trackflight on` |
| 装备、手臂、Bow | `trackgrip on 名称`、`gripstates 名称`、`trackswing`、`trackbow on 名称` |
| 地图与系统路由 | `trackmap on`、`mapstate`、`trackintegration on` |
| 性能与优化模式 | `trackperformance`、`trackcontrolperf`、`perfmode status` |
| Snake 路径 | `showsnakepath on 名称` |

带 `[on|off]` 的命令可显式切换；无参数布尔命令通常切换当前状态，不要反复输入以为是重复启用。过滤器匹配实际实例名称、路径或 ID，实例名以 Remote 场景树为准。

运动日志默认间隔 0.1 秒，性能统计较低频。先用 summary 和单目标过滤，再短时启用 full；全场所有部件高频输出会改变测试负载。性能模式不是日志开关，默认来自 [PerformanceOptimization.tres](../../../Resources/Settings/PerformanceOptimization.tres)。

## 日志位置

运行日志在 `user://logs`。`getlogs` 的 ZIP 在编辑器运行时输出到工程根目录，在正式包输出到 `user://log_archives`，并打印绝对路径。Windows 默认用户根为 `%APPDATA%/Godot/app_userdata/ItIsTime/`。

Godot 断点会暂停脚本，不能依赖游戏内输入再开启控制台；先启用自动归档，或从上述日志目录获取文件。Editor 断点桥由 [runtime_log_archive](../../../addons/runtime_log_archive) 插件提供，运行时错误捕获由 [RuntimeErrorLogCapture](../../../Scripts/Debug/RuntimeErrorLogCapture.gd) 配合。

## 构建

[Windows Desktop 预设](../../../export_presets.cfg) 与 [Build-Windows.ps1](../../../Tools/Export/Build-Windows.ps1) 使用标准 Godot 4.7.2 模板。模板目录相对工程位于 `../../BuildTools/Godot-4.7.2/templates`；脚本默认引擎在同级 `editor` 目录。没有把引擎或模板提交进本工程。

```powershell
& .\Tools\Export\Build-Windows.ps1
```

输出到工作区 `Builds/ItIsTime/<日期时间>/`：`Windows-x86_64/` 可运行文件夹、`ResourcePack/ItIsTime.pck`、`manifest.json`、`export.log`、`smoke.log`，不再自动压缩可运行目录。给玩家分发整个可运行文件夹，PCK 不能单独启动。

地图和本地化 JSON 必须包含；动态路径不能仅靠主场景依赖导出。文本场景保持未转换状态，因为 Factory 需要场景文件哈希。运行时依赖 `Tools/Integration/Frontier/godot/battle_preview.gd`，不能把 Tools 整体当作可排除的编辑器目录。

正式模板不支持外部 `--script` 测试入口，包内自检采用：

```powershell
.\ItIsTime.exe --headless --log-file D:/GameJamWorkspace/Reports/export_verify.log -- --verify-export
```

该标志才会调用 [ExportPackageCheck](../../../Scripts/Debug/ExportPackageCheck.gd)，使用独立测试存档验证地图、角色、部署、战斗启动和日志 ZIP；普通启动不触发。构建脚本同时检查退出码、成功标识和错误日志，不能仅凭退出码 0 判断成功。

## 验证边界

[测试导航](../../../Tests/README.md) 区分无图形检查、真实图形检查和编辑器工具检查。2026-10-18 首轮独立包通过 47 项无图形与 50 项图形检查，但不代表长期混战、全部物种和低配硬件达标。历史混战中的失效关节与原生崩溃、Bird 编辑器空 Mesh 检查等问题见 [验证记录与边界](../../Integration/Windows导出与资源包_2026-10-18.txt)。
