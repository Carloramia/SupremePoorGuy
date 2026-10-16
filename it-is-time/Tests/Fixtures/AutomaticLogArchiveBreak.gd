extends Node

func _ready() -> void: call_deferred("run")

func run() -> void:
	var status_path := OS.get_environment("ITISTIME_EDITOR_ARCHIVE_STATUS")
	if status_path.is_empty(): get_tree().quit(1); return
	var console := get_tree().root.get_node("RuntimeConsole")
	for frame: int in 10: await get_tree().process_frame
	var status := FileAccess.open(status_path,FileAccess.WRITE)
	status.store_string(JSON.stringify({"pid":OS.get_process_id(),"bridge_connected":console._archive_bridge_connected}))
	status.close()
	breakpoint
	console.execute_command("autogetlogs on")
	freed_reference_error()
	print("EDITOR_ARCHIVE_FIXTURE_RESUMED")
	get_tree().quit()

func freed_reference_error() -> void:
	var node := Node.new()
	var cache := {"node":node}
	node.free()
	var _invalid: Node = cache.node
