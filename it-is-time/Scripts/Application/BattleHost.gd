extends Node3D
signal finished(result: Dictionary)
signal reinforcements_required
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
var application: Node
var battle_id := ""
var last_error := ""
var actors: Array[Node3D] = []
var camera: Node3D
var cursor: Node3D
var items: Node3D
var ended := false
var ready_for_combat := false
var elapsed := 0.0
var enemy_definitions: Array[String] = ["human"]
var defeat_below_y := -20.0
var definition: SceneDefinition
var delivery_request: Dictionary = {}
var delivery_settings: DeliveryBattleSettings
var delivery_adapter: RefCounted
var deployment: Node3D
var deployment_polygon := PackedVector2Array([Vector2(-80,-60),Vector2(-2,-60),Vector2(-2,60),Vector2(-80,60)])
var monster_config_definitions: Dictionary = {}
var capacity_settings: Resource = preload("res://Resources/Application/DefaultBattleCapacity.tres")
var _initial_allies: Array = []
var _allied_roster: Array = []
var _enemy_initial: Array = []
var _enemy_reserves: Array = []
var _participants: Array[Dictionary] = []
var _rosters_spawned := false
var _enemy_reinforcement_clock := 0.0
var _awaiting_allies := false
var reinforcing := false
var _preview: Node3D
var _preview_record := {}
var _saved_cursor_mode := Node.PROCESS_MODE_INHERIT
var _saved_camera_mode := Node.PROCESS_MODE_INHERIT
var _deployment: Array[Dictionary] = []
var _enemy_positions: Array[Dictionary] = []
var _geometry: Node3D
var _floor_polygon := PackedVector2Array([Vector2(-90,-70),Vector2(90,-70),Vector2(90,70),Vector2(-90,70)])

func _ready() -> void:
	# The UI host processes while paused; physical descendants must not inherit that.
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_meta(&"gameplay_level",true)
	var environment := WorldEnvironment.new()
	environment.name = "BattleEnvironment"
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("75858c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.name = "BattleSun"
	sun.rotation_degrees = Vector3(-55,-25,0)
	add_child(sun)
	var floor_body := StaticBody3D.new()
	floor_body.name = "Ground"
	floor_body.position.y = -0.5
	floor_body.add_to_group(&"scenario_ground")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(180,1,140)
	shape.shape = box
	floor_body.add_child(shape)
	var mesh := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = box.size
	mesh.mesh = box_mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("526b51")
	mesh.material_override = material
	floor_body.add_child(mesh)
	add_child(floor_body)
	items = Node3D.new()
	items.name = "Items"
	add_child(items)
	camera = preload("res://Scenes/Camera/DragCamera3D.tscn").instantiate()
	add_child(camera)
	camera.set_distance(45.0)
	# Listen near the viewed ground, so zooming far out does not silence the battle.
	var listener := AudioListener3D.new()
	listener.name = "CombatAudioListener"
	listener.position.y = 8.0
	camera.add_child(listener)
	listener.make_current()
	cursor = preload("res://Scenes/Input/TerrainCursor3D.tscn").instantiate()
	cursor.free_cursor_mode = true
	cursor.free_camera_rig = camera
	add_child(cursor)

func deploy(records: Array, id: String) -> bool:
	battle_id = id
	if records.is_empty(): return false
	_allied_roster = records.duplicate(true)
	var selected: Dictionary = capacity_settings.initial_roster(records)
	last_error = selected.error
	if not last_error.is_empty(): return false
	_initial_allies = selected.records
	if _initial_allies.is_empty(): last_error = "队伍中没有容量足够的首发生物。"; return false
	records = _initial_allies
	if not delivery_request.is_empty():
		if delivery_settings == null: last_error = "战场配置缺失。"; return false
		last_error = delivery_settings.availability_error(str(delivery_request.get("enemy_config_id","")))
		if not last_error.is_empty(): return false
		enemy_definitions.assign(delivery_settings.enemy_rosters[delivery_request.enemy_config_id].definitions)
	if definition == null and not configure_enemy_roster(): return false
	# Validate before loading terrain, navigation or physical creatures.
	last_error = capacity_status().error
	if last_error.is_empty(): last_error = capacity_status(1).error
	if not last_error.is_empty(): return false
	if not delivery_request.is_empty():
		delivery_adapter = preload("res://Scripts/Application/DeliveryBattleEnvironmentAdapter.gd").new()
		if not delivery_adapter.build(self,records): return false
	elif definition != null and not _prepare_editor_layout(): return false
	last_error = capacity_status().error
	if not last_error.is_empty(): return false
	if application != null: application.session.trace("battle_capacity",capacity_status())
	var authored := definition!=null or not delivery_request.is_empty()
	var navigation := NavigationRegion3D.new()
	navigation.name = "NavigationRegion3D"
	var navmesh := NavigationMesh.new()
	navmesh.agent_radius = 1.0
	navmesh.vertices = PackedVector3Array([Vector3(-86,0,-66),Vector3(86,0,-66),Vector3(86,0,66),Vector3(-86,0,66)])
	navmesh.add_polygon(PackedInt32Array([0,3,2,1]))
	navigation.navigation_mesh = navmesh
	add_child(navigation)
	if _geometry != null:
		navigation.add_child(_geometry)
		navmesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
		var completed: Array[bool] = []
		navigation.bake_finished.connect(func(): completed.append(true),CONNECT_ONE_SHOT)
		navigation.bake_navigation_mesh(false)
		# Even a synchronous bake installs the resulting mesh via a deferred callback.
		for frame: int in 120:
			if not completed.is_empty(): break
			await get_tree().process_frame
		if navigation.navigation_mesh.get_polygon_count()==0: last_error = "导航烘焙未生成多边形。"; push_warning(last_error); return false
	var index := 0
	for record: Dictionary in records:
		if authored and index>=_deployment.size(): return false
		if is_instance_valid(application) and not application.session.register_battle_reinforcement(battle_id,str(record.id)):
			last_error = application.session.last_error; return false
		var position_data: Dictionary = _deployment[index] if authored else {"position":Vector3(-32,0.1,(index-(records.size()-1)*0.5)*16),"facing":0.0}
		var actor := FACTORY.spawn(record,self,position_data.position,0,position_data.facing)
		if actor == null: return false
		actors.append(actor)
		_register_actor(actor,record,0)
		if not _inside_level(actor): last_error = "生物碰撞体超出战场边界。"; return false
		index += 1
	for enemy_index: int in _enemy_initial.size():
		var record: Dictionary = _enemy_initial[enemy_index]
		var position_data: Dictionary = _enemy_positions[enemy_index] if authored else {"position":Vector3(28,0.1,enemy_index*16),"facing":PI}
		var enemy := FACTORY.spawn(record,self,position_data.position,1,position_data.facing)
		if enemy == null: return false
		actors.append(enemy)
		_register_actor(enemy,record,1)
		if not _inside_level(enemy): last_error = "敌方碰撞体超出战场边界。"; return false
	_rosters_spawned = true
	await get_tree().physics_frame
	await get_tree().physics_frame
	if delivery_adapter!=null:
		camera.maximum_distance = float(delivery_adapter.layout.radius)*delivery_adapter.scale*3.0
		camera.set_distance(camera.maximum_distance*0.55)
	cursor.set_cursor_world_position(actors[0].get_combat_anchor().global_position)
	camera.global_position = cursor.get_mouse_ground_position()
	deployment = preload("res://Scripts/Application/BattleDeployment3D.gd").new()
	add_child(deployment)
	deployment.begin(self)
	return true

func start_combat() -> bool:
	if ready_for_combat or ended or not is_instance_valid(deployment) or not deployment.can_start(): return false
	last_error = capacity_status().error
	if last_error.is_empty(): last_error = capacity_status(1).error
	if not last_error.is_empty(): return false
	deployment.complete()
	deployment = null
	for actor: Node3D in actors: FACTORY.activate(actor)
	if delivery_adapter != null:
		var effects := preload("res://Scripts/Application/BattleEnvironmentEffects3D.gd").new()
		effects.configure(self,delivery_adapter.layout,delivery_adapter.scale)
		add_child(effects)
	ready_for_combat = true
	return true

func capacity_status(faction: int = 0) -> Dictionary:
	if not _rosters_spawned: return capacity_settings.evaluate(_initial_allies if faction == 0 else _enemy_initial)
	var records: Array = []
	for entry: Dictionary in _participants:
		if entry.faction == faction and _living(entry): records.append(entry.record)
	return capacity_settings.evaluate(records)

func configure_enemy_roster() -> bool:
	var records: Array = []
	for index: int in enemy_definitions.size():
		var record := FACTORY.template(enemy_definitions[index])
		if record.is_empty(): last_error = "敌方生物未配置："+enemy_definitions[index]; return false
		record.id = "enemy_"+str(index)
		record.roster_index = index
		records.append(record)
	var selected: Dictionary = capacity_settings.initial_roster(records)
	if not selected.error.is_empty(): last_error = selected.error; return false
	_enemy_initial = selected.records
	_enemy_reserves = records.filter(func(record): return record not in _enemy_initial)
	if _enemy_initial.is_empty(): last_error = "敌方编队没有容量足够的首发生物。"; return false
	return true

func _register_actor(actor: Node3D, record: Dictionary, faction: int) -> void:
	_participants.append({"record":record.duplicate(true),"faction":faction,"actor":weakref(actor),"dead":false})
	_awaiting_allies = false
	_trace("battle_unit_deployed",{"id":record.id,"faction":faction,"definition_id":record.definition_id,"capacity":capacity_status(faction)})

func _living(entry: Dictionary) -> bool:
	if entry.dead: return false
	var actor: Node3D = entry.actor.get_ref()
	if actor == null or not actor.is_combat_alive(): return false
	var anchor: Node3D = actor.get_combat_anchor()
	return anchor != null and anchor.global_position.y >= defeat_below_y

func reserve_records(faction: int = 0) -> Array:
	if faction != 0: return _enemy_reserves.duplicate()
	var records: Array = application.session.monsters() if is_instance_valid(application) else _allied_roster
	var used := {}
	for entry: Dictionary in _participants:
		if entry.faction == 0: used[str(entry.record.id)] = true
	return records.filter(func(record): return record.get("position","team") in ["team","warehouse"] and not used.has(str(record.id)))

func reinforcement_error(record: Dictionary, faction: int = 0) -> String:
	var cost: int = capacity_settings.creature_cost(record)
	if cost <= 0: return "该生物的容量未配置。"
	if capacity_status(faction).used+cost > capacity_settings.total_capacity: return "剩余战场容量不足。"
	return ""

func has_available_reserve(faction: int = 0) -> bool:
	for record: Dictionary in reserve_records(faction):
		if reinforcement_error(record,faction).is_empty(): return true
	return false

func flush_deaths() -> bool:
	var newly_dead: Array[Dictionary] = []
	var ids: Array = []
	for entry: Dictionary in _participants:
		if not entry.dead and not _living(entry):
			newly_dead.append(entry)
			if entry.faction == 0: ids.append(entry.record.id)
	if not ids.is_empty() and is_instance_valid(application):
		if not application.session.record_battle_deaths(battle_id,ids):
			last_error = application.session.last_error
			return false
	for entry: Dictionary in newly_dead:
		entry.dead = true
		_trace("battle_unit_dead",{"id":entry.record.id,"faction":entry.faction,"permanent":entry.faction == 0})
	return true

func _placement_adapter() -> RefCounted:
	var adapter := delivery_adapter
	if adapter == null:
		adapter = preload("res://Scripts/Application/DeliveryBattleEnvironmentAdapter.gd").new()
		adapter.layout = {"radius":90.0,"objects":[]}
		adapter.scale = 1.0
		adapter.floor_polygon = _floor_polygon
	adapter.occupied.clear()
	for actor: Node3D in actors:
		if not is_instance_valid(actor) or actor == _preview: continue
		var bounds := AABB()
		var found := false
		for shape: CollisionShape3D in actor.find_children("*","CollisionShape3D",true,false):
			if shape.disabled or shape.shape == null or not shape.get_parent() is PhysicsBody3D: continue
			var box: AABB = shape.global_transform*shape.shape.get_debug_mesh().get_aabb()
			bounds = bounds.merge(box) if found else box
			found = true
		if found: adapter.occupied.append(bounds)
	return adapter

func begin_reinforcement(id: String) -> bool:
	if ended or not ready_for_combat or reinforcing: return false
	var record := {}
	for candidate: Dictionary in reserve_records():
		if candidate.id == id: record = candidate; break
	if record.is_empty(): last_error = "该生物已上场或不可调用。"; return false
	last_error = reinforcement_error(record)
	if not last_error.is_empty(): return false
	var placed: Dictionary = _placement_adapter().place(record,false,deployment_polygon)
	if placed.is_empty(): last_error = "部署区没有足够空间，请等待空出位置。"; return false
	_preview = FACTORY.spawn(record,self,placed.position,0,placed.facing)
	if _preview == null: last_error = "增援生物无法生成。"; return false
	_preview_record = record.duplicate(true)
	actors.append(_preview)
	reinforcing = true
	_saved_cursor_mode = cursor.process_mode
	_saved_camera_mode = camera.process_mode
	cursor.process_mode = Node.PROCESS_MODE_ALWAYS
	camera.process_mode = Node.PROCESS_MODE_ALWAYS
	deployment = preload("res://Scripts/Application/BattleDeployment3D.gd").new()
	deployment.process_mode = Node.PROCESS_MODE_ALWAYS
	deployment.allowed_actor = _preview
	add_child(deployment)
	deployment.begin(self,true)
	cursor.set_cursor_world_position(_preview.get_combat_anchor().global_position)
	deployment.pick_up(_preview)
	deployment._drag_pointer = _preview.get_combat_anchor().global_position
	_trace("reinforcement_preview",{"id":record.id,"position":placed.position})
	return true

func confirm_reinforcement() -> bool:
	if not reinforcing or not is_instance_valid(_preview) or not deployment.can_start(): return false
	last_error = reinforcement_error(_preview_record)
	if last_error.is_empty(): last_error = deployment.validate_placement(_preview)
	if not last_error.is_empty(): return false
	if is_instance_valid(application) and not application.session.register_battle_reinforcement(battle_id,str(_preview_record.id)):
		last_error = application.session.last_error; return false
	var actor := _preview
	_register_actor(actor,_preview_record,0)
	_end_reinforcement()
	FACTORY.activate(actor)
	return true

func cancel_reinforcement() -> void:
	if not reinforcing: return
	_trace("reinforcement_cancelled",{"id":_preview_record.get("id","")})
	actors.erase(_preview)
	if is_instance_valid(_preview): _preview.queue_free()
	_end_reinforcement()

func _end_reinforcement() -> void:
	deployment.complete()
	deployment = null
	cursor.process_mode = _saved_cursor_mode
	camera.process_mode = _saved_camera_mode
	_preview = null
	_preview_record = {}
	reinforcing = false

func _reinforce_enemy() -> void:
	for record: Dictionary in _enemy_reserves:
		if not reinforcement_error(record,1).is_empty(): continue
		var region := PackedVector2Array()
		for point: Vector2 in deployment_polygon: region.append(Vector2(-point.x,point.y))
		var placed: Dictionary = _placement_adapter().place(record,true,region)
		if placed.is_empty(): continue
		var actor := FACTORY.spawn(record,self,placed.position,1,placed.facing)
		if actor == null: continue
		var validator := preload("res://Scripts/Application/BattleDeployment3D.gd").new()
		add_child(validator)
		validator.host = self
		validator.cache_ground()
		var error: String = validator.validate_placement(actor,region)
		validator.queue_free()
		if not error.is_empty(): actor.queue_free(); continue
		actors.append(actor)
		_register_actor(actor,record,1)
		_enemy_reserves.erase(record)
		FACTORY.activate(actor)
		return

func _trace(event: String, detail: Dictionary) -> void:
	if is_instance_valid(application):
		application.session.trace(event,detail)
		application.trace_map_event(event,detail)

func _prepare_editor_layout() -> bool:
	var editor: Dictionary = definition.metadata.get("editor_data",{})
	if not editor.get("map") is Dictionary: return false
	var layout: Dictionary = editor.map
	enemy_definitions.clear()
	for object: Dictionary in layout.get("objects",[]):
		if object.type not in ["enemy","deployment","decoration","edge_decoration","broken_barricade","grass","tree","collision_obstacle"]:
			last_error = "尚未接入的战场对象类型："+str(object.type)
			push_warning("[integration] "+last_error)
			return false
		if object.get("damage",0.0)>0.0 or not str(object.get("effect_ref","")).is_empty() or (object.get("region",{}).get("enabled",false) and object.type!="deployment"):
			last_error = "尚未接入的战场区域效果："+str(object.id)
			return false
		if object.type=="deployment" and not str(object.get("rule_ref","")).is_empty():
			last_error = "尚未接入的部署规则："+str(object.rule_ref)
			return false
		var origin := Vector3(float(object.position[0]),float(object.height)+0.1,float(object.position[1]))
		var yaw := -deg_to_rad(float(object.rotation))
		if object.type=="deployment":
			var converter := preload("res://Scripts/Application/DeliveryBattleEnvironmentAdapter.gd").new()
			converter.scale = 1.0
			deployment_polygon = converter.shape_polygon(object,object.region)
			for slot: Array in object.slots:
				var offset := Basis(Vector3.UP,yaw)*Vector3(float(slot[0])*float(object.scale[0]),0,float(slot[1])*float(object.scale[1]))
				_deployment.append({"position":origin+offset,"facing":deg_to_rad(float(object.facing))+yaw})
		elif object.type=="enemy":
			var species: String = monster_config_definitions.get(object.monster_config_id,"")
			if not FACTORY.DEFINITIONS.has(species): return false
			enemy_definitions.append(species)
			_enemy_positions.append({"position":origin,"facing":deg_to_rad(float(object.facing))+yaw})
	if _deployment.is_empty() or enemy_definitions.is_empty(): return false
	var enemy_positions := _enemy_positions.duplicate()
	if not configure_enemy_roster(): return false
	_enemy_positions.clear()
	for record: Dictionary in _enemy_initial: _enemy_positions.append(enemy_positions[int(record.roster_index)])
	var builder := preload("res://Tools/Integration/Frontier/godot/battle_preview.gd").new()
	builder.map_data = layout
	builder.asset_data = editor.get("assets",{})
	builder.build_scene()
	_floor_polygon = builder.hex_points()
	for title: String in ["CameraRig","InteractionController","OcclusionController"]:
		var node := builder.get_node(title)
		builder.remove_child(node)
		node.free()
	for object: Dictionary in layout.objects:
		if object.type in ["enemy","deployment"]: builder.get_node("Objects/"+str(object.id)).free()
	builder.set_script(null)
	_geometry = builder
	for title: String in ["Ground","BattleEnvironment","BattleSun"]: get_node(title).free()
	return true

func _inside_level(actor: Node3D) -> bool:
	for body: PhysicalBodyPart3D in actor.find_children("*","PhysicalBodyPart3D",true,false):
		for collision: CollisionShape3D in body.find_children("*","CollisionShape3D",false,false):
			if collision.disabled or collision.shape==null: continue
			var bounds := collision.shape.get_debug_mesh().get_aabb()
			for corner: int in 8:
				var point := to_local(collision.global_transform*bounds.get_endpoint(corner))
				if not Geometry2D.is_point_in_polygon(Vector2(point.x,point.z),_floor_polygon): return false
	return true

func _exit_tree() -> void:
	if _geometry != null and is_instance_valid(_geometry) and _geometry.get_parent()==null: _geometry.free()

func _physics_process(delta: float) -> void:
	if ended or not ready_for_combat or reinforcing: return
	elapsed += delta
	if elapsed<1.0: return
	if not flush_deaths():
		if is_instance_valid(application): application.battle_save_failed()
		return
	_enemy_reinforcement_clock -= delta
	if _enemy_reinforcement_clock <= 0.0:
		_enemy_reinforcement_clock = maxf(0.1,capacity_settings.enemy_reinforcement_interval)
		_reinforce_enemy()
	var allies := 0
	var enemies := 0
	for actor: Node3D in actors:
		if not is_instance_valid(actor) or not actor.is_combat_alive(): continue
		var anchor: Node3D = actor.get_combat_anchor()
		if anchor == null or anchor.global_position.y < defeat_below_y: continue
		if actor.get_faction_id()==0: allies+=1
		else: enemies+=1
	if allies == 0 and not has_available_reserve(): finish("defeat")
	elif enemies == 0 and not has_available_reserve(1): finish("victory")
	elif allies == 0 and not _awaiting_allies:
		_awaiting_allies = true
		reinforcements_required.emit()

func finish(outcome: String) -> void:
	if ended: return
	if not flush_deaths():
		if is_instance_valid(application): application.battle_save_failed()
		return
	cancel_reinforcement()
	ended = true
	var damage := {}
	for actor: Node3D in actors:
		if not is_instance_valid(actor) or actor.get_faction_id()!=0: continue
		var parts := {}
		var damage_controller := actor.get_node_or_null("CharacterDamageController3D") as CharacterDamageController3D
		if damage_controller != null:
			parts = damage_controller.get_part_damage_states()
		else:
			for part: PhysicalBodyPart3D in actor.find_children("*","PhysicalBodyPart3D",true,false):
				parts[str(part.get_meta(&"creature_part_key",str(part.name)))] = {"hp":part.current_hp,"max_hp":part.max_hp,"broken":part.is_broken}
		damage[str(actor.get_meta(&"creature_instance_id"))] = parts
	var casualties: Array = application.session.data.battle.get("casualties",[]).duplicate() if is_instance_valid(application) else []
	var result := {"battle_id":battle_id,"outcome":outcome,"reward":20 if outcome=="victory" else 0,"parts":damage,"duration":elapsed,"casualties":casualties}
	if delivery_adapter!=null:
		result.battle_map_id = delivery_request.battle_map_id
		result.post_battle_options = []
		if outcome=="victory":
			for object: Dictionary in delivery_adapter.layout.objects:
				if object.type!="post_battle" or object.get("condition_ref","") not in ["","battle_won"]: continue
				for field: String in ["summon_option_ref","upgrade_option_ref"]:
					var option: String = object.get(field,"")
					if not option.is_empty() and option not in result.post_battle_options: result.post_battle_options.append(option)
	finished.emit(result)

