extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_HornedBeast.tscn")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collider.shape = shape
	floor_body.add_child(collider)
	level.add_child(floor_body)
	floor_body.position.y = -0.5
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	level.add_child(actor)
	actor.position.y = 0.15
	assert(actor.generate_creature())
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	var action := actor.get_node("CreatureActionController3D")
	for tick in range(180): await physics_frame
	var torso := actor.get_node("GeneratedParts/Torso") as RigidBody3D
	var start := torso.global_position
	print("[horned_smoke] settled=", start, " feet=", movement.get_leg_parts().size())
	Input.action_press("Right")
	for tick in range(180): await physics_frame
	Input.action_release("Right")
	var distance := torso.global_position.x - start.x
	print("[horned_smoke] displacement_x=", distance)
	assert(distance > 0.1)
	for tick in range(120): await physics_frame
	var started: bool = action.try_start_action()
	print("[horned_smoke] stomp_started=", started, " diagnostics=", action.get_action_diagnostics())
	assert(started)
	for tick in range(420):
		await physics_frame
		if tick % 60 == 59 and action.get_action_diagnostics().active:
			print("[horned_smoke] action_tick=", tick, " ", action.get_action_diagnostics())
	print("[horned_smoke] final_action=", action.get_action_diagnostics())
	assert(action.get_action_diagnostics().reason == &"completed")
	assert(action.get_action_diagnostics().shockwaves_spawned == 2)
	for node: Node in actor.get_node("GeneratedParts").get_children():
		if node is RigidBody3D:
			assert(node.global_position.is_finite())
			assert(not node.is_broken)
	level.free()
	await process_frame
	print("PASS: HornedBeast responds to Right, starts stomp and keeps finite intact bodies.")
	quit()
