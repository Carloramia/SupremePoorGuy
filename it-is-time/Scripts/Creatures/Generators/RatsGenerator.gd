@tool
extends "res://Scripts/Creatures/Generators/BaseCreatureGenerator.gd"

const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const PART_ROOT := "res://Scenes/Creatures/Bodyparts/Rats/"

@export_group("Rats Preset")
@export_enum("Rat 1", "Rat 2") var rat_preset: int = 0

@export_group("Rats Standing Layout")
@export_range(0.4, 0.9, 0.01) var standing_extension_ratio: float = 0.72
@export_range(0.1, 0.45, 0.01) var hip_x_ratio: float = 0.3
@export var fore_foot_forward_ratio: float = 0.12
@export var hind_foot_forward_ratio: float = -0.08
@export_range(-30.0, 30.0, 0.5) var head_pitch_degrees: float = 0.0
@export_range(0.0, 0.5, 0.01) var torso_height_ratio: float = 0.12

@export_group("Rats Attachments")
@export var ears_enabled: bool = true
@export var teeth_enabled: bool = true
@export var tail_enabled: bool = true
@export_range(-45.0, 60.0, 0.5) var closed_jaw_pitch_degrees: float = 28.0
@export_range(-60.0, 60.0, 0.5) var tail_angle_degrees: float = -10.0

func _init() -> void:
	overall_scale = 1.0
	part_width = 0.08
	torso_count = 1
	body_length = 5.329299545288

func _get_defaults_path() -> String:
	return "res://Resources/Generators/Rats/Rat%dGeneratorDefaults.tres" % (rat_preset+1)

func get_part_scene_rule(part_type: String, part_name: String, part_key: String = "") -> PART_SCENE_RULE:
	var authored := super.get_part_scene_rule(part_type, part_name, part_key)
	if authored != null: return authored
	if part_name.begins_with("Leg_") and part_name.ends_with("_Limb_3"):
		var source_name := part_name.trim_suffix("_Limb_3")+"_Limb_2"
		var source_rule := get_part_scene_rule(part_type,source_name,source_name)
		if source_rule == null: return null
		var rule := source_rule.duplicate() as PART_SCENE_RULE
		rule.part_key = part_key if not part_key.is_empty() else part_name
		rule.part_name = part_name
		return rule
	var path := ""
	match part_name:
		"Torso": path = "Torso/TorsoMain"
		"Head": path = "Head/HeadMain"
		"LowerJaw": path = "Head/LowerJaw"
		"EarFront": path = "Head/EarFront"
		"EarBack": path = "Head/EarBack"
		"Tooth1", "Tooth2": path = "Decorations/"+part_name
		_:
			if part_name.begins_with("SubTorso_"): path = "Decorations/Rivet"
			elif part_name.begins_with("Tail_"): path = "Tail/Tail%02d" % part_name.get_slice("_",1).to_int()
			elif part_name.begins_with("ForeLeg_") or part_name.begins_with("Leg_"):
				var fore := part_name.begins_with("ForeLeg_")
				if part_name.ends_with("_Limb_2"): path = "Legs/"+("ForeUpper" if fore else "HindUpper")
				elif part_name.ends_with("_Limb_1"): path = "Legs/"+("ForeLower" if fore else "HindLower")
				elif fore and rat_preset == 0: path = "Feet/ForePawCompleted"
				elif not fore and rat_preset == 1: path = "Feet/HindPawCompleted"
				else: path = "Feet/"+("ForeFoot" if fore else "HindFoot")+part_name.get_slice("_",1)
	if path.is_empty(): return null
	var scene := load(PART_ROOT+"Rat_%d/" % (rat_preset+1)+path+".tscn") as PackedScene
	if scene == null: return null
	var rule := PART_SCENE_RULE.new()
	rule.part_key = part_key if not part_key.is_empty() else part_name
	rule.part_type = part_type
	rule.part_scene = scene
	rule.size_mode = PART_SCENE_RULE.SizeMode.FIT_UNIFORM
	return rule

func _part(label: String, role: String, subtype: String = "") -> Dictionary:
	var rule := get_part_scene_rule(subtype if not subtype.is_empty() else ("LegLimb" if role=="Limb" else role),label,label)
	if rule == null: return {}
	var body := rule.part_scene.instantiate() as PhysicalBodyPart3D
	if body == null: return {}
	body.prepare_generated_geometry()
	var bounds := GEOMETRY.bounds(body,false)
	var actual := GEOMETRY.fit(body,bounds.size,rule,role,part_width)
	var inlet := body.get_node_or_null("JointIn") as Marker3D
	var outlet := body.get_node_or_null("JointOut") as Marker3D
	if actual.size == Vector3.ZERO or inlet == null or outlet == null:
		body.free()
		return {}
	var result := {"name":label,"part_key":label,"role":role,"size":actual.size,"segment_id":0,"transform":Transform3D.IDENTITY,
		"_in":inlet.position,"_out":outlet.position,"_bounds":actual}
	if subtype=="SubTorso": result["sub_torso"]=true
	body.free()
	return result

func _place(part: Dictionary, anchor: Vector3) -> void:
	part.transform.origin=anchor-part.transform.basis*Vector3(part._in)

func _port(part: Dictionary, outlet: bool = false) -> Vector3:
	return Transform3D(part.transform)*Vector3(part._out if outlet else part._in)

func _orient(part: Dictionary, direction: Vector3) -> void:
	part.transform.basis=Basis(Quaternion(Vector3(part._out-part._in).normalized(),direction.normalized()))

func _edge(edges: Array[Dictionary], a: int, b: int, anchor: Vector3, kind: String) -> void:
	edges.append({"a":a,"b":b,"anchor":anchor,"basis":Basis.IDENTITY,"kind":kind})

func _build_rats_blueprint() -> Dictionary:
	if rat_preset not in [0,1] or not is_finite(body_length) or body_length <= 0.0: return {}
	if not is_finite(standing_extension_ratio) or standing_extension_ratio <= 0.0 or standing_extension_ratio >= 1.0 or not is_finite(part_width) or part_width <= 0.0: return {}
	for value: float in [hip_x_ratio,fore_foot_forward_ratio,hind_foot_forward_ratio,head_pitch_degrees,torso_height_ratio,tail_angle_degrees,closed_jaw_pitch_degrees]:
		if not is_finite(value): return {}
	var torso := _part("Torso","Torso")
	var head := _part("Head","Head")
	var jaw := _part("LowerJaw","Decoration")
	if torso.is_empty() or head.is_empty() or jaw.is_empty(): return {}
	var parts: Array[Dictionary] = [torso]
	var edges: Array[Dictionary] = []
	var chains: Array[Dictionary] = []
	var hip_height := INF
	for fore: bool in [false,true]:
		for index: int in 2:
			var prefix := ("ForeLeg_" if fore else "Leg_")+str(index+1)
			var three_links := not fore and rat_preset==0
			var upper := _part(prefix+("_Limb_3" if three_links else "_Limb_2"),"Limb")
			var middle: Dictionary = _part(prefix+"_Limb_2","Limb") if three_links else {}
			var lower := _part(prefix+"_Limb_1","Limb")
			var foot := _part(prefix,"ForeLeg" if fore else "Leg")
			var support := _part("SubTorso_"+prefix,"Torso","SubTorso")
			if upper.is_empty() or lower.is_empty() or foot.is_empty() or support.is_empty(): return {}
			if three_links and middle.is_empty(): return {}
			foot.transform.basis = Basis(Vector3.BACK,deg_to_rad(20.0 if fore else 0.0))
			var foot_box: AABB = Transform3D(foot.transform.basis,Vector3.ZERO)*AABB(foot._bounds)
			var ankle_y: float = (foot.transform.basis*Vector3(foot._in)).y-foot_box.position.y
			var l1: float = Vector3(upper._out-upper._in).length()
			if three_links: l1+=Vector3(middle._out-middle._in).length()
			var l2: float = Vector3(lower._out-lower._in).length()
			if minf(l1,l2)<0.01: return {}
			hip_height=minf(hip_height,ankle_y+(l1+l2)*standing_extension_ratio)
			chains.append({"fore":fore,"index":index,"prefix":prefix,"upper":upper,"middle":middle,"lower":lower,"foot":foot,"support":support,"l1":l1,"l2":l2,"ankle_y":ankle_y})
	for chain: Dictionary in chains:
		var upper: Dictionary=chain.upper
		var middle: Dictionary=chain.middle
		var lower: Dictionary=chain.lower
		var foot: Dictionary=chain.foot
		var support: Dictionary=chain.support
		var upper_length: float=Vector3(upper._out-upper._in).length()
		var x: float=torso.size.x*hip_x_ratio*(1.0 if chain.fore else -1.0)
		# Alternating paper layers touch the central torso's side faces.
		var z:=part_width*(-1.0 if chain.index==0 else 1.0)
		var hip:=Vector3(x,hip_height,z)
		var resting_upper_length: float=upper_length if middle.is_empty() else Vector3(middle._out-middle._in).length()
		var offset: float=(fore_foot_forward_ratio if chain.fore else hind_foot_forward_ratio)*(resting_upper_length+chain.l2)
		var ankle:=Vector3(x+offset,chain.ankle_y,z)
		var d:=Vector2(ankle.x-hip.x,ankle.y-hip.y)
		var l1: float=chain.l1
		var l2: float=chain.l2
		if not middle.is_empty():
			var middle_length: float=Vector3(middle._out-middle._in).length()
			# Fold the added link around the original hip-to-knee span, preserving the lower leg pose.
			l1=middle_length
			l1=clampf(l1,maxf(absf(upper_length-middle_length)+0.001,d.length()-l2+0.001),minf(upper_length+middle_length-0.001,d.length()+l2-0.001))
		if d.length()>=l1+l2 or d.length()<=absf(l1-l2): return {}
		var angle:=d.angle()+(-1.0 if chain.fore else 1.0)*acos(clampf((l1*l1+d.length_squared()-l2*l2)/(2.0*l1*d.length()),-1.0,1.0))
		var upper_angle:=angle
		if not middle.is_empty():
			var middle_length: float=Vector3(middle._out-middle._in).length()
			upper_angle+=acos(clampf((upper_length*upper_length+l1*l1-middle_length*middle_length)/(2.0*upper_length*l1),-1.0,1.0))
		_orient(upper,Vector3(cos(upper_angle),sin(upper_angle),0))
		_place(upper,hip)
		var knee:=_port(upper,true)
		if not middle.is_empty():
			var distal_knee:=hip+Vector3(cos(angle)*l1,sin(angle)*l1,0)
			_orient(middle,distal_knee-knee)
			_place(middle,knee)
			knee=_port(middle,true)
		_orient(lower,ankle-knee)
		_place(lower,knee)
		_place(foot,ankle)
		_place(support,hip)
		var start:=parts.size()
		parts.append_array([support,foot,lower,upper])
		_edge(edges,0,start,hip,"Torso")
		_edge(edges,start+1,start+2,ankle,"Limb")
		if middle.is_empty():
			_edge(edges,start+2,start+3,knee,"Limb")
		else:
			var middle_index:=parts.size()
			parts.append(middle)
			_edge(edges,start+2,middle_index,knee,"Limb")
			_edge(edges,middle_index,start+3,_port(upper,true),"Limb")
		_edge(edges,start,start+3,hip,"Limb")
	torso.transform.origin=Vector3(0,hip_height+torso.size.y*torso_height_ratio,0)
	var torso_box: AABB=torso.transform*AABB(torso._bounds)
	head.transform.basis=Basis(Vector3.BACK,deg_to_rad(head_pitch_degrees))
	_place(head,Vector3(torso_box.end.x-head.size.x*.1,torso.transform.origin.y,0))
	var head_index:=parts.size()
	parts.append(head)
	_edge(edges,0,head_index,_port(head),"Neck")
	jaw.transform.basis=head.transform.basis*Basis(Vector3.BACK,deg_to_rad(closed_jaw_pitch_degrees))
	_place(jaw,_port(head,true))
	var jaw_index:=parts.size()
	parts.append(jaw)
	_edge(edges,head_index,jaw_index,_port(jaw),"Torso")
	if ears_enabled:
		for label: String in ["EarBack","EarFront"]:
			var ear:=_part(label,"Decoration")
			if ear.is_empty(): return {}
			var box: AABB=head.transform*AABB(head._bounds)
			_place(ear,Vector3(box.position.x+box.size.x*.25,box.end.y-box.size.y*.12,part_width*(-1.0 if label=="EarBack" else 1.0)))
			_edge(edges,head_index,parts.size(),_port(ear),"Torso")
			parts.append(ear)
	if teeth_enabled and rat_preset==0:
		for label: String in ["Tooth1","Tooth2"]:
			var tooth:=_part(label,"Decoration")
			if tooth.is_empty(): return {}
			var box: AABB=head.transform*AABB(head._bounds)
			_place(tooth,Vector3(box.end.x-box.size.x*(.12 if label=="Tooth1" else .05),box.position.y+box.size.y*.2,part_width*.65))
			_edge(edges,head_index,parts.size(),_port(tooth),"Torso")
			parts.append(tooth)
	if tail_enabled:
		var previous:=0
		var anchor:=Vector3(torso_box.position.x+torso_box.size.x*.05,torso_box.position.y+torso_box.size.y*.25,0)
		for index: int in (8 if rat_preset==0 else 7):
			var tail:=_part("Tail_%d" % (index+1),"Tail")
			if tail.is_empty(): return {}
			var angle:=deg_to_rad(tail_angle_degrees+float(index)*2.0)
			_orient(tail,Vector3(-cos(angle),sin(angle),0))
			_place(tail,anchor)
			_edge(edges,previous,parts.size(),anchor,"Tail")
			previous=parts.size()
			parts.append(tail)
			anchor=_port(tail,true)
	# Uniform XY scale preserves each part's native texture proportions; Z uses PartWidth.
	var body_box: AABB=head.transform*AABB(head._bounds)
	var jaw_box: AABB=jaw.transform*AABB(jaw._bounds)
	var native_length: float=maxf(maxf(torso_box.end.x,body_box.end.x),jaw_box.end.x)-minf(minf(torso_box.position.x,body_box.position.x),jaw_box.position.x)
	var factor:=body_length/native_length
	for part: Dictionary in parts:
		part.transform.origin*=Vector3(factor,factor,1)
		part.size*=Vector3(factor,factor,1)
		for key: String in ["_in","_out","_bounds"]: part.erase(key)
	for edge: Dictionary in edges: edge.anchor*=Vector3(factor,factor,1)
	return {"parts":parts,"connections":edges}

func generate_torso() -> bool:
	if use_manual_layout: return _generate_manual_framework()
	if not is_inside_tree() or not is_finite(overall_scale) or overall_scale<0.1: return false
	var blueprint:=_build_rats_blueprint()
	if blueprint.is_empty():
		push_warning("[rats_generator] Invalid scene, connector or standing layout; previous layout retained.")
		return false
	var previous:=manual_layout
	manual_layout=MANUAL_LAYOUT.new()
	manual_layout.blueprint=blueprint
	var success:=_generate_manual_framework()
	manual_layout=previous
	return success
