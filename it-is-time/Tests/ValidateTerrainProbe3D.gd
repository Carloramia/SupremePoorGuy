extends SceneTree
const PROBE = preload("res://Scripts/Geometry/TerrainProbe3D.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)

func _initialize() -> void: call_deferred("run")

func add_box(body: CollisionObject3D, y: float) -> CollisionObject3D:
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	body.position.y = y
	root.add_child(body)
	return body

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var floor_body := add_box(StaticBody3D.new(), -0.5)
	var first := RigidBody3D.new()
	first.freeze = true
	add_box(first, 3.0)
	var second := RigidBody3D.new()
	second.freeze = true
	add_box(second, 1.5)
	await physics_frame
	await physics_frame
	var space := floor_body.get_world_3d().direct_space_state
	var performance := preload("res://Scripts/Debug/ControlPerformanceStats.gd").new()
	performance.set_enabled(true)
	var from := Vector3(0,5,0)
	var to := Vector3(0,-2,0)
	check(PROBE.intersect(space,from,to,1,&"",1,performance).is_empty(), "Probe must honor the exclusion budget")
	performance.consume()
	var hit := PROBE.intersect(space,from,to,1,&"",3,performance)
	check(hit.get("collider") == floor_body, "Dynamic bodies are skipped to find terrain")
	check(performance.consume().counters.get(&"terrain_ray_queries",0) == 3, "Count every real query")
	first.add_to_group(&"probe_terrain")
	check(PROBE.intersect(space,from,to,1,&"probe_terrain",3,performance).get("collider") == first, "Explicit terrain groups retain their previous behavior")
	for path: String in ["res://Scenes/Input/TerrainCursor3D.tscn", "res://Scenes/VFX/TerrainArcIndicator3D.tscn"]:
		var component := (load(path) as PackedScene).instantiate()
		root.add_child(component)
		component.set_process(false)
		component.set_physics_process(false)
		component.terrain_group = &""
		component.maximum_probe_exclusions = 3
		check(component._find_terrain_hit(from,to).get("collider") == floor_body, "Both cursor components use the shared terrain rules")
		component.queue_free()
	floor_body.queue_free()
	first.queue_free()
	second.queue_free()
	await process_frame
	print("TERRAIN_PROBE_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
