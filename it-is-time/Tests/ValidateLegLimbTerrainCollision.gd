extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20.0, 1.0, 20.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	root.add_child(floor_body)
	var scene := load("res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn") as PackedScene
	var limb := scene.instantiate() as PhysicalBodyPart3D
	limb.tags = [PhysicalBodyPart3D.BodyPartTag.LegLimb]
	limb.left_distance = 0.2
	limb.right_distance = 0.2
	limb.top_distance = 0.2
	limb.bottom_distance = 0.2
	limb.collision_thickness = 0.4
	limb.position.y = 2.0
	root.add_child(limb)
	var foot := scene.instantiate() as PhysicalBodyPart3D
	foot.tags = [PhysicalBodyPart3D.BodyPartTag.ForeLeg]
	foot.freeze = true
	foot.position.x = 8.0
	root.add_child(foot)
	await process_frame
	assert(floor_body in limb.get_collision_exceptions())
	assert(floor_body not in foot.get_collision_exceptions())
	assert(limb.collision_layer == foot.collision_layer and limb.collision_mask == foot.collision_mask)
	var late_terrain := StaticBody3D.new()
	root.add_child(late_terrain)
	assert(late_terrain in limb.get_collision_exceptions())
	var other_body := RigidBody3D.new()
	root.add_child(other_body)
	assert(other_body not in limb.get_collision_exceptions())
	for tick: int in range(90): await physics_frame
	assert(limb.position.y < -2.0, "Intact LegLimb should fall through terrain")
	limb.ignore_limb_terrain = false
	await process_frame
	assert(floor_body not in limb.get_collision_exceptions())
	assert(late_terrain not in limb.get_collision_exceptions())
	limb.position = Vector3(3.0,2.0,0.0)
	limb.linear_velocity = Vector3.ZERO
	for tick: int in range(90): await physics_frame
	assert(limb.position.y>0.1 and limb.position.y<0.4,"Restored intact limb must rest on terrain")
	limb.ignore_limb_terrain = true
	await process_frame
	assert(floor_body in limb.get_collision_exceptions())
	limb.break_part()
	await process_frame
	assert(floor_body not in limb.get_collision_exceptions())
	assert(late_terrain not in limb.get_collision_exceptions())
	limb.position = Vector3(3.0, 2.0, 0.0)
	limb.linear_velocity = Vector3.ZERO
	for tick: int in range(90): await physics_frame
	assert(limb.position.y > 0.1 and limb.position.y < 0.4, "Broken LegLimb should rest on terrain")
	print("PASS: intact LegLimb ignores existing/new terrain; Broken restores physical ground contact; feet and dynamic body filters unchanged")
	quit()
