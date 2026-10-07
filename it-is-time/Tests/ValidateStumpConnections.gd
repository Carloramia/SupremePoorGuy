extends SceneTree
const STUMP = preload("res://Scripts/Creatures/Generators/StumpBeastGenerator.gd")
const CHARACTER = preload("res://Scripts/Creatures/GeneratedCreatureCharacter3D.gd")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var generator := STUMP.new()
	var actor := CHARACTER.new()
	var maximum_gap := 0.0
	var links := 0
	for scale_value: float in [0.5,1.0,2.0]:
		generator.overall_scale = scale_value
		var previous_layouts: Array[Dictionary] = []
		var previous_network := PackedVector3Array()
		for seed_value: int in range(6):
			generator._random.seed = seed_value
			var plan := generator._create_valid_plan()
			assert(not plan.is_empty())
			plan.overall_scale = scale_value
			var blueprint := actor._build_blueprint(plan,generator.torso_connection_distance)
			if not previous_layouts.is_empty():
				assert(previous_network == plan.limb_network.vertices,"Preview network changed on regeneration")
				for index: int in blueprint.parts.size():
					assert(blueprint.parts[index].transform.is_equal_approx(previous_layouts[index].transform),"Part position/orientation must be deterministic")
					assert(blueprint.parts[index].size.is_equal_approx(previous_layouts[index].size),"Part size must be deterministic")
			previous_layouts = blueprint.parts.duplicate(true)
			previous_network = plan.limb_network.vertices.duplicate()
			for layout: Dictionary in blueprint.parts:
				layout.scene_rule = generator.get_part_scene_rule(actor._get_generated_part_type(layout),str(layout.name),str(layout.part_key))
			var stage := actor._instantiate_blueprint(blueprint,Transform3D.IDENTITY)
			assert(stage != null)
			var body := stage.get_node("Torso") as PhysicalBodyPart3D
			var contour := PackedVector2Array()
			for point: Vector3 in body.get_node("CollisionShape3D").shape.points:
				var p: Vector3 = body.transform * point
				contour.append(Vector2(p.x,p.y))
			contour = Geometry2D.convex_hull(contour)
			for connection: Dictionary in blueprint.connections:
				var a := stage.get_child(connection.a) as PhysicalBodyPart3D
				var b := stage.get_child(connection.b) as PhysicalBodyPart3D
				var anchor: Vector3 = connection.anchor
				for endpoint: int in [connection.a,connection.b]:
					var layout: Dictionary = blueprint.parts[endpoint]
					var rule: Resource = layout.scene_rule
					if rule == null or not rule.align_connectors_to_frame: continue
					var part := stage.get_child(endpoint) as PhysicalBodyPart3D
					var marker := GEOMETRY.connection_marker(part,anchor)
					var gap := marker.distance_to(anchor)
					maximum_gap = maxf(maximum_gap,gap)
					assert(gap < 0.00001,"Connector does not meet planned joint: " + str(part.name))
					links += 1
				if a.name == &"Torso" and str(b.name).begins_with("SubTorso"):
					assert(Geometry2D.is_point_in_polygon(Vector2(anchor.x,anchor.y),contour),"Leg root must touch the actual torso convex silhouette")
			for part: Node in stage.get_children():
				if part is PhysicalBodyPart3D: assert(part.scale.is_equal_approx(Vector3.ONE))
			var ports: Dictionary = {}
			for part: Node3D in stage.get_children():
				if not part is PhysicalBodyPart3D: continue
				for port: Node in part.get_children():
					if not port.has_meta(&"generated_connection_port"): continue
					var key: String = port.get_meta(&"joint_name")
					var point: Vector3 = part.transform * (port as Marker3D).position
					if ports.has(key): assert(point.distance_to(ports[key]) < 0.00001,"JointIn/JointOut port pair must overlap")
					else: ports[key] = point
			assert(ports.size() == blueprint.connections.size())
			stage.free()
	actor.free()
	generator.free()
	var sample: Node3D = load("res://Scenes/Creatures/Characters/Generate_StumpBeast.tscn").instantiate()
	sample.generate_on_ready = false
	root.add_child(sample)
	assert(sample.get_node("StumpBeastGenerator").base_limb_length == 1.0)
	assert(sample.get_node("StumpBeastGenerator").part_scene_rules[1].align_connectors_to_frame)
	assert(sample.generate_creature())
	var saved_transforms: Dictionary = {}
	for part: Node3D in sample.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: saved_transforms[part.name] = part.transform
	assert(sample.generate_creature())
	var saved_ports: Dictionary = {}
	for part: Node3D in sample.get_node("GeneratedParts").get_children():
		if not part is PhysicalBodyPart3D: continue
		assert(part.transform.is_equal_approx(saved_transforms[part.name]))
		for marker: Node in part.get_children():
			if not marker.has_meta(&"generated_connection_port"): continue
			var key: String = marker.get_meta(&"joint_name")
			var position: Vector3 = (marker as Marker3D).global_position
			if saved_ports.has(key): assert(position.distance_to(saved_ports[key]) < 0.00001)
			else: saved_ports[key] = position
	assert(saved_ports.size() == 19)
	sample.free()
	print("STUMP_CONNECTIONS_VALIDATION_PASSED endpoints=%d maximum_gap=%.9f" % [links,maximum_gap])
	quit()
