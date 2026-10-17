extends SceneTree
const REPORT := "D:/GameJamWorkspace/Reports/RatBiteAndSpeed_2026-10-17/"
var failed := false
var checks := 0
var events: Array[Dictionary] = []
var samples: Array[Dictionary] = []

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed=true; push_error("RAT_BITE_CHECK: "+message)

func run() -> void:
	if "--combat" in OS.get_cmdline_user_args():
		await run_combat()
		return
	var world: Node3D = load("res://Scenes/Levels/RatsTestLevel.tscn").instantiate()
	for key: String in ["GenerateRat1NPC","GenerateRat2NPC"]:
		var actor: Node = world.get_node(key)
		actor.get_node("NPCStateMachine3D").behavior=actor.get_node("NPCStateMachine3D").behavior.duplicate(true)
		actor.get_node("NPCStateMachine3D").behavior.auto_find_enemies=false
	root.add_child(world)
	current_scene=world
	for tick: int in 180: await physics_frame
	var rat: Node = world.get_node("GenerateRat1NPC")
	var target: Node = world.get_node("GenerateRat2NPC")
	var attack: Node = rat.get_node("WolfAttackController3D")
	var movement: Node = rat.get_node("GeneratedLegStepMovementController3D")
	attack.module_event.connect(func(module: StringName,event: StringName,details: Dictionary): events.append({"module":module,"event":event,"details":details.duplicate(true)}))
	check(attack.get_script().resource_path.ends_with("RatBiteAttackController3D.gd"),"Rat-specific controller loaded")
	check(movement.get_script().resource_path.ends_with("RatsLegStepMovementController3D.gd"),"Rat-specific movement wrapper loaded")
	var target_part: PhysicalBodyPart3D = target.get_node("GeneratedParts/Torso")
	target.disable_character_controls()
	for part: RigidBody3D in target._get_physical_body_parts(): part.freeze=true
	var delta: Vector3 = attack.head.global_position+Vector3(0.7,0.2,0)-target_part.global_position
	for part: RigidBody3D in target._get_physical_body_parts(): part.global_position+=delta
	var flags: Array[bool]=[attack._joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT),attack.head.head_position_support_enabled,attack.head.head_posture_damping_enabled]
	check(attack.try_start_npc_attack(&"wolf_bite",target_part,0.0),"Static nearby target admitted")
	var point: Vector3=attack._locked_point
	check(attack._lock_count==1,"Target acquired once during preparation")
	check(attack._weapon==null,"No damage volume during preparation")
	for foot: RigidBody3D in movement.get_leg_parts():
		if PhysicalBodyPart3D.BodyPartTag.ForeLeg in foot.tags:
			check(movement._is_leg_action_controlled(foot) and not movement._support_pins.has(foot),"ForeLeg adhesion released")
	# Moving the original victim must not redirect this committed attack.
	for part: RigidBody3D in target._get_physical_body_parts(): part.global_position.x+=12.0
	var had_hitbox:=false
	for tick: int in 240:
		await physics_frame
		check(attack._locked_point.is_equal_approx(point) and attack._lock_count==1,"Committed target point remains fixed")
		had_hitbox=had_hitbox or is_instance_valid(attack._weapon)
		if tick%6==0: samples.append(attack.get_diagnostics())
		if not attack.is_npc_attack_active(): break
	check(had_hitbox,"Damage volume created in strike phase")
	check(attack._arrived,"Head reaches the committed point despite target moving away")
	check(attack._reason==&"completed","Arrival closes the jaw and completes the bite")
	check(attack._weapon==null and movement._action_owners.is_empty(),"Hitbox and movement ownership cleaned up")
	check(attack.head.head_position_support_enabled==flags[1] and attack.head.head_posture_damping_enabled==flags[2],"Head support restored")
	check(attack._joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT)==flags[0],"Jaw joint flags restored")
	for tick: int in 120: await physics_frame
	# An explicit interruption must restore the same state too.
	delta=attack.head.global_position+Vector3(0.5,0.3,0)-target_part.global_position
	for part: RigidBody3D in target._get_physical_body_parts(): part.global_position+=delta
	check(attack.try_start_npc_attack(&"wolf_bite",target_part,0.0),"Second attack admitted after cooldown")
	attack.set_character_control_enabled(false)
	check(not attack.is_npc_attack_active() and movement._action_owners.is_empty() and attack.head.head_position_support_enabled==flags[1],"Control loss restores ownership and support")
	for actor: Node in [rat,target]:
		for part: RigidBody3D in actor._get_physical_body_parts(): check(part.global_position.is_finite() and part.linear_velocity.is_finite(),"Finite physical state")
	DirAccess.make_dir_recursive_absolute(REPORT)
	var output:=FileAccess.open(REPORT+"bite_validation.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed":not failed,"checks":checks,"events":events,"samples":samples},"\t"))
	output.close()
	world.free()
	await process_frame
	print("RAT_BITE_VALIDATION passed=",not failed," checks=",checks)
	quit(1 if failed else 0)

func run_combat() -> void:
	var world: Node3D = load("res://Scenes/Levels/RatsTestLevel.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	for tick: int in 2: await physics_frame
	var hits: Array[Dictionary]=[]
	var actors: Array[Node]=[world.get_node("GenerateRat1NPC"),world.get_node("GenerateRat2NPC")]
	for actor: Node in actors:
		actor.get_node("WolfAttackController3D").module_event.connect(func(module: StringName,event: StringName,details: Dictionary): events.append({"actor":actor.name,"module":module,"event":event,"details":details.duplicate(true)}))
		for part: Node in actor._get_physical_body_parts():
			part.damaged.connect(func(amount: float,hp: float,_source: Node): hits.append({"part":part.get_path(),"damage":amount,"hp":hp}))
	for tick: int in 1800:
		await physics_frame
		if tick%30!=0: continue
		for actor: Node in actors:
			var attack: Node=actor.get_node("WolfAttackController3D")
			check(actor.get_node("GeneratedParts/Torso").global_position.is_finite(),"Combat physical state remains finite")
			samples.append({"actor":actor.name,"time":tick/60.0,"attack":attack.get_diagnostics(),"ai":actor.get_node("NPCStateMachine3D").get_state_diagnostics()})
	var starts:=events.filter(func(row):return row.event==&"started").size()
	var arrivals:=events.filter(func(row):return row.event==&"point_reached").size()
	check(starts>0,"NPCs autonomously start the new bite")
	check(arrivals>0,"At least one autonomous bite reaches its static point")
	check(not hits.is_empty(),"Bite damage reaches the shared damage service")
	var output:=FileAccess.open(REPORT+"combat_validation.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed":not failed,"checks":checks,"events":events,"samples":samples,"hits":hits},"\t"))
	output.close()
	print("RAT_COMBAT passed=",not failed," starts=",starts," arrivals=",arrivals," damage_events=",hits.size())
	world.free()
	await process_frame
	quit(1 if failed else 0)
