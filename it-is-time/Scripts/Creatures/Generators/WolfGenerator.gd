@tool
extends "res://Scripts/Creatures/Generators/BeastGenerator.gd"

const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
@export_group("Wolf Layout")
@export_range(0.02, 4.0, 0.01) var leg_pair_width: float = 0.16
@export_range(0.05, 0.45, 0.01) var hip_x_ratio: float = 0.27
@export_range(0.4, 0.95, 0.01) var standing_extension_ratio: float = 0.65
@export_range(0.1, 2.0, 0.01) var rear_middle_size_scale: float = 0.5
@export var fore_foot_forward_ratios: Vector2 = Vector2(0.05, 0.38)
@export var rear_foot_forward_ratios: Vector2 = Vector2(-0.48, 0.02)
@export_range(-45.0, 45.0, 1.0) var torso_pitch_degrees: float = 4.0
@export_range(-60.0, 60.0, 1.0) var head_pitch_degrees: float = -18.0
@export_range(-60.0, 60.0, 1.0) var tail_pitch_degrees: float = 12.0
@export_range(-2.0, 2.0, 0.01) var torso_height_offset: float = 0.15
@export var tail_enabled: bool = true
@export var jaw_enabled: bool = true
@export var head_attachment_offset: Vector3 = Vector3.ZERO
@export var jaw_attachment_offset: Vector3 = Vector3.ZERO
@export var tail_attachment_offset: Vector3 = Vector3.ZERO
@export_group("Wolf Part Scenes")
@export var torso_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/Wolf/Torso/TorsoMain.tscn")
@export var support_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/Wolf/Decorations/JointRivet.tscn")
@export var head_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/Wolf/Head/HeadSkull.tscn")
@export var jaw_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/Wolf/Head/LowerJaw.tscn")
@export var tail_scene: PackedScene = preload("res://Scenes/Creatures/Bodyparts/Wolf/Tail/TailMain.tscn")
@export var fore_upper_scenes: Array[PackedScene] = [preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Fore_1/UpperLeg.tscn"), preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Fore_2/UpperLeg.tscn")]
@export var fore_lower_scenes: Array[PackedScene] = [preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Fore_1/LowerLeg.tscn"), preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Fore_2/LowerLeg.tscn")]
@export var fore_foot_scenes: Array[PackedScene] = [preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Fore_1/Foot.tscn"), preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Fore_2/Foot.tscn")]
@export var rear_upper_scenes: Array[PackedScene] = [preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Hind_1/UpperLeg.tscn"), preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Hind_2/UpperLeg.tscn")]
@export var rear_middle_scenes: Array[PackedScene] = [preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Hind_2/Wolf2UpperLeg.tscn"), preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Hind_1/Wolf2UpperLeg.tscn")]
@export var rear_lower_scenes: Array[PackedScene] = [preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Hind_1/LowerLeg.tscn"), preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Hind_2/LowerLeg.tscn")]
@export var rear_foot_scenes: Array[PackedScene] = [preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Hind_1/Foot.tscn"), preload("res://Scenes/Creatures/Bodyparts/Wolf/Legs/Hind_2/Foot.tscn")]

func _get_defaults_path() -> String:
	return "res://Resources/Generators/WolfGeneratorDefaults.tres"

func get_part_scene_rule(part_type: String, part_name: String, part_key: String = "") -> PART_SCENE_RULE:
	var authored := super.get_part_scene_rule(part_type, part_name, part_key)
	if authored != null: return authored
	var scene: PackedScene
	if part_type == "SubTorso": scene = support_scene
	elif part_name == "Torso": scene = torso_scene
	elif part_name == "Head": scene = head_scene
	elif part_name == "LowerJaw": scene = jaw_scene
	elif part_name == "Tail": scene = tail_scene
	elif part_name.begins_with("ForeLeg_") or part_name.begins_with("Leg_"):
		var fore := part_name.begins_with("ForeLeg_")
		var choices: Array[PackedScene]
		if part_name.ends_with("_Limb_3"): choices = rear_upper_scenes
		elif part_name.ends_with("_Limb_2"): choices = fore_upper_scenes if fore else rear_middle_scenes
		elif part_name.ends_with("_Limb_1"): choices = fore_lower_scenes if fore else rear_lower_scenes
		else: choices = fore_foot_scenes if fore else rear_foot_scenes
		if choices.is_empty(): return null
		scene = choices[(part_name.get_slice("_", 1).to_int()-1) % choices.size()]
	if scene == null: return null
	var rule := PART_SCENE_RULE.new()
	rule.part_key = part_key if not part_key.is_empty() else part_name
	rule.part_type = part_type
	rule.part_scene = scene
	rule.size_mode = PART_SCENE_RULE.SizeMode.FIT_UNIFORM
	return rule

func _part(node_name: String, role: String, subtype: String = "", xy_multiplier: float = 1.0) -> Dictionary:
	var type := subtype if not subtype.is_empty() else ("LegLimb" if role == "Limb" else role)
	var rule := get_part_scene_rule(type, node_name, node_name)
	if rule == null: return {}
	var part := rule.part_scene.instantiate() as PhysicalBodyPart3D
	if part == null: return {}
	part.prepare_generated_geometry()
	var target := GEOMETRY.bounds(part, false).size
	target *= Vector3(xy_multiplier,xy_multiplier,1.0)
	var actual := GEOMETRY.fit(part, target, rule, role, part_width)
	var inlet := part.get_node_or_null("JointIn") as Marker3D
	var outlet := part.get_node_or_null("JointOut") as Marker3D
	if actual.size == Vector3.ZERO or inlet == null or outlet == null:
		part.free()
		return {}
	# Physical scenes orient the art internally; body +X remains the controller's forward.
	var result := {"name":node_name, "part_key":node_name, "role":role, "size":actual.size, "segment_id":0,
		"transform":Transform3D.IDENTITY, "_in":inlet.position, "_out":outlet.position, "_bounds":actual}
	if subtype == "SubTorso": result["sub_torso"] = true
	part.free()
	return result

func _place(layout: Dictionary, anchor: Vector3) -> void:
	layout.transform.origin = anchor - layout.transform.basis * Vector3(layout._in)

func _port(layout: Dictionary, outlet: bool = false) -> Vector3:
	return layout.transform * Vector3(layout._out if outlet else layout._in)

func _edge(edges: Array[Dictionary], a: int, b: int, anchor: Vector3, kind: String) -> void:
	edges.append({"a":a, "b":b, "anchor":anchor, "basis":Basis.IDENTITY, "kind":kind})

func _build_wolf_blueprint() -> Dictionary:
	if rear_leg_count < 1 or foreleg_count < 1 or rear_leg_count > 10 or foreleg_count > 10: return {}
	for value: float in [part_width, leg_pair_width]:
		if not is_finite(value) or value <= 0.0: return {}
	if not is_finite(standing_extension_ratio) or standing_extension_ratio <= 0.0 or standing_extension_ratio >= 1.0: return {}
	if not is_finite(rear_middle_size_scale) or rear_middle_size_scale <= 0.0: return {}
	if not fore_foot_forward_ratios.is_finite() or not rear_foot_forward_ratios.is_finite(): return {}
	for degrees: float in [torso_pitch_degrees,head_pitch_degrees,tail_pitch_degrees]:
		if not is_finite(degrees): return {}
	if not is_finite(hip_x_ratio) or not is_finite(torso_height_offset): return {}
	for offset: Vector3 in [head_attachment_offset, jaw_attachment_offset, tail_attachment_offset]:
		if not offset.is_finite(): return {}
	var torso := _part("Torso", "Torso")
	if torso.is_empty(): return {}
	var parts: Array[Dictionary] = [torso]
	var edges: Array[Dictionary] = []
	var chains: Array[Dictionary] = []
	var hip_height := INF
	for fore: bool in [false, true]:
		var count := foreleg_count if fore else rear_leg_count
		for index: int in count:
			var prefix := ("ForeLeg_" if fore else "Leg_") + str(index+1)
			var upper := _part(prefix+("_Limb_2" if fore else "_Limb_3"), "Limb")
			var middle: Dictionary = {} if fore else _part(prefix+"_Limb_2", "Limb", "", rear_middle_size_scale)
			var lower := _part(prefix+"_Limb_1", "Limb")
			var foot := _part(prefix, "ForeLeg" if fore else "Leg")
			var support := _part("SubTorso_"+prefix, "Torso", "SubTorso")
			if upper.is_empty() or lower.is_empty() or foot.is_empty() or support.is_empty(): return {}
			if not fore and middle.is_empty(): return {}
			var l1: float = Vector3(upper._out-upper._in).length()
			if not fore:
				var middle_length: float = Vector3(middle._out-middle._in).length()
				if middle_length < 0.01: return {}
				l1 += middle_length
			var l2: float = Vector3(lower._out-lower._in).length()
			if minf(l1,l2) < 0.01: return {}
			var foot_box: AABB = Transform3D(foot.transform.basis,Vector3.ZERO) * AABB(foot._bounds)
			var ankle_y: float = (foot.transform.basis * Vector3(foot._in)).y - foot_box.position.y
			hip_height = minf(hip_height, ankle_y+(l1+l2)*standing_extension_ratio)
			chains.append({"fore":fore,"index":index,"count":count,"upper":upper,"middle":middle,"lower":lower,"foot":foot,"support":support,"l1":l1,"l2":l2,"ankle_y":ankle_y})
	for chain: Dictionary in chains:
		var upper: Dictionary = chain.upper
		var lower: Dictionary = chain.lower
		var foot: Dictionary = chain.foot
		var support: Dictionary = chain.support
		var x: float = torso.size.x * hip_x_ratio * (1.0 if chain.fore else -1.0)
		var z := 0.0 if chain.count == 1 else lerpf(-leg_pair_width*.5,leg_pair_width*.5,float(chain.index)/float(chain.count-1))
		var hip := Vector3(x,hip_height,z)
		var offsets := fore_foot_forward_ratios if chain.fore else rear_foot_forward_ratios
		var forward: float = offsets[chain.index % 2]*(float(chain.l1)+float(chain.l2))
		var ankle := Vector3(x+forward,chain.ankle_y,z)
		var d := Vector2(ankle.x-hip.x,ankle.y-hip.y)
		var l1: float = chain.l1
		var l2: float = chain.l2
		var middle: Dictionary = chain.middle
		var upper_length: float = Vector3(upper._out-upper._in).length()
		var middle_length := 0.0
		if not middle.is_empty():
			middle_length = Vector3(middle._out-middle._in).length()
			# Fold the proximal pair to preserve native sizes and reach the grounded ankle.
			l1 = clampf(d.length()+l2-(l1+l2)*0.06,absf(upper_length-middle_length)+0.001,upper_length+middle_length-0.001)
		if d.length() >= l1+l2 or d.length() <= absf(l1-l2): return {}
		var cosine := clampf((l1*l1+d.length_squared()-l2*l2)/(2.0*l1*d.length()),-1.0,1.0)
		var angle := d.angle()+(-1.0 if chain.fore else 1.0)*acos(cosine)
		var upper_angle := angle
		if not middle.is_empty():
			upper_angle += acos(clampf((upper_length*upper_length+l1*l1-middle_length*middle_length)/(2.0*upper_length*l1),-1.0,1.0))
		var vector: Vector3 = upper.transform.basis * Vector3(upper._out-upper._in)
		upper.transform.basis = Basis(Vector3.BACK,upper_angle-atan2(vector.y,vector.x))*upper.transform.basis
		_place(upper,hip)
		var knee := _port(upper,true)
		if not middle.is_empty():
			var target := hip+Vector3(cos(angle)*l1,sin(angle)*l1,0)
			vector = middle.transform.basis * Vector3(middle._out-middle._in)
			middle.transform.basis = Basis(Vector3.BACK,atan2(target.y-knee.y,target.x-knee.x)-atan2(vector.y,vector.x))*middle.transform.basis
			_place(middle,knee)
			knee = _port(middle,true)
		vector = lower.transform.basis * Vector3(lower._out-lower._in)
		lower.transform.basis = Basis(Vector3.BACK,atan2(ankle.y-knee.y,ankle.x-knee.x)-atan2(vector.y,vector.x))*lower.transform.basis
		_place(lower,knee)
		_place(foot,ankle)
		_place(support,hip)
		var start := parts.size()
		parts.append_array([support,foot,lower,upper])
		_edge(edges,0,start,hip,"Torso")
		_edge(edges,start+1,start+2,ankle,"Limb")
		if middle.is_empty():
			_edge(edges,start+2,start+3,knee,"Limb")
		else:
			var middle_index := parts.size()
			parts.append(middle)
			_edge(edges,start+2,middle_index,knee,"Limb")
			_edge(edges,middle_index,start+3,_port(upper,true),"Limb")
		_edge(edges,start,start+3,hip,"Limb")
	torso.transform = Transform3D(Basis(Vector3.BACK,deg_to_rad(torso_pitch_degrees)),Vector3(0,hip_height+torso_height_offset,0))
	var torso_box: AABB = torso.transform * AABB(torso._bounds)
	var head := _part("Head", "Head")
	if head.is_empty(): return {}
	head.transform.basis = Basis(Vector3.BACK,deg_to_rad(head_pitch_degrees))
	_place(head,Vector3(torso_box.end.x,hip_height+torso_height_offset,0)+head_attachment_offset)
	var head_index := parts.size()
	parts.append(head)
	_edge(edges,0,head_index,_port(head),"Neck")
	if jaw_enabled:
		var jaw := _part("LowerJaw", "Decoration")
		if jaw.is_empty(): return {}
		_place(jaw,_port(head,true)+jaw_attachment_offset)
		_edge(edges,head_index,parts.size(),_port(jaw),"Torso")
		parts.append(jaw)
	if tail_enabled:
		var tail := _part("Tail", "Tail")
		if tail.is_empty(): return {}
		tail.transform.basis = Basis(Vector3.BACK,deg_to_rad(tail_pitch_degrees))
		_place(tail,Vector3(torso_box.position.x,hip_height+torso_height_offset,0)+tail_attachment_offset)
		_edge(edges,0,parts.size(),_port(tail),"Torso")
		parts.append(tail)
	for layout: Dictionary in parts:
		for key: String in ["_in","_out","_bounds"]: layout.erase(key)
	return {"parts":parts,"connections":edges}

func generate_torso() -> bool:
	if use_manual_layout: return super.generate_torso()
	if not is_inside_tree() or not is_finite(overall_scale) or overall_scale < 0.1: return false
	var blueprint := _build_wolf_blueprint()
	if blueprint.is_empty():
		push_warning("[wolf_generator] Invalid model/standing layout; previous layout retained.")
		return false
	var previous := manual_layout
	manual_layout = MANUAL_LAYOUT.new()
	manual_layout.blueprint = blueprint
	var succeeded := _generate_manual_framework()
	manual_layout = previous
	return succeeded
