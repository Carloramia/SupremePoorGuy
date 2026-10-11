extends SceneTree

const NPC = preload("res://Scenes/Creatures/Characters/Generate_Spider_NPC.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var npc := NPC.instantiate()
	level.add_child(npc)
	var controller: Node = npc.get_node("GeneratedLegStepMovementController3D")
	var console: Node = root.get_node("RuntimeConsole")
	console.execute_command("trackperformance")
	console.execute_command("trackcontrolperf")
	await physics_frame
	await process_frame
	var foot: RigidBody3D = controller._legs[0]
	controller._spider_profile_context.clear()
	controller._movement_perf.consume()
	for i: int in 100:
		controller.get_leg_motion_profile(foot)
		controller.get_expected_horizontal_speed()
		controller.get_planned_step_frequency()
	var cache: Dictionary = controller._movement_perf.consume()
	check(int(cache.counters.get(&"spider_profile_builds", 0)) == 8, "Repeated profile/speed/frequency queries must build each leg only once")
	check(int(cache.counters.get(&"spider_profile_cache_hits", 0)) >= 99, "Repeated profile queries must hit cache")
	var started := Time.get_ticks_usec()
	for i: int in 1000: controller.get_leg_motion_profile(foot)
	var cached_usec := Time.get_ticks_usec() - started
	started = Time.get_ticks_usec()
	for i: int in 1000: controller._calculate_spider_motion_profile(foot)
	print("SPIDER_PROFILE_BENCH cached_usec=", cached_usec, " uncached_usec=", Time.get_ticks_usec() - started)
	var before: Dictionary = controller.get_leg_motion_profile(foot).duplicate()
	var slow_plan: Dictionary = controller._plan_spider_catch_up(before, 2.5, 0.35, 0.4, false)
	var faster_profile := before.duplicate()
	faster_profile.target_speed = 6.0
	var fast_plan: Dictionary = controller._plan_spider_catch_up(faster_profile, 2.5, 0.35, 0.4, false)
	check(fast_plan.relative_speed > slow_plan.relative_speed and fast_plan.duration <= slow_plan.duration, "Higher configured speed must raise catch-up capability without waiting for the limited gait speed")
	var limited_profile := before.duplicate()
	limited_profile.reachable_speed = 0.1
	check(controller._plan_spider_catch_up(limited_profile, 2.5, 0.35, 0.4, false) == slow_plan, "Catch-up must not feed back the reduced reachable speed")
	var far_plan: Dictionary = controller._plan_spider_catch_up(before, 20.0, 0.35, 0.4, false)
	check(far_plan.duration >= far_plan.minimum_safe_duration and far_plan.acceleration_budget <= 2000.0, "Long catch-up must respect bounded acceleration even past the duration cap")
	check(slow_plan.duration >= 0.35 and slow_plan.duration < 2.5 / (before.stride / 0.35 * controller.catch_up_speed_ratio), "Catch-up should remove the fixed-ratio delay while retaining nominal flight time")
	controller._spider_step_times[foot] = 1.5
	var after: Dictionary = controller.get_leg_motion_profile(foot)
	check(after.observed_step_duration == 1.5 and before.observed_step_duration != 1.5, "Same-frame observed duration must invalidate the cache")
	controller._spider_step_times.erase(foot)
	controller.structural_stride_enabled = false
	check(not controller.get_spider_stride_limits(foot).valid, "Structural mode toggle must take effect immediately")
	controller.get_leg_motion_profile(foot)
	controller.structural_stride_enabled = true
	check(controller.get_leg_motion_profile(foot).structural_stride_limit > 0.0, "Restored structural mode must rebuild profile")
	for i: int in 8: await physics_frame
	await process_frame
	var stats: Dictionary = controller.consume_performance_stats()
	print("SPIDER_PERF_CHECK ", stats)
	check(int(stats.get(&"physics_frames", 0)) > 0, "Enabled performance tracking must report real physics frames")
	check(int(stats.get(&"total_usec", 0)) > 0, "Enabled performance tracking must report actual elapsed time")
	var old_text: String = console._output.text
	console._append_output("hidden console test")
	console._refresh_output_text()
	check(console._output.text == old_text and console._output_dirty, "Hidden console must defer text layout")
	console.set_console_open(true)
	check("hidden console test" in console._output.text and not console._output_dirty, "Opening console must refresh pending output")
	console.set_console_open(false)
	console.execute_command("motiondetail summary")
	var summary: String = "\n".join(console._collect_motion_snapshot(npc))
	console.execute_command("motiondetail full")
	var full: String = "\n".join(console._collect_motion_snapshot(npc))
	check("detail=summary" in summary and "part=Leg_" in full, "Both summary and full tracking must remain available")
	check(summary.length() * 5 < full.length(), "Summary must substantially reduce diagnostic output")
	print("SPIDER_LOG_SIZE summary=", summary.length(), " full=", full.length(), " cache=", cache.counters)
	console.execute_command("motiondetail summary")
	console._emit_npc_motion_snapshot()
	var logger_stats: Dictionary = console.consume_control_performance_stats()
	check(logger_stats.timings.has(&"npc_motion_snapshot_build") and logger_stats.timings.has(&"log_print") and logger_stats.timings.has(&"console_text_refresh"), "Console must measure snapshot construction, printing and visible text layout separately")
	level.queue_free()
	await process_frame
	if not failed: print("PASS: Spider profile cache invalidation, live performance counters and deferred/compact console output.")
	quit(1 if failed else 0)
