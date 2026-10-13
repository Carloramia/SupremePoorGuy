extends VBoxContainer
signal action_requested(action: String)
const Row = preload("res://Scenes/UI/Components/TaskRow.tscn")
func present_tasks(tasks: Array) -> void:
	for list in [%PendingRows,%DoneRows]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	var completed := 0
	for task in tasks:
		var done: bool = task.get("done",false)
		completed += int(done)
		var row := Row.instantiate()
		(%DoneRows if done else %PendingRows).add_child(row)
		row.get_node("%Title").text = task.get("title", "")
		row.get_node("%Description").text = task.get("description", "")
		row.get_node("%Status").text = "已完成" if done else "待办"
		var action: String = task.get("action", "")
		row.get_node("%Go").visible = not done and not action.is_empty()
		row.get_node("%Go").pressed.connect(func(): action_requested.emit(action))
	%Summary.text = "待办 %d · 已完成 %d" % [tasks.size()-completed,completed]
	%PendingEmpty.visible = completed == tasks.size()
	%DoneEmpty.visible = completed == 0
