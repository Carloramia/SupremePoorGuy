extends SceneTree

const ACTOR = preload("res://Scenes/Creatures/Characters/Generate_Spider.tscn")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var floor_body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100, 1, 100)
	collision.shape = shape
	floor_body.add_child(collision)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	var actor := ACTOR.instantiate()
	level.add_child(actor)
	await process_frame
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	movement.set_physics_process(false)
	actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
	# Remove every physical leg-to-Torso connection. Floating Torso height
	# must survive without any possible leg contact or constraint support.
	for joint: Generic6DOFJoint3D in actor.get_node("GeneratedParts/Joints").get_children():
		if joint.get_meta(&"spider_independent_root", false):
			joint.node_a = NodePath("")
			joint.node_b = NodePath("")
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D and (PhysicalBodyPart3D.BodyPartTag.Leg in part.tags or PhysicalBodyPart3D.BodyPartTag.LegLimb in part.tags):
			part.freeze = true
			part.position += Vector3(30, 10, 0)
	var torso := actor.get_node("GeneratedParts/Torso_Front") as RigidBody3D
	var initial := torso.global_position.y
	torso.linear_velocity.y = -2.0
	for tick: int in 180:
		movement._spider_support_rows.clear()
		movement._apply_spider_independent_support()
		await physics_frame
	check(absf(torso.global_position.y - initial) < 0.1, "Independent Torso support must recover height with all legs disconnected and airborne")
	check(absf(torso.linear_velocity.y) < 0.1, "Height support must damp vertical motion")
	check(movement._spider_support_rows.size() == 2, "Both Spider torsos must receive independent support")
	for row: Dictionary in movement._spider_support_rows:
		check(row.gravity_compensation.y > 0.0 and row.has_floor, "Support must compensate gravity and probe terrain excluding its own parts")
	print("SPIDER_INDEPENDENT height=", torso.global_position.y, " initial=", initial, " velocity=", torso.linear_velocity)
	level.free()
	if not failed: print("PASS: Spider Torso stays supported with every leg connection removed.")
	quit(1 if failed else 0)
