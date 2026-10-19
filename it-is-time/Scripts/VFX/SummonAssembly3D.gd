extends Node3D
## Visual-only summoning component. All coordinates are local to this node.
## A short ground pause is deducted from the existing landing-to-assembly budget.
signal batch_started(count: int, part_count: int)
signal part_landed(unit_index: int, source_path: String)
signal part_attraction_started(unit_index: int, source_path: String)
signal creature_assembled(unit_index: int, visuals: Node3D)
signal creature_landed(unit_index: int, bounce_index: int)
signal creature_settled(unit_index: int, visuals: Node3D)
signal batch_finished(visual_roots: Array[Node3D])

const SNAPSHOT = preload("res://Scripts/VFX/SummonVisualSnapshot.gd")
@export_group("Trajectory")
@export var random_seed: int = 5168
@export_range(1.0, 18.0, 0.1) var burst_height: float = 9.0
@export var scatter_half_extents := Vector2(9.75, 9.75)
@export_range(0.5, 1.5, 0.05) var scatter_center_bias: float = 0.65
@export_range(0.4, 3.0, 0.05) var flight_duration: float = 0.82
@export_range(0.0, 0.4, 0.01) var anticipation_duration: float = 0.12
@export_range(0.0, 0.8, 0.05) var absorption_arc_height: float = 0.24
@export_range(0.1, 4.0, 0.01) var attraction_duration: float = 0.64
@export_range(0.0, 1.5, 0.01) var landing_pause: float = 0.16
@export_range(1.0, 4.0, 0.25) var acceleration_power: float = 2.0
@export_range(0.0, 2.0, 0.01) var launch_window: float = 0.34
@export_group("Air Assembly and Landing")
@export var assembly_height: float = 2.4
@export var assembly_height_variation: float = 1.2
@export var drop_duration: float = 0.32
@export var landing_stagger: float = 0.075
@export var landing_sequence_window: float = 0.6
@export var first_bounce_height: float = 0.08
@export var second_bounce_height: float = 0.025
@export var first_bounce_duration: float = 0.12
@export var second_bounce_duration: float = 0.08
@export_group("Layout")
@export var layout_width: float = 22.0
@export var layout_depth: float = 8.0
@export var max_row_spacing: float = 3.2
@export var layout_gap: float = 1.2
@export_range(0.0, 75.0, 1.0) var card_pitch_degrees: float = 45.0
@export_group("Playback")
## Full presentation, including the last rebound. Zero uses unretimed timings.
@export_range(0.0, 10.0, 0.1) var total_duration: float = 4.0
@export_range(0.1, 3.0, 0.1) var playback_speed: float = 1.0
var natural_duration: float = 0.0
var running := false
var paused := false
var elapsed: float = 0.0
var duration: float = 0.0
var fragments: Array[Dictionary] = []
var units: Array[Dictionary] = []
var load_error := ""
var _cache: Dictionary = {}
var _finished := false
var _card_frame := Basis.IDENTITY

func _camera_frame() -> Basis:
	var camera := get_viewport().get_camera_3d()
	if camera != null:
		return (global_basis.inverse() * camera.global_basis).orthonormalized()
	return Basis(Vector3.RIGHT, deg_to_rad(-card_pitch_degrees))

func _normalized_pose(box: AABB, factor: float, frame: Basis) -> Transform3D:
	var basis := frame.scaled(Vector3.ONE * factor)
	var pose := Transform3D(basis, -(basis * Vector3(box.get_center().x, box.position.y, box.get_center().z)))
	var normalized_box: AABB = pose * box
	pose.origin.y -= normalized_box.position.y
	return pose

func _sync_camera_alignment() -> bool:
	var frame := _camera_frame()
	if frame.is_equal_approx(_card_frame): return false
	_card_frame = frame
	for unit: Dictionary in units:
		unit.normalize = _normalized_pose(unit.snapshot.bounds, unit.factor, frame)
	for part: Dictionary in fragments:
		var unit: Dictionary = units[part.unit]
		var target: Transform3D = unit.normalize * Transform3D(part.authored_pose)
		target.origin += Vector3(unit.ground)
		part.target = target
		part.loose_basis = target.basis
		var box := _part_bounds(part.node, target.basis)
		part.land.y = 0.035 - box.position.y
	return true

func _exit_tree() -> void:
	for snapshot: Dictionary in _cache.values():
		SNAPSHOT.release(snapshot)

func clear() -> void:
	for unit: Dictionary in units:
		remove_child(unit.root)
		unit.root.queue_free()
	units.clear()
	fragments.clear()
	running = false
	paused = false
	elapsed = 0.0
	duration = 0.0
	natural_duration = 0.0
	_finished = false
	load_error = ""

## requests: [{scene: PackedScene or res:// path, height: float, id: Variant}].
## Pass actual result records here; this component never rolls gameplay results.
func play_batch(requests: Array) -> bool:
	clear()
	if requests.is_empty():
		load_error = "本次没有可召唤的怪物。"
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = random_seed
	_card_frame = _camera_frame()
	for request: Dictionary in requests:
		var resource: Variant = request.get("scene")
		var scene: PackedScene = load(resource) as PackedScene if resource is String else resource as PackedScene
		if scene == null:
			load_error = "无法加载怪物场景：" + str(resource)
			clear_failed()
			return false
		var key := scene.resource_path
		if not _cache.has(key):
			_cache[key] = SNAPSHOT.capture(scene)
		var snapshot: Dictionary = _cache[key]
		if snapshot.parts.is_empty():
			load_error = "场景中没有可见的 PhysicalBodyPart3D 部件：" + key
			clear_failed()
			return false
		var box: AABB = snapshot.bounds
		var wanted: float = clampf(float(request.get("height", 3.2)), 0.4, 10.0)
		# Limit very long creatures by width as well as height.
		var factor := wanted / maxf(maxf(box.size.y, box.size.x * 0.5), 0.01)
		var normalize := _normalized_pose(box, factor, _card_frame)
		var root := Node3D.new()
		root.name = "Summon_%02d" % units.size()
		root.set_meta(&"summon_source_scene", key)
		root.set_meta(&"summon_result_id", request.get("id", units.size()))
		add_child(root)
		units.append({"root": root, "snapshot": snapshot, "normalize": normalize,
			"width": box.size.x * factor, "height": wanted, "factor": factor, "done": false, "end": 0.0,
			"assembled": false, "landing_events": 0,
			"ground": Vector3.ZERO, "id": request.get("id", units.size())})
	_layout_units()
	var landing_points: Array[Vector3] = []
	for unit_index: int in units.size():
		var unit: Dictionary = units[unit_index]
		for part: Dictionary in unit.snapshot.parts:
			var node: Node3D = part.node.duplicate(0)
			unit.root.add_child(node)
			node.set_meta(&"source_part_path", part.path)
			var target: Transform3D = unit.normalize * Transform3D(part.pose)
			target.origin += Vector3(unit.ground)
			var land := _random_landing(rng, landing_points)
			landing_points.append(land)
			# Keep the authored assembly orientation for every phase. Only position
			# changes: no flat-on-floor pose, spin or rotation interpolation.
			var loose_basis := target.basis
			# Correct the geometry bottom without laying the card on the ground.
			var loose_box := _part_bounds(node, loose_basis)
			land.y = 0.035 - loose_box.position.y
			var launch := anticipation_duration + rng.randf_range(0.02, launch_window + 0.02)
			var flight := flight_duration * rng.randf_range(0.88, 1.12)
			# Exact configured durations; keep this RNG draw to preserve the existing
			# template's launch/landing distribution for all subsequent fragments.
			rng.randf_range(0.9, 1.1)
			var attraction := attraction_duration
			var hold := minf(landing_pause, maxf(0.0, attraction - 0.05))
			var land_at := launch + flight
			var attract_at := land_at + hold
			var end := launch + flight + attraction
			unit.end = maxf(float(unit.end), end)
			duration = maxf(duration, end)
			fragments.append({"node": node, "unit": unit_index, "path": part.path,
				"target": target, "authored_pose": part.pose, "land": land, "loose_basis": loose_basis,
				"launch": launch, "flight": flight, "attraction": attraction, "hold": hold,
				"land_at": land_at, "attract_at": attract_at,
				"peak": burst_height * rng.randf_range(0.8, 1.15),
				"landed": false, "attraction_started": false})
	_schedule_landings()
	natural_duration = duration + (0.04 if total_duration <= 0.0 else 0.0)
	duration = total_duration if total_duration > 0.0 else natural_duration
	running = true
	_sample(0.0, false)
	batch_started.emit(units.size(), fragments.size())
	return true

func _schedule_landings() -> void:
	var order: Array = units.duplicate()
	var last_impact := -INF
	var height_rng := RandomNumberGenerator.new()
	height_rng.seed = random_seed + 4229
	var height_order: Array = units.duplicate()
	# Seeded shuffling followed by stratified heights guarantees a visible mix of
	# low/high assembly points even in small batches, without changing unit scale.
	for i: int in range(height_order.size() - 1, 0, -1):
		var j := height_rng.randi_range(0, i)
		var swap: Dictionary = height_order[i]
		height_order[i] = height_order[j]
		height_order[j] = swap
	for i: int in height_order.size():
		var u := (float(i) + height_rng.randf_range(0.2, 0.8)) / height_order.size()
		height_order[i].assembly_lift = maxf(0.4, assembly_height + lerpf(-assembly_height_variation, assembly_height_variation, u))
	for unit: Dictionary in units:
		unit.assembly_end = unit.end
		unit.fall_time = drop_duration * sqrt(float(unit.assembly_lift) / maxf(assembly_height, 0.1))
		unit.desired_impact = float(unit.assembly_end) + 0.02 + float(unit.fall_time)
	# Order by natural contact time, rather than making high/low assemblies queue
	# behind one another. Keep the cadence compact even when the batch is large.
	order.sort_custom(func(a: Dictionary, b: Dictionary): return float(a.desired_impact) < float(b.desired_impact))
	var step := minf(landing_stagger, maxf(0.025, landing_sequence_window / maxi(units.size() - 1, 1)))
	duration = 0.0
	for unit: Dictionary in order:
		var impact := maxf(float(unit.desired_impact), last_impact + step)
		unit.landing_step = step
		unit.impact_at = impact
		# Start moving almost immediately after assembly; spread any necessary
		# contact adjustment over the fall instead of freezing a monster in midair.
		unit.drop_start = float(unit.assembly_end) + 0.02
		unit.fall_time = impact - float(unit.drop_start)
		unit.first_rebound_end = impact + first_bounce_duration
		unit.end = impact + first_bounce_duration + second_bounce_duration
		last_impact = impact
		duration = maxf(duration, unit.end)

func _unit_height(unit: Dictionary, time: float) -> float:
	if time < float(unit.assembly_end):
		return 0.0 # Fragment positions carry their own lift until the whole is ready.
	if time < float(unit.drop_start):
		return unit.assembly_lift
	if time < float(unit.impact_at):
		var p := clampf((time - float(unit.drop_start)) / maxf(float(unit.fall_time), 0.01), 0, 1)
		return float(unit.assembly_lift) * (1.0 - p * p)
	if time < float(unit.first_rebound_end):
		var p := clampf((time - float(unit.impact_at)) / maxf(first_bounce_duration, 0.01), 0, 1)
		return first_bounce_height * 4.0 * p * (1.0 - p)
	if time < float(unit.end):
		var p := clampf((time - float(unit.first_rebound_end)) / maxf(second_bounce_duration, 0.01), 0, 1)
		return second_bounce_height * 4.0 * p * (1.0 - p)
	return 0.0

func clear_failed() -> void:
	var reason := load_error
	clear()
	load_error = reason

func _layout_units() -> void:
	# Count affects spacing only. Never shrink units or move the camera to fit N.
	var columns := maxi(1, ceili(sqrt(float(units.size()) * 1.5)))
	columns = mini(columns, units.size())
	var rows := ceili(float(units.size()) / columns)
	var spacing_x := minf(6.2, layout_width / columns)
	var spacing_z := minf(max_row_spacing, layout_depth / maxi(rows - 1, 1))
	var pose_rng := RandomNumberGenerator.new()
	pose_rng.seed = random_seed + 291
	for i: int in units.size():
		var row: int = i / columns
		var column := i % columns
		var row_count := mini(columns, units.size() - row * columns)
		var x := (column - (row_count - 1) * 0.5) * spacing_x
		# Offset alternate rows slightly so silhouettes do not line up perfectly.
		if row % 2 == 1:
			x += spacing_x * 0.18
		units[i].ground = Vector3(x + pose_rng.randf_range(-0.35, 0.35), 0,
			(row - (rows - 1) * 0.5) * spacing_z + pose_rng.randf_range(-0.6, 0.6))

func _random_landing(rng: RandomNumberGenerator, previous: Array[Vector3]) -> Vector3:
	var result := Vector3.ZERO
	for attempt: int in 24:
		var angle := rng.randf_range(0, TAU)
		# 0.5 gives a uniform disk; 0.65 gently favours the centre while retaining
		# outer landings across the full radius. Do not shrink the scatter envelope.
		var radius := pow(rng.randf(), scatter_center_bias)
		result = Vector3(cos(angle) * radius * scatter_half_extents.x, 0,
			sin(angle) * radius * scatter_half_extents.y)
		var valid := true
		for point: Vector3 in previous:
			if result.distance_to(point) < 0.55:
				valid = false
				break
		if valid:
			break
	return result

func _part_bounds(node: Node3D, basis: Basis) -> AABB:
	var bounds := AABB()
	var first := true
	for child: Node in node.get_children():
		if child is GeometryInstance3D:
			var box: AABB = Transform3D(basis, Vector3.ZERO) * child.transform * child.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
	return bounds

func _process(delta: float) -> void:
	var camera_changed := _sync_camera_alignment()
	if running and not paused:
		seek(elapsed + delta * playback_speed)
	elif camera_changed and not fragments.is_empty():
		_sample(animation_time(), false)

## Public timeline is in presentation seconds; scheduling stays in source seconds.
func animation_time() -> float:
	return natural_duration if elapsed >= duration else elapsed * natural_duration / maxf(duration, 0.0001)

func presentation_scale() -> float:
	return duration / maxf(natural_duration, 0.0001)

func seek(time: float) -> void:
	_sync_camera_alignment()
	var next := clampf(time, 0.0, duration)
	if next < elapsed:
		_finished = false
		for part: Dictionary in fragments:
			part.landed = false
			part.attraction_started = false
		for unit: Dictionary in units:
			unit.done = false
			unit.assembled = false
			unit.landing_events = 0
	elapsed = next
	_sample(animation_time(), true)

func skip() -> void:
	if not fragments.is_empty():
		seek(duration)

func _sample(time: float, emit_events: bool) -> void:
	for unit: Dictionary in units:
		unit.root.position = Vector3.UP * _unit_height(unit, time)
	for part: Dictionary in fragments:
		var node: Node3D = part.node
		var age := time - float(part.launch)
		node.visible = age >= 0.0
		if age < 0.0:
			continue
		var land: Vector3 = part.land
		if age < float(part.flight):
			var t := age / float(part.flight)
			var origin := Vector3(0, 0.12, 0).lerp(land, t)
			origin.y += 4.0 * t * (1.0 - t) * float(part.peak)
			node.transform = Transform3D(part.target.basis, origin)
		else:
			# Hold is INCLUDED in attraction's original budget, never added to it.
			var travel := maxf(float(part.attraction) - float(part.hold), 0.05)
			# Absolute start belongs to this fragment, never to a unit or batch.
			var p := clampf((time - float(part.attract_at)) / travel, 0.0, 1.0)
			# Ease-in only: slow release, continuous acceleration, then socket snap.
			var smooth := pow(p, acceleration_power)
			var target: Transform3D = part.target
			var unit: Dictionary = units[part.unit]
			var air_target := target.origin + Vector3.UP * float(unit.assembly_lift)
			node.transform = Transform3D(target.basis, land.lerp(air_target, smooth))
			# A shallow position-only arc gives the accelerating pull a softer path;
			# endpoints and authored card orientation remain exact.
			node.position.y += sin(smooth * PI) * absorption_arc_height
			if p >= 1.0:
				node.transform = Transform3D(target.basis, air_target)
			if time >= float(unit.assembly_end):
				# Transfer the lift to the root once, so all joined pieces fall/bounce
				# together while preserving their exact authored relative transforms.
				node.transform = part.target
			if emit_events and not part.landed:
				part.landed = true
				part_landed.emit(part.unit, part.path)
			if emit_events and not part.attraction_started and time >= float(part.attract_at):
				part.attraction_started = true
				part_attraction_started.emit(part.unit, part.path)
	for i: int in units.size():
		var unit: Dictionary = units[i]
		if emit_events and not unit.assembled and time >= float(unit.assembly_end):
			unit.assembled = true
			creature_assembled.emit(i, unit.root)
		var contacts: Array[float] = [unit.impact_at, unit.first_rebound_end, unit.end]
		while emit_events and int(unit.landing_events) < contacts.size() and time >= contacts[unit.landing_events]:
			creature_landed.emit(i, unit.landing_events)
			unit.landing_events += 1
		if emit_events and not unit.done and time >= float(unit.end):
			unit.done = true
			creature_settled.emit(i, unit.root)
	if emit_events and not _finished and not units.is_empty() and elapsed >= duration:
		_finished = true
		running = false
		var roots: Array[Node3D] = []
		for unit: Dictionary in units:
			roots.append(unit.root)
		batch_finished.emit(roots)

func statistics() -> Dictionary:
	var sample_time := animation_time()
	var airborne := 0
	var resting := 0
	var attracting := 0
	var assembled := 0
	var settling := 0
	var settled := 0
	for part: Dictionary in fragments:
		var age := sample_time - float(part.launch)
		if age >= 0.0 and age < float(part.flight):
			airborne += 1
		elif age >= float(part.flight) and age < float(part.flight) + float(part.hold):
			resting += 1
		elif age >= float(part.flight) + float(part.hold) and age < float(part.flight) + float(part.attraction):
			attracting += 1
	for unit: Dictionary in units:
		if sample_time >= float(unit.assembly_end):
			assembled += 1
			if sample_time < float(unit.end): settling += 1
		if sample_time >= float(unit.end): settled += 1
	return {"units": units.size(), "parts": fragments.size(), "airborne": airborne,
		"resting": resting, "attracting": attracting, "assembled": assembled,
		"settling": settling, "settled": settled, "time": elapsed, "duration": duration}
