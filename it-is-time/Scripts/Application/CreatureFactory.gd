extends RefCounted
## Saved authored poses are deployed without rerunning a procedural generator.

const DEFINITIONS := {
	"human": {"scene":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Spear1_NPC.tscn","name":"持矛人形","form":"人形","color":"8caaa3"},
	"wolf": {"scene":"res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn","name":"灰狼","form":"兽形","color":"839b78"},
	"snake": {"scene":"res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn","name":"蛇兽","form":"蛇形","color":"bb9272"},
}
static var _templates: Dictionary = {}

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
	var poses := {}
	var parts := {}
	var hp := 0.0
	var armor := 0.0
	var speed := 3.0
	for node: Node in actor.find_children("*","",true,false):
		if node is Node3D: poses[str(actor.get_path_to(node))] = pack_transform(node.transform)
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
	return true

static func spawn(record: Dictionary, parent: Node3D, at: Vector3, faction: int, facing: float = 0.0) -> Node3D:
	if not valid_record(record): return null
	var actor := (load(DEFINITIONS[record.definition_id].scene) as PackedScene).instantiate() as Node3D
	actor.generate_on_ready = false
	actor.faction_id = faction
	actor.name = "Creature_"+str(record.id).validate_node_name()
	actor.position = at
	actor.rotation.y = facing
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

static func activate(actor: Node3D) -> void:
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false):
		if body is PhysicalBodyPart3D and not body.is_broken: body.freeze = false

