extends RefCounted
## Saved authored poses are deployed without rerunning a procedural generator.

const DEFINITIONS := {
	"human": {"scene":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Spear1_NPC.tscn","name":"持矛人形","form":"人形","color":"8caaa3"},
	"stump_beast": {"scene":"res://Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn","name":"树桩兽","form":"兽形","color":"927e60"},
	"wolf": {"scene":"res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn","name":"灰狼","form":"兽形","color":"839b78"},
	"snake": {"scene":"res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn","name":"蛇兽","form":"蛇形","color":"bb9272"},
	"horned_beast": {"scene":"res://Scenes/Creatures/Characters/Generate_HornedBeast_NPC.tscn","name":"角兽","form":"兽形","color":"b49a72"},
	"spider": {"scene":"res://Scenes/Creatures/Characters/Generate_Spider_NPC.tscn","name":"蜘蛛","form":"兽形","color":"826f59"},
}
const SUMMON_POOL := ["stump_beast","wolf","snake","horned_beast","spider"]
const DAMAGE_RULES = preload("res://Resources/Damage/DefaultDamageRules.tres")
const ANATOMY = preload("res://Scripts/Summoning/SummonAnatomy.gd")
static var _templates: Dictionary = {}

static var _collisions: Dictionary = {}
static var _presentation_parts: Dictionary = {}
static var _presentation_cleanup_registered := false

static func cache_key(id: String, anatomy: Dictionary = {}) -> String:
	return id if anatomy.is_empty() else id+":"+JSON.stringify(anatomy,"",true)

static func presentation_part(definition_id: String, path: String, anatomy: Dictionary = {}) -> PackedScene:
	var key := cache_key(definition_id,anatomy)
	if not _presentation_parts.has(key): template(definition_id,anatomy)
	return _presentation_parts.get(key,{}).get(path) as PackedScene

static func _release_presentation_parts() -> void:
	_presentation_parts.clear()

static func _pack_presentation_part(source: Node) -> PackedScene:
	# Flatten nested scene instances before packing, so preview copies cannot duplicate GLB subtrees.
	var copy := source.duplicate(0)
	copy.scene_file_path = ""
	copy.set_script(source.get_script())
	for property: Dictionary in source.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			copy.set(property.name,source.get(property.name))
	for child: Node in copy.find_children("*","",true,false):
		child.scene_file_path = ""
		child.owner = copy
	var packed := PackedScene.new()
	var error := packed.pack(copy)
	copy.free()
	return packed if error == OK else null

static func local_bounds(record: Dictionary) -> AABB:
	var key := cache_key(record.definition_id,record.get("anatomy",{}))
	if not _collisions.has(key): template(record.definition_id,record.get("anatomy",{}))
	var result := AABB()
	var first := true
	for path: String in _collisions[key]:
		var transform := Transform3D.IDENTITY
		var current := path
		while not current.is_empty():
			transform = unpack_transform(record.poses[current])*transform
			current = current.get_base_dir() if "/" in current else ""
		var bounds: AABB = transform*_collisions[key][path]
		result = bounds if first else result.merge(bounds)
		first = false
	return result

static func pack_transform(pose: Transform3D) -> Array:
	return [pose.basis.x.x,pose.basis.x.y,pose.basis.x.z,pose.basis.y.x,pose.basis.y.y,pose.basis.y.z,pose.basis.z.x,pose.basis.z.y,pose.basis.z.z,pose.origin.x,pose.origin.y,pose.origin.z]

static func unpack_transform(values: Array) -> Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[1],values[2]),Vector3(values[3],values[4],values[5]),Vector3(values[6],values[7],values[8])),Vector3(values[9],values[10],values[11]))

static func template(id: String, anatomy: Dictionary = {}) -> Dictionary:
	if not DEFINITIONS.has(id): return {}
	if not ANATOMY.valid(anatomy): return {}
	var key := cache_key(id,anatomy)
	if _templates.has(key): return _templates[key].duplicate(true)
	var definition: Dictionary = DEFINITIONS[id]
	var scene := load(definition.scene) as PackedScene
	if scene == null: return {}
	var actor := scene.instantiate()
	actor.generate_on_ready = false
	if not ANATOMY.apply(actor,anatomy): actor.free(); return {}
	var poses := {}
	var parts := {}
	_collisions[key] = {}
	_presentation_parts[key] = {}
	if not _presentation_cleanup_registered and Engine.get_main_loop() is SceneTree:
		Engine.get_main_loop().root.tree_exiting.connect(_release_presentation_parts,CONNECT_ONE_SHOT)
		_presentation_cleanup_registered = true
	var hp := 0.0
	var armor := 0.0
	var speed := 3.0
	var total_mass := 0.0
	var attack_multiplier := 1.0
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
				_collisions[key][str(actor.get_path_to(node))] = bounds
		if node is PhysicalBodyPart3D:
			# Cache only this small subtree; presentation must not instantiate a generator or AI.
			_presentation_parts[key][str(actor.get_path_to(node))] = _pack_presentation_part(node)
			var derived_hp: float = DAMAGE_RULES.health_for_mass(node.mass) if node.mass_based_health else node.max_hp
			parts[str(actor.get_path_to(node))] = {"key":str(node.get_meta(&"generated_part_key",str(node.name))),"hp":derived_hp,"armor":node.armor,"resilience":node.resilience,"mass":node.mass,"authored_hp":node.max_hp}
			hp += derived_hp
			armor += node.armor
			total_mass += node.mass
		var action: Variant = node.get("data")
		if action is Resource and action.get("damage_multiplier") is float and not is_equal_approx(action.damage_multiplier,1.0): attack_multiplier = action.damage_multiplier
		var actions: Variant = node.get("actions")
		if actions is Array and not actions.is_empty() and actions[0] is Resource: attack_multiplier = actions[0].damage_multiplier
		for property: String in ["slow_gait_data","motion_data"]:
			var motion: Variant = node.get(property)
			if motion is Resource and motion.get("target_speed") is float: speed = motion.target_speed
	actor.free()
	if parts.is_empty(): return {}
	var result := {"definition_id":id,"template_hash":FileAccess.get_sha256(definition.scene),"poses":poses,"parts":parts,
		"hp":hp,"armor":armor/parts.size(),"resilience":0.0,"base_total_mass":total_mass,"balance_revision":DAMAGE_RULES.BALANCE_REVISION,"attack":DAMAGE_RULES.base_attack_damage*pow(total_mass,1.0/3.0)*attack_multiplier,"speed":speed,"interval":1.5,"name":definition.name,"form":definition.form,"color":definition.color}
	if not anatomy.is_empty(): result.anatomy = anatomy.duplicate(true)
	_templates[key] = result
	return result.duplicate(true)

static func valid_record(record: Dictionary) -> bool:
	var id: String = record.get("definition_id","")
	if not DEFINITIONS.has(id) or not record.get("poses") is Dictionary or not record.get("parts") is Dictionary: return false
	if record.get("template_hash") != FileAccess.get_sha256(DEFINITIONS[id].scene): return false
	if not record.get("anatomy",{}) is Dictionary: return false
	if not record.get("magic_eye",false) is bool or not record.get("combat_revival_used",false) is bool: return false
	var durability: Variant = record.get("limb_durability_bonus",0.0)
	if not (durability is float or durability is int) or not is_finite(float(durability)) or float(durability)<0.0: return false
	if not record.get("relic_ids",[]) is Array or not record.get("effects",{}) is Dictionary: return false
	for relic: Variant in record.get("relic_ids",[]):
		if not relic is String or relic not in preload("res://Scripts/Summoning/SummonContent.gd").RELICS.map(func(item):return item.id): return false
	var burn: Variant = record.get("effects",{}).get("burn_ratio",0.0)
	if not (burn is float or burn is int) or not is_finite(float(burn)) or float(burn)<0.0: return false
	var reference := template(id,record.get("anatomy",{}))
	if reference.is_empty(): return false
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
		var resilience: Variant = record.parts[path].get("resilience",0.0)
		if not (resilience is float or resilience is int) or not is_finite(float(resilience)) or float(resilience)<0: return false
	for field: String in ["damage_multiplier","speed_multiplier","interval_multiplier"]:
		var multiplier: Variant = record.get(field,1.0)
		if not (multiplier is float or multiplier is int) or not is_finite(float(multiplier)) or float(multiplier)<=0: return false
	return true

## Upgrade numeric data only; poses, equipment, faction and rune multipliers stay intact.
static func upgrade_damage_record(record: Dictionary) -> bool:
	if int(record.get("balance_revision",0)) >= DAMAGE_RULES.BALANCE_REVISION: return false
	if not valid_record(record): return false
	var reference := template(record.definition_id,record.get("anatomy",{}))
	var hp := 0.0
	for path: String in record.parts:
		var part: Dictionary = record.parts[path]
		var base: Dictionary = reference.parts[path]
		var health_multiplier := float(part.hp)/maxf(float(base.authored_hp),0.000001)
		part.hp = float(base.hp)*health_multiplier
		part.resilience = part.get("resilience",0.0)
		part.mass = base.mass
		hp += float(part.hp)
	record.hp = hp
	record.attack = float(reference.attack)*float(record.get("damage_multiplier",1.0))
	record.resilience = 0.0
	record.base_total_mass = reference.base_total_mass
	record.balance_revision = DAMAGE_RULES.BALANCE_REVISION
	return true

static func spawn(record: Dictionary, parent: Node3D, at: Vector3, faction: int, facing: float = 0.0) -> Node3D:
	if not valid_record(record): return null
	record = record.duplicate(true)
	upgrade_damage_record(record)
	var actor := (load(DEFINITIONS[record.definition_id].scene) as PackedScene).instantiate() as Node3D
	actor.generate_on_ready = false
	if not ANATOMY.apply(actor,record.get("anatomy",{})): actor.free(); return null
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
		body.resilience = float(record.parts[path].get("resilience",0.0))
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
	var effects := preload("res://Scripts/Summoning/SummonCombatEffects3D.gd").new()
	effects.name = "SummonEffects"
	effects.record = record.duplicate(true)
	actor.add_child(effects)
	return actor

static func activate(actor: Node3D) -> void:
	actor.process_mode = Node.PROCESS_MODE_INHERIT
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false):
		if body is PhysicalBodyPart3D and not body.is_broken: body.freeze = false

