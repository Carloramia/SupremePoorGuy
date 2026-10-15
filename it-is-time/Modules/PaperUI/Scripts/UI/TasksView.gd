extends VBoxContainer
signal action_requested(action: String)
const Row = preload("res://Modules/PaperUI/Scenes/UI/Components/TaskRow.tscn")
func present_tasks(tasks: Array) -> void:
	for list in [%PendingRows]:
		for child in list.get_children():
			list.remove_child(child)
			child.queue_free()
	var pending := 0
	for task in tasks:
		var done: bool = task.get("done",false)
		if done:
			continue
		pending += 1
		var row := Row.instantiate()
		%PendingRows.add_child(row)
		row.get_node("%Title").text = task.get("title", "")
		row.get_node("%Description").text = task.get("description", "")
		row.get_node("%Status").text = "待办"
		var action: String = task.get("action", "")
		row.get_node("%Go").visible = not action.is_empty()
		row.get_node("%Go").pressed.connect(func(): action_requested.emit(action))
	%Summary.text = "待办 %d" % pending
	%PendingEmpty.visible = pending == 0
