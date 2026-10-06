extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func frames(count: int) -> void:
	for frame: int in range(count): await physics_frame
func feather_parts(container: Node) -> Array[Node]:
	var result: Array[Node] = []
	for child: Node in container.get_children():
		if child is PhysicalBodyPart3D and PhysicalBodyPart3D.BodyPartTag.Feather in child.tags: result.append(child)
	return result
func run() -> void:
	var actor := BIRD.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator := actor.get_node("BirdGenerator")
	generator.wing_count = 3
	generator.unsymmetrie = 0.0
	generator.inhomogeneity = 0.0
	generator.feather_spacing = 0.3
	generator.feather_length = 1.5
	generator.feather_width = 0.28
	generator.overall_scale = 2.0
	check(actor.generate_creature(),"Feathered bird must generate")
	var count := 0
	var followed_feather: PhysicalBodyPart3D
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if not part is PhysicalBodyPart3D: continue
		var size: Vector3 = part.get_meta("generated_size")
		var density: float = part.get_meta("generated_density")
		var mass_floor: float = actor.minimum_feather_mass if PhysicalBodyPart3D.BodyPartTag.Feather in part.tags else actor.minimum_part_mass
		check(is_equal_approx(part.mass,clampf(size.x*size.y*size.z*density,mass_floor,actor.maximum_part_mass)),"All physical parts must use typed density")
		if PhysicalBodyPart3D.BodyPartTag.Feather not in part.tags: continue
		count += 1
		check(part.owner == actor,"Generated feather bodies must persist in saved character scenes")
		check(part.has_node("CollisionShape3D"),"Physical feathers must have a collision shape")
		var mesh := part.get_node("MeshInstance3D") as MeshInstance3D
		var bounds := mesh.mesh.get_aabb()
		check(is_equal_approx(bounds.size.x,generator.feather_width*generator.overall_scale),"Feather width must scale once")
		check(is_equal_approx(bounds.size.z,generator.feather_thickness*generator.overall_scale),"Feather thickness must scale once")
		check(part.basis.y.dot(Vector3.LEFT)>0.999,"Initially folded feathers must point toward creature -X")
		if followed_feather == null: followed_feather = part
	check(count>0,"Bird must contain feather meshes")
	var controller := actor.get_node("WingPoseController3D")
	check(controller.feather_bindings.size()==count,"Every Feather must have a controller binding")
	for binding: Dictionary in controller.feather_bindings:
		check(PhysicalBodyPart3D.BodyPartTag.Wing in binding.a.tags,"Feather joint must attach to a Wing")
		check(binding.joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)==0.0 and binding.joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)==0.0,"Feather joints must lock X/Y rotation")
		check(binding.joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)>3.0,"Feather joints must allow Z rotation")
	var previews := generator.get_node("Wings").find_children("Feather_*","MeshInstance3D",true,false)
	check(previews.size()==count,"Framework preview and physical character must have identical feather counts")
	var first_preview := previews[0] as MeshInstance3D
	check(is_equal_approx(first_preview.mesh.get_aabb().size.x,generator.feather_width),"Preview mesh stays unscaled under the scaled Wings container")
	var parameters: Dictionary = generator._capture_default_parameters()
	check(parameters.has("feathers_enabled") and parameters.has("feather_spacing") and parameters.has("feather_color"),"Species default saving must capture feather settings")
	for node: Node in actor.find_children("*","",true,false):
		if node.name != "WingPoseController3D": node.set_physics_process(false)
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is PhysicalBodyPart3D: part.freeze = PhysicalBodyPart3D.BodyPartTag.Wing not in part.tags and PhysicalBodyPart3D.BodyPartTag.Feather not in part.tags
	await frames(10)
	var folded_position := followed_feather.global_position
	Input.action_press("Space")
	await frames(360)
	check(followed_feather.global_position.distance_to(folded_position)>0.1,"Feather meshes must move when wings unfold")
	var sample: Dictionary = controller.feather_bindings[0]
	var actual: Quaternion = sample.a.global_basis.orthonormalized().get_rotation_quaternion().inverse()*followed_feather.global_basis.orthonormalized().get_rotation_quaternion()
	print("[physical_feather_test] open_error_degrees=",rad_to_deg(actual.angle_to(sample.open)))
	check(actual.angle_to(sample.open)<0.35,"Feather must rotate into its spread orientation")
	var terminal: Dictionary = controller.feather_bindings[-1]
	check(Basis(terminal.open).y.dot(Vector3.UP)>0.99999,"Terminal feather target must follow its wing tip")
	var terminal_alignment: float = terminal.b.global_basis.y.normalized().dot(terminal.a.global_basis.y.normalized())
	print("[physical_feather_test] terminal_alignment=",terminal_alignment)
	check(terminal_alignment>0.95,"Terminal feather must physically align with its wing tip")
	Input.action_release("Space")
	await frames(360)
	var rear: Vector3 = sample.torso.global_basis.orthonormalized()*Vector3.LEFT
	print("[physical_feather_test] closed_alignment=", followed_feather.global_basis.y.normalized().dot(rear))
	check(followed_feather.global_basis.y.normalized().dot(rear)>0.97,"Refolded feathers must point toward creature -X")
	var packed := PackedScene.new()
	check(packed.pack(actor)==OK,"Feathered character must pack successfully")
	var restored := packed.instantiate()
	check(feather_parts(restored.get_node("GeneratedParts")).size()==count,"Saved scene must retain generated feather bodies")
	restored.free()
	followed_feather.break_part()
	check(not controller._binding_intact(sample),"Broken feathers must stop participating in control")
	check(controller._get_gravity_compensation_force(followed_feather).is_zero_approx(),"Broken feathers must lose gravity compensation")
	check(actor.generate_creature(),"Regeneration with feathers must succeed")
	check(feather_parts(actor.get_node("GeneratedParts")).size()==count,"Regeneration must not accumulate duplicate feathers")
	generator.feathers_enabled = false
	check(actor.generate_creature(),"Feathers-disabled generation must succeed")
	check(feather_parts(actor.get_node("GeneratedParts")).is_empty(),"Switch must remove physical feathers")
	check(generator.get_node("Wings").find_children("Feather_*","MeshInstance3D",true,false).is_empty(),"Switch must remove preview feathers")
	actor.queue_free()
	await frames(3)
	print("BIRD_FEATHERS_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
