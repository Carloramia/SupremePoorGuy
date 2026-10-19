extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
const NPC = preload("res://Scenes/Creatures/Characters/Generate_Bird_NPC.tscn")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)

func _initialize() -> void: call_deferred("run")

func frames(count: int) -> void:
	for index: int in count: await physics_frame

func exercise_feathers(actor: Node) -> void:
	var controller := actor.get_node("WingPoseController3D")
	for node: Node in actor.find_children("*","",true,false):
		if node != controller: node.set_physics_process(false)
	actor.get_node("BirdFlightController3D").set_character_control_enabled(false)
	var tail_joints := []
	for joint: Node in actor.get_node("GeneratedParts/Joints").get_children():
		if joint.get_meta("generated_connection_kind", "") != "Tail": continue
		var tail: PhysicalBodyPart3D = joint.get_node(joint.node_b)
		tail.freeze = false
		tail_joints.append(joint)
	await frames(120)
	var tail_error := 0.0
	for joint: Generic6DOFJoint3D in tail_joints:
		var a: PhysicalBodyPart3D = joint.get_node(joint.node_a)
		var b: PhysicalBodyPart3D = joint.get_node(joint.node_b)
		var relative: Quaternion = a.global_basis.get_rotation_quaternion().inverse()*b.global_basis.get_rotation_quaternion()
		tail_error = maxf(tail_error,relative.angle_to(joint.get_meta("generated_rest_b_relative_a")))
		var frame_a: Transform3D = joint.get_meta("generated_joint_frame_a")
		var frame_b: Transform3D = joint.get_meta("generated_joint_frame_b")
		check((a.global_transform*frame_a.origin).distance_to(b.global_transform*frame_b.origin)<0.02,"Tail feathers must stay attached under gravity")
	check(tail_error<0.2,"Passive tail springs must hold the feather fan against gravity")
	print("BIRD_TAIL_PHYSICS_CHECKED count=",tail_joints.size()," maximum_rest_error_degrees=",rad_to_deg(tail_error))
	for binding: Dictionary in controller.feather_bindings: binding.b.freeze = false
	Input.action_press("Space")
	await frames(300)
	var maximum_error := 0.0
	for binding: Dictionary in controller.feather_bindings:
		var actual: Quaternion = binding.a.global_basis.get_rotation_quaternion().inverse()*binding.b.global_basis.get_rotation_quaternion()
		maximum_error = maxf(maximum_error,actual.angle_to(binding.open))
	check(maximum_error<0.35,"Every individual paper feather must physically reach its spread orientation")
	Input.action_release("Space")
	await frames(300)
	for binding: Dictionary in controller.feather_bindings:
		var rear: Vector3 = binding.torso.global_basis*Vector3.LEFT
		check(binding.b.global_basis.y.normalized().dot(rear)>0.97,"Every individual feather must physically refold toward the body rear")
	print("BIRD_PAPER_FEATHERS_CHECKED count=",controller.feather_bindings.size()," maximum_open_error_degrees=",rad_to_deg(maximum_error))

func signature(actor: Node) -> Dictionary:
	var result := {}
	for node: Node in actor.get_node("GeneratedParts").get_children():
		if not node is PhysicalBodyPart3D: continue
		result[str(node.name)] = {"pose":node.transform,"size":GEOMETRY.bounds(node,false).size,"source":node.get_meta("generated_scene_path","")}
	return result

func authored_state(actor: Node) -> Dictionary:
	var result := {}
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if not part is PhysicalBodyPart3D: continue
		var nodes := {}
		for node: Node in part.find_children("*","Node3D",true,false):
			if node.has_meta("generated_connection_port"): continue
			var entry := {"transform":node.transform}
			if node is VisualInstance3D: entry["visible"] = node.visible
			if node is CollisionShape3D:
				entry["disabled"] = node.disabled
				if node.shape is ConvexPolygonShape3D: entry["points"] = node.shape.points
				elif node.shape is BoxShape3D: entry["shape_size"] = node.shape.size
			if node is MeshInstance3D and node.mesh != null: entry["mesh_bounds"] = node.mesh.get_aabb()
			nodes[str(part.get_path_to(node))] = entry
		var generator := actor.get_node("BirdGenerator")
		var rule: Resource = generator.get_part_scene_rule(str(part.get_meta("generated_part_type")),str(part.name),str(part.get_meta("generated_part_key")))
		result[str(part.name)] = {"transform":part.transform,"nodes":nodes,"scene":rule.part_scene.resource_path,"size_mode":rule.size_mode,"size_multiplier":rule.size_multiplier}
	return result

func same_authored_value(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b): return false
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same_authored_value(a[key],b[key]): return false
		return true
	if a is PackedVector3Array:
		if a.size() != b.size(): return false
		for index: int in a.size():
			if not a[index].is_equal_approx(b[index]): return false
		return true
	if a is Transform3D or a is AABB or a is Vector3: return a.is_equal_approx(b)
	if a is float: return is_equal_approx(a,b)
	return a == b

func inspect(actor: Node) -> void:
	var container := actor.get_node("GeneratedParts")
	var bodies: Array[PhysicalBodyPart3D] = []
	var wings := 0
	var feathers := 0
	var tails := 0
	var feet := 0
	var heads := 0
	for node: Node in container.get_children():
		if not node is PhysicalBodyPart3D: continue
		var part := node as PhysicalBodyPart3D
		part.freeze = true
		bodies.append(part)
		check(part.geometry_mode == part.GeometryMode.CUSTOM_MODEL,"Every generated body must use Bird paper geometry")
		check(str(part.get_meta("generated_scene_path","")).contains("/Bodyparts/Bird/"),"Every Part must resolve a Bird scene")
		check(part.scale.is_equal_approx(Vector3.ONE),"Rigid bodies must retain unit scale")
		check(part.has_node("Model/PaperVolume") and part.get_node("Model/PaperVolume").visible,"Every Part must have visible paper volume")
		var shape := part.get_node("CollisionShape3D").shape as ConvexPolygonShape3D
		check(shape != null,"Bird collider must retain the texture contour")
		check(is_equal_approx(GEOMETRY.bounds(part).size.z,GEOMETRY.bounds(part,false).size.z*2.0),"Collision thickness must stay twice the paper thickness")
		var tag = PhysicalBodyPart3D.BodyPartTag
		if tag.Wing in part.tags:
			wings += 1
			check(tag.LegLimb not in part.tags and tag.Feather not in part.tags,"Wing stems must not also participate as legs or feather fans")
		if tag.Feather in part.tags:
			feathers += 1
			check(tag.Wing not in part.tags and tag.LegLimb not in part.tags,"Feathers must not receive duplicate Wing/Leg control")
			check(is_equal_approx(float(part.get_meta("generated_density")),0.001),"Individual feather density must match the calibrated light feather preset")
			check(str(part.get_meta("source_png","")).contains("Bird_3/Feathers/Flight"),"Feathers must use individual Bird_3 artwork")
		if tag.Leg in part.tags:
			feet += 1
			var rule: Resource = actor.get_node("BirdGenerator").get_part_scene_rule("Leg",str(part.name),str(part.get_meta("generated_part_key")))
			check(str(part.get_meta("generated_scene_path","")) == rule.part_scene.resource_path,"Each Leg must retain the user's current scene assignment")
		if tag.Head in part.tags: heads += 1
		if tag.Tail in part.tags:
			tails += 1
			check(tag.Feather in part.tags and part.name.begins_with("TailFeather_"),"Tail cluster must use individually referenced feather parts")
	check(bodies.size() == 45 and wings == 12 and feathers == 23 and tails == 5 and feet == 2 and heads == 1,"Bird must retain six blocks per wing and five tail feathers")
	check(not container.has_node("Neck_1_1"),"Bird must have no physical Neck")
	var joints := container.get_node("Joints")
	check(joints.get_child_count() == 44,"Bird must connect all subdivided wings and retain five tail joints")
	var direct_head := false
	for node: Node in joints.get_children():
		check(node is Generic6DOFJoint3D,"Assembly must not leave dangling segment spring proxies")
		var joint := node as Generic6DOFJoint3D
		var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
		var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
		check(a != null and b != null,"Joint endpoints must exist")
		var kind := str(joint.get_meta("generated_connection_kind"))
		if a.name == &"Torso" and b.name == &"Head_1": direct_head = true
		if kind == "Tail":
			check(a.name == &"Torso" and PhysicalBodyPart3D.BodyPartTag.Tail in b.tags,"Each tail feather must attach directly to Torso")
			check(not joint.has_meta("feather_open_relative_a"),"Tail must remain independent of wing unfold commands")
			for axis: String in ["x","y"]:
				check(is_zero_approx(joint.call("get_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)),"Tail must stay in the creature XY plane")
			check(joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING),"Tail must retain a passive rest spring")
		for part: PhysicalBodyPart3D in [a,b]:
			if kind == "Torso" and part.name == &"Torso": continue
			if kind == "Wing" and part.name == &"Torso": continue
			if kind == "Neck" and part.name == &"Torso": continue
			if kind == "Feather" and part == a:
				var start: Vector3 = part.transform*part.get_node("JointIn").position
				var end: Vector3 = part.transform*part.get_node("JointOut").position
				var root_xy := Vector3(joint.position.x,joint.position.y,start.z)
				check(Geometry3D.get_closest_point_to_segment(root_xy,start,end).distance_to(root_xy)<0.0001,"Feather roots must lie along the wing stem")
				continue
			var frame: Transform3D = joint.get_meta("generated_joint_frame_a" if part == a else "generated_joint_frame_b")
			check((part.transform*frame.origin).distance_to(joint.position)<0.0001,"Authored joint frame must retain its attachment: "+str(part.name)+" / "+str(joint.name))
	check(direct_head,"Head must connect directly to Torso")
	var support := actor.get_node("HeadPositionSupport3D")
	support.refresh_physics_query_cache()
	check(support.bindings.size() == 1 and not support.bindings[0].has_neck,"Head support must recognize the direct Torso attachment")
	var controller := actor.get_node("WingPoseController3D")
	controller.refresh_physics_query_cache()
	check(controller.bindings.size() == 12 and controller.feather_bindings.size() == 18,"Wing and feather controllers must discover every new binding")
	var section_feathers := [0,0,0]
	for binding: Dictionary in controller.bindings:
		section_feathers[binding.section_index] += binding.feathers.size()
	check(section_feathers == [4,6,8],"Subdivision must preserve the feathers assigned to each wing section")
	for binding: Dictionary in controller.feather_bindings:
		if not str(binding.b.name).ends_with("_3_004"): continue
		check(Basis(binding.open).y.dot(Vector3.UP)>0.99999,"Last feather must align with its unfolded wing tip")
	var audit: Dictionary = actor.get_internal_collision_diagnostics()
	check(audit.missing_pairs == 0 and audit.pairs == 990,"All internal collisions must remain ignored")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	movement.refresh_physics_query_cache()
	check(movement._chains.size() == 2,"Ground gait must find both two-link leg chains")
	var flight := actor.get_node("BirdFlightController3D")
	flight.refresh_physics_query_cache()
	check(flight._legs.size() == 2,"Flight tuck must find both feet")

func run() -> void:
	var console := root.get_node_or_null("RuntimeConsole")
	if console != null: console.set("auto_getlogs_enabled",false)
	var baseline := {}
	for argument: String in OS.get_cmdline_user_args():
		if not argument.begins_with("--baseline="): continue
		var previous: Node = load(argument.trim_prefix("--baseline=")).instantiate()
		previous.generate_on_ready = false
		previous.process_mode = Node.PROCESS_MODE_DISABLED
		root.add_child(previous)
		baseline = authored_state(previous)
		baseline.erase("Neck_1_1")
		previous.free()
	for packed: PackedScene in [CHARACTER,NPC]:
		var actor := packed.instantiate()
		actor.generate_on_ready = false
		actor.get_node("NPCStateMachine3D").enabled = false
		root.add_child(actor)
		var generator := actor.get_node("BirdGenerator")
		check(generator.use_manual_layout and generator.manual_layout != null,"Paper asset layout must persist in scene")
		check(generator.part_scene_rules.size() == 45,"Existing and added Parts must each retain their scene rules")
		check(generator.neck_segment_count == 0,"Procedural Neck count must stay zero")
		check(actor.density_data.is_valid(),"Bird density resource must be valid")
		inspect(actor)
		var saved := signature(actor)
		var authored := authored_state(actor)
		for key: String in baseline:
			check(authored.has(key) and same_authored_value(baseline[key],authored[key]),"Tail addition must preserve every existing model, collider and scene setting: "+key)
		check(actor.generate_creature(),"Regeneration must succeed")
		inspect(actor)
		var regenerated := authored_state(actor)
		for key: String in authored:
			check(same_authored_value(authored[key],regenerated[key]),"Regeneration must preserve authored model/collision transforms and source settings: "+key)
		var current := signature(actor)
		check(saved.keys() == current.keys(),"Regeneration must keep all authored part identities")
		for key: String in saved:
			check(saved[key].source == current[key].source,"Regeneration must retain physical scene references")
			if not saved[key].pose.is_equal_approx(current[key].pose) or not saved[key].size.is_equal_approx(current[key].size):
				print("BIRD_REGEN_DIFFERENCE ",key," saved_size=",saved[key].size," current_size=",current[key].size," saved_pose=",saved[key].pose," current_pose=",current[key].pose)
			check(saved[key].pose.is_equal_approx(current[key].pose) and saved[key].size.is_equal_approx(current[key].size),"Regeneration must retain connector placement and XY scale")
		generator.overall_scale = 1.5
		check(actor.generate_creature(),"Overall Scale must still scale the authored assembly")
		inspect(actor)
		for node: Node in actor.get_node("GeneratedParts").get_children():
			if not node is PhysicalBodyPart3D: continue
			check(GEOMETRY.bounds(node,false).size.is_equal_approx(saved[str(node.name)].size*1.5),"Overall Scale must scale XY and depth exactly once")
		print("BIRD_ASSEMBLY_CHECKED ",packed.resource_path)
		if packed == CHARACTER: await exercise_feathers(actor)
		actor.free()
		await process_frame
	print("BIRD_ASSEMBLY_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
