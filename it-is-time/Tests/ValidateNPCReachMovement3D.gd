extends SceneTree
const NPC = preload("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn")
class Command extends Node:
	var direction := Vector3.ZERO
	func get_movement_direction() -> Vector3: return direction
	func is_jump_requested() -> bool: return false
	func is_fast_requested() -> bool: return false
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,200)
	collision.shape = box
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var actors: Array[Node3D] = []
	var commands: Array[Command] = []
	for i: int in range(2):
		var actor := NPC.instantiate() as Node3D
		if not OS.get_cmdline_user_args().has("--equipped"): actor.initial_weapon_scene = null
		actor.position = Vector3(-20 if i == 0 else 20,0.38,20*i)
		actor.rotation.y = PI*i
		actor.get_node("NPCStateMachine3D").enabled = false
		root.add_child(actor)
		var command := Command.new()
		root.add_child(command)
		actor.get_node("NPCLegStepMovementController3D").command_source = command
		actors.append(actor)
		commands.append(command)
	for frame: int in range(120): await physics_frame
	var starts: Array[Vector3] = []
	for i: int in range(2):
		var movement: Node = actors[i].get_node("NPCLegStepMovementController3D")
		var torso := actors[i].get_node("Torso") as RigidBody3D
		starts.append(torso.global_position)
		check(movement._get_contact_drive_body(actors[i].get_node("Leg_R")) == torso, "NPC traction must target Torso")
		var foot := actors[i].get_node("Leg_R") as RigidBody3D
		movement._expand_hip_joint_for_step(foot,foot.global_position+Vector3(0.5,0.1,0))
		var joint := actors[i].get_node("HipJoint_R") as Generic6DOFJoint3D
		check(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT) > 0.5, "Hip limits must budget the vertical lift")
		check(actors[i].get_node("NPCStateMachine3D/NavigationAgent3D").path_postprocessing == 0, "NPC path must use Funnel")
		commands[i].direction = Vector3(1 if i == 0 else -1,0,0.25).normalized()
	var saw_torso_force := false
	var saw_stance_pin := false
	var late_positions: Array[Vector3] = []
	for frame: int in range(600):
		await physics_frame
		if frame == 480:
			for actor: Node3D in actors: late_positions.append(actor.get_node("Torso").global_position)
		for actor: Node3D in actors:
			var movement: Node = actor.get_node("NPCLegStepMovementController3D")
			for row: Dictionary in movement.get_contact_drive_diagnostics().legs:
				if row.applied.length() > 0.01: saw_torso_force = row.driver == &"Torso"
			if not movement._support_pins.is_empty(): saw_stance_pin = true
	check(saw_torso_force and saw_stance_pin, "Torso must move while stance feet retain ground pins")
	for i: int in range(2):
		var torso := actors[i].get_node("Torso") as RigidBody3D
		var movement: Node = actors[i].get_node("NPCLegStepMovementController3D")
		var displacement := torso.global_position-starts[i]
		print("NPC_REACH_MOVEMENT yaw=",i*180," displacement=",displacement," velocity=",torso.linear_velocity," steps=",movement.get_step_sequence())
		check(displacement.dot(commands[i].direction)>2.0, "Both initial headings must make forward progress")
		check(displacement.z>0.2, "NPC must respond to Z movement rather than stall sideways")
		check(movement.get_step_sequence()>2, "Extension planner must keep starting steps")
		check(movement.get_step_sequence()<100, "Landing must not restart a swing every frame")
		check((torso.global_position-late_positions[i]).dot(commands[i].direction)>0.5, "NPC must continue moving after initial acceleration")
		check(absf(displacement.y)<0.5, "Expanded hip joints must retain standing height")
		check(torso.global_position.is_finite(), "Physics pose must remain finite")
	print("NPC_REACH_MOVEMENT_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
