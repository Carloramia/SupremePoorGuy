extends Node
## Region membership is counted per body, but effects are applied once per creature.
var host: Node3D
var unit_scale := 1.0
var zones: Array[Dictionary] = []
var owners := {}
var speeds := {}
var multipliers := {}
var elapsed := 0.0
var physics_time := 0.0

func configure(battle: Node3D, layout: Dictionary, scale: float) -> void:
	host = battle
	unit_scale = scale
	name = "BattleEnvironmentEffects"
	for actor: Node3D in battle.actors:
		var resources := {}
		for node: Node in actor.find_children("*","",true,false):
			if node is PhysicalBodyPart3D: owners[node] = actor
			for property: String in ["slow_gait_data","fast_gait_data","motion_data"]:
				var resource: Variant = node.get(property)
				if resource is Resource and resource.get("target_speed") is float: resources[resource] = resource.target_speed
		speeds[actor] = resources
		multipliers[actor] = 1.0
	for object: Dictionary in layout.objects:
		if object.type not in ["mud","thorns","web","collision_damage"]: continue
		var origin := battle._geometry.get_node("Objects/"+str(object.id)) as Node3D
		var area := origin.get_node_or_null("region") as Area3D
		# Unbound handoff references must not fall back to demo slow/control values.
		if bool(object.get("integration_unresolved",false)):
			if area!=null: area.monitoring=false
			if host.application!=null: host.application.session.trace("environment_effect_disabled",{"id":object.id,"effect_ref":object.get("effect_ref",""),"condition_ref":object.get("condition_ref","")})
			continue
		# Effect volumes use the authored region, never the paper model's concave mesh.
		var obstacle := origin.get_node_or_null("collision") as StaticBody3D
		if area==null and object.type=="collision_damage" and obstacle!=null:
			for collision: CollisionShape3D in obstacle.find_children("*","CollisionShape3D",true,false):
				area = Area3D.new()
				area.name = "DamageRegion"
				area.collision_layer = 0
				area.transform = collision.get_parent().transform
				var shape := CollisionShape3D.new()
				shape.shape = collision.shape
				shape.transform = collision.transform
				area.add_child(shape)
				origin.add_child(area)
				break
		if area==null: continue
		area.collision_mask = 0xFFFFFFFF
		area.monitoring = object.type!="collision_damage" or float(object.get("damage",0.0))>0.0
		if object.type=="web":
			var collision := area.get_node("Shape") as CollisionShape3D
			var shape := collision.shape.duplicate() as ConvexPolygonShape3D
			var points := shape.points
			for index: int in points.size(): points[index].y = float(object.get("max_height",6.0)) if points[index].y>0.0 else 0.0
			shape.points = points
			collision.shape = shape
		var zone := {"object":object,"area":area,"obstacle":obstacle,"bodies":{},"next_tick":0.0,"impact_next":{}}
		zones.append(zone)
		area.body_entered.connect(func(body): _entered(zone,body))
		area.body_exited.connect(func(body): _exited(zone,body))
		if area.monitoring:
			for body: Node3D in area.get_overlapping_bodies(): _entered(zone,body)

func _entered(zone: Dictionary, body: Node3D) -> void:
	if owners.has(body): zone.bodies[body] = owners[body]

func _exited(zone: Dictionary, body: Node3D) -> void:
	zone.bodies.erase(body)

func flying(actor: Node3D) -> bool:
	var controller := actor.find_child("BirdFlightController3D",true,false)
	return controller!=null and controller.has_method("is_airborne") and controller.is_airborne()

func _eligible(actor: Node3D, object: Dictionary) -> bool:
	if not is_instance_valid(actor) or not actor.is_combat_alive(): return false
	var airborne := flying(actor)
	var targets: String = object.get("targets","all")
	if targets=="flying" and not airborne or targets=="ground" and airborne: return false
	if object.type=="web":
		var anchor: Node3D = actor.get_combat_anchor()
		if anchor==null: return false
		var height := host.to_local(anchor.global_position).y/unit_scale
		if height<float(object.get("min_height",0.0)) or height>float(object.get("max_height",INF)): return false
	return true

func _physics_process(delta: float) -> void:
	if host.ended: return
	physics_time += delta
	for zone: Dictionary in zones:
		if zone.object.type!="collision_damage" or float(zone.object.get("damage",0.0))<=0.0: continue
		var members := {}
		for part: Variant in zone.bodies.keys():
			if not is_instance_valid(part) or part.is_broken: zone.bodies.erase(part); continue
			members[zone.bodies[part]] = true
		for actor: Node3D in members:
			if not _eligible(actor,zone.object) or physics_time<float(zone.impact_next.get(actor,0.0)): continue
			if _apply_collision_damage(zone,actor)>0.0: zone.impact_next[actor]=physics_time+maxf(float(zone.object.get("interval",1.0)),0.1)
	elapsed += delta
	if elapsed<0.1: return
	elapsed = 0.0
	var desired := {}
	for actor: Node3D in speeds: desired[actor] = 1.0
	for zone: Dictionary in zones:
		var members := {}
		for body: Variant in zone.bodies.keys():
			if not is_instance_valid(body) or body.is_broken: zone.bodies.erase(body); continue
			var actor: Node3D = zone.bodies[body]
			if _eligible(actor,zone.object): members[actor] = body
		var object: Dictionary = zone.object
		if object.type in ["mud","thorns"]:
			for actor: Node3D in members: desired[actor] = minf(desired[actor],clampf(1.0-float(object.get("slow_ratio",0.0)),0.0,1.0))
		var now := physics_time
		if now<float(zone.next_tick): continue
		zone.next_tick = now+maxf(float(object.get("interval",1.0)),0.1)
		for actor: Node3D in members:
			if object.type=="web": actor.apply_timed_hit_ragdoll(maxf(float(object.get("duration",1.0)),0.0))
			elif float(object.get("damage",0.0))>0.0:
				if object.type=="collision_damage": continue
				var part: PhysicalBodyPart3D = members[actor]
				var damage: float = get_node("/root/DamageService").apply_armor(float(object.damage),part.armor,part.resilience)
				part.apply_damage(damage,self)
	for actor: Node3D in desired: _set_speed(actor,desired[actor])

func _apply_collision_damage(zone: Dictionary, actor: Node3D) -> float:
	var impulse := 0.0
	var hit: PhysicalBodyPart3D
	for part: PhysicalBodyPart3D in zone.bodies:
		if zone.bodies[part]!=actor or part.is_broken: continue
		var state := PhysicsServer3D.body_get_direct_state(part.get_rid())
		if state==null: continue
		for index: int in state.get_contact_count():
			if state.get_contact_collider_object(index)!=zone.obstacle: continue
			var contact := state.get_contact_impulse(index).length()
			if contact>impulse: impulse=contact; hit=part
	return _apply_impact(hit,impulse,float(zone.object.damage)) if hit!=null else 0.0

func _apply_impact(part: PhysicalBodyPart3D, impulse: float, multiplier: float) -> float:
	var service := get_node("/root/DamageService")
	var raw: float = service.calculate_raw_damage(impulse)*multiplier
	return part.apply_damage(service.apply_armor(raw,part.armor,part.resilience),self)

func _set_speed(actor: Node3D, multiplier: float) -> void:
	if not is_instance_valid(actor) or is_equal_approx(float(multipliers[actor]),multiplier): return
	for resource: Resource in speeds[actor]: resource.target_speed = float(speeds[actor][resource])*multiplier
	multipliers[actor] = multiplier
	actor.set_meta(&"environment_speed_multiplier",multiplier)
	if host.application!=null: host.application.session.trace("environment_speed",{"actor":str(actor.name),"multiplier":multiplier})

func _exit_tree() -> void:
	for actor: Node3D in speeds: _set_speed(actor,1.0)
