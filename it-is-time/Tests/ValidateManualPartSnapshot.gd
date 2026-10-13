extends SceneTree
const SNAPSHOT = preload("res://Scripts/Creatures/Generators/ManualPartSnapshot.gd")
const GEO = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
func _initialize() -> void: call_deferred("run")
func inspect(actor: Node) -> Dictionary:
	var result := {}
	for body: Node in actor.get_node("GeneratedParts").get_children():
		if not body is PhysicalBodyPart3D: continue
		var entries := {"root":body.transform}
		for child: Node in body.find_children("*","Node3D",true,false):
			if child.has_meta("generated_connection_port"): continue
			var key := str(body.get_path_to(child))
			entries[key] = SNAPSHOT.relative_transform(child,body)
			if child is CollisionShape3D:
				assert(child.shape is ConvexPolygonShape3D)
				entries[key+"/points"] = child.shape.points
		result[str(body.name)] = entries
	return result
func compare(actual: Dictionary, expected: Dictionary, factor: float) -> void:
	assert(actual.size()==expected.size())
	for part: String in expected:
		for path: String in expected[part]:
			var value: Variant = expected[part][path]
			if value is Transform3D:
				value.origin *= factor
				if path != "root" and not path.ends_with("CollisionShape3D"): value.basis = value.basis.scaled(Vector3.ONE*factor)
				assert(actual[part][path].is_equal_approx(value),part+"/"+path)
			else:
				assert(actual[part][path].size()==value.size())
				for i: int in range(value.size()): assert(actual[part][path][i].is_equal_approx(value[i]*factor),part+" collision point")
func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Wolf.tscn").instantiate()
	actor.generate_on_ready=false
	root.add_child(actor)
	var gen = actor.get_node("WolfGenerator")
	var before := inspect(actor)
	assert(actor._capture_manual_layout())
	var file := "res://Tests/.internal_snapshot_roundtrip.tres"
	assert(ResourceSaver.save(gen.manual_layout,file)==OK)
	gen.manual_layout = ResourceLoader.load(file,"",ResourceLoader.CACHE_MODE_REPLACE)
	var original_shape = gen.manual_layout.blueprint.parts[0].internal_snapshot.nodes.filter(func(entry: Dictionary) -> bool: return entry.has("shape"))[0].shape
	assert(actor.generate_creature())
	compare(inspect(actor),before,1.0)
	assert(actor.get_node("GeneratedParts/Torso/CollisionShape3D").shape != original_shape)
	assert(actor.generate_creature())
	compare(inspect(actor),before,1.0)
	gen.overall_scale *= 2.0
	assert(actor.generate_creature())
	compare(inspect(actor),before,2.0)
	assert(actor._capture_manual_layout())
	assert(actor.generate_creature())
	compare(inspect(actor),before,2.0)
	gen.overall_scale *= 0.5
	assert(actor.generate_creature())
	compare(inspect(actor),before,1.0)
	var torso = actor.get_node("GeneratedParts/Torso")
	var untouched: Transform3D = torso.get_node("Model").transform
	assert(not SNAPSHOT.apply_to(torso,gen.manual_layout.blueprint.parts[0].internal_snapshot,1.0,"res://changed_part.tscn"))
	assert(torso.get_node("Model").transform==untouched)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file))
	actor.free()
	await process_frame
	print("PASS: Wolf internal transforms/shapes, save/reload, repeated generation, 2x scale/recapture, independent collisions and source mismatch fallback.")
	quit()
