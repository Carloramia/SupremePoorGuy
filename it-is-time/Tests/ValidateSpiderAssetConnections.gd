extends "res://Tests/ValidateManualPartSnapshot.gd"

func mesh_point(mesh: Mesh, uv: Vector2) -> Vector3:
	var arrays := mesh.surface_get_arrays(0)
	var coords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i: int in range(0,indices.size(),3):
		var a := indices[i]
		var b := indices[i+1]
		var c := indices[i+2]
		var v := coords[b]-coords[a]
		var w := coords[c]-coords[a]
		var determinant := v.cross(w)
		if absf(determinant)<0.0000000001: continue
		var relative := uv-coords[a]
		var u := relative.cross(w)/determinant
		var t := v.cross(relative)/determinant
		if u>=-0.0001 and t>=-0.0001 and u+t<=1.0001:
			return points[a]+(points[b]-points[a])*u+(points[c]-points[a])*t
	assert(false,"UV point outside calibrated mesh")
	return Vector3.ZERO

func verify_holes() -> void:
	var calibration: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/generator_calibration.json"))
	for r: Dictionary in calibration.models:
		var mesh: Mesh = load(r.calibrated_mesh)
		var size := Vector2(r.texture_size[0],r.texture_size[1])
		var origin := Vector2(r.origin_pixel[0],r.origin_pixel[1])
		var axis := Vector2(r.axis_pixel[0],r.axis_pixel[1])
		var across := Vector2(r.across_pixel[0],r.across_pixel[1])
		var endpoints := [origin,origin+axis*float(r.source_span)] if r.name=="UpperLeg" else [origin]
		for i: int in endpoints.size():
			var center: Vector2 = endpoints[i]
			var p := mesh_point(mesh,center/size)
			var target := float(r.calibrated_span)*(0.5 if i==1 else -0.5)
			if r.name!="UpperLeg": target=-target
			assert(Vector2(p.x,p.y).distance_to(Vector2(0,target))<0.0001,r.key+" ring center")
			var radius := 0.05/float(r.scales[i])
			for direction: Vector2 in [axis,across]:
				var a := mesh_point(mesh,(center-direction*radius)/size)
				var b := mesh_point(mesh,(center+direction*radius)/size)
				assert(absf(a.distance_to(b)-0.1)<0.002,r.key+" ring diameter")
	print("PASS: 24 endpoint holes have matching 0.1 diameter and calibrated UV centers.")

func verify_actor(actor: Node, mapping: Dictionary) -> void:
	var parts := actor.get_node("GeneratedParts")
	var generator := actor.get_node("SpiderGenerator")
	var rear_model: Node3D = parts.get_node("Torso_Rear/Model")
	assert(absf(rear_model.scale.x-rear_model.scale.y)<0.000001,"Rear Torso preserves original texture aspect ratio")
	var expected_depth := float(generator.part_width)*float(generator.overall_scale)*2.0
	for key: String in mapping:
		var body: PhysicalBodyPart3D = parts.get_node(key)
		assert(body.get_meta("generated_scene_path")==mapping[key],key+" scene rule")
		assert(body.basis.get_scale().is_equal_approx(Vector3.ONE),key+" root scale")
		assert(absf(preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd").bounds(body).size.z-expected_depth)<0.0001,key+" PartWidth")
	for joint: Generic6DOFJoint3D in parts.get_node("Joints").get_children():
		for body: Node3D in [joint.get_node(joint.node_a),joint.get_node(joint.node_b)]:
			var closest := INF
			for marker: Node in body.get_children():
				if not marker is Marker3D or marker.get_meta("generated_connection_port",false): continue
				var delta: Vector3 = marker.global_position-joint.global_position
				closest=minf(closest,Vector2(delta.x,delta.y).length())
			assert(closest<0.0002,str(joint.name)+" visual connector "+str(body.name)+" gap="+str(closest))
		if joint.get_meta("generated_connection_kind","")=="Limb":
			assert(joint.has_meta("spider_axial_slide"))
			assert(joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING))
			if joint.get_meta("spider_axial_slide").connection == "root":
				for axis: String in ["x", "y", "z"]:
					assert(joint.call("get_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT))
					assert(is_zero_approx(joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)))
					assert(is_zero_approx(joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)))
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	for leg: RigidBody3D in movement.get_leg_parts():
		assert(movement.get_spider_stride_limits(leg).valid,str(leg.name)+" structural stride")
	for body: Node in parts.get_children():
		if body is RigidBody3D: body.freeze=true

func run() -> void:
	verify_holes()
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/generator_part_mapping.json"))
	assert(mapping.size()==19)
	for suffix: String in ["","_NPC"]:
		var actor: Node = load("res://Scenes/Creatures/Characters/Generate_Spider"+suffix+".tscn").instantiate()
		actor.generate_on_ready=false
		root.add_child(actor)
		actor.set_physics_process(false)
		for child: Node in actor.get_children(): child.set_physics_process(false)
		verify_actor(actor,mapping)
		var baseline := inspect(actor)
		for iteration: int in 2:
			assert(actor.generate_creature())
			verify_actor(actor,mapping)
			compare(inspect(actor),baseline,1.0)
			await process_frame
		actor.free()
	print("PASS: 19 mapped Parts, 18 ring-aligned joints, PartWidth, structural stride and two regenerations for both Spider and NPC.")
	quit()
