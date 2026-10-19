extends SceneTree

const PART = preload("res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn")
const HOST = preload("res://Scripts/Application/BattleHost.gd")
var capture := preload("res://Scripts/Debug/RuntimeErrorLogCapture.gd").new()
var failed := false
var checks := 0

class MovementCommand:
	extends Node
	func get_movement_direction() -> Vector3: return Vector3.RIGHT
	func is_fast_movement_requested() -> bool: return false
	func is_jump_requested() -> bool: return false

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	print("BROKEN_CLEANUP_CHECK ",ok," ",message)
	failed = failed or not ok

func frames(count: int) -> void:
	for frame: int in count: await process_frame

func make_part(parent: Node = root) -> PhysicalBodyPart3D:
	var part := PART.instantiate() as PhysicalBodyPart3D
	part.freeze = true
	parent.add_child(part)
	return part

func timeline() -> void:
	var part := make_part()
	var healthy := make_part()
	var sprite: Sprite3D = part.get_node("Sprite3D")
	var mesh: MeshInstance3D = part.get_node("MeshInstance3D")
	var shared := StandardMaterial3D.new()
	mesh.material_override = shared
	healthy.get_node("MeshInstance3D").material_override = shared
	mesh.transparency = 0.25
	check(part.broken_linger_duration==10.0 and part.broken_fade_duration==1.0,"Default corpse remains for 10 seconds, then fades for one second")
	part.break_part()
	part.set_process(false)
	var tween: Tween = part._broken_cleanup_tween
	tween.pause()
	tween.custom_step(9.9)
	check(sprite.modulate.a==1.0 and mesh.transparency==0.25 and not part.is_queued_for_deletion(),"No fade or deletion during the first 10 seconds")
	tween.custom_step(0.6)
	check(is_equal_approx(sprite.modulate.a,0.5) and is_equal_approx(mesh.transparency,0.625),"Sprite and mesh fade together while retaining their original transparency")
	check(shared.albedo_color.a==1.0 and healthy.get_node("MeshInstance3D").transparency==0.0,"Shared materials and living parts remain unchanged")
	if DisplayServer.get_name()!="headless":
		check(mesh.material_override!=shared and mesh.material_override.transparency==BaseMaterial3D.TRANSPARENCY_ALPHA,"Fade uses a private alpha-blended material")
	part.break_part()
	check(part._broken_cleanup_tween==tween,"Repeated break cannot reset the cleanup timer")
	tween.custom_step(0.6)
	check(sprite.modulate.a==0.0 and mesh.transparency==1.0 and part.is_queued_for_deletion(),"Delete only after every visual has fully faded")
	await frames(2)
	check(not is_instance_valid(part),"The body, colliders and visuals are freed")
	healthy.queue_free()
	await frames(2)

func pause_and_disabled_parent() -> void:
	var part := make_part()
	part.broken_linger_duration = 0.1
	part.broken_fade_duration = 0.1
	part.break_part()
	paused = true
	await frames(20)
	check(is_instance_valid(part) and part.get_node("MeshInstance3D").transparency==0.0,"Battle pause also pauses corpse lifetime and fading")
	paused = false
	await create_timer(0.35).timeout
	check(not is_instance_valid(part),"Cleanup resumes when the game resumes")
	var disabled := Node3D.new()
	disabled.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(disabled)
	var prebroken := PART.instantiate() as PhysicalBodyPart3D
	prebroken.freeze = true
	prebroken.is_broken = true
	prebroken.broken_linger_duration = 0.02
	prebroken.broken_fade_duration = 0.05
	disabled.add_child(prebroken)
	await frames(12)
	check(not is_instance_valid(prebroken),"Saved Broken parts clean up even under disabled character processing")
	disabled.queue_free()
	var presentation := make_part()
	presentation.set_meta(&"summon_presentation",true)
	presentation.break_part()
	check(not presentation.is_broken and presentation._broken_cleanup_tween==null,"Summon presentation remains immune to break and cleanup")
	presentation.queue_free()
	await frames(2)

func outline() -> void:
	var group := Node3D.new()
	root.add_child(group)
	var part := make_part(group)
	part.sprite_visible = true
	var effect := preload("res://Scripts/VFX/AutoOutline.gd").new()
	group.add_child(effect)
	await frames(2)
	part.break_part()
	part._broken_cleanup_tween.pause()
	part._broken_cleanup_tween.custom_step(10.5)
	await frames(2)
	var sprite: Sprite3D = part.get_node("Sprite3D")
	check(effect._entries.has(sprite) and is_equal_approx(effect._entries[sprite].mesh.transparency,0.5),"External AutoOutline follows the fading Sprite without leaving a black silhouette")
	part._broken_cleanup_tween.custom_step(0.6)
	await frames(3)
	check(effect._entries.is_empty(),"Outline nodes disappear after their body is freed")
	group.queue_free()
	await frames(2)

func damage_receipt() -> void:
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate()
	actor.set_meta(&"creature_instance_id","cleanup_receipt")
	root.add_child(actor)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	for part: PhysicalBodyPart3D in actor._get_physical_body_parts():
		part.freeze = true
		part.broken_linger_duration = 0.0
		part.broken_fade_duration = 0.05
	await frames(2)
	var damage: CharacterDamageController3D = actor.get_node("CharacterDamageController3D")
	var leg: PhysicalBodyPart3D = actor.get_node("Leg_R")
	var max_hp := leg.max_hp
	leg.break_part()
	await frames(10)
	check(not is_instance_valid(leg) and not actor.has_node("HipJoint_R"),"Detached leg and its joint are removed safely")
	var states := damage.get_part_damage_states()
	check(states.Leg_R.broken and states.Leg_R.hp==0.0 and states.Leg_R.max_hp==max_hp,"Deleted Broken part retains its battle damage receipt")
	check(damage.get_parts().size()==5 and actor._get_physical_body_parts().size()==5 and actor.is_combat_alive(),"Living character and caches remain usable after partial cleanup")
	damage.set_damage_logging_enabled(false)
	actor.get_node("Head").break_part()
	await frames(20)
	check(damage.get_parts().is_empty() and not actor.is_combat_alive(),"Whole-body death cleans every part without reviving character controls")
	states = damage.get_part_damage_states()
	check(states.size()==6 and states.values().all(func(state): return state.broken and state.hp==0.0),"All destroyed parts remain in the final damage state")
	var host := HOST.new()
	host.actors.append(actor)
	var result := [{}]
	host.finished.connect(func(value): result[0] = value)
	host.finish("victory")
	check(result[0].parts.get("cleanup_receipt",{}).size()==6 and result[0].parts.cleanup_receipt.Leg_R.broken,"Battle settlement includes parts that no longer exist in the scene")
	host.free()
	actor.queue_free()
	await frames(2)

func controller_cleanup_smoke() -> void:
	var paths: Array[String] = []
	var factory = preload("res://Scripts/Application/CreatureFactory.gd")
	for definition: Dictionary in factory.DEFINITIONS.values(): paths.append(definition.scene)
	paths.append_array(["res://Scenes/Creatures/Characters/Generate_Bird_NPC.tscn","res://Scenes/Creatures/Characters/Generate_Rat_1_NPC.tscn","res://Scenes/Creatures/Characters/Generate_Rat_2_NPC.tscn","res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Bow_NPC.tscn"])
	var actors: Array[Node3D] = []
	var targets: Array[PhysicalBodyPart3D] = []
	for path: String in paths:
		var actor: Node3D = load(path).instantiate()
		actor.generate_on_ready = false
		actor.position.x = actors.size()*100.0
		root.add_child(actor)
		actors.append(actor)
		var ai := actor.get_node_or_null("NPCStateMachine3D")
		if ai!=null: ai.set_physics_process(false); ai.set_process(false)
		var parts: Array = actor._get_physical_body_parts()
		var target: PhysicalBodyPart3D
		for part: PhysicalBodyPart3D in parts:
			part.freeze = true
			part.collision_layer = 0
			part.collision_mask = 0
			part.broken_linger_duration = 0.04
			part.broken_fade_duration = 0.08
			if target==null and (PhysicalBodyPart3D.BodyPartTag.Leg in part.tags or PhysicalBodyPart3D.BodyPartTag.Arm in part.tags): target = part
		if path.contains("Snake"): target = actor.get_node("GeneratedParts/Torso_001")
		if path.contains("Bird"): target = actor.get_node("GeneratedParts/Wing_1_Root_1")
		targets.append(target)
	await frames(3)
	for part: PhysicalBodyPart3D in targets: part.break_part()
	await frames(24)
	for index: int in actors.size():
		check(not is_instance_valid(targets[index]) and actors[index].is_combat_alive(),"Controllers survive partial part removal: "+paths[index].get_file())
		root.get_node("RuntimeConsole")._collect_motion_snapshot(actors[index])
	for actor: Node3D in actors:
		for part: PhysicalBodyPart3D in actor.get_body_parts_with_tag(PhysicalBodyPart3D.BodyPartTag.Head): part.break_part()
	await frames(24)
	for index: int in actors.size():
		check(not actors[index].is_combat_alive() and actors[index]._get_physical_body_parts().is_empty(),"Whole-body cleanup retains death state: "+paths[index].get_file())
		root.get_node("RuntimeConsole")._collect_motion_snapshot(actors[index])
		actors[index].queue_free()
	await frames(3)

func moving_wolf_chain_cleanup() -> void:
	for scene: String in ["Generate_Wolf", "Generate_Wolf_NPC"]:
		for removal: String in ["broken_foot", "broken_limb", "removed_foot", "removed_joint", "queued_root"]:
			var actor: Node3D = load("res://Scenes/Creatures/Characters/"+scene+".tscn").instantiate()
			actor.generate_on_ready = false
			root.add_child(actor)
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			for body: PhysicalBodyPart3D in actor._get_physical_body_parts(): body.freeze = true
			var movement = actor.get_node("GeneratedLegStepMovementController3D")
			movement.input_enabled = true
			movement.recovery_control_active = false
			var command := MovementCommand.new()
			actor.add_child(command)
			movement.command_source = command
			var foot: Variant = movement._legs[0]
			var foot_id: int = foot.get_instance_id()
			var chain: Dictionary = movement._chains[foot]
			var healthy: RigidBody3D = movement._legs[1]
			var healthy_chain: Dictionary = movement._chains[healthy]
			var caches: Array[Dictionary] = [movement._wolf_traction, movement._wolf_step_times, movement._wolf_profiles, movement._wolf_recovery_steps, movement._wolf_last_landings, movement._wolf_foot_lock_timers]
			for cache: Dictionary in caches: cache[foot] = {}
			var target: Variant = foot
			if removal=="broken_limb": target = chain.bodies[1]
			elif removal=="removed_joint": target = chain.joints[0]
			elif removal=="queued_root": target = chain.bodies[-2]
			if removal.begins_with("broken_"):
				target.break_part()
				target._broken_cleanup_tween.pause()
				target._broken_cleanup_tween.custom_step(11.1)
				await frames(2)
			elif removal=="queued_root":
				target.queue_free()
			else:
				target.free()
			# Private update runs before the parent update; logs can also be requested first.
			movement._update_wolf_traction(1.0/60.0)
			movement.get_stance_support_diagnostics()
			check(not movement._chains.has(foot) and movement._legs.all(func(leg): return leg.get_instance_id()!=foot_id),scene+" removes invalid chain: "+removal)
			var caches_cleared := true
			for cache: Dictionary in caches: caches_cleared = caches_cleared and not cache.has(foot)
			check(caches_cleared,"All Wolf foot caches release the same chain: "+removal)
			check(movement._chains.get(healthy,{})==healthy_chain,"Healthy chain retains its authored reference: "+removal)
			movement._physics_process(1.0/60.0)
			root.get_node("RuntimeConsole")._collect_motion_snapshot(actor)
			actor.queue_free()
			await frames(3)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var audio := root.get_node("CombatAudio")
	audio.settings = audio.settings.duplicate()
	audio.settings.enabled = false
	OS.add_logger(capture)
	await timeline()
	await pause_and_disabled_parent()
	await outline()
	await damage_receipt()
	await controller_cleanup_smoke()
	await moving_wolf_chain_cleanup()
	var error := capture.take_error()
	check(error.is_empty(),"No runtime errors or freed references: "+str(error))
	OS.remove_logger(capture)
	print("BROKEN_PART_CLEANUP_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
