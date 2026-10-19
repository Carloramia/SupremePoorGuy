extends Node3D
## One battle-local controller per actual actor. Never writes inventory or map progress.
const SETTINGS = preload("res://Resources/Application/DefaultSummonGameplay.tres")
var record: Dictionary = {}
var actor: Node3D
var shield := 0.0
var shield_remaining := 0.0
var elapsed := 0.0
var pending_revive := false
var revived := false
var _revive_remaining := 0.0
var _last_position := Vector3.ZERO
var _regen_remaining := 4.0
var _shield_period_remaining := 0.0
var _taunt_period_remaining := 2.0
var _taunt_remaining := 0.0
var _taunt_immunity := 0.0
var _taunted_by: WeakRef
var _eye_remaining := 1.0
var _beam_remaining := 0.0
var _beam: MeshInstance3D
var _eye_body: PhysicalBodyPart3D
var _burns: Dictionary = {}
var _heal_window := 0.0
var _healed_this_second := 0.0
var _support_remaining := 0.0
var _lost_before_death: Dictionary = {}

func _ready() -> void:
	actor = get_parent()
	actor.set_meta(&"summon_effects",self)
	revived = bool(record.get("combat_revival_used",false))
	_regen_remaining = SETTINGS.regeneration_period
	if record.get("magic_eye",false): _eye_body = add_eye_visual(actor)

static func owner_of(source: Node) -> Node3D:
	if not is_instance_valid(source): return null
	if source is SampleWeapon3D and is_instance_valid(source.wielder_character): return source.wielder_character
	var node: Node = source
	while node != null:
		if node.has_method("get_faction_id") and node.has_method("is_combat_alive"): return node as Node3D
		node = node.get_parent()
	return null

static func add_eye_visual(target: Node3D) -> PhysicalBodyPart3D:
	for node: Node in target.find_children("*","",true,false):
		if not node is PhysicalBodyPart3D or 3 not in node.tags: continue
		if node.has_node("SummonMagicEye"): return node
		var visual := MeshInstance3D.new()
		visual.name = "SummonMagicEye"
		var sphere := SphereMesh.new()
		sphere.radius=0.22; sphere.height=0.44
		visual.mesh=sphere
		visual.position=Vector3(0.0,0.2,0.35)
		var material := StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=Color("ef58bc")
		visual.material_override=material
		node.add_child(visual)
		return node
	return null

func has_relic(id: String) -> bool:
	return id in record.get("relic_ids",[])

func parts() -> Array:
	return actor._get_physical_body_parts()

func max_health() -> float:
	var total := 0.0
	for part: PhysicalBodyPart3D in parts(): total+=part.max_hp
	return total

func heal_amount(amount: float) -> float:
	if amount<=0.0 or not actor.is_combat_alive(): return 0.0
	var total := max_health()
	if total<=0.0: return 0.0
	var healed := 0.0
	for part: PhysicalBodyPart3D in parts():
		if part.is_broken: continue
		var gain := minf(part.max_hp-part.current_hp,amount*part.max_hp/total)
		part.current_hp+=gain
		healed+=gain
	return healed

func filter_damage(part: PhysicalBodyPart3D, amount: float) -> float:
	if shield_remaining>0.0 and shield>0.0:
		var absorbed := minf(shield,amount)
		shield-=absorbed
		amount-=absorbed
	if 0 not in part.tags and 3 not in part.tags:
		# Equivalent extra non-vital durability; it does not strengthen the shared shield.
		amount/=1.0+float(record.get("limb_durability_bonus",0.0))
	return amount

func on_dealt_damage(target: PhysicalBodyPart3D, amount: float, derived: bool) -> void:
	var enemy := owner_of(target)
	if amount<=0.0 or enemy==null or enemy.get_faction_id()==actor.get_faction_id(): return
	if has_relic("blood-crystal"):
		var cap := maxf(0.0,max_health()*SETTINGS.lifesteal_cap_per_second-_healed_this_second)
		_healed_this_second+=heal_amount(minf(amount*SETTINGS.lifesteal_ratio,cap))
	if derived: return
	var ratio := float(record.get("effects",{}).get("burn_ratio",0.0))
	if ratio>0.0:
		var receiver: Node = enemy.get_meta(&"summon_effects",null)
		if is_instance_valid(receiver): receiver.apply_burn(target,float(record.attack)*ratio,self)

func apply_burn(part: PhysicalBodyPart3D, dps: float, source: Node) -> void:
	# One strongest burn per creature, not one stack on every physical body part.
	var key := actor.get_instance_id()
	var previous: Dictionary = _burns.get(key,{})
	if previous.is_empty() or dps>=float(previous.dps):
		_burns[key]={"part":weakref(part),"dps":dps,"left":3.0,"tick":0.0,"source":weakref(source)}
	else:
		previous.left=3.0
		var previous_part: Node = previous.part.get_ref()
		if not is_instance_valid(previous_part) or previous_part.is_broken: previous.part=weakref(part)

func _actors() -> Array:
	var result: Array = []
	for other: Node3D in get_tree().get_nodes_in_group(&"physical_characters_3d"):
		if is_instance_valid(other) and other.is_inside_tree() and other.get_world_3d()==actor.get_world_3d() and other.is_combat_alive(): result.append(other)
	return result

func receive_taunt(source: Node3D) -> void:
	if _taunt_remaining>0.0 or _taunt_immunity>0.0: return
	if absf(source.get_combat_anchor().global_position.y-actor.get_combat_anchor().global_position.y)>3.0: return
	_taunted_by=weakref(source)
	_taunt_remaining=SETTINGS.taunt_duration
	_taunt_immunity=SETTINGS.taunt_duration+SETTINGS.taunt_immunity

func taunt_target() -> Node3D:
	if _taunt_remaining<=0.0 or _taunted_by==null: return null
	var target := _taunted_by.get_ref() as Node3D
	return target if is_instance_valid(target) and target.is_combat_alive() else null

func has_pending_return() -> bool:
	return has_relic("clockwork-box") and not revived

func capture_living_losses() -> void:
	if not has_pending_return() or not actor.is_combat_alive(): return
	var living_head := false
	var living_torso := false
	for part: PhysicalBodyPart3D in parts():
		if part.is_broken: continue
		living_head = living_head or 3 in part.tags
		living_torso = living_torso or 0 in part.tags
	if not living_head or not living_torso: return
	_lost_before_death.clear()
	for part: PhysicalBodyPart3D in parts():
		# Necessary head/core/connectors may be restored; unrelated lost limbs are not.
		if part.is_broken and 0 not in part.tags and 3 not in part.tags and 6 not in part.tags:
			_lost_before_death[str(actor.get_path_to(part))]=true

func _physics_process(delta: float) -> void:
	if not is_instance_valid(actor) or actor.get_meta(&"summon_presentation",false): return
	if not actor.is_combat_alive():
		if has_pending_return():
			if not pending_revive: pending_revive=true; _revive_remaining=SETTINGS.revival_delay
			_revive_remaining-=delta
			if _revive_remaining<=0.0: _revive()
		return
	elapsed+=delta
	_last_position=actor.get_combat_anchor().global_position
	capture_living_losses()
	_heal_window+=delta
	if _heal_window>=1.0: _heal_window=fmod(_heal_window,1.0); _healed_this_second=0.0
	shield_remaining=maxf(0.0,shield_remaining-delta)
	if shield_remaining<=0.0: shield=0.0
	_taunt_remaining=maxf(0.0,_taunt_remaining-delta)
	_taunt_immunity=maxf(0.0,_taunt_immunity-delta)
	if has_relic("moss-heart"):
		_regen_remaining-=delta
		if _regen_remaining<=0.0: _regen_remaining+=SETTINGS.regeneration_period; heal_amount(max_health()*SETTINGS.regeneration_ratio)
	if has_relic("shell-carving"):
		_shield_period_remaining-=delta
		if _shield_period_remaining<=0.0:
			_shield_period_remaining+=SETTINGS.shield_period
			shield=max_health()*SETTINGS.shield_ratio
			shield_remaining=SETTINGS.shield_duration
	_support_remaining-=delta
	if _support_remaining<=0.0:
		_support_remaining=0.20
		_update_support()
	if has_relic("taunt-bell"):
		_taunt_period_remaining-=delta
		if _taunt_period_remaining<=0.0:
			_taunt_period_remaining+=SETTINGS.taunt_period
			for other: Node3D in _actors():
				if other.get_faction_id()==actor.get_faction_id() or other.get_combat_anchor().global_position.distance_to(_last_position)>SETTINGS.support_range: continue
				var effects: Node = other.get_meta(&"summon_effects",null)
				if is_instance_valid(effects): effects.receive_taunt(actor)
	_tick_burns(delta)
	if record.get("magic_eye",false):
		_eye_remaining-=delta
		_beam_remaining=maxf(0.0,_beam_remaining-delta)
		if is_instance_valid(_beam): _beam.visible=_beam_remaining>0.0
		if _eye_remaining<=0.0: _eye_remaining=SETTINGS.eye_cooldown; fire_eye()

func _update_support() -> void:
	var bonus := 0.0
	for other: Node3D in _actors():
		if other==actor or other.get_faction_id()!=actor.get_faction_id(): continue
		if other.get_combat_anchor().global_position.distance_to(_last_position)>SETTINGS.support_range: continue
		var effects: Node = other.get_meta(&"summon_effects",null)
		if is_instance_valid(effects) and effects.has_relic("propaganda-banner"): bonus=SETTINGS.support_attack_bonus; break
	actor.set_meta(&"summon_damage_multiplier",float(record.get("damage_multiplier",1.0))*(1.0+bonus))

func _tick_burns(delta: float) -> void:
	for key: int in _burns.keys():
		var burn: Dictionary = _burns[key]
		var part: PhysicalBodyPart3D = burn.part.get_ref()
		var source: Node = burn.source.get_ref()
		if not is_instance_valid(part) or part.is_broken or not is_instance_valid(source): _burns.erase(key); continue
		burn.tick+=delta
		burn.left-=delta
		if burn.tick>=0.5:
			var service: Node = get_node("/root/DamageService")
			part.apply_damage(service.apply_armor(float(burn.dps)*0.5,part.armor,part.resilience),source)
			burn.tick-=0.5
		if burn.left<=0.0: _burns.erase(key)

func fire_eye() -> float:
	if not is_instance_valid(_eye_body) or _eye_body.is_broken or not actor.is_combat_alive(): return 0.0
	var origin := _eye_body.global_position
	var nearest: Node3D
	var best := SETTINGS.eye_range
	for other: Node3D in _actors():
		if other.get_faction_id()==actor.get_faction_id(): continue
		var distance: float = other.get_combat_anchor().global_position.distance_to(origin)
		if distance<best: best=distance; nearest=other
	if nearest==null: return 0.0
	var target: Node3D = nearest.get_combat_anchor()
	var excluded: Array[RID] = []
	for part: PhysicalBodyPart3D in parts(): excluded.append(part.get_rid())
	var query := PhysicsRayQueryParameters3D.create(origin,target.global_position,0xFFFFFFFF,excluded)
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty() or not hit.collider is PhysicalBodyPart3D: return 0.0
	var victim := hit.collider as PhysicalBodyPart3D
	if owner_of(victim)!=nearest: return 0.0
	if not is_instance_valid(_beam):
		_beam=MeshInstance3D.new()
		_beam.name="MagicEyeBeam"
		var cylinder := CylinderMesh.new()
		cylinder.top_radius=0.035; cylinder.bottom_radius=0.035; cylinder.height=1.0
		_beam.mesh=cylinder
		var material := StandardMaterial3D.new()
		material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color=Color("ff56b8")
		_beam.material_override=material
		add_child(_beam)
		_beam.top_level=true
	var end: Vector3 = hit.position
	var direction := end-origin
	if direction.length()<0.001: return 0.0
	_beam.global_transform=Transform3D(Basis(Quaternion(Vector3.UP,direction.normalized())).scaled(Vector3(1,direction.length(),1)),(origin+end)*0.5)
	_beam.visible=true
	_beam_remaining=0.12
	var service: Node = get_node("/root/DamageService")
	return victim.apply_damage(service.apply_armor(float(record.attack)*SETTINGS.eye_attack_ratio,victim.armor,victim.resilience),self)

func _revive() -> void:
	var host := actor.get_parent() as Node3D
	if host==null: return
	var revived_record := record.duplicate(true)
	revived_record.combat_revival_used=true
	var factory = load("res://Scripts/Application/CreatureFactory.gd")
	var replacement: Node3D = factory.spawn(revived_record,host,_last_position,actor.get_faction_id(),actor.rotation.y)
	if replacement==null: return
	var effects: Node = replacement.get_meta(&"summon_effects",null)
	if is_instance_valid(effects):
		effects.elapsed=elapsed
		effects._regen_remaining=_regen_remaining
		effects._shield_period_remaining=_shield_period_remaining
		effects._taunt_period_remaining=_taunt_period_remaining
		effects._eye_remaining=_eye_remaining
		effects._taunt_remaining=_taunt_remaining
		effects._taunt_immunity=_taunt_immunity
		effects._taunted_by=_taunted_by
		effects.shield=shield
		effects.shield_remaining=shield_remaining
		effects._heal_window=_heal_window
		effects._healed_this_second=_healed_this_second
	for part: PhysicalBodyPart3D in replacement._get_physical_body_parts():
		if _lost_before_death.has(str(replacement.get_path_to(part))):
			part.is_broken=true
			part.current_hp=0.0
		else: part.current_hp=part.max_hp*SETTINGS.revival_health_ratio
	# Death already drops equipment through the inventory controller; never mint a second copy.
	for property: Dictionary in replacement.get_property_list():
		if property.name=="initial_weapon_scene": replacement.set("initial_weapon_scene",null)
	for connection: Node in replacement.get_body_connections():
		var first := connection.get_node_or_null(connection.node_a) as PhysicalBodyPart3D
		var second := connection.get_node_or_null(connection.node_b) as PhysicalBodyPart3D
		if (first!=null and first.is_broken) or (second!=null and second.is_broken): connection.queue_free()
	for property: Dictionary in host.get_property_list():
		if property.name!="actors": continue
		var actors: Variant = host.get("actors")
		if actors is Array:
			var index: int = actors.find(actor)
			if index>=0: actors[index]=replacement
	factory.activate(replacement)
	revived=true
	actor.queue_free()
