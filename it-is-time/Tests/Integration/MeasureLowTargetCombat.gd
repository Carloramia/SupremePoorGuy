extends "res://Tests/Integration/SimulateCreatureMelee.gd"
## Fixture builder and frozen-query baseline only. For melee hit rates run MeasureLiveLowTargetCombat.gd;
## frozen bodies do not run the victim-side integration callback used by ordinary weapons.
const LOW_SCENES := {
	"stump_beast":"res://Scenes/Creatures/Characters/Generate_StumpBeast_NPC.tscn",
	"wolf":"res://Scenes/Creatures/Characters/Generate_Wolf_NPC.tscn",
	"snake":"res://Scenes/Creatures/Characters/Generate_Snake_NPC.tscn",
	"horned_beast":"res://Scenes/Creatures/Characters/Generate_HornedBeast_NPC.tscn",
	"spider":"res://Scenes/Creatures/Characters/Generate_Spider_NPC.tscn",
	"rat_1":"res://Scenes/Creatures/Characters/Generate_Rat_1_NPC.tscn",
	"rat_2":"res://Scenes/Creatures/Characters/Generate_Rat_2_NPC.tscn",
	"bird":"res://Scenes/Creatures/Characters/Generate_Bird_NPC.tscn",
	"human_spear1":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Spear1_NPC.tscn",
	"human_spear5":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Spear5_NPC.tscn",
	"human_sword":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_CurvedSword_NPC.tscn",
	"human_claw":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_ClawGauntlet_NPC.tscn",
	"human_flail":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Flail_NPC.tscn",
	"human_shield":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Shield_NPC.tscn",
	"human_bow":"res://Scenes/Creatures/Characters/Human/Armed/Generate_Human_Bow_NPC.tscn",
}
var _records: Dictionary = {}
var contacts: Array[Dictionary] = []
var completed := false

func _initialize() -> void:
	options.merge({"mode":"duel","seconds":35.0,"separation":60.0,"side":"left","gap":35.0},true)
	super._initialize()

func available_species() -> Array: return LOW_SCENES.keys()

func creature_record(species: String) -> Dictionary:
	if _records.has(species): return _records[species].duplicate(true)
	var actor: Node3D = load(LOW_SCENES[species]).instantiate()
	actor.generate_on_ready = false
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	root.add_child(actor)
	var parts := {}
	var hp := 0.0
	var bounds := AABB()
	var first := true
	for node: Node in actor.find_children("*","",true,false):
		if node is PhysicalBodyPart3D:
			var health: float = node.mass*40.0 if node.mass_based_health else node.max_hp
			parts[str(actor.get_path_to(node))] = {"hp":health,"mass":node.mass,"armor":node.armor,"resilience":node.resilience}
			hp += health
		if node is CollisionShape3D and node.get_parent() is PhysicalBodyPart3D and node.shape != null and not node.disabled:
			var local: AABB
			if node.shape is BoxShape3D: local = AABB(-node.shape.size*0.5,node.shape.size)
			elif node.shape is ConvexPolygonShape3D:
				var points: PackedVector3Array = node.shape.points
				if points.is_empty(): continue
				local = AABB(points[0],Vector3.ZERO)
				for point: Vector3 in points: local = local.expand(point)
			else: continue
			var pose := Transform3D.IDENTITY
			var current: Node3D = node
			while current != actor:
				pose = current.transform*pose
				current = current.get_parent()
			var box: AABB = pose*local
			bounds = box if first else bounds.merge(box)
			first = false
	actor.free()
	_records[species] = {"definition_id":species,"parts":parts,"hp":hp,"bounds":bounds,"template_hash":FileAccess.get_sha256(LOW_SCENES[species])}
	return _records[species].duplicate(true)

func creature_bounds(record: Dictionary) -> AABB: return record.bounds

func spawn_creature(record: Dictionary, host: Node3D, _at: Vector3, team: int, _yaw: float) -> Node3D:
	var actor: Node3D = load(LOW_SCENES[record.definition_id]).instantiate()
	actor.generate_on_ready = false
	actor.faction_id = team
	actor.name = "LowTarget_"+str(record.definition_id)+"_"+str(team)
	var side := -1.0 if str(options.side)=="right" else 1.0
	var yaw: float = (0.0 if team==0 else PI) + (PI if side<0.0 else 0.0)
	var bounds: AABB = Transform3D(Basis(Vector3.UP,yaw),Vector3.ZERO)*record.bounds
	actor.rotation.y = yaw
	actor.position = Vector3(float(options.separation)*(-0.5 if team==0 else 0.5)*side-bounds.get_center().x,0.1-bounds.position.y,-bounds.get_center().z)
	actor.process_mode = Node.PROCESS_MODE_DISABLED
	actor.set_meta(&"low_target_fixture",team==1)
	host.add_child(actor)
	for part: PhysicalBodyPart3D in actor._get_physical_body_parts(): part.freeze = true
	return actor

func activate_creature(actor: Node3D) -> void:
	if actor.get_meta(&"low_target_fixture",false): return
	super.activate_creature(actor)

func _register_module(actor: Dictionary, node: Node, action: String, wolf: bool = false) -> void:
	if not actor.has("initial_parts"):
		actor.initial_parts = []
		for part: PhysicalBodyPart3D in actor.node._get_physical_body_parts():
			actor.initial_parts.append({"name":str(part.name),"hp":part.max_hp,"mass":part.base_combat_mass,"armor":part.armor,"resilience":part.resilience})
		actor.target_fixture = actor.team==1
	super._register_module(actor,node,action,wolf)

func _action_for_source(source: Node) -> int:
	var index := super._action_for_source(source)
	if index >= 0: return index
	var actor := _source_actor(source)
	if actor == null: return -1
	for row: Dictionary in modules:
		if row.actor.node != actor: continue
		if _active(row): return _ensure_action(row)
		index = maxi(index,int(last_actions.get(row.actor.id+":"+row.action,-1)))
	return index

func _on_attack_contact(details: Dictionary) -> void:
	if not collecting: return
	var source: Node = details.source
	var actor := _source_actor(source)
	var target := details.target as PhysicalBodyPart3D
	var copy := details.duplicate()
	copy.source = str(source.name)
	copy.target = str(target.get_path())
	copy.attacker = str(actor.name) if actor != null else ""
	copy.time = clock
	copy.action_index = _action_for_source(source)
	copy.target_hp_before = target.current_hp
	contacts.append(copy)

func sample() -> void:
	super.sample()
	if not collecting or completed: return
	var dead := false
	for row: Dictionary in actors:
		if not row.node.is_combat_alive(): dead = true
	if dead or clock>=float(options.seconds):
		completed = true
		options.end_reason = "first_death" if dead else "time_limit"
		options.requested_seconds = 35.0
		options.seconds = clock
		options.damage_contacts = contacts
		options.balance_revision = 2
		options.fixture = "stationary_saved_rat_with_normal_mass_health_defenses"
		for row: Dictionary in actors:
			row.final_parts = []
			for part: PhysicalBodyPart3D in row.node._get_physical_body_parts():
				row.final_parts.append({"name":str(part.name),"hp":part.current_hp,"broken":part.is_broken})

func run() -> void:
	var pair := str(options.get("pair","wolf,rat_1")).split(",")
	# Audio is validated separately; fast fixed-step physics must not leave unfinished mixer voices at shutdown.
	root.get_node("CombatAudio").settings = root.get_node("CombatAudio").settings.duplicate()
	root.get_node("CombatAudio").settings.enabled = false
	options.separation = (creature_bounds(creature_record(pair[0])).size.x+creature_bounds(creature_record(pair[1])).size.x)*0.5+float(options.gap)
	root.get_node("DamageService").attack_contact.connect(_on_attack_contact)
	await super.run()
