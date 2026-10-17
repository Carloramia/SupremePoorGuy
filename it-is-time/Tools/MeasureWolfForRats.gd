extends SceneTree

const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var low := INF
	var high := -INF
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D and str(part.name) in ["Torso", "Head", "LowerJaw"]:
			var bounds: AABB = part.transform * GEOMETRY.bounds(part, false)
			low = minf(low, bounds.position.x)
			high = maxf(high, bounds.end.x)
	assert(is_finite(low) and high > low)
	print("RATS_REFERENCE_WOLF body_length=", high-low, " rats_length=", (high-low)*0.3)
	actor.free()
	quit()
