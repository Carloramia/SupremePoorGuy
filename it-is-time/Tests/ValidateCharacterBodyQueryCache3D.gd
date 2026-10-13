extends SceneTree
const CHARACTER = preload("res://Scripts/Creatures/PhysicalCharacterController.gd")
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
const SPRING = preload("res://Scripts/Creatures/SegmentDistanceSpring3D.gd")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func actor() -> Node3D:
	var node := Node3D.new()
	node.set_script(CHARACTER)
	node.require_head_and_torso_connectivity = false
	root.add_child(node)
	return node
func run() -> void:
	var first := actor()
	var second := actor()
	check(first._get_physical_body_parts().is_empty(), "Initially empty cache must be valid")
	var container := Node3D.new()
	first.add_child(container)
	var part := PART.instantiate() as PhysicalBodyPart3D
	part.freeze = true
	container.add_child(part)
	check(first._get_physical_body_parts() == [part], "Adding a nested part must invalidate the cache")
	check(part.get_rid() in first.get_physical_body_rids(), "RID cache must match parts")
	var copy: Array = first._get_physical_body_parts()
	copy.clear()
	var rid_copy: Array = first.get_physical_body_rids()
	rid_copy.clear()
	check(first._get_physical_body_parts().size() == 1 and first.get_physical_body_rids().size() == 1, "Callers must not mutate cached arrays")
	part.tags.assign([1])
	check(first.get_body_parts_with_tag(1) == [part] and first.get_body_parts_with_tag(0).is_empty(), "Tag lookup must read current tags without a stale classification cache")
	part.mass = 3.0
	check(is_equal_approx(first.get_living_body_mass(), 3.0), "Mass lookup must read current physics masses")
	var item := RigidBody3D.new()
	item.freeze = true
	container.add_child(item)
	check(first._get_physical_body_parts().size() == 1, "Untagged item bodies must not enter part cache")
	var revision: int = first.get_body_parts_revision()
	part.reparent(second)
	check(first._get_physical_body_parts().is_empty(), "Reparenting must remove the old owner's part")
	check(second._get_physical_body_parts() == [part], "Reparenting must register the new owner's part")
	check(first.get_body_parts_revision() > revision, "Reparenting must update structure revision")
	revision = second.get_body_parts_revision()
	part.break_part()
	check(second.get_body_parts_with_tag(1).is_empty() and second.get_body_parts_with_tag(1, true) == [part], "Broken parts must be excluded by default and available for explicit inspection")
	check(is_zero_approx(second.get_living_body_mass()), "Broken parts must not contribute living mass")
	check(second.get_body_parts_revision() > revision, "Breaking a part must refresh query exclusions")
	check(part.get_rid() in second.get_physical_body_rids(), "Detached broken parts still inside the character must remain collision exclusions")
	part.queue_free()
	check(second._get_physical_body_parts().is_empty(), "Queued deletion must not return a stale part")
	await process_frame
	check(second.get_physical_body_rids().is_empty(), "Freed parts must not leave stale RIDs")
	var replacement := PART.instantiate() as PhysicalBodyPart3D
	replacement.freeze = true
	second.add_child(replacement)
	check(second._get_physical_body_parts() == [replacement], "New generation must replace the old cache")
	check(second.get_body_connections().is_empty(), "Initially empty connection cache must be valid")
	var joint := PinJoint3D.new()
	second.add_child(joint)
	check(second.get_body_connections() == [joint], "Adding a joint must invalidate the connection cache")
	var guide := PinJoint3D.new()
	guide.set_meta(&"planar_depth_guide", true)
	second.add_child(guide)
	check(second.get_body_connections() == [joint], "World depth guides must not count as character body connections")
	guide.remove_meta(&"planar_depth_guide")
	check(second.get_body_connections().size() == 2, "Connection metadata must be checked when read")
	var spring := SPRING.new()
	spring.enabled = false
	second.add_child(spring)
	check(spring in second.get_body_connections(), "Logical springs must remain discoverable so callers can evaluate their current enabled state")
	var connections: Array = second.get_body_connections()
	connections.clear()
	check(second.get_body_connections().size() == 3, "Callers must not mutate the cached connection catalog")
	joint.reparent(first)
	check(joint not in second.get_body_connections() and joint in first.get_body_connections(), "Reparented joints must move between character catalogs")
	spring.queue_free()
	check(spring not in second.get_body_connections(), "Queued connections must be excluded immediately")
	first.free()
	second.free()
	await process_frame
	print("CHARACTER_BODY_QUERY_CACHE_FAILED" if failed else "CHARACTER_BODY_QUERY_CACHE_PASSED")
	quit(1 if failed else 0)
