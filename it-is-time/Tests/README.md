# 测试入口与判定

测试使用当前保存的场景、资源和脚本；很多旧脚本还会生成临时场景与预览，不是所有文件都适合无差别批量运行。`.runtime/` 和 `.godot/` 为测试/导入产物，不能作为正式源资产。

## 如何运行

剧情事件接线检查为 [ValidateStoryEvents](Integration/ValidateStoryEvents.gd)，覆盖真实UI入口、会话事务及观战BattleHost；[ValidateStoryEventPaths](Integration/ValidateStoryEventPaths.gd)遍历20条剧情全部98个节点和57条路径，[ValidateStoryEventBoundaries](Integration/ValidateStoryEventBoundaries.gd)检查配置/存档拒绝、开场续接和幽灵时机。使用隔离存档，未填正式值的分支仍不可发布。完整配置与验证边界见 [事件交接](../Docs/Systems/StoryEvents/README.md)。

在工程根执行`python Tools/Testing/RunStoryIntegrationChecks.py --godot <Godot控制台exe路径>`，联合运行30个连续对白、正文布局、Demo魔力、剧情及相邻系统测试；支持`--only`指定脚本名、`--output`指定日志目录。2026-10-20本轮全部通过，覆盖明细见事件交接；`ValidateOpeningAppointment`复用事件边界测试，不重复计作新覆盖。[ValidateDemoMagic](Integration/ValidateDemoMagic.gd)检查32项费用、固定奖励与等级掉落占位规则。此前旧脚本关于战斗固定+20的断言已改为“等级掉落待配置且不发放”，但保留结算、回执幂等与失败回滚断言；通用会话中人工指定奖励的事务测试仍保留，不能当作当前正式战斗掉落数值。

[ValidateStoryDialogueLog](Integration/ValidateStoryDialogueLog.gd)无图形41项、实际截图43项，检查同一面板内向下追加、控件复用、自动滚到最新句、读档与失败重试去重、设置返回及事件/分支隔离。使用隔离存档，非headless加`-- --capture`可输出`Tests/.runtime/story-dialogue-log/opening_three_lines.png`及`opening_accumulated.png`。

[ValidateStoryTextLayout](Integration/ValidateStoryTextLayout.gd)检查正文滚动区实际尺寸和裁切，而非只检查节点可见标志。无图形894项通过；非headless运行并传`-- --capture`，900项通过并生成三种尺寸的正文、长文末尾截图。视频反馈的旧布局可被该测试检出；统一大号事件面板的显示规则与输出位置见[事件交接](../Docs/Systems/StoryEvents/README.md)。

在工程根，令 `$godot` 指向 Godot 4.7.2 编辑器控制台程序：

```powershell
& $godot --headless --path . --script res://Tests/ValidateRuntimeConsole.gd --log-file D:/GameJamWorkspace/Reports/console-check.log
```

需要 EditorInterface、插件或编辑器撤销功能的测试额外使用 `--editor`；依赖图形的头像、Shader 和截图测试不能用 headless 验收外观。

| 重点 | 脚本 |
|---|---|
| 会话、交易与存档 | [ValidateGameSession](Integration/ValidateGameSession.gd)、[ValidateApplicationRecovery](Integration/ValidateApplicationRecovery.gd) |
| 完整游戏与地图交付包 | [ValidateGameRoot](Integration/ValidateGameRoot.gd)、[ValidateDeliveryApplication](Integration/ValidateDeliveryApplication.gd) |
| 20261019 六边形地图迁入 | [ValidateHexMapHandoff](Integration/ValidateHexMapHandoff.gd) 检查资源路径、41 场、高清裁切与旧地图内容未变（MapCatalog 已增加版本选择）；[Python 规则测试](../Tools/Integration/test_import_hex_map_handoff.py)，完整指纹/图片复核使用 `python Tools/Integration/ImportHexMapHandoff.py --verify`；[方案](../Docs/Systems/WorldMapUI/地图交接包资源对应与更新方案_2026-10-19.md) |
| 20261019 正式地图接入 | [ValidateHexWorldIntegration](Integration/ValidateHexWorldIntegration.gd)、[ValidateHexWorldApplication](Integration/ValidateHexWorldApplication.gd)、[ValidateHexBattleDeployment](Integration/ValidateHexBattleDeployment.gd)、[ValidateHexStoneActions](Integration/ValidateHexStoneActions.gd)、[ValidateHexLegacySelection](Integration/ValidateHexLegacySelection.gd)；图形模式为 Application 传 `-- --capture` 保存地图/部署截图；[接入记录](../Docs/Systems/WorldMapUI/新版六边形地图接入_2026-10-19.md) |
| 大地图时间与旅行速度 | [ValidateWorldTime](Integration/ValidateWorldTime.gd)；图形模式额外传 `-- <截图目录>` 验证 1120×680、1920×1080 的实际界面 |
| 召唤临时小战场 | [ValidateSummonAssembly](Integration/ValidateSummonAssembly.gd)，覆盖五物种增强喷发、真实部件出地自由运动并确认接地后吸附、每隔 1 秒并行召唤、连接/姿态/碰撞箱一致、持续散件喷发与池上限、完成后淡出清理、空气墙、暂停隔离、观察控制和真实跳过；多种宽高比验证完整活动圆/生物、35° 俯角及暗场材质，输出自由运动时间与并行统计；`-- --seed=99 --radius=1` 检查另一随机分布，图形模式传 `-- <截图目录>` 查看自由飞行等阶段 |
| 控制台 ZIP | [ValidateRuntimeConsole](ValidateRuntimeConsole.gd)、[ValidateAutomaticLogArchives](ValidateAutomaticLogArchives.gd) |
| 战斗音效 | [ValidateCombatAudio](ValidateCombatAudio.gd)，含独立视口的非静音混音检查 |
| Spear 手部驱动 | [ValidateSpearHandDrive3D](ValidateSpearHandDrive3D.gd)，验证左右手部物理收敛、肢体关节跟随、施力上限、常态控制让出与约束恢复；[ValidateSpearNPCCombat3D](ValidateSpearNPCCombat3D.gd) 验证真实武器接触 |
| Spear 蓄力与伤害窗口 | [ValidateSpearPreparation3D](ValidateSpearPreparation3D.gd)，对照左右朝向的收矛实际速度、力和扭矩，验证蓄力零伤害、释放伤害、取消恢复及实体碰撞保留 |
| Spear 提前蓄力 | [ValidateSpearEarlyCharge3D](ValidateSpearEarlyCharge3D.gd)，验证左右朝向、几何比例起手范围、静止/接近目标、地形阻挡、性能模式下的蓄力接近、范围外保持与超时取消，以及释放时停止接近 |
| Human 持物视觉对齐 | [ValidateGeneratedHumanGrip3D](ValidateGeneratedHumanGrip3D.gd)，验证两只手的持物腕部对齐、未持物恢复、关节/碰撞/持握点不变、继承场景与重新生成后的引用保留 |
| Human 肘关节对齐 | [ValidateHumanElbowAlignment3D](ValidateHumanElbowAlignment3D.gd)，从纹理孔心与网格 UV 验证肘部转轴，检查 ±90° 转动时的孔洞间距、连接标记、继承场景和重新生成 |
| 手工内部模型与碰撞快照 | [ValidateManualPartSnapshot](ValidateManualPartSnapshot.gd) |
| 编辑器快捷替换部件 | [ValidateGeneratedPartEditor3D](ValidateGeneratedPartEditor3D.gd)，需编辑器模式 |
| 模组 | [ValidateCreatureModules](ValidateCreatureModules.gd)、[ValidateCreatureModulesEditor](ValidateCreatureModulesEditor.gd) |
| 按需性能诊断与探测 | [ValidateDemandDiagnostics3D](ValidateDemandDiagnostics3D.gd)、[ValidateTerrainProbe3D](ValidateTerrainProbe3D.gd) |
| NPC 左右朝向与 Z 对齐 | [ValidateGeneratedNPCAxisPositioning3D](ValidateGeneratedNPCAxisPositioning3D.gd)，覆盖生成 NPC 配置、X/Z 独立站位、无攻击追踪、侧向限速、避让余量和朝向确认；[ValidateWolfAxisApproach](Integration/ValidateWolfAxisApproach.gd) 使用两只敌对 Wolf 验证实际侧移与偏航 |
| 断肢与失效关节 | [ValidateFreedCreatureJoints3D](ValidateFreedCreatureJoints3D.gd)，覆盖十种生成生物在关节待删除、释放和真实 Broken 后的控制/完整诊断，以及 Bird 翅膀、落地、头部和 Human 持握缓存；结果与旧回归边界见 [修复记录](../Docs/Creatures/断肢与失效关节引用修复_2026-10-19.txt) |
| HornedBeast 与 Snake 转向 | [ValidateHornedTurnControl3D](ValidateHornedTurnControl3D.gd) 验证左右转向换步；[ValidateSnakeIndependentTurning3D](ValidateSnakeIndependentTurning3D.gd) 验证上段独立转向、接地实际到达标记与路径显示；[ValidateSnakeTurnedBite3D](ValidateSnakeTurnedBite3D.gd) 验证转向后啃咬与接地保持；[说明](../Docs/Creatures/HornedBeast转身与Snake路径分段转向_2026-10-19.txt) |
| 新手待办 | [ValidateNewPlayerTaskUI](Integration/ValidateNewPlayerTaskUI.gd) |
| 对战样本 | [MeasureSummonCombat](Integration/MeasureSummonCombat.gd) 与 [运行器](../Tools/Testing/RunSummonCombat.py) |
| 本地化 | [ValidateLocalization](Integration/ValidateLocalization.gd)、[ValidateLocalizationPack](Integration/ValidateLocalizationPack.gd) |

## 成功条件

2026-10-20当前符文与奇物检查：`Integration/ValidateCurrentSummoning.gd`（276项，含回退后配置复核）、`ValidateSummonCombatEffects.gd`（25项）、`ValidateSummonContentLab.gd`（13项）。运行边界与当前限制见 [接入交接](../Docs/Systems/Summoning/README.md)。这些检查使用独立测试存档，不证明完整剧情事件、长期战斗平衡或美术表现已验收。

同时检查退出码、脚本成功标识、`ERROR:` / `SCRIPT ERROR:`、断言和超时。Godot 脚本异常可能仍返回 0；某个子函数失败后调用者继续打印 PASS，也不能判为全测试通过。`--fixed-fps 60` 用于可重复步进，不表示机器实际达到 60FPS。

[RunOptimizationChecks.py](../Tools/Testing/RunOptimizationChecks.py) 和剧情运行器均联合检查这些条件。[ValidateQuests](Integration/ValidateQuests.gd)现为29项独立QuestService测试，覆盖前置、目标计数、去重、配置回滚和状态往返；不再调用不存在的GameSession通用任务接口，也不宣称正式会话能自动发放该框架奖励。旧接口文档仅作未来接线参考。

2026-10-18 部件编辑器回归中，Bird 的 `test_feather` 有空 Mesh `get_aabb` 异常；不能用其随后输出的总 PASS 忽略该错误。历史混战还记录过失效关节和原生崩溃。更多边界见 [包体与验证记录](../Docs/Integration/Windows导出与资源包_2026-10-18.txt)。

本轮实际运行上述30个入口，另做正文与连续对白图形截图专项；不等于已运行本目录所有物理、编辑器、性能与图形测试，历史问题须以各自最新专项回归为准。
