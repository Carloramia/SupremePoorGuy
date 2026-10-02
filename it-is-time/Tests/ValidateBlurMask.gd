extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var mask: CanvasLayer = load("res://Scenes/Masks/BlurMask.tscn").instantiate()
	root.add_child(mask)
	await process_frame
	assert(not mask.visible)
	assert(mask.layer == 90)
	var overlay: ColorRect = mask.get_node("Overlay")
	assert(overlay.mouse_filter == Control.MOUSE_FILTER_STOP)
	assert(overlay.material is ShaderMaterial)
	mask.show_mask()
	assert(mask.visible)
	mask.hide_mask()
	assert(not mask.visible)
	print("BLUR_MASK_VALIDATION_PASSED")
	mask.queue_free()
	quit()
