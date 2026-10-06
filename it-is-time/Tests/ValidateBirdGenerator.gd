extends SceneTree
const BIRD = preload("res://Scenes/Creatures/Generators/BirdGenerator.tscn")
const BEAST = preload("res://Scenes/Creatures/Generators/BeastGenerator.tscn")
const OLD = preload("res://Scripts/Creatures/CreatureGenerator.gd")
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
const BIRD_CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Bird.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var compatibility_scene := load("res://Scenes/Creatures/Generators/CreatureGenerator.tscn") as PackedScene
	check(compatibility_scene.get_state().get_base_scene_state()!=null,"Old generator scene must inherit BeastGenerator")
	var compatibility := compatibility_scene.instantiate()
	check(compatibility.has_method("generate_framework"),"Old scene must preserve the generator interface")
	compatibility.free()
	var bird := BIRD.instantiate()
	root.add_child(bird)
	bird.unsymmetrie = 0.0
	bird._random.seed = 417
	for count: int in [0,1,2,3,6,11]:
		bird.wing_count = count
		var plan: Dictionary = bird._create_valid_plan()
		check(not plan.is_empty(),"Bird plan must be valid")
		if plan.is_empty(): continue
		check(plan.layouts.size()==2 and plan.wings.size()==count,"Bird must have exactly two feet and the requested wings")
		for leg: Dictionary in plan.layouts:
			check(leg.role=="Leg" and leg.limb_points.size()==3 and leg.limb_block_sizes.size()==2,"Bird legs must retain Leg role with exactly two limb segments")
			check(leg.limb_points[1].x < (leg.limb_points[0].x+leg.limb_points[2].x)*0.5,"Bird leg intermediate joint must bend rearward along -X")
		for wing: Dictionary in plan.wings:
			check(wing.blocks.size()==bird.wing_segment_count,"Every wing must have the requested segments")
			var bends := 0
			for segment: int in range(1,wing.blocks.size()):
				var before: Dictionary = wing.blocks[segment-1]
				var after: Dictionary = wing.blocks[segment]
				if before.section != after.section:
					bends += 1
					check(not before.basis.y.is_equal_approx(after.basis.y),"Section boundaries must form bends")
				else:
					check(before.basis.y.is_equal_approx(after.basis.y),"Blocks within a wing section must align")
			check(bends==2 and wing.blocks[0].section=="Root" and wing.blocks[-1].section=="Tip","Each wing must have root, middle and tip with two bends")
			for point: Vector3 in wing.points:
				check(is_equal_approx(point.z,wing.points[0].z),"Wing segments must stay in the root's XY plane")
			for segment: int in range(wing.blocks.size()):
				var block: Dictionary = wing.blocks[segment]
				check(block.basis.z.is_equal_approx(Vector3.BACK),"Wing thickness must stay along Z")
				check(block.basis.y.is_equal_approx((wing.points[segment+1]-wing.points[segment]).normalized()),"Wing block must follow its segment")
			var torso: Dictionary = plan.network_torsos[wing.parent_torso_index]
			var parents: Array[Dictionary] = [torso]
			check(bird._nearest_neck_torso_distance(wing.points[0],parents)<0.00001,"Wing root must touch its Torso shell")
		for index: int in range(0,count-1,2):
			for point: int in range(plan.wings[index].points.size()):
				check(plan.wings[index].points[point].is_equal_approx(bird._mirror_point(plan.wings[index+1].points[point])),"Wings must mirror at zero asymmetry")
		if count%2==1:
			for point: Vector3 in plan.wings[-1].points: check(is_zero_approx(point.z),"Odd extra wing must remain in the center plane")
	check(not bird.get_property_list().any(func(p: Dictionary)->bool: return p.name in [&"rear_leg_count",&"foreleg_count"]),"Bird must not expose variable leg counts")
	var saved_segments: int = bird.wing_segment_count
	var saved_lengths := Vector3(bird.wing_root_length,bird.wing_middle_length,bird.wing_tip_length)
	var saved_inhomogeneity: float = bird.inhomogeneity
	bird.wing_root_length = 0.4
	bird.wing_middle_length = 0.9
	bird.wing_tip_length = 1.3
	bird.inhomogeneity = 0.0
	for count: int in range(3,7):
		bird.wing_segment_count = count
		bird.wing_count = 1
		var section_plan: Dictionary = bird._create_valid_plan()
		check(not section_plan.is_empty(),"Every supported wing subdivision must generate")
		if section_plan.is_empty(): continue
		var sections: Array[String] = []
		var measured := {"Root":0.0,"Middle":0.0,"Tip":0.0}
		for block: Dictionary in section_plan.wings[0].blocks:
			if not sections.has(block.section): sections.append(block.section)
			measured[block.section] += block.size.y
		check(sections==["Root","Middle","Tip"],"Subdivision must preserve all three ordered wing sections")
		check(is_equal_approx(measured.Root,0.4) and is_equal_approx(measured.Middle,0.9) and is_equal_approx(measured.Tip,1.3),"Independent section lengths must remain exact for every subdivision")
	bird.wing_segment_count = saved_segments
	bird.wing_root_length = saved_lengths.x
	bird.wing_middle_length = saved_lengths.y
	bird.wing_tip_length = saved_lengths.z
	bird.inhomogeneity = saved_inhomogeneity
	bird.wing_count = 5
	check(bird._get_defaults_path()=="res://Resources/Generators/BirdGeneratorDefaults.tres","Bird must use an independent defaults resource")
	var defaults: Dictionary = bird._capture_default_parameters()
	check(defaults.wing_count==5 and defaults.has("body_length") and not defaults.has("rear_leg_count"),"Bird snapshot must include shared and bird-only settings")
	bird.unsymmetrie = 100.0
	var asymmetric: Dictionary = bird._create_valid_plan()
	check(not asymmetric.is_empty() and not asymmetric.wings[0].points[-1].is_equal_approx(bird._mirror_point(asymmetric.wings[1].points[-1])),"Wing asymmetry must respond to Unsymmetrie")
	for wing: Dictionary in asymmetric.get("wings",[]):
		for point: Vector3 in wing.points:
			check(is_equal_approx(point.z,wing.points[0].z),"Asymmetric wings must also stay in XY planes")
	for leg: Dictionary in asymmetric.get("layouts",[]):
		check(leg.limb_points.size()==3 and leg.limb_points[1].x < (leg.limb_points[0].x+leg.limb_points[2].x)*0.5,"Asymmetric bird legs must retain two rearward-bending segments")
	bird.wing_count = -1
	check(bird._create_valid_plan().is_empty(),"Invalid wing count must fail rather than silently changing the requested count")
	bird.wing_count = 2
	var old := OLD.new()
	var beast := BEAST.instantiate()
	root.add_child(old)
	root.add_child(beast)
	old._random.seed = 42
	beast._random.seed = 42
	check(var_to_str(old._create_valid_plan())==var_to_str(beast._create_valid_plan()),"Compatibility entry point must preserve Beast output")
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	actor.generator_path = ^"BirdGenerator"
	var previous := actor.get_node("CreatureGenerator")
	actor.remove_child(previous)
	previous.free()
	var attached := BIRD.instantiate()
	attached.name = "BirdGenerator"
	attached.wing_count = 3
	attached.unsymmetrie = 0.0
	actor.add_child(attached)
	root.add_child(actor)
	check(actor.generate_creature(),"Generated character must accept a BirdGenerator via Generator Path")
	var feet := 0
	var wings := 0
	var limbs := 0
	var leg_limbs := 0
	for part: Node in actor.find_children("*","RigidBody3D",true,false):
		if 1 in part.tags: feet += 1
		if 7 in part.tags: wings += 1
		if 8 in part.tags: limbs += 1
		if 5 in part.tags: leg_limbs += 1
		if 7 in part.tags or 8 in part.tags: check(1 not in part.tags and 4 not in part.tags and 5 not in part.tags,"Wings must not be recognized as walking legs")
	check(feet==2 and wings==3*attached.wing_segment_count and limbs==3*(attached.wing_segment_count-1),"Every wing block must carry Wing, with WingLimb retained on intermediate blocks")
	check(leg_limbs==4,"Physical bird legs must have two LegLimb bodies per foot")
	var movement := actor.get_node("GeneratedLegStepMovementController3D")
	check(movement.get_leg_parts().size()==2 and movement._chains.size()==2,"Walking controller must only discover the two bird legs")
	check(attached.get_node("Wings").scale.is_equal_approx(Vector3.ONE*attached.overall_scale),"Wing preview must apply Overall Scale once")
	for mesh: Node in attached.get_node("Wings").get_children():
		if mesh is MeshInstance3D:
			check(mesh.basis.z.is_equal_approx(Vector3.BACK),"Rendered wing blocks must retain the XY orientation")
	check(attached.generate_framework() and attached.get_node("Wings").scale.is_equal_approx(Vector3.ONE*attached.overall_scale),"Repeated generation must replace wing preview without accumulating scale")
	var bird_actor := BIRD_CHARACTER.instantiate()
	bird_actor.density_data = preload("res://Scripts/Creatures/GeneratedCreatureDensityData.gd").new()
	bird_actor.density_data.sub_torso = 2.0
	bird_actor.density_data.wing_root = 3.0
	bird_actor.density_data.wing_middle = 4.0
	bird_actor.density_data.wing_tip = 5.0
	check(bird_actor.name==&"Generate_Bird" and bird_actor.generator_path==^"BirdGenerator","Bird character must use its own named generator")
	check(BIRD_CHARACTER.get_state().get_base_scene_state()!=null,"Bird character must inherit SampleCharacter")
	root.add_child(bird_actor)
	# The saved scene must auto-generate via its normal runtime initialization.
	await process_frame
	await process_frame
	check(bird_actor.get_node("GeneratedParts").get_child_count()>0,"Bird character must generate physical parts on startup")
	var generated_types := {}
	for part: Node in bird_actor.get_node("GeneratedParts").get_children():
		if not part is PhysicalBodyPart3D: continue
		var part_type: String = part.get_meta("generated_part_type")
		generated_types[part_type] = true
		var size: Vector3 = part.get_meta("generated_size")
		var density: float = bird_actor.density_data.get_density(part_type, bird_actor.mass_density)
		var mass_floor: float = bird_actor.minimum_feather_mass if part_type == "Feather" else bird_actor.minimum_part_mass
		check(is_equal_approx(part.mass, clampf(size.x*size.y*size.z*density,mass_floor,bird_actor.maximum_part_mass)),"Actual generated geometry must use its typed density and scaled volume")
	for part_type: String in ["SubTorso", "WingRoot", "WingMiddle", "WingTip"]:
		check(generated_types.has(part_type),"Bird blueprint must preserve the explicit generated type: "+part_type)
	var bird_movement := bird_actor.get_node("GeneratedLegStepMovementController3D")
	check(bird_movement.get_leg_parts().size()==2,"Bird character must discover only its two legs")
	check(bird_actor.has_node("CreatureRecoveryStateMachine3D") and bird_actor.has_node("CreatureActionController3D"),"Bird character must preserve recovery and action components")
	check(bird_movement.slow_gait_data==actor.get_node("GeneratedLegStepMovementController3D").slow_gait_data,"Bird and beast must share the configured gait resource")
	# Exercise regeneration with an active runtime action before physics can change its phase.
	var action := bird_actor.get_node("CreatureActionController3D")
	action._data = action.actions[0]
	action._movement = bird_movement
	action.phase = action.Phase.RISING
	action._feet.append({"body":bird_actor.get_node("GeneratedParts").get_child(0)})
	check(bird_actor.generate_creature(),"Runtime regeneration during an action must succeed")
	check(not action.is_active() and action._feet.is_empty() and action._reason==&"regenerated","Runtime regeneration must still cancel actions and release old part references")
	print("BIRD_GENERATOR_", "FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
