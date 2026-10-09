extends SceneTree

const SPIDER = preload("res://Scripts/Creatures/SpiderCharacter3D.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var level := Node3D.new()
	root.add_child(level)
	var config := SPIDER.new()
	var upper := PhysicalBodyPart3D.new()
	upper.name = "Upper"
	upper.tags.assign([PhysicalBodyPart3D.BodyPartTag.LegLimb])
	upper.gravity_scale = 0.0
	upper.freeze = true
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	upper.add_child(shape)
	var upper_sprite := Sprite3D.new()
	upper_sprite.name = "Sprite3D"
	upper.add_child(upper_sprite)
	level.add_child(upper)
	var foot := PhysicalBodyPart3D.new()
	foot.name = "Foot"
	foot.tags.assign([PhysicalBodyPart3D.BodyPartTag.Leg])
	foot.lock_foot_pitch_roll = false
	foot.gravity_scale = 0.0
	foot.linear_damp = 0.0
	foot.collision_layer = 0
	foot.collision_mask = 0
	var foot_shape := CollisionShape3D.new()
	foot_shape.name = "CollisionShape3D"
	foot_shape.shape = BoxShape3D.new()
	foot.add_child(foot_shape)
	var foot_sprite := Sprite3D.new()
	foot_sprite.name = "Sprite3D"
	foot.add_child(foot_sprite)
	level.add_child(foot)
	var joint := Generic6DOFJoint3D.new()
	level.add_child(joint)
	config._configure_spider_axial_joint(joint, foot, upper)
	check(joint.get_node(joint.node_a) == upper, "Upper limb must be endpoint A")
	check(joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING), "Axial slider needs its return spring")
	var slack := joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)
	check(slack > 0.0 and is_zero_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)) and is_zero_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)), "Only the upper-limb Y axis may slide")
	# Rotate both bodies AFTER capture. A frame fixed to world Y would fail.
	upper.rotation.z = PI / 3.0
	foot.rotation.z = PI / 3.0
	var axis := upper.global_basis.y.normalized()
	for tick: int in 90:
		foot.apply_central_force(axis * 100.0)
		await physics_frame
	var offset := foot.global_position - upper.global_position
	print("SPIDER_AXIAL offset=", offset, " along=", offset.dot(axis), " transverse=", offset.slide(axis).length(), " limit=", slack)
	check(offset.dot(axis) > slack * 0.5, "Force along the rotated upper limb must produce axial travel")
	check(offset.dot(axis) < slack + 0.02 and offset.slide(axis).length() < 0.01, "Travel must stay bounded and transverse motion locked")
	for tick: int in 120: await physics_frame
	check(foot.global_position.distance_to(upper.global_position) < 0.01, "Unloaded spring must return toward its zero offset")
	config.spider_axial_sliding_enabled = false
	config._configure_spider_axial_joint(joint, upper, foot)
	check(is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)) and not joint.get_flag_y(Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING), "Disabling sliding must restore a locked connection")
	level.free()
	config.free()
	if not failed: print("PASS: Spider axial sliding follows the upper limb, stays bounded, returns and can be disabled.")
	quit(1 if failed else 0)
