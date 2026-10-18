# 开发工具

工具分为导出、只读验证和会重写资产/布局的制作工具。先读脚本参数与输出路径，再执行；历史 Author、Connect、Bake 脚本不保证保留后来手工校准的场景。

| 入口 | 用途 |
|---|---|
| [Export/Build-Windows.ps1](Export/Build-Windows.ps1) | 当前 Windows 文件夹导出、真实包体自检、独立 PCK 与清单 |
| [Testing/RunOptimizationChecks.py](Testing/RunOptimizationChecks.py) | 一组有成功标识、退出码与错误日志联合检查的回归 |
| [Testing/RunSummonCombat.py](Testing/RunSummonCombat.py) | 当前五种召唤生物的重复对战和护甲对照批次，需传引擎与新输出目录 |
| [Testing/SummarizeSummonCombat.py](Testing/SummarizeSummonCombat.py) | 汇总已有对战结果，不把失败运行计作有效样本 |
| [Testing/DiagnoseCreatureMelee.py](Testing/DiagnoseCreatureMelee.py) | 对战诊断与其他旧测量入口，先查看 `--help` |
| [Localization](Localization) | 文本提取和验证 |
| [Audio](Audio/README.md) | 可复现地生成简单攻击与受击 WAV 音效 |
| [Integration](Integration) | 地图导入、模块同步和环境资源替换 |
| `Bake*Volumes.gd` | 按物种源图/清单烘焙带厚度 Mesh |
| `Author*`、`Connect*`、`Orient*` | 创建或改写生成器、角色、引用、姿态；属于制作写操作 |
| [ExportHumanLayout.gd](ExportHumanLayout.gd) | Human 布局导出辅助 |

各物种还在 `Assets/3DResources/Creatures/<类别>/Tools` 保留 Python 制作工具。不要按命名推断能跨物种通用。模型元数据与已保存的手工布局可能需要分别更新。

常见 Godot 脚本检查方式（在工程根，`$godot` 指向 4.7.2 编辑器控制台程序）：

```powershell
& $godot --headless --path . --script res://Tests/ValidateRuntimeConsole.gd --log-file D:/GameJamWorkspace/Reports/console-check.log
```

`--editor` 只用于明确要求编辑器 API 的脚本。正式导出模板不能靠外部 `--script` 执行这些测试，使用包内 `--verify-export`。

**运行时例外**：[battle_preview.gd](Integration/Frontier/godot/battle_preview.gd) 被 BattleHost 直接 preload 使用。清理或导出时不能整体排除 Tools，只按已知子目录排除。细节见 [导出系统](../Docs/Systems/DebugExport/README.md)。
