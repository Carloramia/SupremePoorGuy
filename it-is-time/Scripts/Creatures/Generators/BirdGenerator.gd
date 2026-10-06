@tool
extends "res://Scripts/Creatures/Generators/BaseCreatureGenerator.gd"

const FEATHER_GEOMETRY = preload("res://Scripts/Creatures/Generators/BirdFeatherGeometry.gd")

func _init() -> void:
	_apply_default_preset()

func _get_defaults_path() -> String:
	return "res://Resources/Generators/BirdGeneratorDefaults.tres"

@export_group("Bird Legs")
## Fixed count, deliberately not exported as an editable setting.
const LEG_COUNT: int = 2

@export_group("Wing Generation")
## Total wings, not pairs. An odd extra wing lies in the center XY plane.
@export_range(0,32,1,"or_greater") var wing_count: int = 2
## Total blocks distributed over Root, Middle and Tip; each section has at least one.
@export_range(3,6,1) var wing_segment_count: int = 6
## Independent section lengths before Overall Scale and Inhomogeneity variation.
@export_range(0.01,100.0,0.01,"or_greater") var wing_root_length: float = 2.0
@export_range(0.01,100.0,0.01,"or_greater") var wing_middle_length: float = 2.5
@export_range(0.01,100.0,0.01,"or_greater") var wing_tip_length: float = 3.0
@export_range(0.01,10.0,0.01,"or_greater") var wing_chord: float = 0.6
@export_range(0.01,10.0,0.01,"or_greater") var wing_thickness: float = 0.08
@export_range(0.0,1.0,0.01) var wing_root_height: float = 0.75
## Root-to-middle bend within XY. The tip bends back in the opposite direction.
@export_range(0.0,180.0,1.0) var wing_fold_degrees: float = 170.0
@export_range(0.0,180.0,1.0) var wing_tip_fold_degrees: float = 160.0
@export_range(0.0,75.0,1.0) var wing_elevation_degrees: float = 10.0

@export_group("Feather Generation")
@export var feathers_enabled: bool = true
## Distance between feather roots along each wing block, before Overall Scale.
@export_range(0.05, 5.0, 0.01, "or_greater") var feather_spacing: float = 0.3
@export_range(0.01, 10.0, 0.01, "or_greater") var feather_length: float = 1.5
@export_range(0.1, 3.0, 0.01, "or_greater") var feather_tip_length_multiplier: float = 1.5
@export_range(0.01, 5.0, 0.01, "or_greater") var feather_width: float = 0.28
@export_range(0.001, 1.0, 0.001, "or_greater") var feather_thickness: float = 0.025
## Lean toward the wing tip. Feathers grow from the local -X edge within the wing's XY plane.
@export_range(-60.0, 60.0, 1.0) var feather_lean_degrees: float = 15.0
@export var feather_color: Color = Color(0.9, 0.92, 0.96)

@export_group("Feather Spread")
## Small fan angle across the whole wing, before the special tip alignment.
@export_range(0.0, 30.0, 0.1) var feather_spread_degrees: float = 6.0
@export var feather_tip_alignment_enabled: bool = true
## Higher values concentrate alignment near the outermost tip feather.
@export_range(1.0, 8.0, 0.1) var feather_tip_alignment_falloff: float = 2.0

func _validate_species_settings() -> bool:
	if feathers_enabled:
		for value: float in [feather_spacing,feather_length,feather_tip_length_multiplier,feather_width,feather_thickness]:
			if not is_finite(value) or value <= 0.0: return false
		if not is_finite(feather_lean_degrees) or absf(feather_lean_degrees)>60.0: return false
		if not is_finite(feather_spread_degrees) or feather_spread_degrees < 0.0 or feather_spread_degrees > 30.0: return false
		if not is_finite(feather_tip_alignment_falloff) or feather_tip_alignment_falloff < 1.0 or feather_tip_alignment_falloff > 8.0: return false
	return wing_count >= 0 and wing_segment_count >= 3 and wing_segment_count <= 6 and wing_root_length >= 0.01 and wing_middle_length >= 0.01 and wing_tip_length >= 0.01 and wing_chord >= 0.01 and wing_thickness >= 0.01

func _plan_feathers(block_size: Vector3, progress: float) -> Array[Dictionary]:
	var feathers: Array[Dictionary] = []
	if not feathers_enabled: return feathers
	# Bound visual node count for unusually long wings or small spacing.
	var count := clampi(ceili(block_size.y/feather_spacing), 1, 128)
	var length := feather_length*lerpf(1.0,feather_tip_length_multiplier,progress)
	var basis := Basis(Vector3.BACK, deg_to_rad(90.0-feather_lean_degrees))
	for index: int in range(count):
		var root := Vector3(-block_size.x*0.5, -block_size.y*0.5+block_size.y*(index+0.5)/count, 0.0)
		feathers.append({"size": Vector3(feather_width,length,feather_thickness), "transform": Transform3D(basis,root), "color": feather_color})
	return feathers

func _arrange_feather_edge(blocks: Array[Dictionary]) -> void:
	# Work in the unfolded wing plane: all block +Y axes align in this pose.
	var entries: Array[Dictionary] = []
	var offset := 0.0
	var tip_start := 0.0
	var tip_found := false
	for block: Dictionary in blocks:
		if block.section == "Tip" and not tip_found:
			tip_start = offset
			tip_found = true
		for feather: Dictionary in block.feathers:
			var root: Vector3 = feather.transform.origin + Vector3(0.0, offset + block.size.y*0.5, 0.0)
			entries.append({"feather":feather,"root":root})
		offset += block.size.y
	if entries.is_empty(): return
	var first: Vector3 = entries[0].root
	var last: Vector3 = entries[-1].root
	# A dense smooth edge is sampled by arc length, not separately per block.
	# Feather lengths are adjusted together with angles so endpoints really lie on it.
	var edge := PackedVector3Array()
	var distances := PackedFloat32Array([0.0])
	for index: int in range(257):
		var t := float(index)/256.0
		var root := first.lerp(last,t)
		var angle := deg_to_rad(90.0-feather_lean_degrees + feather_spread_degrees*(t-0.5))
		if feather_tip_alignment_enabled and tip_found:
			var influence := pow(clampf((root.y-tip_start)/maxf(last.y-tip_start,0.00001),0.0,1.0),feather_tip_alignment_falloff)
			angle = lerpf(angle,0.0,influence)
		var length := feather_length*lerpf(1.0,feather_tip_length_multiplier,t)
		var point := root + Basis(Vector3.BACK,angle).y*length
		if not edge.is_empty(): distances.append(distances[-1]+point.distance_to(edge[-1]))
		edge.append(point)
	var cursor := 1
	for index: int in range(entries.size()):
		var distance := distances[-1]*float(index)/maxi(entries.size()-1,1)
		while cursor < distances.size()-1 and distances[cursor]<distance: cursor += 1
		var blend := (distance-distances[cursor-1])/maxf(distances[cursor]-distances[cursor-1],0.00001)
		var target := edge[cursor-1].lerp(edge[cursor],blend)
		var direction: Vector3 = target-entries[index].root
		var feather: Dictionary = entries[index].feather
		var transform: Transform3D = feather.transform
		transform.basis = Basis(Vector3.BACK,atan2(-direction.x,direction.y))
		feather.transform = transform
		feather.size.y = maxf(direction.length(),0.001)
		feather["spread_endpoint"] = target

func _append_species_feet(layouts: Array[Dictionary], width: float) -> void:
	_append_foot_group(layouts,LEG_COUNT,"Leg",-1.0,width)

func _create_limb_points(_role: String, foot_height: float, total_length: float) -> PackedVector3Array:
	# Reuse the two-segment rearward bend, while keeping the bird feet tagged Leg.
	# The intermediate joint lies behind the foot-to-root line along -X.
	return super._create_limb_points("ForeLeg",foot_height,total_length)

func _complete_species_plan(plan: Dictionary) -> Dictionary:
	var wings: Array[Dictionary] = []
	var section_lengths := Vector3(wing_root_length,wing_middle_length,wing_tip_length)
	var rows := ceili(float(wing_count)/2.0)
	for row: int in range(rows):
		var requested_x := lerpf(-body_length*0.35,body_length*0.35,float(row)/maxi(rows-1,1)) if rows>1 else 0.0
		var parent := 0
		var best := INF
		for index: int in range(plan.network_torsos.size()):
			var distance: float = absf(plan.network_torsos[index].position.x-requested_x)
			if distance < best: best = distance; parent = index
		var torso: Dictionary = plan.network_torsos[parent]
		var paired := row*2+1<wing_count
		var pair_scale := 1.0+_random.randf_range(-0.25,0.25)*clampf(inhomogeneity/100.0,0.0,1.0)
		for member: int in range(2 if paired else 1):
			var side := (1.0 if member==0 else -1.0) if paired else 0.0
			var length_scale := pair_scale
			if member==1: length_scale = lerpf(pair_scale,1.0+_random.randf_range(-0.25,0.25)*clampf(inhomogeneity/100.0,0.0,1.0),_asymmetry())
			var x: float = clampf(requested_x+_random.randf_range(-1.0,1.0)*_asymmetry()*torso.size.x*0.2,torso.position.x-torso.size.x*0.45,torso.position.x+torso.size.x*0.45)
			var height := clampf(wing_root_height+_random.randf_range(-0.1,0.1)*_asymmetry(),0.0,1.0)
			var root := Vector3(x,torso.position.y+torso.size.y*(height-0.5),side*torso.size.z*0.5)
			if not paired: root.y = torso.position.y+torso.size.y*0.5
			var points := PackedVector3Array([root])
			var blocks: Array[Dictionary] = []
			for segment: int in range(wing_segment_count):
				var section := mini(floori(float(segment)*3.0/wing_segment_count),2)
				var angle := deg_to_rad(wing_elevation_degrees)
				if section >= 1: angle += deg_to_rad(wing_fold_degrees)
				if section == 2: angle -= deg_to_rad(wing_tip_fold_degrees)
				var direction := Vector3(-cos(angle),sin(angle),0.0)
				# Subdivision changes block count, never the requested section length.
				var section_blocks := ceili(float((section+1)*wing_segment_count)/3.0)-ceili(float(section*wing_segment_count)/3.0)
				var end := points[-1]+direction*(section_lengths[section]*length_scale/section_blocks)
				# Local Y follows the segment; local Z remains the wing thickness axis.
				var basis := Basis(Vector3.BACK,atan2(-direction.x,direction.y))
				blocks.append({"section":["Root","Middle","Tip"][section],"position":(points[-1]+end)*0.5,"basis":basis,"size":Vector3(wing_chord*(1.0-0.35*float(segment)/wing_segment_count),points[-1].distance_to(end),wing_thickness)})
				blocks[-1]["feathers"] = _plan_feathers(blocks[-1].size, float(segment)/maxi(wing_segment_count-1,1))
				points.append(end)
			_arrange_feather_edge(blocks)
			wings.append({"parent_torso_index":parent,"points":points,"blocks":blocks,"side":side})
	plan["wings"] = wings
	plan["generator_type"] = "bird"
	return plan

func _generate_species_preview(plan: Dictionary, scene_owner: Node, material: Material) -> void:
	var previous := get_node_or_null("Wings")
	if previous != null:
		remove_child(previous)
		previous.queue_free()
	var container := Node3D.new()
	container.name = "Wings"
	container.set_meta(&"generated_wings",true)
	add_child(container)
	container.owner = scene_owner
	for index: int in range(plan.wings.size()):
		var wing: Dictionary = plan.wings[index]
		for segment: int in range(wing.blocks.size()):
			var block: Dictionary = wing.blocks[segment]
			var mesh := MeshInstance3D.new()
			mesh.name = "Wing_%d_%s_%d" % [index+1,block.section,segment+1]
			mesh.mesh = _create_wireframe(block.size)
			mesh.material_override = material
			mesh.transform = Transform3D(block.basis,block.position)
			container.add_child(mesh)
			mesh.owner = scene_owner
			var folded_feathers: Array = block.get("feathers",[]).duplicate(true)
			for feather: Dictionary in folded_feathers:
				var transform: Transform3D = feather.transform
				transform.basis = Basis(block.basis).inverse()*Basis(Vector3.BACK,PI*0.5)
				feather.transform = transform
			FEATHER_GEOMETRY.add_feathers(mesh,folded_feathers,scene_owner,material)
		var label := Label3D.new()
		label.text = "Wing_%d" % [index+1]
		label.font_size = label_font_size
		label.pixel_size = 0.01
		label.modulate = label_color
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = wing.points[-1]+Vector3.UP*0.2
		container.add_child(label)
		label.owner = scene_owner
