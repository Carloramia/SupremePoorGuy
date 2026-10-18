extends SceneTree
## Author the Bird_1 paper assembly through the existing manual-layout/scene-rule path.

const RULE = preload("res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd")
const LAYOUT = preload("res://Scripts/Creatures/Generators/CreatureManualLayout.gd")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const CHARACTER_PATH = "res://Scenes/Creatures/Characters/Generate_Bird.tscn"
const ASSETS = "res://Scenes/Creatures/Bodyparts/Bird/Bird_1/"
const ADAPTERS = "res://Scenes/Creatures/Bodyparts/Bird/Calibrated/Bird_1/"
const SETTINGS = "res://Resources/Generators/BirdParts/"
var records: Dictionary = {}
var rules: Array[RULE] = []
var parts: Array[Dictionary] = []
var connections: Array[Dictionary] = []
var mapping: Dictionary = {}
var factor: float
var depth: float

func _initialize() -> void: call_deferred("run")

func write(path: String, content: String) -> void:
	assert(DirAccess.make_dir_recursive_absolute(path.get_base_dir()) == OK)
	var file := FileAccess.open(path,FileAccess.WRITE)
	assert(file != null)
	file.store_string(content)
	file.close()

func pixel(part: String, point: Vector2) -> Vector3:
	var r: Dictionary = records["Bird_1/"+part]
	return Vector3(point.x-float(r.pivot_pixel[0]),float(r.pivot_pixel[1])-point.y,0)*float(r.units_per_texture_pixel)

func adapter(name: String, source: String, tags: Array, desired: Vector3 = Vector3.ZERO, inlet_override: Variant = null, ports: Dictionary = {}) -> String:
	var source_path := source if source.begins_with("res://") else ASSETS+source+".tscn"
	var part := load(source_path).instantiate() as PhysicalBodyPart3D
	assert(part != null)
	var inlet := part.get_node("JointIn") as Marker3D
	var outlet := part.get_node("JointOut") as Marker3D
	var incoming: Vector3 = inlet.position if inlet_override == null else Vector3(inlet_override)
	var outgoing := outlet.position
	var rotation := Basis.IDENTITY
	if not desired.is_zero_approx(): rotation = Basis(Quaternion((outgoing-incoming).normalized(),desired.normalized()))
	var collider := part.get_node("CollisionShape3D") as CollisionShape3D
	var coordinates := PackedStringArray()
	for point: Vector3 in collider.shape.points:
		var transformed := rotation*(collider.transform*point)
		coordinates.append("%.9f, %.9f, %.9f" % [transformed.x,transformed.y,transformed.z])
	# Bake the calibration into points. An inherited rotated collider otherwise
	# reappears after a fitted scene serializes its identity reset as a default.
	var lines := ['[gd_scene format=3]', '[ext_resource type="PackedScene" path="%s" id="base"]' % source_path,
		'[sub_resource type="ConvexPolygonShape3D" id="calibrated_shape"]','resource_local_to_scene = true',
		'points = PackedVector3Array(%s)' % ", ".join(coordinates),'metadata/body_part_collision_depth_multiplier = 2.0',
		'[node name="Bird1%s" instance=ExtResource("base")]' % name, 'tags = Array[int](%s)' % str(tags),
		'metadata/connector_calibration = "Bird_1_v1"']
	for key: String in ["Model"]:
		var node := part.get_node(key) as Node3D
		var transform := Transform3D(rotation,Vector3.ZERO)*node.transform
		lines.append('[node name="%s" parent="."]\ntransform = %s' % [key,var_to_str(transform)])
	lines.append('[node name="CollisionShape3D" parent="."]\ntransform = Transform3D(1,0,0,0,1,0,0,0,1,0,0,0)\nshape = SubResource("calibrated_shape")')
	lines.append('[node name="JointIn" parent="."]\nposition = %s' % var_to_str(rotation*incoming))
	lines.append('[node name="JointOut" parent="."]\nposition = %s' % var_to_str(rotation*outgoing))
	for key: String in ports:
		lines.append('[node name="%s" type="Marker3D" parent="."]\nposition = %s' % [key,var_to_str(rotation*Vector3(ports[key]))])
	var path := ADAPTERS+name+".tscn"
	write(path,"\n".join(lines)+"\n")
	part.free()
	return path

func piece(name: String, role: String, asset: String, length: float = 0.0, type_override: String = "") -> Dictionary:
	var rule := RULE.new()
	rule.part_name = name
	rule.part_key = name
	rule.part_type = type_override if not type_override.is_empty() else ("LegLimb" if role == "Limb" else role)
	rule.part_scene = ResourceLoader.load(asset,"PackedScene",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	rule.size_mode = RULE.SizeMode.FIT_UNIFORM
	rule.use_joint_markers = true
	rule.align_connectors_to_frame = role == "Limb"
	var part := rule.part_scene.instantiate() as PhysicalBodyPart3D
	part.prepare_generated_geometry()
	var original := GEOMETRY.bounds(part,false)
	var incoming := part.get_node("JointIn") as Marker3D
	var outgoing := part.get_node("JointOut") as Marker3D
	var scale := factor
	if length > 0.0: scale = length/incoming.position.distance_to(outgoing.position)
	var target := original.size*scale
	target.z = depth
	if role == "Limb": target.y = length
	var bounds := GEOMETRY.fit(part,target,rule,role,depth)
	assert(bounds.size.x > 0.0 and bounds.size.y > 0.0)
	var result := {"name":name,"part_key":name,"role":role,"size":bounds.size,"transform":Transform3D.IDENTITY,"segment_id":0,
		"_in":incoming.position,"_out":outgoing.position,"_bounds":bounds,"_ports":{}}
	if role == "Limb": result["connector_span"] = length
	for key: String in ["WingPort","NeckPort","HipPort"]:
		var marker := part.get_node_or_null(key) as Marker3D
		if marker != null: result._ports[key] = marker.position
	rules.append(rule)
	mapping[name] = {"asset":asset,"type":rule.part_type,"source":str(part.get_meta("source_png",""))}
	part.free()
	return result

func place(piece_data: Dictionary, anchor: Vector3, basis: Basis = Basis.IDENTITY) -> void:
	piece_data.transform = Transform3D(basis,anchor-basis*Vector3(piece_data._in))

func port(piece_data: Dictionary, outgoing: bool = false) -> Vector3:
	return Transform3D(piece_data.transform)*Vector3(piece_data._out if outgoing else piece_data._in)

func append(piece_data: Dictionary) -> int:
	parts.append(piece_data)
	return parts.size()-1

func connect_parts(a: int, b: int, anchor: Vector3, kind: String, basis: Basis = Basis.IDENTITY) -> void:
	connections.append({"a":a,"b":b,"anchor":anchor,"kind":kind,"basis":basis})

func externalize_settings(text: String) -> String:
	var declarations := '[ext_resource type="Resource" path="'+SETTINGS+'Bird1Layout.tres" id="bird_layout"]\n'
	declarations += '[ext_resource type="Script" path="res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd" id="bird_rules_class"]\n'
	var references := PackedStringArray()
	for index: int in rules.size():
		declarations += '[ext_resource type="Resource" path="%s%s.tres" id="bird_rule_%d"]\n' % [SETTINGS,rules[index].part_key,index]
		references.append('ExtResource("bird_rule_%d")' % index)
	text = text.insert(text.find("[sub_resource"),declarations+"\n")
	var regex := RegEx.new()
	regex.compile('(?m)^manual_layout = [^\\n]*')
	text = regex.sub(text,'manual_layout = ExtResource("bird_layout")')
	regex.compile('(?m)^part_scene_rules = [^\\n]*')
	text = regex.sub(text,'part_scene_rules = Array[ExtResource("bird_rules_class")](['+", ".join(references)+'])')
	# Packed local-to-scene resources otherwise hide the editable external presets.
	# Drop only unreferenced serialized blocks; keep fitted collision/model overrides.
	var section := RegEx.new()
	section.compile('(?m)^\\[')
	regex.compile('(?m)^\\[sub_resource[^\\n]* id="([^"]+)"\\]')
	var removed := true
	while removed:
		removed = false
		for match: RegExMatch in regex.search_all(text):
			if text.contains('SubResource("'+match.get_string(1)+'")'): continue
			var next := section.search(text,match.get_end())
			var end := next.get_start() if next != null else text.length()
			text = text.substr(0,match.get_start())+text.substr(end)
			removed = true
			break
	return text

func limb_pose(piece_data: Dictionary, top: Vector3, bottom: Vector3) -> void:
	var basis := Basis(Quaternion(Vector3.UP,(top-bottom).normalized()))
	place(piece_data,top,basis)
	assert(port(piece_data,true).distance_to(bottom)<0.0001)

func build(generator: Node) -> Dictionary:
	factor = float(generator.body_length)/float(records["Bird_1/Torso/TorsoMain"].visible_world_size[0])
	depth = float(generator.part_width)
	var torso_ports := {"WingPort":pixel("Torso/TorsoMain",Vector2(150.90062,30.73913)),
		"NeckPort":pixel("Torso/TorsoMain",Vector2(439.30263,61.50658)),
		"HipPort":pixel("Torso/TorsoMain",Vector2(210,335))}
	var torso_asset := adapter("Torso","Torso/TorsoMain",[0],Vector3.ZERO,null,torso_ports)
	var hip_asset := adapter("SubTorso","Legs/ThighLeft",[6])
	# The visible beak rivet is not the neck socket; attach at the rear nape.
	var head_asset := adapter("Head","Head/HeadMain",[3],Vector3.ZERO,Vector3(-1.33,-0.14,0))
	var root_asset := adapter("WingRoot","Wings/RootRight",[7,8],Vector3.UP)
	var middle_asset := adapter("WingMiddle","Wings/RootRight",[7,8],Vector3.UP)
	var tip_asset := adapter("WingTip","Legs/BodyLinkLower",[7],Vector3.UP)
	var feather_assets := []
	for side: String in ["Left","Right"]:
		var variants := []
		for index: int in [1,2]:
			var name := "Flight%s%02d" % [side,index]
			variants.append(adapter(name,"res://Scenes/Creatures/Bodyparts/Bird/Bird_3/Feathers/"+name+".tscn",[9],Vector3.UP))
		feather_assets.append(variants)
	var foot_assets := [adapter("FootLeft","res://Scenes/Creatures/Bodyparts/Bird/Bird_3/Feet/Claw01.tscn",[1],Vector3(0.2,-1,0)),adapter("FootRight","res://Scenes/Creatures/Bodyparts/Bird/Bird_3/Feet/Claw02.tscn",[1],Vector3(0.2,-1,0))]
	var torso := piece("Torso","Torso",torso_asset)
	torso.transform.origin = Vector3(0,1.9,0)
	var torso_index := append(torso)
	for side_index: int in 2:
		var side := 1.0 if side_index == 0 else -1.0
		var suffix := str(side_index+1)
		var hip := piece("SubTorso"+("" if side_index==0 else "_2"),"Torso",hip_asset,0.0,"SubTorso")
		hip["sub_torso"] = true
		var hip_anchor: Vector3 = torso.transform*Vector3(torso._ports.HipPort)+Vector3(0,0,side*depth)
		place(hip,hip_anchor)
		var hip_index := append(hip)
		connect_parts(torso_index,hip_index,hip_anchor,"Torso")
		var upper := piece("Leg_"+suffix+"_Limb_2","Limb",ASSETS+"Legs/Variant%02dUpper.tscn" % (3 if side_index==0 else 4),0.60)
		var lower := piece("Leg_"+suffix+"_Limb_1","Limb",ASSETS+"Legs/Variant%02dUpper.tscn" % (2 if side_index==0 else 5),0.56)
		# Keep the new claws within the existing ankle-to-sole space for flight tuck.
		var foot := piece("Leg_"+suffix,"Leg",foot_assets[side_index],0.50 if side_index==0 else 0.44)
		var hip_end := port(hip,true)+Vector3(0,0,side*depth)
		# Source feet differ slightly in ankle height; solve each knee against its sole.
		var ankle_height := float(foot._in.y)-float(foot._bounds.position.y)
		var ankle := Vector3(hip_end.x+(0.22 if side_index==0 else -0.10),ankle_height,hip_end.z)
		var reach := hip_end.distance_to(ankle)
		if reach > 1.10: ankle.y = hip_end.y-1.00; reach = hip_end.distance_to(ankle)
		var direction := (ankle-hip_end).normalized()
		var along := (0.60*0.60-0.56*0.56+reach*reach)/(2.0*reach)
		var height := sqrt(maxf(0.60*0.60-along*along,0.0))
		var back := Vector3(direction.y,-direction.x,0).normalized()
		var knee := hip_end+direction*along+back*height
		limb_pose(upper,hip_end,knee)
		limb_pose(lower,knee,ankle)
		place(foot,ankle)
		# Keep foot-to-root ordering used by gait and flight chain discovery.
		var foot_index := append(foot)
		var lower_index := append(lower)
		var upper_index := append(upper)
		connect_parts(foot_index,lower_index,ankle,"Limb",lower.transform.basis)
		connect_parts(lower_index,upper_index,knee,"Limb",upper.transform.basis)
		connect_parts(hip_index,upper_index,hip_end,"Limb",upper.transform.basis)
	var head := piece("Head_1","Head",head_asset)
	var head_anchor: Vector3 = torso.transform*Vector3(torso._ports.NeckPort)
	place(head,head_anchor)
	var head_index := append(head)
	connect_parts(torso_index,head_index,head_anchor,"Neck")
	var sections := ["Root","Middle","Tip"]
	var lengths := [float(generator.wing_root_length),float(generator.wing_middle_length),float(generator.wing_tip_length)]
	var angle := float(generator.wing_elevation_degrees)
	var angles := [angle,angle+float(generator.wing_fold_degrees),angle+float(generator.wing_fold_degrees)-float(generator.wing_tip_fold_degrees)]
	var opened := Basis(Vector3.BACK,deg_to_rad(90.0-angle))
	# Use the existing continuous feather edge and terminal alignment calculation.
	var feather_blocks: Array[Dictionary] = []
	for section: int in 3:
		var planned: Array[Dictionary] = []
		var count := [2,3,4][section] as int
		for index: int in count:
			planned.append({"size":Vector3.ONE,"transform":Transform3D(Basis.IDENTITY,Vector3(0,lengths[section]*((index+0.5)/count-0.5),0))})
		feather_blocks.append({"section":sections[section],"size":Vector3(0.0,lengths[section],depth),"feathers":planned})
	generator._arrange_feather_edge(feather_blocks)
	for side_index: int in 2:
		var side := 1.0 if side_index==0 else -1.0
		var anchor: Vector3 = torso.transform*Vector3(torso._ports.WingPort)+Vector3(0,0,side*depth)
		var previous := torso_index
		for section: int in 3:
			var asset: String = [root_asset,middle_asset,tip_asset][section]
			var wing := piece("Wing_%d_%s_%d" % [side_index+1,sections[section],section+1],"Wing" if section==2 else "WingLimb",asset,lengths[section],"Wing"+str(sections[section]))
			var basis := Basis(Vector3.BACK,deg_to_rad(90.0-float(angles[section])))
			place(wing,anchor,basis)
			wing["wing_section"] = sections[section]
			wing["wing_open_basis"] = opened
			var next := append(wing)
			connect_parts(previous,next,anchor,"Wing",basis)
			var feathers: Array = feather_blocks[section].feathers
			for index: int in feathers.size():
				var planned: Dictionary = feathers[index]
				var feather := piece("Feather_%d_%d_%03d" % [side_index+1,section+1,index+1],"Feather",feather_assets[side_index][index%2],planned.size.y)
				var local_root: Vector3 = planned.transform.origin+Vector3.UP*lengths[section]*0.5
				# Small depth layers prevent coplanar paper surfaces from flickering.
				var feather_anchor := anchor+basis*local_root+Vector3(0,0,side*depth*(1.0+0.1*(section*3+index)))
				place(feather,feather_anchor,Basis(Vector3.BACK,PI*0.5))
				# Assembly stores this target relative to the stem's authored basis.
				feather["feather_open_basis"] = basis*Basis(planned.transform.basis)
				var feather_index := append(feather)
				connect_parts(next,feather_index,feather_anchor,"Feather",basis)
			anchor = port(wing,true)
			previous = next
	var tail_root: Vector3 = torso._bounds.position+Vector3(torso._bounds.size.x*0.12,torso._bounds.size.y*0.32,torso._bounds.size.z*0.5)
	for index: int in 5:
		var progress := float(index-2)/2.0
		var tail := piece("TailFeather_%03d" % (index+1),"Feather",ADAPTERS+"TailFlight%02d.tscn" % (index%2+1),float(generator.body_length)*(0.55-0.125*absf(progress)))
		var tail_angle := deg_to_rad(12.0+24.0*progress)
		var basis: Basis = torso.transform.basis*Basis(Quaternion(Vector3.UP,Vector3(-cos(tail_angle),sin(tail_angle),0)))
		var anchor: Vector3 = torso.transform*(tail_root+Vector3(0,progress*depth*0.06,float(index-2)*depth*0.12))
		place(tail,anchor,basis)
		var next := append(tail)
		connect_parts(torso_index,next,anchor,"Tail",torso.transform.basis)
	# Leave every sole at its own measured height; translate the complete assembly once.
	var minimum := INF
	for part: Dictionary in parts:
		if part.role != "Leg": continue
		minimum = minf(minimum,float(part.transform.origin.y)+float(part._bounds.position.y))
	for part: Dictionary in parts:
		part.transform.origin.y -= minimum
		for key: String in ["_in","_out","_bounds","_ports"]: part.erase(key)
	for connection: Dictionary in connections: connection.anchor.y -= minimum
	return {"parts":parts,"connections":connections,"create_connection_markers":true,"asset_set":"Bird_1","manual_layout":true}

func run() -> void:
	var console := root.get_node_or_null("RuntimeConsole")
	if console != null: console.set("auto_getlogs_enabled",false)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Bird/Metadata/model_manifest.json"))
	for record: Dictionary in manifest.models: records[record.key] = record
	var original := FileAccess.get_file_as_string(CHARACTER_PATH)
	var actor := load(CHARACTER_PATH).instantiate() as Node3D
	actor.set("generate_on_ready",false)
	var order := {}
	for child: Node in actor.get_children(): order[str(child.name)] = child.get_index()
	root.add_child(actor)
	var generator := actor.get_node("BirdGenerator")
	var layout := LAYOUT.new()
	layout.blueprint = build(generator)
	assert(parts.size() == 39 and connections.size() == 38)
	DirAccess.make_dir_recursive_absolute(SETTINGS)
	assert(ResourceSaver.save(layout,SETTINGS+"Bird1Layout.tres") == OK)
	generator.set("manual_layout",layout)
	generator.set("use_manual_layout",true)
	generator.set("part_scene_rules",rules)
	generator.set("torso_count",1)
	generator.set("wing_segment_count",3)
	generator.set("neck_segment_count",0)
	for rule: RULE in rules: assert(ResourceSaver.save(rule,SETTINGS+rule.part_key+".tres") == OK)
	assert(actor.generate_creature())
	generator._clear_generated_preview()
	for child: Node in actor.get_children():
		if order.has(str(child.name)): actor.move_child(child,mini(int(order[str(child.name)]),actor.get_child_count()-1))
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true
	var damage := actor.get_node_or_null("CharacterDamageController3D")
	if damage != null: actor.remove_child(damage); damage.free()
	actor.set("generate_on_ready",true)
	var packed := PackedScene.new()
	assert(packed.pack(actor) == OK)
	assert(ResourceSaver.save(packed,CHARACTER_PATH) == OK)
	var text := FileAccess.get_file_as_string(CHARACTER_PATH)
	var header := text.get_slice("\n",0)
	text = text.replace(header,original.get_slice("\n",0)+'\n\n[ext_resource type="PackedScene" path="res://Scenes/Creatures/Characters/_BaseGeneratedCreature.tscn" id="bird_asset_base"]')
	var regex := RegEx.new()
	regex.compile('(?m)^\\[node name="Generate_Bird"[^\\n]*')
	text = regex.sub(text,'[node name="Generate_Bird" instance=ExtResource("bird_asset_base")]',true)
	for key: String in ["GeneratedLegStepMovementController3D","CreatureRecoveryStateMachine3D","CreatureActionController3D"]:
		regex.compile('(?m)^\\[node name="'+key+'"[^\\n]*')
		text = regex.sub(text,'[node name="'+key+'" parent="." index="'+str(order[key])+'"]',true)
	write(CHARACTER_PATH,externalize_settings(text))
	write("res://Assets/3DResources/Creatures/Bird/Metadata/generator_part_mapping.json",JSON.stringify({"asset_set":"Bird_1","feather_asset_set":"Bird_3","parts":mapping,"part_count":parts.size(),"joint_count":connections.size(),"layout":SETTINGS+"Bird1Layout.tres"},"  ")+"\n")
	actor.free()
	await process_frame
	print("PASS: Bird_1 with a direct Head/Torso joint, 18 wing feathers and 5 tail feathers; 39 bodies, 38 joints.")
	quit()
