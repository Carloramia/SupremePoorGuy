extends Node3D
## Saved parts erupt separately and assemble in an isolated presentation; no combat AI.
signal finished
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const TEXT = preload("res://Scripts/Localization/GameText.gd")
const FLIGHT_DAMPING := 0.2
var settings: Resource
var creatures: Array[Dictionary] = []
var pieces: Array[Dictionary] = []
var phase := "stopped"
var elapsed := 0.0
var paused := false
var rng := RandomNumberGenerator.new()
var _records: Array = []
var _occupied: Array[AABB] = []
var emission_radius := 0.0
var _largest := Vector3(8,8,2)
var _sources: Array[RigidBody3D] = []
var _decorations_remaining := -1
var _next_creature := 0
var _next_decoration_time := 0.0
var decorations_emitted := 0
var last_decoration_time := -1.0
var summon_complete_time := -1.0
var _arena_size := Vector3(120,1,80)
var _arena_initialized := false
var _maximum_height := 10.0
var _aspect := 1.7
var _reveal_elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()

func configure(records: Array, configuration: Resource) -> void:
	settings = configuration
	_records = records.duplicate(true)
	$Preparing.text = TEXT.text("正在准备召唤部件…")
	var footprint_area := 0.0
	for record: Dictionary in _records:
		if not FACTORY.valid_record(record): continue
		var size := FACTORY.local_bounds(record).size
		_largest = _largest.max(size)
		footprint_area += (size.x+settings.creature_spacing)*(size.z+settings.creature_spacing)
	emission_radius = settings.emission_radius if settings.emission_radius>0.0 else maxf(8.0,sqrt(footprint_area/PI)*1.8)
	_resize_arena()
	phase = "preparing"

func _resize_arena() -> void:
	_maximum_height = _largest.y
	frame_camera(_aspect)

func _fit_ground_to_camera(camera: Camera3D) -> void:
	var drift_margin: float = maxf(settings.horizontal_speed*settings.free_motion_duration,settings.part_spawn_radius)+6.0
	var next_size: Vector3 = (Vector3.ONE*2.0*(emission_radius+drift_margin)+_largest).max(Vector3(120,1,80))
	var tangent := tan(deg_to_rad(camera.fov)*0.5)
	# Extend the ground past the four view rays, independently of the activity framing.
	for x: float in [-1.0,1.0]:
		for y: float in [-1.0,1.0]:
			var ray := camera.global_basis*Vector3(x*tangent*_aspect,y*tangent,-1.0)
			if ray.y >= -0.01: continue # Sky-facing rays blend into the black background instead of a finite floor.
			var point := camera.global_position-ray*(camera.global_position.y/ray.y)
			next_size.x = maxf(next_size.x,(absf(point.x)+8.0)*2.0)
			next_size.z = maxf(next_size.z,(absf(point.z)+8.0)*2.0)
	next_size.y = 1.0
	var wall_height := _maximum_height+20.0
	if _arena_initialized and next_size.is_equal_approx(_arena_size) and is_equal_approx($BoundaryWalls/Left/CollisionShape3D.shape.size.y,wall_height): return
	_arena_size = next_size
	_arena_initialized = true
	$Ground/CollisionShape3D.shape.size = _arena_size
	$Ground/Mesh.mesh.size = _arena_size
	var ground_material := $Ground/Mesh.mesh.material as ShaderMaterial
	if ground_material != null: ground_material.set_shader_parameter("ground_half_size",Vector2(_arena_size.x,_arena_size.z)*0.5)
	for wall: StaticBody3D in $BoundaryWalls.get_children():
		var side_wall := wall.name in [&"Left",&"Right"]
		var side := -1.0 if wall.name in [&"Left",&"Back"] else 1.0
		wall.position = Vector3(side*(_arena_size.x*0.5+1),wall_height*0.5-2,0) if side_wall else Vector3(0,wall_height*0.5-2,side*(_arena_size.z*0.5+1))
		wall.get_node("CollisionShape3D").shape.size = Vector3(2,wall_height,_arena_size.z+4) if side_wall else Vector3(_arena_size.x+4,wall_height,2)
	$TerrainCursor3D.world_horizontal_bounds = Rect2(Vector2(-_arena_size.x,-_arena_size.z)*0.5+Vector2.ONE,Vector2(_arena_size.x,_arena_size.z)-Vector2.ONE*2)
	$TerrainCursor3D.probe_height = wall_height+5.0
	$TerrainCursor3D.probe_depth = wall_height+10.0

func frame_camera(aspect: float) -> void:
	_aspect = maxf(aspect,0.1)
	var rig := $DragCamera3D
	var camera: Camera3D = rig.get_camera()
	var center: Vector3 = rig.global_position
	var inverse := camera.global_basis.inverse()
	var radius: float = emission_radius+settings.part_spawn_radius
	var tangent := tan(deg_to_rad(camera.fov)*0.5)
	var distance := 1.0
	var ceiling: float = _maximum_height+pow(settings.maximum_upward_speed,2)/19.6+4.0
	var points := PackedVector3Array()
	for x: float in [-radius,radius]:
		for z: float in [-radius,radius]:
			for y: float in [0.0,ceiling]:
				points.append(Vector3(x,y,z))
	for creature: Dictionary in creatures:
		var bounds := _creature_envelope(creature,true)
		for corner: int in 8: points.append(bounds.get_endpoint(corner))
	for point: Vector3 in points:
		var projected: Vector3 = inverse*(point-center)
		distance = maxf(distance,projected.z+maxf(absf(projected.x)/(tangent*_aspect),absf(projected.y)/tangent))
	rig.maximum_distance = maxf(50.0,distance*2.0)
	rig.set_distance(distance*1.05)
	camera.far = maxf(2000.0,rig.maximum_distance*2.0)
	_fit_ground_to_camera(camera)

func prepare_frame() -> void:
	if paused or phase != "preparing": return
	var deadline := Time.get_ticks_usec()+int(maxf(settings.preparation_budget_ms,1.0)*1000.0)
	while Time.get_ticks_usec() < deadline:
		if creatures.size() < _records.size():
			_prepare_creature(_records[creatures.size()])
			return # A whole scene is the largest indivisible preparation job.
		if _decorations_remaining < 0:
			_decorations_remaining = mini(ceili(_sources.size()*settings.wrong_part_ratio),settings.maximum_wrong_parts)
		if _decorations_remaining > 0 and not _sources.is_empty():
			_prepare_decoration(_sources[rng.randi_range(0,_sources.size()-1)])
			_decorations_remaining -= 1
		else:
			_sources.clear()
			_records.clear()
			_resize_arena()
			$Preparing.hide()
			phase = "burst"
			return

func _prepare_creature(record: Dictionary) -> void:
	var bounds := FACTORY.local_bounds(record)
	var origin := Vector3(-bounds.get_center().x,0.12-bounds.position.y,-bounds.get_center().z)
	var actor := FACTORY.spawn(record,$Creatures,origin,0)
	actor.hide()
	actor.set_meta(&"summon_presentation",true)
	actor.remove_from_group(&"physical_characters_3d")
	# Preserve endpoints, but remove solver connections before scattering any body.
	var joints: Array[Dictionary] = []
	for joint: Joint3D in actor.find_children("*","Joint3D",true,false):
		joints.append({"node":joint,"a":joint.node_a,"b":joint.node_b})
		joint.node_a = NodePath()
		joint.node_b = NodePath()
		if joint.has_meta(&"spider_root_anchor"): joint.remove_meta(&"spider_root_anchor")
	if actor.has_method("_clear_spider_root_anchors"): actor._clear_spider_root_anchors()
	# Reuse the character's ragdoll ownership/cancellation, but keep all gameplay controllers disabled.
	actor.set_temporary_ragdoll(self,true)
	var parts: Array[Dictionary] = []
	var mass := 0.0
	for body: RigidBody3D in actor._get_physical_body_parts():
		body.set_meta(&"summon_presentation",true)
		body.remove_from_group(&"damage_components")
		body.process_mode = Node.PROCESS_MODE_ALWAYS
		body.set_process(false)
		body.disable_mode = CollisionObject3D.DISABLE_MODE_KEEP_ACTIVE
		body.ignore_limb_terrain = false
		body.surface_contact_tracking = true
		body.surface_contact_terrain_only = true
		body.lock_foot_pitch_roll = false
		body.axis_lock_angular_x = true
		body.axis_lock_angular_y = true
		body.axis_lock_angular_z = false
		body.axis_lock_linear_z = false
		body.gravity_scale = 1.0
		body.can_sleep = false
		body.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		body.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
		body.linear_damp = FLIGHT_DAMPING
		body.angular_damp = 0.8
		body.collision_layer = 0
		body.collision_mask = 0
		var rest := body.global_transform
		parts.append({"body":body,"rest":rest,"envelope":_body_envelope(body),
			"state":"waiting","launch_time":-1.0,"emerged_time":-1.0,"ground_time":-1.0,"attraction_time":-1.0,"arrival_time":-1.0,"stable_time":0.0})
		mass += body.mass
		_sources.append(body)
	var springs: Array[Dictionary] = []
	for node: Node in actor.find_children("*","",true,false):
		if node.has_method("is_segment_spring"):
			springs.append({"node":node,"mode":node.process_mode})
			node.process_mode = Node.PROCESS_MODE_DISABLED
	parts.sort_custom(func(a,b):
		var first := _part_order(a.body)
		var second := _part_order(b.body)
		return first < second if first != second else String(a.body.get_path()).naturalnocasecmp_to(String(b.body.get_path())) < 0)
	var creature := {"actor":actor,"record_id":record.id,"parts":parts,"joints":joints,"springs":springs,
		"state":"waiting","mass":mass,"bounds":bounds,"launch_time":-1.0,"idle_time":-1.0,"next_part":0}
	var envelope := _creature_envelope(creature)
	_largest = _largest.max(Vector3(maxf(absf(envelope.position.x),absf(envelope.end.x))*2.0,envelope.size.y,maxf(absf(envelope.position.z),absf(envelope.end.z))*2.0))
	var point := _choose_position(envelope)
	creature["emission_point"] = point
	_occupied.append(_footprint(envelope,point))
	var shift := Vector3(point.x,0,point.y)
	for part: Dictionary in parts:
		part.rest.origin += shift
		part.body.global_transform = part.rest
		part.body.hide()
	var label := Label3D.new()
	label.text = TEXT.creature_name(record)
	label.font_size = 42
	label.pixel_size = 0.035
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.hide()
	add_child(label)
	creature["label"] = label
	creatures.append(creature)

func _ground_bounds() -> AABB:
	var collision: CollisionShape3D = $Ground/CollisionShape3D
	return collision.global_transform*AABB(-collision.shape.size*0.5,collision.shape.size)

func _body_envelope(body: RigidBody3D) -> AABB:
	var result := AABB()
	var first := true
	for child: Node3D in body.find_children("*","Node3D",true,false):
		var box: AABB
		if child is CollisionShape3D and not child.disabled and child.shape != null:
			box = child.shape.get_debug_mesh().get_aabb()
		elif child is GeometryInstance3D and (child is MeshInstance3D or child is Sprite3D):
			var ancestor: Node = child
			var shown := true
			while ancestor != body:
				if ancestor is Node3D: shown = shown and ancestor.visible
				ancestor = ancestor.get_parent()
			if not shown: continue
			box = child.get_aabb()
		else: continue
		box = _relative_transform(child,body)*box
		result = box if first else result.merge(box)
		first = false
	return result

func _creature_envelope(creature: Dictionary, rest := false) -> AABB:
	var result := AABB()
	var first := true
	for part: Dictionary in creature.parts:
		var pose: Transform3D = part.rest if rest else part.body.global_transform
		var box: AABB = pose*part.envelope
		result = box if first else result.merge(box)
		first = false
	return result

func _footprint(bounds: AABB, offset := Vector2.ZERO) -> AABB:
	var margin: float = settings.creature_spacing*0.5
	return AABB(Vector3(bounds.position.x+offset.x-margin,0,bounds.position.z+offset.y-margin),Vector3(bounds.size.x+margin*2,1,bounds.size.z+margin*2))

func _obstacles(ignore: int) -> Array[AABB]:
	var obstacles: Array[AABB] = []
	for index: int in _occupied.size():
		if index == ignore: continue
		var box := _occupied[index]
		if index < creatures.size() and creatures[index].state != "waiting":
			box = box.merge(_footprint(_creature_envelope(creatures[index])))
		obstacles.append(box)
	return obstacles

func _random_point(radius: float) -> Vector2:
	return Vector2.from_angle(rng.randf()*TAU)*sqrt(rng.randf())*radius

func _choose_position(bounds: AABB, ignore := -1, preferred := Vector2(INF,INF)) -> Vector2:
	var obstacles := _obstacles(ignore)
	for expansion: int in 8:
		for attempt: int in 128:
			var point := preferred if expansion==0 and attempt==0 and preferred.is_finite() else _random_point(emission_radius)
			if point.length()>emission_radius: continue
			var box := _footprint(bounds,point)
			if not obstacles.any(func(used): return box.intersects(used)): return point
		emission_radius = emission_radius*1.25+1.0
	# A random direction beyond every reserved footprint guarantees bounded preparation work.
	var radius := 0.0
	for box: AABB in obstacles:
		for corner: int in 8:
			var point := box.get_endpoint(corner)
			radius = maxf(radius,Vector2(point.x,point.z).length())
	radius += Vector2(bounds.position.x,bounds.position.z).length()+Vector2(bounds.size.x,bounds.size.z).length()+settings.creature_spacing+1.0
	emission_radius = maxf(emission_radius,radius)
	return Vector2.from_angle(rng.randf()*TAU)*radius

func _part_order(body: PhysicalBodyPart3D) -> int:
	var tag := PhysicalBodyPart3D.BodyPartTag
	if body.get_meta(&"generated_role","")=="Neck" or String(body.get_meta(&"creature_part_key",body.name)).begins_with("Neck"): return 4
	if tag.SubTorso in body.tags: return 1
	if tag.Torso in body.tags: return 0
	if tag.LegLimb in body.tags or tag.ArmLimb in body.tags or tag.WingLimb in body.tags: return 2
	if tag.Leg in body.tags or tag.ForeLeg in body.tags or tag.Arm in body.tags: return 3
	if tag.Head in body.tags: return 5
	return 6

func _relative_transform(node: Node3D, ancestor: Node) -> Transform3D:
	var pose := Transform3D.IDENTITY
	var current: Node = node
	while current != ancestor:
		if current is Node3D: pose = current.transform*pose
		current = current.get_parent()
	return pose

func _prepare_decoration(source: RigidBody3D) -> void:
	var body := RigidBody3D.new()
	body.name = "DecorativePart"
	var visuals: Array[GeometryInstance3D] = []
	var bounds := AABB()
	var first := true
	for visual: GeometryInstance3D in source.find_children("*","GeometryInstance3D",true,false):
		var ancestor: Node = visual
		var shown := true
		while ancestor != source:
			if ancestor is Node3D: shown = shown and ancestor.visible
			ancestor = ancestor.get_parent()
		if not shown: continue
		if not (visual is MeshInstance3D or visual is Sprite3D): continue
		var copy := visual.duplicate(0) as GeometryInstance3D
		for child: Node in copy.get_children(): copy.remove_child(child); child.free()
		copy.set_script(null)
		copy.transform = _relative_transform(visual,source)
		var box: AABB = copy.transform*copy.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
		body.add_child(copy)
		visuals.append(copy)
	var factor: float = settings.decoration_size/maxf(maxf(bounds.size.x,bounds.size.y),bounds.size.z+0.001)
	for visual: GeometryInstance3D in visuals:
		visual.transform = Transform3D(visual.basis.scaled(Vector3.ONE*factor),(visual.position-bounds.get_center())*factor)
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = (bounds.size*factor).max(Vector3.ONE*0.08)
	body.add_child(shape)
	body.freeze = true
	body.collision_layer = 0
	body.collision_mask = 0
	body.axis_lock_angular_x = true
	body.axis_lock_angular_y = true
	body.gravity_scale = 1.0
	body.angular_damp = 0.2
	body.hide()
	$Decorations.add_child(body)
	pieces.append({"body":body,"visuals":visuals,"launched":false,"launch_time":-1.0,"emission_count":0,"age":0.0,"fade":0.0,"emerged_time":-1.0,"envelope":AABB(-shape.shape.size*0.5,shape.shape.size)})

func _physics_process(delta: float) -> void:
	if paused or phase in ["stopped","preparing","finished"]: return
	elapsed += delta
	if _next_creature < creatures.size() and (_next_creature==0 or elapsed-creatures[_next_creature-1].launch_time>=settings.creature_start_interval-0.000001):
		var creature: Dictionary = creatures[_next_creature]
		creature.launch_time = elapsed
		creature.actor.show()
		_change_state(creature,"assembling")
		_next_creature += 1
	for creature: Dictionary in creatures:
		if creature.state=="idle":
			_animate_creature_label(creature)
			continue
		if creature.state!="assembling": continue
		var next: int = creature.next_part
		if next < creature.parts.size() and (next==0 or elapsed-creature.parts[next-1].launch_time >= settings.part_interval-0.000001):
			_launch_part(creature,creature.parts[next])
			creature.next_part += 1
		for part: Dictionary in creature.parts:
			if part.state == "emerging":
				var bounds: AABB = part.body.global_transform*part.envelope
				if bounds.position.y >= _ground_bounds().end.y+settings.emergence_clearance:
					part.emerged_time = elapsed
					part["emergence_bounds"] = bounds
					part.body.collision_layer = 4
					part.body.collision_mask = 2
					_change_part_state(creature,part,"free_motion")
				else: _lift_emerging([part],part.upward_speed)
			if part.state == "free_motion":
				var contact: Dictionary = part.body.get_support_surface_contact()
				if not contact.is_empty() and int(contact.collider_id)==$Ground.get_instance_id():
					if part.ground_time<0.0:
						part.ground_time = elapsed
						part["ground_position"] = contact.position
						part["ground_normal"] = contact.normal
						part["ground_collider_id"] = contact.collider_id
					if elapsed-part.emerged_time>=settings.part_free_motion_duration:
						part.attraction_time = elapsed
						part.body.collision_layer = 0
						part.body.collision_mask = 0
						_change_part_state(creature,part,"attracting")
			if part.state == "attracting": _attract_part(creature,part,delta)
		if creature.parts.all(func(part): return part.state=="assembled"):
			_complete_creature(creature)
	var summoning: bool = _next_creature<creatures.size() or creatures.any(func(creature): return creature.state!="idle")
	if not summoning and summon_complete_time<0.0: summon_complete_time = elapsed
	_tick_decorations(delta,summoning)
	if _next_creature == creatures.size() and phase == "burst": phase = "settling"
	if not summoning and pieces.is_empty():
		phase = "reveal"
		_reveal_elapsed += delta
		if _reveal_elapsed >= settings.reveal_duration:
			phase = "finished"
			finished.emit()

func _launch_part(creature: Dictionary, part: Dictionary) -> void:
	var body: RigidBody3D = part.body
	var point: Vector2 = creature.emission_point+_random_point(settings.part_spawn_radius)
	body.global_transform = part.rest
	body.global_position.x = point.x
	body.global_position.z = point.y
	var bounds: AABB = body.global_transform*part.envelope
	body.global_position.y += _ground_bounds().position.y-settings.emergence_clearance-bounds.end.y
	part["emission_point"] = point
	part["initial_bounds"] = body.global_transform*part.envelope
	part["initial_basis"] = body.global_basis
	part["upward_speed"] = rng.randf_range(settings.minimum_upward_speed,settings.maximum_upward_speed)
	part.launch_time = elapsed
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = Vector3(rng.randf_range(-settings.part_horizontal_speed,settings.part_horizontal_speed),part.upward_speed,rng.randf_range(-settings.part_horizontal_speed,settings.part_horizontal_speed))
	body.angular_velocity = Vector3.ZERO
	body.show()
	_change_part_state(creature,part,"emerging")

func _complete_creature(creature: Dictionary) -> void:
	# All bodies are already exactly at saved poses; reconnect only in that reference frame.
	for connection: Dictionary in creature.joints:
		connection.node.node_a = connection.a
		connection.node.node_b = connection.b
	for spring: Dictionary in creature.springs: spring.node.process_mode = spring.mode
	creature.actor.set_temporary_ragdoll(self,false)
	for component: Node in creature.actor.get_control_components(): component.process_mode = Node.PROCESS_MODE_DISABLED
	for part: Dictionary in creature.parts:
		part.body.collision_layer = 4
		part.body.collision_mask = 2
	# Completed exhibition copies stay frozen in their authored idle pose, independent of gameplay forces.
	creature.idle_time = elapsed
	var envelope := _creature_envelope(creature,true)
	creature["label_target"] = Vector3(envelope.get_center().x,envelope.end.y+0.8,envelope.get_center().z)
	_animate_creature_label(creature)
	creature.label.show()
	_change_state(creature,"idle")

func _animate_creature_label(creature: Dictionary) -> void:
	var progress := clampf((elapsed-float(creature.idle_time))/maxf(settings.name_fade_in_duration,0.001),0.0,1.0)
	var eased := 1.0-pow(1.0-progress,3.0)
	var label: Label3D = creature.label
	label.position = creature.label_target-Vector3.UP*settings.name_rise_distance*(1.0-eased)
	label.modulate.a = eased
	label.outline_modulate.a = eased

func _change_part_state(creature: Dictionary, part: Dictionary, state: String) -> void:
	part.state = state
	if settings.diagnostic_logging:
		print("[summon_part] id=",creature.record_id," part=",part.body.name," state=",state," time=",elapsed," source=",part.get("emission_point",Vector2.ZERO)," target=",part.rest.origin)

func _lift_emerging(parts: Array, speed: float) -> void:
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity",9.8)
	for part: Dictionary in parts:
		var body: RigidBody3D = part.body
		var acceleration := gravity+clampf((speed-body.linear_velocity.y)*12.0,-30.0,30.0)
		body.apply_central_force(Vector3.UP*acceleration*body.mass)

func _attract_part(creature: Dictionary, part: Dictionary, delta: float) -> void:
	var body: RigidBody3D = part.body
	var rest: Transform3D = part.rest
	var omega := TAU*float(settings.attraction_frequency)
	var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity",9.8)
	var direct := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var local_center := direct.center_of_mass_local if direct != null else body.center_of_mass
	# Track the real mass center so off-center visual pivots do not couple translation and rotation.
	var error := rest*local_center-body.to_global(local_center)
	var acceleration := (error*omega*omega-body.linear_velocity*2.2*omega).limit_length(settings.attraction_maximum_acceleration)
	body.apply_central_force((acceleration+Vector3.UP*gravity)*body.mass)
	var current := body.global_basis.x.normalized()
	var desired := rest.basis.x.normalized()
	var angle := atan2(current.cross(desired).z,current.dot(desired))
	var angular_acceleration := clampf(angle*omega*omega-body.angular_velocity.z*2.2*omega,-settings.attraction_maximum_angular_acceleration,settings.attraction_maximum_angular_acceleration)
	var inverse := body.get_inverse_inertia_tensor().z.z
	if inverse > 0.00001: body.apply_torque(Vector3.BACK*angular_acceleration/inverse)
	var stable: bool = rest.origin.distance_to(body.global_position)<settings.arrival_distance and absf(angle)<deg_to_rad(2.0) and body.linear_velocity.length()<settings.arrival_speed and body.angular_velocity.length()<0.1
	part.stable_time = part.stable_time+delta if stable else 0.0
	if part.stable_time >= settings.arrival_confirmation_time:
		body.freeze = true
		body.global_transform = rest
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		part.arrival_time = elapsed
		_change_part_state(creature,part,"assembled")

func _tick_decorations(delta: float, emitting: bool) -> void:
	if emitting and elapsed>=_next_decoration_time:
		for piece: Dictionary in pieces:
			if piece.launched: continue
			_launch_decoration(piece)
			_next_decoration_time = elapsed+settings.decoration_interval
			break
	for index: int in range(pieces.size()-1,-1,-1):
		var piece: Dictionary = pieces[index]
		var body: RigidBody3D = piece.body
		if not piece.launched:
			if not emitting:
				body.queue_free()
				pieces.remove_at(index)
			continue
		if piece.emerged_time < 0.0:
			var bounds: AABB = body.global_transform*piece.envelope
			if bounds.position.y < _ground_bounds().end.y+settings.emergence_clearance:
				_lift_emerging([piece],piece.upward_speed)
				continue
			body.collision_layer = 1
			body.collision_mask = 2
			piece.emerged_time = elapsed
			piece["emergence_bounds"] = bounds
		piece.age += delta
		piece.fade = clampf((piece.age-settings.free_motion_duration)/maxf(settings.decoration_fade_duration,0.001),0.0,1.0)
		for visual: GeometryInstance3D in piece.visuals:
			if visual is Sprite3D: visual.modulate.a = 1.0-piece.fade
			else: visual.transparency = piece.fade
		if piece.fade >= 1.0:
			if emitting:
				body.freeze = true
				body.hide()
				body.collision_layer = 0
				body.collision_mask = 0
				piece.launched = false
			else:
				body.queue_free()
				pieces.remove_at(index)

func _launch_decoration(piece: Dictionary) -> void:
	var body: RigidBody3D = piece.body
	var point := _random_point(emission_radius)
	piece["emission_point"] = point
	body.rotation.z = rng.randf_range(-PI,PI)
	var bounds: AABB = body.transform*piece.envelope
	body.position = Vector3(point.x,_ground_bounds().position.y-settings.emergence_clearance-bounds.end.y,point.y)
	piece["initial_bounds"] = body.global_transform*piece.envelope
	piece["upward_speed"] = rng.randf_range(settings.minimum_upward_speed,settings.maximum_upward_speed)
	piece.emerged_time = -1.0
	piece.age = 0.0
	piece.fade = 0.0
	piece.launched = true
	piece.launch_time = elapsed
	piece.emission_count += 1
	decorations_emitted += 1
	last_decoration_time = elapsed
	for visual: GeometryInstance3D in piece.visuals:
		if visual is Sprite3D: visual.modulate.a = 1.0
		else: visual.transparency = 0.0
	body.freeze = false
	body.sleeping = false
	body.linear_velocity = Vector3(rng.randf_range(-settings.horizontal_speed,settings.horizontal_speed),piece.upward_speed,rng.randf_range(-settings.horizontal_speed,settings.horizontal_speed))
	body.angular_velocity = Vector3(0,0,rng.randf_range(-settings.spin_speed,settings.spin_speed))
	body.show()

func _change_state(creature: Dictionary, state: String) -> void:
	creature.state = state
	if settings.diagnostic_logging: print("[summon_stage] id=",creature.record_id," state=",state," time=",elapsed," emission=",creature.emission_point," radius=",emission_radius)

func stop() -> void:
	phase = "stopped"
	_records.clear()
	_sources.clear()
	for creature: Dictionary in creatures:
		for part: Dictionary in creature.parts: part.body.freeze = true
	for piece: Dictionary in pieces: piece.body.freeze = true
