extends SceneTree

const CHARACTER = preload("res://Scripts/Creatures/SpiderCharacter3D.gd")
var failed := false

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var owner_script := CHARACTER.new()
	var world := Node3D.new()
	root.add_child(world)
	var cases: Array[Dictionary] = []
	for child_is_a: bool in [true, false]:
		for side: float in [-1.0, 1.0]:
			var parent_body := RigidBody3D.new()
			parent_body.freeze = true
			parent_body.collision_layer = 0
			parent_body.collision_mask = 0
			var parent_collision := CollisionShape3D.new()
			parent_collision.shape = BoxShape3D.new()
			parent_body.add_child(parent_collision)
			world.add_child(parent_body)
			var child := RigidBody3D.new()
			child.gravity_scale = 0.0
			child.collision_layer = 0
			child.collision_mask = 0
			child.angular_damp = 5.0
			child.rotation.z = deg_to_rad(30.0 * side)
			var collision := CollisionShape3D.new()
			collision.shape = BoxShape3D.new()
			child.add_child(collision)
			world.add_child(child)
			child.add_collision_exception_with(parent_body)
			var before := child.global_transform
			var joint := Generic6DOFJoint3D.new()
			world.add_child(joint)
			joint.node_a = joint.get_path_to(child if child_is_a else parent_body)
			joint.node_b = joint.get_path_to(parent_body if child_is_a else child)
			joint.set_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT, true)
			for axis: String in ["x", "y", "z"]:
				joint.call("set_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT, false)
			joint.set_meta(&"spider_world_angle", {"child_is_a": child_is_a, "initial_angle": deg_to_rad(30.0 * side), "parent_path": joint.get_path_to(parent_body), "parent_rest_basis": parent_body.global_basis})
			owner_script._update_spider_world_limits(joint)
			if not child.global_transform.is_equal_approx(before): failed = true
			cases.append({"child": child, "side": side})
	await physics_frame
	for entry: Dictionary in cases: entry.child.rotation.z = deg_to_rad(100.0 * entry.side)
	for tick: int in 90: await physics_frame
	for entry: Dictionary in cases:
		var angle: float = entry.child.rotation_degrees.z
		print("SPIDER_WORLD_LIMIT final_angle=", angle)
		if absf(angle) > 76.0: failed = true
	world.free()
	owner_script.free()
	if not failed: print("PASS: Absolute Y angle limits preserve authored pose and constrain both signs at roots and knees.")
	quit(1 if failed else 0)
