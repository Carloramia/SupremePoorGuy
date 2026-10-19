extends SceneTree
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var failures := 0
var checks := 0
class Host extends Node3D:
	var actors: Array[Node3D] = []

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok: failures+=1; push_error("FAIL: "+label)

func _initialize() -> void: call_deferred("run")

func spawn(host: Host, name_text: String, faction: int, at: Vector3, extra: Dictionary = {}) -> Node3D:
	var record := FACTORY.template("human")
	record.merge({"id":name_text,"relic_ids":[],"effects":{},"magic_eye":false},true)
	record.merge(extra,true)
	var actor := FACTORY.spawn(record,host,at,faction)
	host.actors.append(actor)
	return actor

func health(actor: Node3D) -> float:
	var total := 0.0
	for part: PhysicalBodyPart3D in actor._get_physical_body_parts(): total+=part.current_hp
	return total

func run() -> void:
	var host := Host.new()
	root.add_child(host)
	var attacker := spawn(host,"attacker",0,Vector3(0,10,0),{"relic_ids":["blood-crystal"],"effects":{"burn_ratio":0.12},"magic_eye":true})
	var target := spawn(host,"target",1,Vector3(12,10,0),{"limb_durability_bonus":0.4})
	await physics_frame
	await physics_frame
	var attack: Node = attacker.get_meta(&"summon_effects")
	attack.record.attack=400.0 # Keep burn ticks above this fixture's flat armor.
	var defense: Node = target.get_meta(&"summon_effects")
	var torso: PhysicalBodyPart3D
	var limb: PhysicalBodyPart3D
	var head: PhysicalBodyPart3D
	for part: PhysicalBodyPart3D in target._get_physical_body_parts():
		if 0 in part.tags: torso=part
		elif 3 in part.tags: head=part
		else: limb=part
	check(torso!=null and limb!=null and head!=null,"Fixture has core, head and limb")
	check(is_equal_approx(defense.filter_damage(limb,14.0),10.0),"Fortitude gives effective nonfatal durability")
	check(is_equal_approx(defense.filter_damage(head,14.0),14.0) and is_equal_approx(defense.filter_damage(torso,14.0),14.0),"Fortitude never protects vital head/core")
	for part: PhysicalBodyPart3D in attacker._get_physical_body_parts(): part.current_hp=part.max_hp*0.5
	var start_hp := health(attacker)
	attack.on_dealt_damage(torso,10.0,false)
	check(is_equal_approx(health(attacker)-start_hp,2.0),"Lifesteal heals 20 percent of actual enemy HP damage")
	attack.on_dealt_damage(torso,1e9,true)
	check(is_equal_approx(health(attacker)-start_hp,attack.max_health()*0.03),"Lifesteal per-second cap applies across hits")
	start_hp=health(attacker)
	attack.on_dealt_damage(attacker._get_physical_body_parts()[0],100.0,false)
	check(is_equal_approx(health(attacker),start_hp),"Friendly/self hits do not lifesteal")
	check(defense._burns.size()==1,"Basic hit applies burn to receiver")
	defense.apply_burn(limb,1.0,attack)
	check(defense._burns.size()==1 and defense._burns.values()[0].dps==48.0,"Different limbs cannot stack burns; strongest burn is retained")
	var burned_hp := torso.current_hp
	for tick: int in 6: defense._tick_burns(0.5)
	check(torso.current_hp<burned_hp and defense._burns.is_empty(),"Burn deals actual HP damage and expires after three seconds")
	defense.record.relic_ids=["shell-carving"]
	defense._physics_process(0.01)
	check(defense.shield>0.0 and defense.shield_remaining>0.0,"Shell opens a shared timed shield")
	var shield: float = defense.shield
	var applied := torso.apply_damage(shield*0.5,attacker)
	check(is_zero_approx(applied) and is_equal_approx(defense.shield,shield*0.5),"Shield-only hit is not HP damage")
	defense._physics_process(4.1)
	check(is_zero_approx(defense.shield),"Unused shield expires, not stored")
	defense.record.relic_ids=["moss-heart"]
	torso.current_hp=torso.max_hp*0.5
	var before := health(target)
	defense._regen_remaining=0.01
	defense._physics_process(0.02)
	check(health(target)>before,"Moss heart heals living parts")
	defense.receive_taunt(attacker)
	check(defense.taunt_target()==attacker,"Taunt supplies a valid living enemy target")
	defense._physics_process(2.1)
	check(defense.taunt_target()==null,"Taunt target expires")
	defense.receive_taunt(attacker)
	check(defense.taunt_target()==null,"Taunt has temporary reapplication immunity")
	defense.record.relic_ids=[]
	defense.shield=0.0
	defense.shield_remaining=0.0
	var beam_damage: float = attack.fire_eye()
	check(beam_damage>0.0,"Eye ray hits an actual opposing physical body")
	var banner := spawn(host,"banner",0,attacker.position+Vector3(1,0,0),{"relic_ids":["propaganda-banner"]})
	await process_frame
	attack._last_position=attacker.get_combat_anchor().global_position
	attack._update_support()
	check(is_equal_approx(attacker.get_meta(&"summon_damage_multiplier"),1.08),"Nearby banner buffs another ally")
	var banner_effect: Node = banner.get_meta(&"summon_effects")
	banner_effect._last_position=banner.get_combat_anchor().global_position
	banner_effect._update_support()
	check(is_equal_approx(banner.get_meta(&"summon_damage_multiplier"),1.0),"Banner does not buff itself")
	host.free()
	await process_frame
	await validate_revival()
	print("SUMMON_COMBAT_CHECKS=",checks," FAILURES=",failures)
	quit(0 if failures==0 else 1)

func validate_revival() -> void:
	var host := Host.new()
	root.add_child(host)
	var actor := spawn(host,"revival",0,Vector3(0,10,0),{"relic_ids":["clockwork-box"]})
	await process_frame
	var effects: Node = actor.get_meta(&"summon_effects")
	effects._last_position=actor.get_combat_anchor().global_position
	var lost: PhysicalBodyPart3D
	for part: PhysicalBodyPart3D in actor._get_physical_body_parts():
		if 12 in part.tags: lost=part; break
	check(lost!=null,"Revival fixture has a nonfatal arm")
	if lost==null: host.free(); return
	var lost_path := actor.get_path_to(lost)
	lost.break_part()
	await process_frame
	check(actor.is_combat_alive(),"Losing an arm does not end the actor")
	for part: PhysicalBodyPart3D in actor._get_physical_body_parts():
		if 3 in part.tags: part.break_part()
	await process_frame
	check(not actor.is_combat_alive() and effects.has_pending_return(),"Dead actor keeps battle pending for clockwork return")
	effects._regen_remaining=2.5
	effects._physics_process(2.1)
	var replacement: Node3D = host.actors[0]
	check(replacement!=actor and replacement.is_combat_alive(),"Clockwork restores a new live actor with the same creature ID")
	replacement.process_mode=Node.PROCESS_MODE_DISABLED
	var returned: Node = replacement.get_meta(&"summon_effects")
	check(not returned.has_pending_return() and is_equal_approx(returned._regen_remaining,2.5),"Revival is once per battle and does not reset other cooldowns")
	check(replacement.get_node(lost_path).is_broken,"Previously lost unrelated arm is not regenerated")
	await process_frame
	host.free()
	await process_frame
