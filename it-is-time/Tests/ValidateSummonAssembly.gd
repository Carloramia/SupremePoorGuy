extends SceneTree
const EFFECT = preload("res://Scenes/VFX/SummonAssembly3D.tscn")
const SNAPSHOT = preload("res://Scripts/VFX/SummonVisualSnapshot.gd")
const DIR := "res://Scenes/Creatures/Characters/"
const SOURCES := ["Generate_Wolf.tscn", "Generate_Snake.tscn", "Generate_HornedBeast.tscn",
	"Generate_StumpBeast.tscn", "Generate_Spider.tscn", "Generate_Human.tscn"]
var failures: Array[String] = []
var finished_count := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, description: String) -> void:
	if not ok:
		failures.append(description)
		push_error(description)

func requests(count: int, height: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i: int in count:
		result.append({"scene": DIR + SOURCES[i % SOURCES.size()], "height": height, "id": i})
	return result

func run() -> void:
	var effect = EFFECT.instantiate()
	root.add_child(effect)
	# Check source-phase mechanics independently, then the fixed presentation clock.
	effect.total_duration = 0.0
	effect.batch_finished.connect(func(_roots: Array[Node3D]): finished_count += 1)
	for source: String in SOURCES:
		var asset := SNAPSHOT.capture(load(DIR + source))
		print("SOURCE_PARTS ", source, " ", asset.parts.size(), " bounds=", asset.bounds)
		SNAPSHOT.release(asset)
	for profile: Array in [[2, 6.0], [5, 3.2], [12, 1.5], [20, 1.0], [30, 0.8]]:
		var count: int = profile[0]
		check(effect.play_batch(requests(count, profile[1])), "profile failed: " + str(profile))
		if effect.fragments.is_empty():
			print("SOURCE_LOAD_ERROR ", effect.load_error)
			continue
		effect.paused = true
		effect.seek(effect.anticipation_duration * 0.5)
		for f: Dictionary in effect.fragments:
			check(not f.node.visible, "fragment appears before anticipation ends")
		check(effect.units.size() == count, "wrong unit count")
		check(effect.fragments.size() >= count, "no bodyparts extracted")
		check(effect.find_children("*", "RigidBody3D", true, false).is_empty(), "physics leaked into VFX")
		var ordered: Array = effect.fragments.duplicate()
		ordered.sort_custom(func(a: Dictionary, b: Dictionary): return a.land_at < b.land_at)
		for index: int in range(1, ordered.size()):
			check(float(ordered[index].attract_at) >= float(ordered[index - 1].attract_at), "early landing starts attraction after late landing")
		var early: Dictionary = ordered[0]
		var late: Dictionary = ordered[-1]
		var sample_time := float(early.attract_at) + 0.04
		effect.seek(sample_time)
		check(early.attraction_started, "early fragment waits for batch")
		check(not late.attraction_started and float(late.attract_at) > sample_time, "all fragments start together")
		check(early.node.position.distance_to(early.land) > 0.001, "early fragment has not begun moving")
		var node_ids: Dictionary = {}
		for f: Dictionary in effect.fragments:
			check(not node_ids.has(f.node.get_instance_id()), "fragment shared across monsters")
			node_ids[f.node.get_instance_id()] = true
			var box: AABB = effect._part_bounds(f.node, f.loose_basis)
			check(absf(box.position.y + f.land.y - 0.035) < 0.002, "part not grounded")
			var radial := pow(float(f.land.x) / effect.scatter_half_extents.x, 2.0) + pow(float(f.land.z) / effect.scatter_half_extents.y, 2.0)
			check(radial <= 1.00001, "fragment landed outside circular scatter")
		var impacts: Array[float] = []
		for unit: Dictionary in effect.units:
			impacts.append(unit.impact_at)
			check(float(unit.drop_start) >= float(unit.assembly_end), "creature descends before assembly")
			check(float(unit.drop_start) - float(unit.assembly_end) <= 0.021, "creature hovers waiting for landing queue")
			check(is_equal_approx(effect._unit_height(unit, unit.assembly_end), unit.assembly_lift), "assembly is not airborne")
			check(absf(float(unit.assembly_lift) - effect.assembly_height) <= effect.assembly_height_variation, "assembly lift outside configured range")
			check(is_zero_approx(effect._unit_height(unit, unit.impact_at)), "creature first contact misses ground")
			check(is_equal_approx(effect._unit_height(unit, unit.impact_at + effect.first_bounce_duration * 0.5), effect.first_bounce_height), "first bounce missing")
			check(is_equal_approx(effect._unit_height(unit, unit.first_rebound_end + effect.second_bounce_duration * 0.5), effect.second_bounce_height), "second bounce missing")
			check(is_zero_approx(effect._unit_height(unit, unit.end)), "creature does not settle on ground")
		impacts.sort()
		var lifts: Array[float] = []
		for unit: Dictionary in effect.units: lifts.append(unit.assembly_lift)
		lifts.sort()
		check(lifts[-1] - lifts[0] > 0.1, "assembly heights remain level")
		for index: int in range(1, impacts.size()):
			check(impacts[index] - impacts[index - 1] >= float(effect.units[0].landing_step) - 0.0001, "creature landings are not staggered")
		var fragment: Dictionary = effect.fragments[0]
		effect.seek(float(fragment.launch) + float(fragment.flight) * 0.5)
		check(fragment.node.basis.is_equal_approx(fragment.target.basis), "fragment rotated during flight")
		var landing_time: float = fragment.launch + fragment.flight
		effect.seek(landing_time + 0.001)
		check(effect.statistics().resting > 0, "landing pause not reported")
		effect.seek(landing_time + 0.1)
		check(fragment.node.position.is_equal_approx(fragment.land), "fragment moves during ground pause")
		effect.seek(landing_time + float(fragment.hold) - 0.001)
		check(fragment.node.position.is_equal_approx(fragment.land), "ground pause shorter than requested")
		var travel: float = fragment.attraction - fragment.hold
		var distances: Array[float] = []
		for progress: float in [0.25, 0.5, 0.75]:
			effect.seek(landing_time + float(fragment.hold) + travel * progress)
			check(fragment.node.basis.is_equal_approx(fragment.target.basis), "fragment rotated during attraction")
			distances.append(fragment.node.position.distance_to(fragment.land))
		check(distances[1] - distances[0] < distances[2] - distances[1], "attraction does not accelerate")
		var first_land: Vector3 = fragment.land
		finished_count = 0
		effect.skip()
		effect.skip()
		check(finished_count == 1, "skip duplicated completion")
		check(effect.statistics().assembled == count, "incomplete assembled batch")
		check(effect.statistics().settled == count, "batch completes before all bounces end")
		for unit: Dictionary in effect.units:
			check(unit.root.position.is_zero_approx(), "root remains in the air after skip")
			check(unit.landing_events == 3, "expected initial contact plus two bounce contacts")
		for f: Dictionary in effect.fragments:
			check(f.node.transform.is_equal_approx(f.target), "socket alignment lost")
		effect.seek(0.0)
		check(effect.statistics().assembled == 0, "rewind leaves completed units")
		effect.play_batch(requests(count, profile[1]))
		check(Vector3(effect.fragments[0].land).is_equal_approx(first_land), "same seed changes trajectory")
		effect.random_seed += 1
		effect.play_batch(requests(count, profile[1]))
		check(not Vector3(effect.fragments[0].land).is_equal_approx(first_land), "new seed does not change scatter")
		effect.random_seed -= 1
		print("SUMMON_ASSEMBLY_PROFILE_PASS units=%d parts=%d height=%.1f" % [count, effect.fragments.size(), float(profile[1])])
	# All finished species, including sources outside the default five-monster batch.
	check(effect.play_batch(requests(6, 3.2)), "six-species batch failed")
	for unit: Dictionary in effect.units:
		check(not unit.snapshot.parts.is_empty(), "empty source species")
	var direct := SNAPSHOT.capture(load("res://Scenes/Creatures/Bodyparts/Wolf/Torso/TorsoMain.tscn"))
	check(direct.parts.size() == 1, "standalone Bodyparts prefab unsupported")
	SNAPSHOT.release(direct)
	check(not effect.play_batch([]), "empty batch accepted")
	check(effect.fragments.is_empty() and effect.units.is_empty(), "clear left stale nodes")
	check(not effect.play_batch([{"scene": "res://Scenes/VFX/SummonAssembly3D.tscn"}]), "non-creature accepted")
	check(not effect.load_error.is_empty(), "invalid asset has no diagnosis")
	# The pause replaces part of the old attraction budget, preserving the deadline.
	effect.landing_pause = 0.0
	effect.play_batch(requests(5, 3.2))
	var original_duration: float = effect.duration
	effect.landing_pause = 0.16
	effect.play_batch(requests(5, 3.2))
	check(is_equal_approx(effect.duration, original_duration), "ground pause extends total duration")
	for f: Dictionary in effect.fragments:
		check(is_equal_approx(f.hold, 0.16), "standard hold is not 0.16 seconds")
		check(is_equal_approx(f.attraction - f.hold, 0.48), "standard attraction is not 0.48 seconds")
	# Count must never influence a fragment's scale.
	effect.play_batch(requests(1, 3.2))
	var single_basis: Basis = effect.fragments[0].target.basis
	effect.play_batch(requests(20, 3.2))
	check(Basis(effect.fragments[0].target.basis).is_equal_approx(single_basis), "count changed unit scale")
	# Density may overlap, but all screen-space targets remain addressable.
	var lab = load("res://Scenes/Tests/SummonAssemblyLab.tscn").instantiate()
	lab.auto_play = false
	root.add_child(lab)
	check(lab.count_input.value == 12 and lab.seed_input.value == 5169, "screenshot template not applied")
	check(is_equal_approx(lab.effect.landing_pause, 0.16), "template pause missing")
	lab.preset(2, 3.2)
	var camera_pose: Transform3D = lab.get_node("Camera3D").transform
	lab.preset(20, 3.2)
	check(lab.get_node("Camera3D").transform.is_equal_approx(camera_pose), "count changed camera distance")
	lab.effect.skip()
	lab._update_selection()
	check(lab._selection_entries.size() == 20, "assembled units are not all selectable")
	lab._hovered.assign([0, 1, 2])
	lab._selected = -1
	lab._cycle_selection()
	check(lab._selected == 0, "overlap selection did not start at front candidate")
	lab._hovered.assign([0, 1, 2])
	lab._cycle_selection()
	check(lab._selected == 1, "covered unit cannot be selected")
	# Automatic repeat pacing speeds up NEW draws only; R stays comparable.
	lab.play()
	var standard_duration: float = lab.effect.duration
	check(lab._last_pace == 0, "first draw is not standard")
	lab.play()
	check(lab._last_pace == 1, "repeat draw is not quick")
	check(is_equal_approx(standard_duration, 4.0) and is_equal_approx(lab.effect.duration, 4.0), "presentation is not fixed to four seconds")
	check(is_equal_approx(lab.effect.landing_pause, 0.06), "quick hold incorrect")
	check(is_equal_approx(lab.effect.attraction_duration - lab.effect.landing_pause, 0.3), "quick attraction incorrect")
	var draws: int = lab._draws_played
	var quick_duration: float = lab.effect.duration
	lab.play(true)
	check(lab._draws_played == draws and is_equal_approx(lab.effect.duration, quick_duration), "replay changed pacing")
	lab.effect.skip()
	lab.effect.skip()
	check(lab._finish_count == 1, "quick skip duplicates result completion")
	# Camera changes must update even paused/completed cards, with sockets intact.
	lab.get_node("Camera3D").rotation_degrees = Vector3(-30, 15, 0)
	lab.effect.seek(lab.effect.duration)
	var expected_frame: Basis = lab.get_node("Camera3D").basis.orthonormalized()
	check(Basis(lab.effect.units[0].normalize.basis).orthonormalized().is_equal_approx(expected_frame), "cards do not follow camera orientation")
	for f: Dictionary in lab.effect.fragments:
		check(f.node.transform.is_equal_approx(f.target), "camera change breaks assembly alignment")
	lab.queue_free()
	effect.total_duration = 4.0
	for count: int in [1, 2, 5, 12, 20, 30]:
		check(effect.play_batch(requests(count, 3.2)), "fixed duration batch failed")
		check(is_equal_approx(effect.duration, 4.0), "count changed total duration")
		effect.seek(3.999)
		check(effect.statistics().settled < count and effect.running, "fixed timeline padded with frozen results")
		effect.seek(4.0)
		check(effect.statistics().settled == count and not effect.running, "last monster did not settle at four seconds")
		check(is_equal_approx(effect.animation_time(), effect.natural_duration), "presentation clock did not reach source endpoint")
		print("FIXED_DURATION count=", count, " presentation=", effect.duration, " source=", effect.natural_duration)
	effect.clear()
	effect.queue_free()
	await process_frame
	print("SUMMON_ASSEMBLY_VALIDATION ", "PASS" if failures.is_empty() else "FAIL", " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
