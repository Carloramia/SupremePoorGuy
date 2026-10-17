extends SceneTree

const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const REPORT := "D:/GameJamWorkspace/Reports/Rats_2026-10-17/"
var failed := false
var checks := 0
var events: Array[Dictionary] = []
var hits: Array[Dictionary] = []
var snapshots: Array[Dictionary] = []
var clock := 0.0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error("RATS_CHECK: "+message)

func on_attack(module: StringName, event: StringName, details: Dictionary, actor: Node) -> void:
	events.append({"time":clock,"actor":str(actor.name),"module":str(module),"event":str(event),"details":details})

func on_damage(amount: float, hp: float, _source: Node, part: Node) -> void:
	hits.append({"time":clock,"part":str(part.get_path()),"damage":amount,"hp":hp})

func run() -> void:
	DirAccess.make_dir_recursive_absolute(REPORT)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Rats/Metadata/model_manifest.json"))
	check(manifest.models.size()==55,"55 complete resource chains")
	for record: Dictionary in manifest.models:
		check(FileAccess.get_sha256(record.source)==record.source_sha256,"Texture source hash: "+record.key)
		var scene := load(record.physical_scene) as PackedScene
		check(scene!=null,"Physical scene loads: "+record.key)
		if scene==null: continue
		var part := scene.instantiate() as PhysicalBodyPart3D
		part.prepare_generated_geometry()
		check(part!=null and part.paper_volume_enabled and part.geometry_mode==part.GeometryMode.CUSTOM_MODEL,"Paper PhysicalPart inherits base")
		var bounds:=GEOMETRY.bounds(part,false)
		check(bounds.size.is_finite() and bounds.size.x>0 and bounds.size.y>0,"Finite convex geometry")
		check(is_equal_approx(GEOMETRY.bounds(part).size.z,bounds.size.z*2.0),"Collision depth is twice visual thickness")
		part.free()
	for variant: int in [1,2]:
		var actor = load("res://Scenes/Creatures/Characters/Generate_Rat_%d.tscn" % variant).instantiate()
		actor.generate_on_ready = false
		var saved_upper: Dictionary={}
		if variant==1:
			for side: int in [1,2]:
				var key:="Leg_%d_Limb_3" % side
				var saved: Node3D=actor.get_node_or_null("GeneratedParts/"+key)
				check(saved!=null,"New upper limb is saved for editor viewing")
				if saved!=null: saved_upper[key]=saved.transform
		root.add_child(actor)
		check(actor.get_children().filter(func(child: Node)->bool: return child.has_method("get_input_movement_direction")).size()==1,"Exactly one movement controller")
		check(actor.generate_creature(),"Generator builds variant "+str(variant))
		if failed: actor.free(); quit(1); return
		var container: Node = actor.get_node("GeneratedParts")
		var initial: Dictionary = {}
		var low:=INF
		var high:=-INF
		var legs:=0
		var limbs:=0
		var tails:=0
		for body: Node in container.get_children():
			if not body is PhysicalBodyPart3D: continue
			initial[str(body.name)]=body.transform
			var bounds: AABB=body.transform*GEOMETRY.bounds(body,false)
			if str(body.name) in ["Torso","Head","LowerJaw"]:
				low=minf(low,bounds.position.x); high=maxf(high,bounds.end.x)
			if 1 in body.tags or 4 in body.tags: legs+=1
			if 5 in body.tags: limbs+=1
			if 10 in body.tags: tails+=1
			check(body.scale.is_equal_approx(Vector3.ONE),"Unit-scale physical root")
			check(is_equal_approx(GEOMETRY.bounds(body,false).size.z,.08),"Uniform generated visual thickness")
			check((body.get_collision_exceptions().size()>=container.get_child_count()-2),"All internal body collisions ignored")
		check(legs==4 and limbs==(10 if variant==1 else 8),"Rat 1 has three hind links; Rat 2 retains two")
		if variant==1:
			var generator: Node=actor.get_node("RatsGenerator")
			for side: int in [1,2]:
				var prefix:="Leg_%d_Limb_" % side
				check(container.has_node(prefix+"3"),"Extra proximal hind limb exists")
				check(saved_upper.has(prefix+"3") and saved_upper[prefix+"3"].is_equal_approx(container.get_node(prefix+"3").transform),"Saved upper limb pose matches regeneration")
				var source: Resource=generator.get_part_scene_rule("LegLimb",prefix+"2",prefix+"2")
				var added: Resource=generator.get_part_scene_rule("LegLimb",prefix+"3",prefix+"3")
				check(added.part_scene==source.part_scene,"New upper limb uses its own Limb_2 scene")
				var links: Dictionary={}
				for joint: Node in container.get_node("Joints").get_children():
					var a: Node=joint.get_node(joint.node_a)
					var b: Node=joint.get_node(joint.node_b)
					links[str(a.name)+"/"+str(b.name)]=true
				check(links.has("SubTorso_Leg_%d/" % side+prefix+"3"),"Hip connects to new Limb_3")
				check(links.has(prefix+"2/"+prefix+"3") and links.has(prefix+"1/"+prefix+"2"),"Three-link hind chain is connected in order")
		check(tails==(8 if variant==1 else 7),"Segmented tail count")
		check(absf(high-low-5.329299545288)<0.02,"Body length is 30 percent of measured Wolf")
		for joint: Node in container.get_node("Joints").get_children():
			check(joint is Generic6DOFJoint3D,"Physical joint exists")
			var a: Node3D=joint.get_node(joint.node_a)
			var b: Node3D=joint.get_node(joint.node_b)
			var frame_a: Transform3D=joint.get_meta("generated_joint_frame_a")
			var frame_b: Transform3D=joint.get_meta("generated_joint_frame_b")
			check((a.transform*frame_a).origin.distance_to((b.transform*frame_b).origin)<0.0001,"Joint anchors agree at generation")
		check(actor.generate_creature(),"Repeated generation succeeds")
		for body: Node in actor.get_node("GeneratedParts").get_children():
			if body is PhysicalBodyPart3D: check(initial[str(body.name)].is_equal_approx(body.transform),"Repeated layout is deterministic")
		check(actor.get_node("WolfAttackController3D").get_script().resource_path=="res://Scripts/Creatures/RatBiteAttackController3D.gd","Independent static-point Rat bite; no Wolf attack modules")
		actor.free()
		await process_frame
	if failed: quit(1); return
	var world: Node3D=load("res://Scenes/Levels/RatsTestLevel.tscn").instantiate()
	root.add_child(world)
	current_scene=world
	await physics_frame
	await physics_frame
	var actors: Array = [world.get_node("GenerateRat1NPC"),world.get_node("GenerateRat2NPC")]
	for actor: Node in actors:
		actor.get_node("WolfAttackController3D").module_event.connect(on_attack.bind(actor))
		for part: Node in actor.get_node("GeneratedParts").get_children():
			if part is PhysicalBodyPart3D: part.damaged.connect(on_damage.bind(part))
	if "--capture" in OS.get_cmdline_user_args():
		for actor: Node in actors:
			actor.process_mode=Node.PROCESS_MODE_DISABLED
			for part: Node in actor.get_node("GeneratedParts").get_children():
				if part is RigidBody3D: part.freeze=true
		await process_frame
		await RenderingServer.frame_post_draw
		check(root.get_texture().get_image().save_png(REPORT+"RatsTestLevel.png")==OK,"Rendered scene saved")
	else:
		for tick: int in 1800:
			await physics_frame
			clock=float(tick)/60.0
			if tick%60!=0: continue
			for actor: Node in actors:
				var torso: PhysicalBodyPart3D=actor.get_node("GeneratedParts/Torso")
				check(torso.global_position.is_finite() and torso.linear_velocity.is_finite(),"Physics remains finite")
				var movement: Node=actor.get_node("GeneratedLegStepMovementController3D")
				var ai: Node=actor.get_node("NPCStateMachine3D")
				var feet: Array[Dictionary]=[]
				for foot: RigidBody3D in movement.get_leg_parts():
					feet.append({"foot":str(foot.name),"step":movement.get_leg_step_diagnostics(foot),"support":movement.get_support_foot_diagnostics(foot)})
				snapshots.append({"time":clock,"actor":str(actor.name),"position":torso.global_position,"velocity":torso.linear_velocity,
					"state":ai.get_state_diagnostics(),"ranges":ai.get_attack_range_diagnostics(),"execution":movement.get_npc_motion_execution_diagnostics(),"feet":feet,"gait":movement.get_stance_support_diagnostics()})
		var started:=events.filter(func(row: Dictionary)->bool: return row.event=="started").size()
		print("RATS_RUNTIME attacks_started=",started," damage_events=",hits.size())
		check(started>0,"NPCs attempt bite attacks")
		check(not hits.is_empty(),"Bite deals damage through the global damage service")
	var report:=FileAccess.open(REPORT+("capture_validation.json" if "--capture" in OS.get_cmdline_user_args() else "validation.json"),FileAccess.WRITE)
	report.store_string(JSON.stringify({"passed":not failed,"checks":checks,"events":events,"hits":hits,"snapshots":snapshots},"\t"))
	report.close()
	world.free()
	await process_frame
	print("RATS_VALIDATION_","FAILED" if failed else "PASSED"," checks=",checks)
	quit(1 if failed else 0)
