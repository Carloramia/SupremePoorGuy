extends "res://Tests/Integration/SimulateCreatureMelee.gd"
## Same NPCs/physics as production; the probe delegates every numeric damage result unchanged.

class ArmorProbe:
	extends Resource
	var delegate: Resource
	var last: Dictionary = {}
	var serial := 0
	func calculate_raw_damage(impulse: float) -> float:
		return delegate.calculate_raw_damage(impulse)
	func calculate_weapon_raw_damage(impulse: float, swinging: bool) -> float:
		return delegate.calculate_weapon_raw_damage(impulse,swinging)
	func apply_armor(raw: float, armor: float) -> float:
		var result: float = delegate.apply_armor(raw,armor)
		_record(raw,armor,result,raw,"shockwave")
		return result
	func apply_weapon_armor(raw: float, armor: float, swinging: bool) -> float:
		var result: float = delegate.apply_weapon_armor(raw,armor,swinging)
		var unarmored: float = delegate.apply_weapon_armor(raw,0.0,swinging)
		_record(raw,armor,result,unarmored,"swing" if swinging else "passive")
		return result
	func _record(raw: float, armor: float, result: float, unarmored: float, kind: String) -> void:
		serial += 1
		last = {"evaluation":serial,"frame":Engine.get_physics_frames(),"raw":raw,"armor":armor,
			"after_armor":result,"without_armor":unarmored,"profile":kind}

var probe := ArmorProbe.new()
var requested_seconds := 120.0
var ended_by_death := false
var audit_events := 0

func _initialize() -> void:
	options.merge({"mode":"duel","seconds":120.0,"gap":60.0,"armor":"on","stop_on_death":"true"},true)
	super._initialize()

func run() -> void:
	assert(SPECIES==FACTORY.SUMMON_POOL,"Update benchmark population when the summon pool changes")
	requested_seconds = float(options.seconds)
	options["requested_seconds"] = requested_seconds
	options["benchmark_schema"] = 1
	options["rune_modifiers"] = false
	options["source_hashes"] = {}
	for path: String in ["res://Scripts/Items/SampleWeapon3D.gd","res://Scripts/Damage/DamageRules.gd","res://Resources/Damage/DefaultDamageRules.tres","res://Scripts/Application/CreatureFactory.gd","res://Scripts/Creatures/NPCStateMachine3D.gd"]:
		options.source_hashes[path] = FileAccess.get_sha256(path)
	var service: Node = root.get_node("DamageService")
	probe.delegate = service.active_rules
	options["damage_rules"] = {}
	for property: Dictionary in probe.delegate.get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and property.usage & PROPERTY_USAGE_STORAGE:
			options.damage_rules[property.name] = probe.delegate.get(property.name)
	assert(service.set_active_rules(probe))
	if str(options.mode)=="duel":
		var pair := str(options.get("pair","wolf,snake")).split(",")
		var a: AABB = FACTORY.local_bounds(FACTORY.template(pair[0]))
		var b: AABB = FACTORY.local_bounds(FACTORY.template(pair[1]))
		options.separation = (a.size.x+b.size.x)*0.5+float(options.gap)
	await super.run()
	service.set_active_rules(probe.delegate)

func _register_module(actor: Dictionary, node: Node, action: String, wolf: bool = false) -> void:
	if not actor.has("initial_parts"):
		actor["initial_parts"] = []
		for part: PhysicalBodyPart3D in actor.node._get_physical_body_parts():
			if str(options.armor)=="off": part.armor = 0.0
			actor.initial_parts.append({"name":str(part.name),"hp":part.max_hp,"armor":part.armor,"tags":part.tags.duplicate(),"mass":part.mass})
	super._register_module(actor,node,action,wolf)

func _on_damage(amount: float, hp: float, source: Node, actor: Dictionary, part: PhysicalBodyPart3D) -> void:
	var before := damage_events.size()
	super._on_damage(amount,hp,source,actor,part)
	if damage_events.size()==before: return
	var evaluation := probe.last.duplicate()
	var hp_before := hp+amount
	var matched: bool = not evaluation.is_empty() and evaluation.frame==Engine.get_physics_frames() and is_equal_approx(float(evaluation.armor),part.armor) and is_equal_approx(minf(float(evaluation.after_armor),hp_before),amount)
	assert(matched,"Damage telemetry did not match the synchronous HP event")
	var event: Dictionary = damage_events[-1]
	event.merge(evaluation,true)
	event["hp_before"] = hp_before
	event["armor_absorbed"] = minf(float(evaluation.raw),maxf(part.armor,0.0))
	event["passive_suppression"] = maxf(float(evaluation.raw)-float(event.armor_absorbed)-float(evaluation.after_armor),0.0)
	event["overkill"] = maxf(float(evaluation.after_armor)-amount,0.0)
	event["effective_armor_hp_saved"] = minf(float(evaluation.without_armor),hp_before)-amount
	assert(is_equal_approx(float(evaluation.raw),amount+float(event.armor_absorbed)+float(event.passive_suppression)+float(event.overkill)),"Damage decomposition must reconcile")
	audit_events += 1

func sample() -> void:
	super.sample()
	if not collecting: return
	var dead := 0
	for actor: Dictionary in actors:
		if not actor.node.is_combat_alive():
			dead += 1
			if actor.death_time==null: actor.death_time = clock
	if dead>0 and str(options.stop_on_death)=="true":
		ended_by_death = true
		options["end_reason"] = "first_death"
		options.seconds = clock
	else:
		options["end_reason"] = "time_limit"
	if ended_by_death or clock>=requested_seconds:
		for actor: Dictionary in actors:
			actor["final_parts"] = []
			actor["remaining_hp"] = 0.0
			for part: PhysicalBodyPart3D in actor.node._get_physical_body_parts():
				actor.final_parts.append({"name":str(part.name),"hp":part.current_hp,"broken":part.is_broken})
				actor.remaining_hp += part.current_hp
	options["audited_damage_events"] = audit_events
