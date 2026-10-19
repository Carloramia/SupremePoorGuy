# 任务、符文与召唤

## 实际运行的新手待办

当前正式 GameSession 调用 [NewPlayerTasks](../../../Scripts/Application/NewPlayerTasks.gd)，由 [GameUIController](../../../Scripts/Application/GameUIController.gd) 显示待办页面。四项为“探索边境”“完成召唤”“准备出战”“赢得一次战斗”；前置关系、事实收集和原子保存由该路径处理。开始新游戏后首次进入地图自动打开待办，返回地图不反复弹出。

新手进度位于会话的 `new_player_tasks`，定义当前默认奖励均为 0。修改条件、前置和奖励应检查 `NewPlayerTasks.DEFINITIONS` 与保存校验，不能只改 TasksPanel 文字。详见 [当前新手任务说明](../../Integration/新手任务栏使用说明_2026-10-18.md)。

## 独立的通用任务框架

[QuestDefinition](../../../Scripts/Quests/QuestDefinition.gd)、[QuestObjectiveData](../../../Scripts/Quests/QuestObjectiveData.gd)、[QuestService](../../../Scripts/Quests/QuestService.gd) 和 [FirstVictory 示例](../../../Resources/Quests/Examples/FirstVictory.tres) 仍存在。框架支持前置关系、COUNT/MAXIMUM 目标、事件回执去重和 `locked → available → active → completed → claimed` 状态。

**当前 GameRoot、GameSession 及其 PrototypeState 父类未提供通用任务说明中列出的 `quest_definitions`、`configure_quests()`、`record_quest_event()`、`claim_quest_reward()` 接线。** 因而不能仅把 `.tres` 挂进现有场景就自动运行，也不能把 `Tests/Integration/ValidateQuests.gd` 中的期望 API 当作已存在接口。

[原通用任务接口说明](../../Integration/任务系统接口说明_2026-10-18.txt) 是后续恢复接线的参考；应先补齐会话、持久化与 UI 接口，再启用该资源框架。它目前不替代新手待办，本次 README 没有恢复这些代码。

## 符文和召唤链

[RuneRules](../../../Modules/PaperUI/Scripts/Ritual/RuneRules.gd) 定义符文 ID、格形、描述与效果；[RuneBoard](../../../Modules/PaperUI/Scripts/Ritual/RuneBoard.gd) 负责格盘；[SummonExperiment](../../../Modules/PaperUI/Scripts/SummonExperiment.gd) 计算当前试验规则与结果。正式 [GameSession.summon()](../../../Scripts/Application/GameSession.gd) 负责调用、扣费、实例与保存。

2026-10-20首轮已切换为9类符文、8件奇物；`SummonContent.gd`是当前目录及事件奖励映射的来源。`SUPPORTED_RUNES`包含生命、防御、攻击、撕咬诅咒、好战、沸血、血肉顽强、巨化、大群。大群合并缩小效果，5只真实本体共1队位，不生成分身；螺旋人像增加一对同类肢体，不增加变异率；结晶化眼球保证本批1只获得射线魔眼。

真实战斗效果、独立测试入口、旧存档策略与事件发奖接口见 [符文与奇物接入交接](../Summoning/README.md)。完整剧情事件仍待事件负责人挂接，不能把奖励映射表当作已运行的事件状态机。

`CreatureFactory.SUMMON_POOL` 决定抽到哪个角色，符文效果决定如何修饰它；二者是独立配置。当前池没有 Human/Bird/Rat/Ratkin。队伍上限按队位计算：普通、巨化、超巨化及缩小批次的占位方式可能不同，不等于永远最多 6 个刚体角色实例。

新增符文时应同时检查规则定义、会话白名单、可序列化结果、实际 HP/护甲/速度/伤害应用、显示、本地化和存档校验。不要通过翻译修改符文 ID。
