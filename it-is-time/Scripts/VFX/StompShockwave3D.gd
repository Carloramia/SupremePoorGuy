extends Node3D

const DATA = preload("res://Scripts/VFX/StompShockwaveData.gd")
const SHADER = preload("res://Shaders/StompShockwave.gdshader")
var data: DATA
var source_character: Node3D
var source_faction: int
var normal := Vector3.UP
var contact := Vector3.ZERO
var elapsed := 0.0
var hit_count := 0
var _hit: Dictionary = {}
var _material: ShaderMaterial
var _visual: MeshInstance3D
var impact_impulse := 0.0
var raw_impact_damage := 0.0

func setup(settings: DATA, source: Node3D, point: Vector3, surface_normal: Vector3, measured_impulse: float = 0.0) -> void:
	data = settings
	source_character = source
	source_faction = source.get_faction_id()
	contact = point
	normal = surface_normal.normalized() if not surface_normal.is_zero_approx() else Vector3.UP
	impact_impulse = maxf(measured_impulse,0.0) if is_finite(measured_impulse) else 0.0

func _ready() -> void:
	if data == null or not data.enabled or not data.is_valid(): queue_free(); return
	add_to_group(&"stomp_shockwaves")
	global_position = contact
	var service := get_tree().root.get_node_or_null("DamageService")
	if service != null: raw_impact_damage = service.calculate_raw_damage(impact_impulse*data.impulse_scale)
	var tangent := normal.cross(Vector3.FORWARD).normalized()
	if tangent.is_zero_approx(): tangent = normal.cross(Vector3.RIGHT).normalized()
	global_basis = Basis(tangent,normal,tangent.cross(normal))
	_visual = MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	_visual.mesh = sphere
	_visual.scale = Vector3.ONE*0.001
	_visual.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter(&"energy",data.emission_energy)
	_material.set_shader_parameter(&"wave_color",data.color)
	_visual.material_override = _material
	add_child(_visual)
	_log("spawn", "radius=%.2f contact=%s stomp_impulse=%.3f raw_damage=%.3f" % [data.radius,contact,impact_impulse,raw_impact_damage])

func _physics_process(delta: float) -> void:
	if data == null or _material == null: return
	elapsed += delta
	var progress := clampf(elapsed/data.duration,0.0,1.0)
	var radius := data.radius*progress
	_visual.scale = Vector3.ONE*maxf(radius,0.001)
	_material.set_shader_parameter(&"progress",progress)
	_material.set_shader_parameter(&"opacity",1.0-smoothstep(0.35,1.0,progress))
	for actor: Node in get_tree().get_nodes_in_group(&"physical_characters_3d"):
		if actor == source_character or actor.is_queued_for_deletion() or _hit.has(actor.get_instance_id()): continue
		if not actor.is_combat_alive() or actor.get_faction_id() == source_faction: continue
		var parts: Array = _parts(actor)
		var nearest: PhysicalBodyPart3D
		var nearest_point := Vector3.ZERO
		var distance := INF
		for part: PhysicalBodyPart3D in parts:
			if not is_instance_valid(part) or part.is_broken or part.is_queued_for_deletion(): continue
			var point := _nearest_surface_point(part)
			var offset := point-contact
			var spatial_distance := offset.length()
			if spatial_distance < distance:
				nearest = part; nearest_point = point; distance = spatial_distance
		if nearest == null or distance > radius or not _visible(actor,nearest_point): continue
		_hit[actor.get_instance_id()] = true
		hit_count += 1
		_strike(actor,parts,nearest,distance)
	if progress >= 1.0: queue_free()

func _parts(actor: Node) -> Array:
	var damage := actor.get_node_or_null("CharacterDamageController3D")
	return damage.get_parts() if damage != null else actor._get_physical_body_parts()

## Generated parts have boxes; measure from their shell rather than their center.
func _nearest_surface_point(part: PhysicalBodyPart3D) -> Vector3:
	for node: Node in part.get_children():
		if node is CollisionShape3D and not node.disabled and node.shape is BoxShape3D:
			var half: Vector3 = node.shape.size*0.5
			return node.to_global(node.to_local(contact).clamp(-half,half))
	return part.global_position

func _visible(actor: Node, point: Vector3) -> bool:
	if not data.require_line_of_sight: return true
	var excluded: Array[RID] = []
	for body: PhysicalBodyPart3D in _parts(actor):
		if is_instance_valid(body): excluded.append(body.get_rid())
	if is_instance_valid(source_character):
		for body: PhysicalBodyPart3D in _parts(source_character):
			if is_instance_valid(body): excluded.append(body.get_rid())
	var query := PhysicsRayQueryParameters3D.create(contact+normal*0.12,point+normal*0.12,data.obstacle_mask,excluded)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _strike(actor: Node3D, parts: Array, part: PhysicalBodyPart3D, distance: float) -> void:
	var strength := lerpf(1.0,data.edge_strength,clampf(distance/data.radius,0.0,1.0))
	var raw_damage := raw_impact_damage*strength
	var service := get_tree().root.get_node_or_null("DamageService")
	var hp_damage: float = service.apply_armor(raw_damage,part.armor) if service != null else 0.0
	var applied := part.apply_damage(hp_damage,source_character if is_instance_valid(source_character) else self)
	var torsos: Array[PhysicalBodyPart3D] = []
	var total_mass := 0.0
	var torso_mass := 0.0
	for body: PhysicalBodyPart3D in parts:
		if not is_instance_valid(body) or body.is_broken or body.freeze: continue
		total_mass += body.mass
		if 0 in body.tags: torsos.append(body); torso_mass += body.mass
	var direction: Vector3 = (actor.get_combat_anchor().global_position-contact).normalized()
	if direction.is_zero_approx(): direction = global_basis.x
	var impulse: Vector3 = (direction*data.outward_speed+normal*data.upward_speed)*total_mass*strength
	if not impulse.is_zero_approx() and torso_mass > 0.0:
		var module := actor.get_node_or_null("CreatureActionController3D")
		if module != null: module.cancel_action(&"shockwave_impact")
		for component: Node in actor.get_children():
			if component.has_method("release_support_for_impact"): component.release_support_for_impact(data.adhesion_release_time)
		for body: PhysicalBodyPart3D in torsos:
			body.sleeping = false
			body.apply_central_impulse(impulse*(body.mass/torso_mass))
	_log("hit", "target=%s part=%s distance=%.2f stomp_impulse=%.3f raw=%.2f armor=%.2f damage=%.2f knockback_impulse=%s" % [actor.name,part.name,distance,impact_impulse,raw_damage,part.armor,applied,impulse])

func _log(event: String, details: String) -> void:
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null and console.is_damage_tracking_enabled():
		print("[stomp_shockwave] event=",event," faction=",source_faction," ",details)
