# 测试入口与判定

测试使用当前保存的场景、资源和脚本；很多旧脚本还会生成临时场景与预览，不是所有文件都适合无差别批量运行。`.runtime/` 和 `.godot/` 为测试/导入产物，不能作为正式源资产。

## 如何运行

在工程根，令 `$godot` 指向 Godot 4.7.2 编辑器控制台程序：

```powershell
& $godot --headless --path . --script res://Tests/ValidateRuntimeConsole.gd --log-file D:/GameJamWorkspace/Reports/console-check.log
```

需要 EditorInterface、插件或编辑器撤销功能的测试额外使用 `--editor`；依赖图形的头像、Shader 和截图测试不能用 headless 验收外观。

| 重点 | 脚本 |
|---|---|
| 会话、交易与存档 | [ValidateGameSession](Integration/ValidateGameSession.gd)、[ValidateApplicationRecovery](Integration/ValidateApplicationRecovery.gd) |
| 完整游戏与地图交付包 | [ValidateGameRoot](Integration/ValidateGameRoot.gd)、[ValidateDeliveryApplication](Integration/ValidateDeliveryApplication.gd) |
| 控制台 ZIP | [ValidateRuntimeConsole](ValidateRuntimeConsole.gd)、[ValidateAutomaticLogArchives](ValidateAutomaticLogArchives.gd) |
| 战斗音效 | [ValidateCombatAudio](ValidateCombatAudio.gd)，含独立视口的非静音混音检查 |
| 手工内部模型与碰撞快照 | [ValidateManualPartSnapshot](ValidateManualPartSnapshot.gd) |
| 编辑器快捷替换部件 | [ValidateGeneratedPartEditor3D](ValidateGeneratedPartEditor3D.gd)，需编辑器模式 |
| 模组 | [ValidateCreatureModules](ValidateCreatureModules.gd)、[ValidateCreatureModulesEditor](ValidateCreatureModulesEditor.gd) |
| 按需性能诊断与探测 | [ValidateDemandDiagnostics3D](ValidateDemandDiagnostics3D.gd)、[ValidateTerrainProbe3D](ValidateTerrainProbe3D.gd) |
| 新手待办 | [ValidateNewPlayerTaskUI](Integration/ValidateNewPlayerTaskUI.gd) |
| 对战样本 | [MeasureSummonCombat](Integration/MeasureSummonCombat.gd) 与 [运行器](../Tools/Testing/RunSummonCombat.py) |
| 本地化 | [ValidateLocalization](Integration/ValidateLocalization.gd)、[ValidateLocalizationPack](Integration/ValidateLocalizationPack.gd) |

## 成功条件

同时检查退出码、脚本成功标识、`ERROR:` / `SCRIPT ERROR:`、断言和超时。Godot 脚本异常可能仍返回 0；某个子函数失败后调用者继续打印 PASS，也不能判为全测试通过。`--fixed-fps 60` 用于可重复步进，不表示机器实际达到 60FPS。

[RunOptimizationChecks.py](../Tools/Testing/RunOptimizationChecks.py) 已联合检查这些条件，但它的内置列表包含 [ValidateQuests](Integration/ValidateQuests.gd)。该测试引用当前会话里不存在的通用任务 API，应按失败/待恢复接线处理，不以历史报告替代当前执行结果；可用 `--only` 运行明确适用的单项。

2026-10-18 部件编辑器回归中，Bird 的 `test_feather` 有空 Mesh `get_aabb` 异常；不能用其随后输出的总 PASS 忽略该错误。历史混战还记录过失效关节和原生崩溃。更多边界见 [包体与验证记录](../Docs/Integration/Windows导出与资源包_2026-10-18.txt)。

本批 README 只做路径、引用和文档检查，没有重新运行全部玩法回归。
