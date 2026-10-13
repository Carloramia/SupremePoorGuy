extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var mode: Resource = load("res://Resources/Settings/PerformanceOptimization.tres")
	mode.set(&"enabled", not "off" in OS.get_cmdline_user_args())
	var sample_count := 120 if "short" in OS.get_cmdline_user_args() else 300
	var level: Node3D = load("res://Scenes/Levels/TestLevel.tscn").instantiate()
	root.add_child(level)
	current_scene = level
	var controllers := get_nodes_in_group(&"leg_step_movement_controllers")
	var machines := get_nodes_in_group(&"npc_state_machines")
	assert(controllers.size() == 8 and machines.size() == 8)
	for controller: Node in controllers:
		controller.set_performance_tracking_enabled(true)
		controller.set_control_performance_tracking_enabled("phases" in OS.get_cmdline_user_args())
	for machine: Node in machines: machine.set_performance_tracking_enabled(true)
	for tick: int in 60: await process_frame
	if "micro" in OS.get_cmdline_user_args():
		for controller: Node in controllers:
			if not "Generate" in str(controller.get_parent().name): continue
			var foot: RigidBody3D = controller._legs[0]
			for method: StringName in [&"_get_gait_data", &"get_input_movement_direction", &"_gallop_active", &"get_torso_parts", &"get_leg_motion_profile", &"_get_speed_leg_plan", &"_support_surface_contact"]:
				var start := Time.get_ticks_usec()
				for iteration: int in 300:
					if method in [&"get_leg_motion_profile", &"_get_speed_leg_plan", &"_support_surface_contact"]: controller.call(method, foot)
					else: controller.call(method)
				print("NPC_MICRO actor=", controller.get_parent().name, " method=", method, " avg_us=", float(Time.get_ticks_usec()-start)/300.0)
	for controller: Node in controllers: controller.consume_performance_stats()
	for controller: Node in controllers: controller.consume_control_performance_stats()
	for machine: Node in machines: machine.consume_performance_stats()
	var started := Time.get_ticks_usec()
	var physics_ms: Array[float] = []
	for tick: int in sample_count:
		await process_frame
		physics_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var elapsed := float(Time.get_ticks_usec() - started) / 1000.0
	physics_ms.sort()
	var movement_ms := 0.0
	var ai_ms := 0.0
	for controller: Node in controllers:
		var stats: Dictionary = controller.consume_performance_stats()
		assert(int(stats.physics_frames) >= sample_count - 1, "All eight movement controllers must keep updating each physics frame")
		var average := float(stats.total_usec) / maxi(int(stats.physics_frames), 1) / 1000.0
		movement_ms += average
		print("NPC_PERF_COMPONENT actor=", controller.get_parent().name, " average_ms=", average, " stats=", stats)
		print("NPC_PERF_PHASES actor=", controller.get_parent().name, " stats=", controller.consume_control_performance_stats())
	for machine: Node in machines:
		var stats: Dictionary = machine.consume_performance_stats()
		assert(int(stats.physics_frames) >= sample_count - 1, "AI execution and timers must keep updating each physics frame")
		ai_ms += float(stats.total_usec) / maxi(int(stats.physics_frames), 1) / 1000.0
	for body: Node in level.find_children("*", "RigidBody3D", true, false):
		assert(body.global_transform.is_finite() and body.linear_velocity.is_finite(), "NPC physics must remain finite")
	print("NPC_PERF_RESULT ", JSON.stringify({"enabled": mode.enabled, "wall_ms_per_frame": elapsed / sample_count, "movement_ms": movement_ms, "ai_ms": ai_ms, "physics_p50_ms": physics_ms[sample_count/2], "physics_p95_ms": physics_ms[int(sample_count*0.95)], "physics_max_ms": physics_ms[-1]}))
	print("PASS: Eight TestLevel NPCs keep full physics updates with performance mode ", "ON" if mode.enabled else "OFF")
	level.free()
	await process_frame
	quit()
