# 增量交付归档

此目录保存原始交付包与来源说明，用于追溯和比对。[.gdignore](.gdignore) 阻止 Godot 扫描其中的源工程副本，避免同名全局类和重复脚本 UID；导出预设也排除本目录。

归档中的脚本、资源和 README 不会自动替换正式文件。接入后应在 Scripts、Resources、Scenes、Modules 或 Content 的实际位置检查引用，并记录本地改动；不要直接运行归档工程来判断主流程已完成接线。

例如 NewPlayerTasks 的当前正式逻辑在 [NewPlayerTasks.gd](../Scripts/Application/NewPlayerTasks.gd)，而不是归档包里的 source 副本。当前状态见 [任务系统 README](../Docs/Systems/QuestsRunes/README.md)。
