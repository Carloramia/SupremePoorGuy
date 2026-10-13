extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level = load("res://Scenes/Levels/TestLevel.tscn").instantiate()
	root.add_child(level)
	await process_frame
	var movement: Node
	for node: Node in get_nodes_in_group("leg_step_movement_controllers"):
		if node.get_parent().has_method("get_spider_joint_spring"): movement = node
	if movement == null:
		push_error("Spider controller missing")
		quit(1)
		return
	root.get_node("RuntimeConsole").execute_command("trackcontrolperf")
	var start: Vector3 = movement.get_parent().get_node("GeneratedParts/Torso_Front").global_position
	var samples: Array[float] = []
	for tick: int in 240:
		await physics_frame
		if tick % 60 == 59:
			var stats: Dictionary = movement._movement_perf.consume()
			print("SPIDER_MOVEMENT_BENCH tick=", tick + 1, " stats=", stats)
			var timing: Dictionary = stats.timings.get(&"movement_spider_full", {})
			if timing.get("calls", 0) > 0: samples.append(float(timing.get("total_usec", 0)) / timing.calls)
	var torso = movement.get_parent().get_node("GeneratedParts/Torso_Front")
	var valid: bool = torso.global_position.is_finite() and torso.global_position.distance_to(start) > 1.0
	for foot: RigidBody3D in movement.get_leg_parts(): valid = valid and foot.global_position.is_finite() and not foot.is_broken
	print("SPIDER_MOVEMENT_BENCH travel=", torso.global_position - start, " valid=", valid, " samples=", samples)
	level.free()
	quit(0 if valid else 1)
