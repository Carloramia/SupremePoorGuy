extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var layouts: Array = []
	for set_index: int in [1,2,3,4,5]:
		var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
		actor.generate_on_ready = false
		root.add_child(actor)
		actor.get_node("HumanGenerator").human_set = set_index
		assert(actor.generate_creature())
		var pieces: Array = []
		for part: Node in actor.get_node("GeneratedParts").get_children():
			if not part is PhysicalBodyPart3D: continue
			var model: Node3D = part.get_node("Model")
			pieces.append(record(str(part.name), str(part.get_meta("source_png")), model.global_transform))
		var waist: Node3D = actor.get_node("GeneratedParts/Torso/WaistVisual")
		pieces.append(record("WaistVisual", "human%d_pelvis" % set_index, waist.global_transform))
		layouts.append({"set":set_index,"pieces":pieces})
		actor.free()
	var file := FileAccess.open("D:/GameJamWorkspace/Reports/Human_layout.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(layouts))
	file.close()
	await process_frame
	print("PASS: Exported Human layout projections.")
	quit()
func record(node_name: String, source: String, pose: Transform3D) -> Dictionary:
	return {"name":node_name,"source":source,"origin":[pose.origin.x,pose.origin.y],
		"x":[pose.basis.x.x,pose.basis.x.y],"y":[pose.basis.y.x,pose.basis.y.y]}
