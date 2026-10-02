extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var output: CanvasLayer = load("res://Scenes/Debug/RuntimeDebugOutput.tscn").instantiate()
	root.add_child(output)
	await process_frame
	assert(not output.get_node("MarginContainer").visible)
	output.log_line("Validation message")
	assert(output._lines[-1].contains("Validation message"))
	print("RUNTIME_DEBUG_OUTPUT_VALIDATION_PASSED")
	output.queue_free()
	quit()
