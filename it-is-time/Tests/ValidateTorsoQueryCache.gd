extends SceneTree

class CustomPart:
	extends RigidBody3D
	var tags: Array[int] = [0]

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate()
	root.add_child(character)
	for body: Node in character.find_children("*", "RigidBody3D", true, false): body.freeze = true
	var movement := character.get_node("LegStepMovementController3D")
	movement.set_physics_process(false)
	movement.set_control_performance_tracking_enabled(true)
	var torso: PhysicalBodyPart3D = character.get_node("Torso")
	assert(movement.get_torso_parts() == [torso])
	for lookup: int in range(50): assert(movement.get_torso_parts() == [torso])
	var stats: Dictionary = movement.consume_control_performance_stats()
	assert(stats.counters.torso_cache_refreshes == 1, "Queries must share one classification per physics step")
	assert(stats.counters.tag_checks == movement._character_body_cache.size())
	# Broken filtering is immediate; it must not wait for another physics step.
	torso.is_broken = true
	assert(movement.get_torso_parts().is_empty())
	torso.is_broken = false
	assert(movement.get_torso_parts() == [torso])
	var extra := CustomPart.new()
	extra.freeze = true
	character.add_child(extra)
	assert(extra in movement.get_torso_parts(), "Added parts must invalidate the cache")
	character.remove_child(extra)
	assert(extra not in movement.get_torso_parts(), "Removed parts must not receive force")
	extra.free()
	var ordinary := RigidBody3D.new()
	assert(not movement._has_body_tag(ordinary, 0))
	ordinary.free()
	# Custom tagged RigidBody3D remains compatible, and tag edits are observed next physics step.
	var custom := CustomPart.new()
	custom.freeze = true
	character.add_child(custom)
	assert(custom in movement.get_torso_parts())
	custom.tags.clear()
	await physics_frame
	assert(custom not in movement.get_torso_parts())
	custom.tags.append(0)
	await physics_frame
	assert(custom in movement.get_torso_parts())
	# Replacing an entire parts subtree must attach invalidation listeners to the new root.
	var replacement := Node3D.new()
	replacement.name = "ReplacementParts"
	character.add_child(replacement)
	movement.parts_root_path = NodePath("../ReplacementParts")
	assert(movement.get_torso_parts().is_empty())
	var replacement_torso := CustomPart.new()
	replacement_torso.freeze = true
	replacement.add_child(replacement_torso)
	assert(movement.get_torso_parts() == [replacement_torso])
	character.queue_free()
	await process_frame
	print("TORSO_QUERY_CACHE_VALIDATION_PASSED")
	quit()
