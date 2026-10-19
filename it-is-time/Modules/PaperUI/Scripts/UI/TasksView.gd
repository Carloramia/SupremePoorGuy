extends VBoxContainer
signal action_requested(action: String)
const Row = preload("res://Modules/PaperUI/Scenes/UI/Components/TaskRow.tscn")
func present_tasks(tasks: Array) -> void:
	for list in [%PendingRows]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	var pending := 0
	var completed := 0
	var persistent := tasks.any(func(task): return task.has("id"))
	for task in tasks:
		var done: bool = task.get("done",false)
		if done: completed += 1
		if done and not persistent:
			continue
		if not done: pending += 1
		var row := Row.instantiate()
		row.set_meta("task_id",task.get("id",""))
		%PendingRows.add_child(row)
		row.get_node("%Title").text = task.get("title", "")
		row.get_node("%Description").text = task.get("description", "")
		var locked: bool = task.get("locked",false)
		row.get_node("%Status").text = "✓ 已完成" if done else ("未解锁" if locked else "待办")
		for key: String in ["prerequisite_text","reward_text"]:
			if not str(task.get(key,"")).is_empty():
				row.get_node("%Description").text += "\n"+("奖励：" if key=="reward_text" else "")+str(task[key])
		var action: String = task.get("action", "")
		row.get_node("%Go").visible = not action.is_empty()
		row.get_node("%Go").disabled = done or locked
		row.get_node("%Go").tooltip_text = "已完成" if done else (task.get("prerequisite_text","") if locked else "前往对应界面")
		row.get_node("%Go").pressed.connect(func(): action_requested.emit(str(task.get("id",action))))
	%Summary.text = "新手指引 %d / %d 已完成" % [completed,tasks.size()] if persistent else "待办 %d" % pending
	var story_rows: Array = tasks.filter(func(task):return str(task.get("id","")).begins_with("event:"))
	if not story_rows.is_empty():
		var guides: Array = tasks.filter(func(task):return not str(task.get("id","")).begins_with("event:"))
		%Summary.text="新手指引 %d / %d 已完成 · 事件待办 %d" % [guides.filter(func(task):return task.get("done",false)).size(),guides.size(),story_rows.size()]
	%PendingEmpty.text = "新手指引已完成" if persistent else "当前事项均已完成"
	%PendingEmpty.visible = pending == 0
