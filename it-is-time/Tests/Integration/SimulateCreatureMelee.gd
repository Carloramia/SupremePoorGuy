extends SceneTree
## Runs the actual NPCs and physics. No HP, attack, gait or faction rules are replaced.
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
const SPECIES := ["stump_beast", "wolf", "snake", "horned_beast", "spider"]

class ErrorCapture:
	extends Logger
	var mutex := Mutex.new()
	var errors: Array[Dictionary] = []
	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _notify: bool, kind: int, _traces: Array[ScriptBacktrace]) -> void:
		if kind == ERROR_TYPE_WARNING: return
		mutex.lock()
		errors.append({"function": function, "file": file, "line": line, "code": code, "message": rationale})
		mutex.unlock()
	func snapshot() -> Array[Dictionary]:
		mutex.lock()
		var copy := errors.duplicate(true)
		mutex.unlock()
		return copy

class Sampler:
	extends Node
	var test: SceneTree
	func _physics_process(_delta: float) -> void: test.sample()

var actors: Array[Dictionary] = []
var modules: Array[Dictionary] = []
var attacks: Array[Dictionary] = []
var damage_events: Array[Dictionary] = []
var breaks: Array[Dictionary] = []
var effects: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var intents: Array[Dictionary] = []
var lifecycle_events: Array[Dictionary] = []
var current_intents: Dictionary = {}
var source_actions: Dictionary = {}
var last_actions: Dictionary = {}
var clock := 0.0
var frames := 0
var collecting := false
var capture := ErrorCapture.new()
var options := {"seed": 161001, "seconds": 60.0, "mode": "mixed", "separation": 100.0, "out": "res://Tests/.runtime/melee.json"}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--") and "=" in argument:
			var pair := argument.substr(2).split("=", true, 1)
			options[pair[0]] = pair[1]
	OS.add_logger(capture)
	call_deferred("run")

func _register_module(actor: Dictionary, node: Node, action: String, wolf: bool = false) -> void:
	if node == null: return
	modules.append({"actor": actor, "node": node, "action": action, "wolf": wolf, "current": -1, "final_event": ""})
	var npc_callback := _on_combat_event.bind(actor)
	if not actor.ai.combat_event.is_connected(npc_callback): actor.ai.combat_event.connect(npc_callback)
	if wolf:
		var callback := _on_wolf_event.bind(actor)
		if not node.get_parent().module_event.is_connected(callback): node.get_parent().module_event.connect(callback)

func _context(actor: Dictionary) -> Dictionary:
	var target: Variant = actor.ai.get("_target")
	return {"alive": actor.node.is_combat_alive(), "ragdolled": actor.node.is_temporarily_ragdolled(),
		"target_valid": is_instance_valid(target) and target.is_inside_tree() and not target.is_broken,
		"target": _target_actor(target), "state": actor.ai.current_state}

func _on_combat_event(event: StringName, details: Dictionary, actor: Dictionary) -> void:
	if not collecting or event not in [&"attack_started", &"attack_ended", &"target_lost"]: return
	lifecycle_events.append({"time": clock, "actor": actor.id, "kind": "npc", "event": event,
		"details": details.duplicate(true), "context": _context(actor)})
	if event == &"attack_started":
		assert(not current_intents.has(actor.id), "NPC cannot accept overlapping attack intents")
		var index := intents.size()
		current_intents[actor.id] = index
		intents.append({"id": index, "actor": actor.id, "species": actor.species, "action": str(details.attack),
			"start": clock, "end": null, "modules": [], "start_context": _context(actor), "start_details": details.duplicate(true)})
		for row: Dictionary in modules:
			if row.actor.id == actor.id and row.action == str(details.attack) and _active(row):
				var attack := attacks[_ensure_action(row)]
				attack.ai_selected = true
				attack["intent_id"] = index
				if attack.id not in intents[index].modules: intents[index].modules.append(attack.id)
	elif event == &"attack_ended" and current_intents.has(actor.id):
		var index: int = current_intents[actor.id]
		intents[index]["end"] = clock
		intents[index]["end_context"] = _context(actor)
		intents[index]["end_details"] = details.duplicate(true)
		current_intents.erase(actor.id)

func _on_wolf_event(module: StringName, event: StringName, details: Dictionary, actor: Dictionary) -> void:
	if not collecting: return
	for row: Dictionary in modules:
		if row.actor.id != actor.id or row.node.name != module: continue
		if event == &"started":
			row.final_event = ""
			_ensure_action(row)
		if row.current < 0: return
		lifecycle_events.append({"time": clock, "actor": actor.id, "kind": "wolf", "attack_id": row.current,
			"event": event, "details": details.duplicate(true), "context": _context(actor)})
		if not _active(row):
			row.final_event = str(event)
			attacks[row.current]["finish_details"] = details.duplicate(true)
		return

func _active(row: Dictionary) -> bool:
	return bool(row.node.active) if row.wolf else bool(row.node.is_npc_attack_active())

func _phase(row: Dictionary) -> String:
	if row.wolf or row.action == "snake_lunge_bite": return str(row.node.get("_phase"))
	return str(row.node.get_script().get_script_constant_map().get("Phase", {}).find_key(row.node.phase))

func _target_actor(part: Variant) -> String:
	if not is_instance_valid(part) or not part is Node: return ""
	var actor := CONTEXT.character_of(part)
	return str(actor.name) if actor != null else ""

func _ensure_action(row: Dictionary) -> int:
	if row.current >= 0: return row.current
	var ai: Node = row.actor.ai
	var part: Variant = row.node.get("target") if row.wolf else row.node.get("_target")
	if not is_instance_valid(part): part = ai.get("_target")
	row.current = attacks.size()
	row.final_event = ""
	attacks.append({"id": row.current, "actor": row.actor.id, "species": row.actor.species, "action": row.action,
		"target": _target_actor(part), "start": clock, "end": null, "reason": "", "phases": [], "damage": 0.0,
		"damage_events": 0, "victims": [], "victim_parts": [], "ai_selected": ai.get("_active_attack") != null and str(ai._active_attack.action_id) == row.action})
	last_actions[row.actor.id + ":" + row.action] = row.current
	if current_intents.has(row.actor.id):
		var index: int = current_intents[row.actor.id]
		attacks[row.current]["intent_id"] = index
		intents[index].modules.append(row.current)
	return row.current

func _reason(row: Dictionary) -> String:
	if not str(row.final_event).is_empty(): return str(row.final_event)
	var value: Variant = row.node.get("_last_reason") if row.action == "snake_lunge_bite" else row.node.get("_reason")
	return str(value) if value != null else "module_inactive"

func _poll_module(row: Dictionary) -> void:
	if not is_instance_valid(row.node): return
	if _active(row):
		var index := _ensure_action(row)
		var selection: Variant = row.actor.ai.get("_active_attack")
		if selection != null and str(selection.action_id) == row.action: attacks[index].ai_selected = true
		var phase := _phase(row)
		var changes: Array = attacks[index].phases
		if changes.is_empty() or changes[-1].phase != phase:
			var change := {"phase": phase, "time": clock, "reason": _reason(row)}
			if row.action == "snake_lunge_bite":
				var diagnostics: Dictionary = row.node.get_attack_diagnostics()
				for key: String in ["alignment", "head_error", "head_aim_error_degrees", "planned_distance", "expected_alignment_time"]:
					change[key] = diagnostics.get(key)
			changes.append(change)
	elif row.current >= 0:
		attacks[row.current].end = clock
		attacks[row.current].reason = _reason(row)
		attacks[row.current]["end_context"] = _context(row.actor)
		if row.action == "snake_lunge_bite":
			attacks[row.current]["attack_result"] = row.node._attack_result
			attacks[row.current]["recovery_result"] = row.node._recovery_result
		row.current = -1

func _source_actor(source: Node) -> Node:
	if not is_instance_valid(source): return null
	if source is SampleWeapon3D and is_instance_valid(source.wielder_character): return source.wielder_character
	return CONTEXT.character_of(source)

func _action_for_source(source: Node) -> int:
	var actor := _source_actor(source)
	if actor == null: return -1
	# A shockwave passes its character as source; the character survives across attacks.
	if source != actor and source_actions.has(source.get_instance_id()): return source_actions[source.get_instance_id()]
	var action := "foreleg_stomp" if source == actor else ""
	if source is SampleWeapon3D:
		if "Snake" in str(source.name): action = "snake_lunge_bite"
		elif "Bite" in str(source.name): action = "wolf_bite"
		elif source is ChargeWeapon3D: action = "ground_charge"
		elif "Spider" in str(source.name): action = "spider_pounce"
	for row: Dictionary in modules:
		if row.actor.node == actor and (row.action == action or action.is_empty()) and _active(row):
			var index := _ensure_action(row)
			if source != actor: source_actions[source.get_instance_id()] = index
			return index
	return int(last_actions.get(str(actor.name) + ":" + action, -1))

func _on_damage(amount: float, hp: float, source: Node, actor: Dictionary, part: PhysicalBodyPart3D) -> void:
	if not collecting or amount <= 0.0: return
	var attacker := _source_actor(source)
	var index := _action_for_source(source) if is_instance_valid(source) else -1
	var event := {"time": clock, "victim": actor.id, "victim_species": actor.species, "part": str(part.name), "amount": amount,
		"hp": hp, "source": str(source.name) if is_instance_valid(source) else "none", "attacker": str(attacker.name) if attacker != null else "", "attack_id": index,
		"friendly": attacker != null and attacker.get_faction_id() == actor.node.get_faction_id()}
	damage_events.append(event)
	if index >= 0:
		var attack: Dictionary = attacks[index]
		attack.damage += amount
		attack.damage_events += 1
		if actor.id not in attack.victims: attack.victims.append(actor.id)
		var key: String = actor.id + "/" + str(part.name)
		if key not in attack.victim_parts: attack.victim_parts.append(key)

func _on_break(_source: Node, actor: Dictionary, part: PhysicalBodyPart3D) -> void:
	if collecting: breaks.append({"time": clock, "actor": actor.id, "species": actor.species, "part": str(part.name)})

func _on_node_added(node: Node) -> void:
	if collecting and node is SampleWeapon3D: _action_for_source(node)
	if collecting and node.get_script() == preload("res://Scripts/VFX/StompShockwave3D.gd"):
		var source: Node = node.source_character
		var index := _action_for_source(source)
		node.tree_exiting.connect(_on_wave_finished.bind(node, index), CONNECT_ONE_SHOT)

func _on_wave_finished(wave: Node, index: int) -> void:
	if not collecting: return
	var victims: Array[String] = []
	for id: int in wave._hit:
		var actor: Variant = instance_from_id(id)
		if is_instance_valid(actor): victims.append(str(actor.name))
	effects.append({"time": clock, "attack_id": index, "kind": "stomp_shockwave", "contacts": wave.hit_count,
		"victims": victims, "impact_impulse": wave.impact_impulse, "raw_damage": wave.raw_impact_damage})

func sample() -> void:
	if not collecting: return
	frames += 1
	clock = float(frames) / Engine.physics_ticks_per_second
	for row: Dictionary in modules: _poll_module(row)
	if frames % 30 != 0: return
	for row: Dictionary in actors:
		var ai: Node = row.ai
		var alive: bool = row.node.is_combat_alive()
		if not alive and row.death_time == null: row.death_time = clock
		var anchor: Node3D = row.node.get_combat_anchor()
		var point := anchor.global_position if anchor != null else Vector3.ZERO
		var velocity := Vector3.ZERO
		if anchor is RigidBody3D: velocity = anchor.linear_velocity
		snapshots.append({"time": clock, "actor": row.id, "alive": alive, "state": ai.current_state,
			"block": str(ai._attack_block_reason), "enemy": _target_actor(ai._target),
			"position": [point.x, point.y, point.z], "speed": velocity.length(), "gates": ai._attack_gate_rejections.duplicate(true),
			"predictions": ai._attack_predictions.duplicate(true)})
		if not point.is_finite() or not velocity.is_finite(): push_error("Non-finite melee physics: " + row.id)
	if frames % 900 == 0: print("MELEE_PROGRESS seconds=", clock, " attacks=", attacks.size(), " damage_events=", damage_events.size())

func run() -> void:
	var wall_start := Time.get_ticks_msec()
	seed(int(options.seed))
	var console := root.get_node_or_null("RuntimeConsole")
	if console != null: console.auto_getlogs_enabled = false
	var viewport := SubViewport.new()
	viewport.name = "MeleeViewport"
	viewport.own_world_3d = true
	root.add_child(viewport)
	var host := preload("res://Scripts/Application/BattleHost.gd").new()
	host.name = "MeleeArena"
	host.ended = true
	viewport.add_child(host)
	(host.get_node("Ground").get_child(0).shape as BoxShape3D).size = Vector3(500, 1, 260)
	var navigation := NavigationRegion3D.new()
	var navmesh := NavigationMesh.new()
	navmesh.vertices = PackedVector3Array([Vector3(-245,0,-125),Vector3(245,0,-125),Vector3(245,0,125),Vector3(-245,0,125)])
	navmesh.add_polygon(PackedInt32Array([0,3,2,1]))
	navigation.navigation_mesh = navmesh
	host.add_child(navigation)
	await physics_frame
	await physics_frame
	var teams: Array = [SPECIES.duplicate(), SPECIES.duplicate()]
	if str(options.mode) == "duel":
		var pair := str(options.get("pair", "wolf,snake")).split(",")
		assert(pair.size() == 2 and pair[0] in SPECIES and pair[1] in SPECIES)
		teams = [[pair[0]], [pair[1]]]
	else:
		teams[0].shuffle()
		teams[1].shuffle()
	for team: int in 2:
		for slot: int in teams[team].size():
			var species: String = teams[team][slot]
			var record := FACTORY.template(species)
			record.merge({"id": "%s_%s_%s" % [species, team, options.seed], "position": "team", "traits": []}, true)
			var yaw := 0.0 if team == 0 else PI
			var bounds: AABB = Transform3D(Basis(Vector3.UP, yaw), Vector3.ZERO) * FACTORY.local_bounds(record)
			var center := Vector3(float(options.separation)*(-0.5 if team == 0 else 0.5), 0.0, (slot - (teams[team].size()-1)*0.5)*18.0)
			var at := center - Vector3(bounds.get_center().x, bounds.position.y-0.1, bounds.get_center().z)
			var actor := FACTORY.spawn(record, host, at, team, yaw)
			assert(actor != null)
			var ai: Node = actor.get_node("NPCStateMachine3D")
			var row := {"id": str(actor.name), "species": species, "team": team, "node": actor, "ai": ai,
				"initial_hp": record.hp, "death_time": null, "parts": record.parts.size(), "mass": actor.get_living_body_mass(),
				"bounds": [bounds.size.x,bounds.size.y,bounds.size.z], "scene_sha256": record.template_hash, "initial_position": [at.x,at.y,at.z]}
			actors.append(row)
			for part: PhysicalBodyPart3D in actor._get_physical_body_parts():
				part.damaged.connect(_on_damage.bind(row, part))
				part.broken.connect(_on_break.bind(row, part))
			match species:
				"wolf":
					_register_module(row, actor.get_node("WolfAttackController3D/Pounce"), "wolf_pounce", true)
					_register_module(row, actor.get_node("WolfAttackController3D/Bite"), "wolf_bite", true)
				"snake": _register_module(row, actor.get_node("SnakeBiteAttackController3D"), "snake_lunge_bite")
				"spider": _register_module(row, actor.get_node("CreatureActionController3D"), "spider_pounce")
				"stump_beast": _register_module(row, actor.get_node("CreatureActionController3D"), "foreleg_stomp")
				"horned_beast":
					_register_module(row, actor.get_node("CreatureActionController3D"), "foreleg_stomp")
					_register_module(row, actor.get_node("ChargeAttackController3D"), "ground_charge")
	await physics_frame
	await physics_frame
	node_added.connect(_on_node_added)
	var sampler := Sampler.new()
	sampler.test = self
	sampler.process_physics_priority = 100000
	host.add_child(sampler)
	collecting = true
	for row: Dictionary in actors: FACTORY.activate(row.node)
	while clock < float(options.seconds):
		await physics_frame
	collecting = false
	for row: Dictionary in modules:
		if row.current >= 0:
			attacks[row.current].end = clock
			attacks[row.current].reason = "observation_ended"
	for index: int in current_intents.values():
		intents[index]["end"] = clock
		intents[index]["censored"] = true
	var roster: Array[Dictionary] = []
	for row: Dictionary in actors:
		var copy := row.duplicate()
		copy.erase("node")
		copy.erase("ai")
		copy["alive"] = row.node.is_combat_alive()
		roster.append(copy)
	var report := {"schema": 2, "options": options, "simulated_seconds": clock, "physics_hz": Engine.physics_ticks_per_second,
		"wall_seconds": float(Time.get_ticks_msec()-wall_start)/1000.0, "roster": roster, "attacks": attacks, "damage_events": damage_events,
		"breaks": breaks, "effects": effects, "snapshots": snapshots, "intents": intents, "lifecycle_events": lifecycle_events,
		"errors": capture.snapshot(), "engine": Engine.get_version_info()}
	var path := ProjectSettings.globalize_path(str(options.out))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	assert(file != null)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	assert(damage_events.all(func(event: Dictionary): return not event.friendly), "Friendly damage violates combat rules")
	assert(damage_events.all(func(event: Dictionary): return event.attack_id >= 0), "Damage attribution must be complete")
	print("MELEE_RESULT path=", path, " attacks=", attacks.size(), " damage_events=", damage_events.size(), " errors=", report.errors.size(), " wall_seconds=", report.wall_seconds)
	viewport.queue_free()
	await process_frame
	await process_frame
	OS.remove_logger(capture)
	quit(0 if report.errors.is_empty() else 1)
