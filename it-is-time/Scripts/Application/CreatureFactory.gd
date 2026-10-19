extends RefCounted
## Saved authored poses are deployed without rerunning a procedural generator.

const DEFINITIONS := {
	"human": {"scene":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Spear1_NPC.tscn","name":"持矛人形","form":"人形","color":"8caaa3"},
	"stump_beast": {"scene":"res://Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn","name":"树桩兽","form":"兽形","color":"927e60"},
	"wolf": {"scene":"res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn","name":"灰狼","form":"兽形","color":"839b78"},
	"snake": {"scene":"res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn","name":"蛇兽","form":"蛇形","color":"bb9272"},
	"horned_beast": {"scene":"res://Scenes/Creatures/Characters/Generate_HornedBeast_NPC.tscn","name":"角兽","form":"兽形","color":"b49a72"},
	"spider": {"scene":"res://Scenes/Creatures/Characters/Generate_Spider_NPC.tscn","name":"蜘蛛","form":"兽形","color":"826f59"},
	"rat": {"scene":"res://Scenes/Creatures/Characters/Generate_Rat_1_NPC.tscn","name":"矿鼠","form":"兽形","color":"938471"},
	"bird": {"scene":"res://Scenes/Creatures/Characters/Generate_Bird_NPC.tscn","name":"食矿鸟","form":"兽形","color":"8c9a81"},
	"scarecrow": {"scene":"res://Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn","name":"敬业稻草人","form":"兽形","color":"b39f71"},
	"two_head_wolf": {"scene":"res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn","name":"双头甲狼","form":"兽形","color":"7f8c89"},
	"magic_eye_beast": {"scene":"res://Scenes/Creatures/Characters/Generate_HornedBeast_NPC.tscn","name":"魔眼拱兽","form":"兽形","color":"a489bd"},
}
const SUMMON_POOL := ["stump_beast","wolf","snake","horned_beast","spider","bird","rat"]
static var _templates: Dictionary = {}

static var _collisions: Dictionary = {}

static func local_bounds(record: Dictionary) -> AABB:
	if not _collisions.has(record.definition_id): template(record.definition_id)
	var result := AABB()
	var first := true
	for path: String in _collisions[record.definition_id]:
		var transform := Transform3D.IDENTITY
		var current := path
		while not current.is_empty():
			transform = unpack_transform(record.poses[current])*transform
			current = current.get_base_dir() if "/" in current else ""
		var bounds: AABB = transform*_collisions[record.definition_id][path]
		result = bounds if first else result.merge(bounds)
		first = false
	return Transform3D(Basis.IDENTITY.scaled(Vector3.ONE*float(record.get("size_multiplier",1.0))),Vector3.ZERO)*result

static func pack_transform(pose: Transform3D) -> Array:
	return [pose.basis.x.x,pose.basis.x.y,pose.basis.x.z,pose.basis.y.x,pose.basis.y.y,pose.basis.y.z,pose.basis.z.x,pose.basis.z.y,pose.basis.z.z,pose.origin.x,pose.origin.y,pose.origin.z]

static func unpack_transform(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[1],values[2]),Vector3(values[3],values[4],values[5]),Vector3(values[6],values[7],values[8])),Vector3(values[9],values[10],values[11]))

static func template(id: String) -> Dictionary:
	if not DEFINITIONS.has(id): return {}
	if _templates.has(id): return _templates[id].duplicate(true)
	var definition: Dictionary = DEFINITIONS[id]
	var scene := load(definition.scene) as PackedScene
	if scene == null: return {}
	var actor := scene.instantiate()
	_decorate_variant(actor,id)
	var poses := {}
	var parts := {}
	_collisions[id] = {}
	var hp := 0.0
	var armor := 0.0
	var speed := 3.0
	for node: Node in actor.find_children("*","",true,false):
		if node is Node3D: poses[str(actor.get_path_to(node))] = pack_transform(node.transform)
		if node is CollisionShape3D and not node.disabled and node.shape!=null and node.get_parent() is PhysicalBodyPart3D:
			var points := PackedVector3Array()
			if node.shape is ConvexPolygonShape3D: points = node.shape.points
			elif node.shape is BoxShape3D:
				var box := AABB(-node.shape.size*0.5,node.shape.size)
				for corner: int in 8: points.append(box.get_endpoint(corner))
			if not points.is_empty():
				var bounds := AABB(points[0],Vector3.ZERO)
				for point: Vector3 in points: bounds = bounds.expand(point)
				_collisions[id][str(actor.get_path_to(node))] = bounds
		if node is PhysicalBodyPart3D:
			parts[str(actor.get_path_to(node))] = {"key":str(node.get_meta(&"generated_part_key",str(node.name))),"hp":node.max_hp,"armor":node.armor}
			hp += node.max_hp
			armor += node.armor
		for property: String in ["slow_gait_data","motion_data"]:
			var motion: Variant = node.get(property)
			if motion is Resource and motion.get("target_speed") is float: speed = motion.target_speed
	actor.free()
	if parts.is_empty(): return {}
	var result := {"definition_id":id,"template_hash":FileAccess.get_sha256(definition.scene),"poses":poses,"parts":parts,
		"hp":hp,"armor":armor/parts.size(),"attack":preload("res://Resources/Damage/DefaultDamageRules.tres").calculate_weapon_raw_damage(10.0,true),"speed":speed,"interval":1.5,"name":definition.name,"form":definition.form,"color":definition.color}
	_templates[id] = result
	result.merge({"fur":id in ["wolf","rat","two_head_wolf"],"flying":id=="bird","snake":id=="snake","hands":2 if id=="human" else 0,"feet":0 if id=="snake" else 2 if id in ["human","bird"] else 4,"large":id in ["stump_beast","horned_beast","magic_eye_beast"],"size_multiplier":1.0,"magic_eye":id=="magic_eye_beast"},true)
	_templates[id] = result
	return result.duplicate(true)

static func valid_record(record: Dictionary) -> bool:
	var id: String = record.get("definition_id","")
	if not DEFINITIONS.has(id) or not record.get("poses") is Dictionary or not record.get("parts") is Dictionary: return false
	if record.get("template_hash") != FileAccess.get_sha256(DEFINITIONS[id].scene): return false
	var reference := template(id)
	if record.poses.size() != reference.poses.size() or record.parts.size() != reference.parts.size(): return false
	for path: String in record.poses:
		if not reference.poses.has(path) or not record.poses[path] is Array or record.poses[path].size()!=12: return false
		for value: Variant in record.poses[path]:
			if not (value is float or value is int) or not is_finite(float(value)): return false
		var pose := unpack_transform(record.poses[path])
		if absf(pose.basis.determinant())<0.000001 or (record.parts.has(path) and not pose.basis.get_scale().is_equal_approx(Vector3.ONE)): return false
	for path: String in record.parts:
		if not reference.parts.has(path) or not record.parts[path] is Dictionary: return false
		if record.parts[path].get("key") != reference.parts[path].key: return false
		for key: String in ["hp","armor"]:
			var value: Variant = record.parts[path].get(key)
			if not (value is float or value is int) or not is_finite(float(value)) or float(value)<0: return false
	for field: String in ["damage_multiplier","speed_multiplier","interval_multiplier"]:
		var multiplier: Variant = record.get(field,1.0)
		if not (multiplier is float or multiplier is int) or not is_finite(float(multiplier)) or float(multiplier)<=0: return false
	if not (record.get("size_multiplier",1.0) is float or record.get("size_multiplier",1.0) is int) or not is_finite(float(record.get("size_multiplier",1.0))) or float(record.get("size_multiplier",1.0))<=0 or float(record.get("size_multiplier",1.0))>10: return false
	if record.has("magic_eye") and not record.magic_eye is bool: return false
	return true

static func spawn(record: Dictionary, parent: Node3D, at: Vector3, faction: int, facing: float = 0.0) -> Node3D:
	if not valid_record(record): return null
	var actor := (load(DEFINITIONS[record.definition_id].scene) as PackedScene).instantiate() as Node3D
	_decorate_variant(actor,str(record.definition_id))
	actor.generate_on_ready = false
	actor.faction_id = faction
	actor.name = "Creature_"+str(record.id).validate_node_name()
	actor.position = at
	actor.rotation.y = facing
	actor.scale = Vector3.ONE*float(record.get("size_multiplier",1.0))
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.set_meta(&"creature_instance_id",record.id)
	actor.set_meta(&"summon_damage_multiplier",record.get("damage_multiplier",1.0))
	parent.add_child(actor)
	for path: String in record.poses:
		var node := actor.get_node_or_null(NodePath(path)) as Node3D
		if node != null: node.transform = unpack_transform(record.poses[path])
	for path: String in record.parts:
		var body := actor.get_node(NodePath(path)) as PhysicalBodyPart3D
		body.max_hp = record.parts[path].hp
		body.current_hp = body.max_hp
		body.armor = record.parts[path].armor
		body.freeze = true
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.set_meta(&"creature_part_key",record.parts[path].key)
	if record.get("magic_eye",false) or record.definition_id=="two_head_wolf":
		var ability := preload("res://Scripts/Events/StoryCreatureAbilities.gd").new()
		ability.name="StoryCreatureAbilities"
		ability.record = record.duplicate(true)
		actor.add_child(ability)
	var ai := actor.get_node_or_null("NPCStateMachine3D")
	if ai != null and ai.behavior != null:
		ai.behavior = ai.behavior.duplicate(true)
		for attack: Resource in ai.behavior.attacks: attack.cooldown *= float(record.get("interval_multiplier",1.0))
	for node: Node in actor.find_children("*","",true,false):
		var action_data: Variant = node.get("data")
		if action_data is Resource and action_data.get("cooldown") is float:
			action_data = action_data.duplicate(true)
			action_data.cooldown *= float(record.get("interval_multiplier",1.0))
			node.set("data",action_data)
		for property: String in ["slow_gait_data","fast_gait_data","motion_data"]:
			var motion: Variant = node.get(property)
			if motion is Resource and motion.get("target_speed") is float:
				motion = motion.duplicate(true)
				motion.target_speed *= float(record.get("speed_multiplier",1.0))
				node.set(property,motion)
	return actor

static func _decorate_variant(actor: Node3D, id: String) -> void:
	if id=="scarecrow":
		var straw:=StandardMaterial3D.new(); straw.albedo_color=Color("b99a50"); straw.roughness=1.0
		for mesh: Node in actor.find_children("*","MeshInstance3D",true,false): mesh.material_override=straw
		for part: Node in actor.find_children("*","PhysicalBodyPart3D",true,false):
			if str(part.get_meta(&"generated_part_key",part.name))!="Head": continue
			var hat:=MeshInstance3D.new(); hat.name="StrawHat"
			var cone:=CylinderMesh.new(); cone.top_radius=.1; cone.bottom_radius=2.0; cone.height=1.0
			hat.mesh=cone; hat.position.y=1.0; hat.material_override=straw; part.add_child(hat)
	if id!="two_head_wolf": return
	var head: PhysicalBodyPart3D
	var jaw: PhysicalBodyPart3D
	var torso: PhysicalBodyPart3D
	for part: Node in actor.find_children("*","PhysicalBodyPart3D",true,false):
		var key: String = str(part.get_meta(&"generated_part_key",part.name))
		if key=="Head": head=part
		elif "Jaw" in key: jaw=part
		elif torso==null and "Torso" in key: torso=part
	if head==null or jaw==null or torso==null: return
	var extra_head := head.duplicate() as PhysicalBodyPart3D
	var extra_jaw := jaw.duplicate() as PhysicalBodyPart3D
	extra_head.name="ExtraHead"; extra_jaw.name="ExtraJaw"
	extra_head.set_meta(&"generated_part_key","ExtraHead")
	extra_jaw.set_meta(&"generated_part_key","ExtraJaw")
	head.get_parent().add_child(extra_head); jaw.get_parent().add_child(extra_jaw)
	head.position.z-=.65; jaw.position.z-=.65
	extra_head.position.z+=.65; extra_jaw.position.z+=.65
	for own: Node in actor.find_children("*","PhysicalBodyPart3D",true,false):
		if own!=extra_head: extra_head.add_collision_exception_with(own)
		if own!=extra_jaw: extra_jaw.add_collision_exception_with(own)
	for pair: Array in [[torso,extra_head],[extra_head,extra_jaw]]:
		var joint := PinJoint3D.new()
		joint.name="ExtraHeadJoint" if pair[0]==torso else "ExtraJawJoint"
		head.get_parent().add_child(joint)
		joint.position=pair[1].position
		joint.node_a=joint.get_path_to(pair[0]); joint.node_b=joint.get_path_to(pair[1])
		extra_head.add_collision_exception_with(pair[0]); extra_jaw.add_collision_exception_with(pair[0])

static func activate(actor: Node3D) -> void:
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false):
		if body is PhysicalBodyPart3D and not body.is_broken: body.freeze = false

