extends SceneTree

const ATTACHMENT = preload("res://Scripts/Creatures/Modules/CreatureModuleAttachment.gd")
const ASSEMBLER = preload("res://Scripts/Creatures/Modules/GeneratedModuleAssembler.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
const BASE = "res://Scenes/Creatures/Modules/"

func _initialize() -> void: run.call_deferred()

func attachment(id: String, scene: String, host: String = "Torso") -> ATTACHMENT:
	var entry := ATTACHMENT.new()
	entry.instance_id = StringName(id)
	entry.module_scene = load(BASE+scene+".tscn")
	entry.host_part_key = host
	return entry

func bodies(actor: Node) -> Array[PhysicalBodyPart3D]:
	var result: Array[PhysicalBodyPart3D] = []
	for child: Node in actor.get_node("GeneratedParts").get_children():
		if child is PhysicalBodyPart3D: result.append(child)
	return result

func run() -> void:
	create_timer(20).timeout.connect(func() -> void: push_error("Module test timed out"); quit(1))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://Tests/.runtime/creature_modules"))
	root.get_node("RuntimeConsole").set("auto_getlogs_enabled",false)
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor._capture_manual_layout())
	var generator: Node3D = actor.get_node(actor.generator_path)
	assert(actor.generate_creature())
	var base_count := bodies(actor).size()
	var base_links: int = actor.get_node("GeneratedParts/Joints").get_child_count()
	var empty := attachment("empty","_SampleModule")
	var logic_source: Node = empty.module_scene.instantiate()
	logic_source.scene_file_path = ""
	var probe := Node.new()
	probe.name = "Logic"
	probe.set_script(preload("res://Tests/Fixtures/ModuleLogicProbe.gd"))
	logic_source.add_child(probe)
	for node: Node in logic_source.find_children("*","",true,false): node.owner = logic_source
	var logic_scene := PackedScene.new()
	assert(logic_scene.pack(logic_source)==OK)
	logic_source.free()
	empty.module_scene = logic_scene
	var visual := attachment("visual","VisualModule")
	var leg := attachment("leg","TwoSegmentLegModule")
	var arm := attachment("arm","TwoSegmentArmModule")
	var single := attachment("single","SinglePartModule")
	leg.mount_offset.origin = Vector3(0,0,1)
	arm.mount_offset.origin = Vector3(0.5,0.2,-1)
	single.size_multiplier = 1.5
	actor.module_attachments.assign([empty,visual,leg,arm,single])
	assert(actor.generate_creature())
	var container: Node3D = actor.get_node("GeneratedParts")
	assert(bodies(actor).size()==base_count+7)
	assert(container.get_node("Joints").get_child_count()==base_links+7)
	var logic: Node = container.get_node("Torso/Module_empty")
	logic._bind_host()
	assert(logic.get_node("Logic").character==actor and logic.get_node("Logic").active)
	logic.set_character_control_enabled(false)
	assert(not logic.get_node("Logic").active and not logic.visible)
	logic.set_character_control_enabled(true)
	var foot: PhysicalBodyPart3D = container.get_node("Module_leg__Foot")
	var movement: Node = actor.get_node("GeneratedLegStepMovementController3D")
	assert(foot in movement._legs and movement._chains.has(foot),"Added foot must join the gait controller")
	assert(movement._chains[foot].bodies.size()==4)
	assert(preload("res://addons/creature_part_editor/part_edit.gd").context(foot).is_empty(),"Module edits must not write base generator rules")
	assert(container.get_node("Module_arm__Hand") not in movement._legs)
	for body: PhysicalBodyPart3D in bodies(actor):
		assert(body.scale.is_equal_approx(Vector3.ONE))
		assert(not body.is_broken)
		assert(body.get_node("CollisionShape3D").is_inside_tree())
		assert(body.find_children("*","CollisionShape3D",true,false).size()==1)
		for other: PhysicalBodyPart3D in bodies(actor):
			if body!=other: assert(other in body.get_collision_exceptions())
	var module: Node3D = container.get_node("Torso/Module_leg")
	module._bind_host()
	assert(module.get_host_character()==actor and module.get_module_part(&"Foot")==foot)
	var elbow: Generic6DOFJoint3D = container.get_node("Joints/Module_leg__Elbow")
	assert(is_equal_approx(elbow.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),deg_to_rad(60.0)))
	movement.refresh_physics_query_cache()
	assert(is_equal_approx(elbow.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),deg_to_rad(60.0)))
	var first_pack := PackedScene.new()
	assert(first_pack.pack(actor)==OK)
	var first_restore := first_pack.instantiate()
	root.add_child(first_restore)
	assert(bodies(first_restore).size()==base_count+7,"Saving before capture must not duplicate template Parts")
	assert(first_restore.get_node("GeneratedParts/Torso/Module_leg/Parts").get_child_count()==0)
	assert(first_restore.get_node("GeneratedParts/Module_leg__Foot/CollisionShape3D").is_inside_tree())
	first_restore.queue_free()
	# Manual edits are captured separately and never leak into the base blueprint.
	var edited: PhysicalBodyPart3D = container.get_node("Module_single__Attachment")
	edited.position += Vector3(0.1,0.2,0)
	var collider: CollisionShape3D = edited.get_node("CollisionShape3D")
	collider.position.x += 0.04
	var expected_pose := edited.transform
	var expected_collider := collider.transform
	var expected_shape: Vector3 = collider.shape.size
	var visual_root: Node3D = container.get_node("Torso/Module_visual")
	visual_root.position.x += 0.15
	var visual_pose := visual_root.transform
	assert(actor._capture_manual_layout())
	assert(generator.manual_layout.blueprint.parts.size()==base_count)
	assert(single.captured_scene!=null)
	assert(actor.generate_creature())
	container = actor.get_node("GeneratedParts")
	edited = container.get_node("Module_single__Attachment")
	assert(edited.transform.is_equal_approx(expected_pose),"Captured module pose must survive regeneration")
	assert(edited.get_node("CollisionShape3D").transform.is_equal_approx(expected_collider),"Captured collider offsets must survive regeneration")
	assert(edited.get_node("CollisionShape3D").shape.size.is_equal_approx(expected_shape))
	assert(container.get_node("Torso").find_children("Module_single","",true,false).size()==1)
	assert(container.get_node("Torso/Module_visual").transform.is_equal_approx(visual_pose))
	# A saved character and its resources retain the same installations.
	var packed := PackedScene.new()
	assert(packed.pack(actor)==OK)
	var save_path := "res://Tests/.runtime/creature_modules/Character.tscn"
	assert(ResourceSaver.save(packed,save_path)==OK)
	var restored: Node3D = ResourceLoader.load(save_path,"",ResourceLoader.CACHE_MODE_IGNORE).instantiate()
	restored.generate_on_ready = false
	root.add_child(restored)
	assert(restored.generate_creature())
	assert(bodies(restored).size()==base_count+7)
	assert(restored.get_node("GeneratedParts/Module_single__Attachment").transform.is_equal_approx(expected_pose))
	restored.queue_free()
	var scale_before: float = generator.overall_scale
	generator.overall_scale *= 2.0
	assert(actor.generate_creature())
	var twice: Transform3D = expected_pose
	twice.origin *= 2.0
	assert(actor.get_node("GeneratedParts/Module_single__Attachment").transform.is_equal_approx(twice))
	assert(actor.get_node("GeneratedParts/Module_single__Attachment/CollisionShape3D").shape.size.is_equal_approx(expected_shape*2.0))
	generator.overall_scale = scale_before
	assert(actor.generate_creature())
	# Validation must preserve the old assembly and manual data.
	var previous := actor.get_node("GeneratedParts")
	var previous_capture: PackedScene = single.captured_scene
	single.host_part_key = "Missing"
	assert(not actor.generate_creature())
	assert(actor.get_node("GeneratedParts")==previous and single.captured_scene==previous_capture)
	single.host_part_key = "Torso"
	single.host_socket = ^"MissingSocket"
	assert(not actor.generate_creature())
	assert(actor.get_node("GeneratedParts")==previous)
	single.host_socket = NodePath()
	var valid_leg_scene: PackedScene = leg.captured_scene
	var disconnected: Node = valid_leg_scene.instantiate()
	disconnected.get_node("Joints/End").free()
	var disconnected_scene := PackedScene.new()
	assert(disconnected_scene.pack(disconnected)==OK)
	disconnected.free()
	leg.captured_scene = disconnected_scene
	assert(not actor.generate_creature())
	assert(actor.get_node("GeneratedParts")==previous)
	leg.captured_scene = valid_leg_scene
	actor.module_attachments.append(attachment("leg","_SampleModule"))
	assert(not actor.generate_creature())
	assert(actor.get_node("GeneratedParts")==previous)
	actor.module_attachments.pop_back()
	var second := attachment("second","SinglePartModule")
	actor.module_attachments.append(second)
	assert(actor.generate_creature())
	assert(bodies(actor).size()==base_count+8)
	var a_shape: Shape3D = actor.get_node("GeneratedParts/Module_single__Attachment/CollisionShape3D").shape
	var b_shape: Shape3D = actor.get_node("GeneratedParts/Module_second__Attachment/CollisionShape3D").shape
	assert(a_shape!=b_shape,"Independent installations must not share mutable colliders")
	actor.module_attachments.pop_back()
	# Removing an installation removes it once, without touching other instances.
	single.enabled = false
	assert(actor.generate_creature())
	assert(bodies(actor).size()==base_count+6)
	assert(not actor.get_node("GeneratedParts").has_node("Module_single__Attachment"))
	# Imported paper models retain their proportions and collider snapshot too.
	var paper_template: Node = load(BASE+"SinglePartModule.tscn").instantiate()
	paper_template.scene_file_path = ""
	paper_template.get_node("Parts/Attachment").free()
	var paper: PhysicalBodyPart3D = load("res://Scenes/Creatures/Bodyparts/Wolf/Tail/TailMain.tscn").instantiate()
	paper.name = "Attachment"
	paper_template.get_node("Parts").add_child(paper)
	paper.prepare_generated_geometry()
	var geometry = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
	var source_size: Vector3 = geometry.bounds(paper,false).size
	for node: Node in paper_template.find_children("*","",true,false):
		if node.owner==null: node.owner = paper_template
	paper_template.set_editable_instance(paper,true)
	var paper_scene := PackedScene.new()
	assert(paper_scene.pack(paper_template)==OK)
	paper_template.free()
	var custom := attachment("paper","SinglePartModule")
	custom.module_scene = paper_scene
	actor.module_attachments.append(custom)
	assert(actor.generate_creature())
	var paper_body: PhysicalBodyPart3D = actor.get_node("GeneratedParts/Module_paper__Attachment")
	var paper_size: Vector3 = geometry.bounds(paper_body,false).size
	assert(is_equal_approx(paper_size.x,source_size.x*generator.overall_scale))
	assert(is_equal_approx(paper_size.y,source_size.y*generator.overall_scale))
	assert(is_equal_approx(paper_size.z,generator.part_width*generator.overall_scale))
	assert(actor._capture_manual_layout())
	assert(actor.generate_creature())
	assert(geometry.bounds(actor.get_node("GeneratedParts/Module_paper__Attachment"),false).size.is_equal_approx(paper_size))
	# Broken module feet leave controller caches; their external collision behavior stays normal.
	foot = actor.get_node("GeneratedParts/Module_leg__Foot")
	foot.break_part(null)
	movement.refresh_physics_query_cache()
	assert(foot not in movement._legs)
	actor.module_attachments.clear()
	assert(actor.generate_creature())
	assert(bodies(actor).size()==base_count)
	assert(actor.get_node("GeneratedParts").find_children("Module_*","",true,false).is_empty())
	actor.queue_free()
	await process_frame
	await process_frame
	# Species-specific activation must respect an installed template's limits.
	for species: String in ["Wolf","Spider","Human","Bird","Snake"]:
		var other: Node3D = load("res://Scenes/Creatures/Characters/Generate_"+species+".tscn").instantiate()
		other.generate_on_ready = false
		root.add_child(other)
		var host_key := ""
		for body: PhysicalBodyPart3D in bodies(other):
			if PhysicalBodyPart3D.BodyPartTag.Torso in body.tags:
				host_key = str(body.get_meta(&"generated_part_key",body.name))
				break
		assert(not host_key.is_empty())
		var extra := attachment("test","SinglePartModule" if species=="Snake" else "ThreeSegmentLegModule",host_key)
		if species=="Wolf": extra.host_socket = ^"JointIn"
		other.module_attachments.append(extra)
		assert(other.generate_creature(),"Module assembly failed for "+species)
		other._activate_parts(other.get_node("GeneratedParts"))
		for joint: Node in other.get_node("GeneratedParts/Joints").get_children():
			if joint.has_meta(&"module_joint_settings"):
				assert(ASSEMBLER.joint_settings(joint)==joint.get_meta(&"module_joint_settings"),"Species rewrote module joint settings: "+species+"/"+str(joint.name))
		other.queue_free()
		await process_frame
		await process_frame
	# The ready-to-edit example also generates its two installations at runtime.
	var example: Node3D = load("res://Scenes/Creatures/Characters/Examples/Generate_ModularBeast.tscn").instantiate()
	root.add_child(example)
	await process_frame
	assert(example.has_node("GeneratedParts/Torso/Module_indicator"))
	example.queue_free()
	await process_frame
	await process_frame
	print("ValidateCreatureModules PASSED")
	quit()
