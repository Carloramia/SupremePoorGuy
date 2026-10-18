# 通用任务资源

[FirstVictory.tres](Examples/FirstVictory.tres) 使用 [QuestDefinition](../../Scripts/Quests/QuestDefinition.gd) 和 [QuestObjectiveData](../../Scripts/Quests/QuestObjectiveData.gd)，描述一次 `battle.victory` 示例与奖励。处理逻辑在 [QuestService](../../Scripts/Quests/QuestService.gd)。

当前主流程没有通用 `quest_definitions` 挂载数组，也没有会话 `configure_quests()` / `record_quest_event()` / `claim_quest_reward()` 方法。此目录提供框架资源，不会因文件存在自动启用。现有新手待办由 `Scripts/Application/NewPlayerTasks.gd` 处理。

扩展前阅读 [实际接入状态](../../Docs/Systems/QuestsRunes/README.md)。历史任务接口说明和测试脚本含预期 API，不能代替当前代码确认。
