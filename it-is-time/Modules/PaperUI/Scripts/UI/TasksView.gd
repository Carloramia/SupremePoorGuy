extends VBoxContainer
const L10N = preload("res://Scripts/Localization/GameText.gd")
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
		L10N.bind(row.get_node("%Title"),&"text",func(): return L10N.text(task.get("title", "")))
		L10N.bind(row.get_node("%Description"),&"text",func(): return L10N.text(task.get("description", "")))
		L10N.bind(row.get_node("%Status"),&"text","ui.52fdbbaeda4c")
		var action: String = task.get("action", "")
		row.get_node("%Go").visible = not action.is_empty()
		row.get_node("%Go").pressed.connect(func(): action_requested.emit(action))
	L10N.bind(%Summary,&"text",func(): return L10N.text(L10N.text("ui.874f181d8183") % pending))
	%PendingEmpty.visible = pending == 0
