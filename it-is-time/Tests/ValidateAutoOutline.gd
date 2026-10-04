extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var host := Node3D.new()
	root.add_child(host)
	var part := load("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCrature_Part_Physic_Arm.tscn").instantiate() as PhysicalBodyPart3D
	part.freeze = true
	part.sprite_visible = true
	host.add_child(part)
	var physical_part := load("res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn").instantiate() as RigidBody3D
	physical_part.freeze = true
	physical_part.sprite_visible = true
	host.add_child(physical_part)
	var unrelated := Sprite3D.new()
	unrelated.texture = load("res://Assets/2DResources/Samples/WhiteCube.png")
	host.add_child(unrelated)
	var outline: Node3D = load("res://Scenes/VFX/Outline/AutoOutline.tscn").instantiate()
	host.add_child(outline)
	await process_frame
	await process_frame
	assert(outline._entries.size() == 2, "Both inherited and base physical body scenes should match")
	var sprite := part.get_node("Sprite3D") as Sprite3D
	var physical_sprite := physical_part.get_node("Sprite3D") as Sprite3D
	assert(outline._entries.has(physical_sprite), "Physical body Sprite3D must be outlined")
	var entry: Dictionary = outline._entries[sprite]
	assert(entry.container.get_node("OutlinePath").curve.point_count >= 5)
	assert(entry.mesh.mesh != null)
	var first_mesh: ArrayMesh = entry.mesh.mesh
	outline.set_outline_enabled(false)
	assert(not outline.is_outline_enabled())
	assert(not outline.is_processing())
	assert(not entry.container.visible)
	part.scale = Vector3(2.0, 3.0, 1.0)
	part.right_distance = 2.0
	await process_frame
	await process_frame
	assert(entry.mesh.mesh == first_mesh, "Disabled outlines must not rebuild")
	outline.set_outline_enabled(true)
	await process_frame
	await process_frame
	assert(outline.is_processing())
	assert(entry.container.visible)
	assert(entry.mesh.mesh != first_mesh, "Changing dimensions must regenerate the mesh")
	assert(entry.container.global_basis.is_equal_approx(Basis.IDENTITY), "Outline must not inherit scale")
	var points: Curve3D = entry.container.get_node("OutlinePath").curve
	var vertices: PackedVector3Array = entry.mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert(is_equal_approx(vertices[0].distance_to(points.get_point_position(0)), outline.outline_width * 0.5))
	var sprite_normal := Vector3.FORWARD * -1.0
	var plane_offset := (points.get_point_position(0) - sprite.global_position).dot(sprite_normal)
	assert(plane_offset < 0.0, "Outline must be behind the Sprite3D plane")
	part.queue_free()
	physical_part.queue_free()
	await process_frame
	await process_frame
	assert(outline._entries.is_empty(), "Removed target must clean up")
	print("AUTO_OUTLINE_VALIDATION_PASSED")
	host.queue_free()
	quit()
