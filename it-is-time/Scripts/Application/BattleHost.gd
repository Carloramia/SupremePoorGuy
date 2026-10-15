extends Node3D
signal finished(result: Dictionary)
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
var monster_config_definitions: Dictionary = {}
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
	cursor = preload("res://Scenes/Input/TerrainCursor3D.tscn").instantiate()
	cursor.free_cursor_mode = true
	cursor.free_camera_rig = camera
	add_child(cursor)

func deploy(records: Array, id: String) -> bool:
	battle_id = id
	if records.is_empty(): return false
	if definition != null and not _prepare_editor_layout(): return false
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
		if definition != null and index>=_deployment.size(): return false
		var position_data: Dictionary = _deployment[index] if definition != null else {"position":Vector3(-32,0.1,(index-(records.size()-1)*0.5)*16),"facing":0.0}
		var actor := FACTORY.spawn(record,self,position_data.position,0,position_data.facing)
		if actor == null: return false
		actors.append(actor)
		if not _inside_level(actor): last_error = "生物碰撞体超出战场边界。"; return false
		index += 1
	for enemy_index: int in enemy_definitions.size():
		var record := FACTORY.template(enemy_definitions[enemy_index])
		record.id = "enemy_"+str(enemy_index)
		var position_data: Dictionary = _enemy_positions[enemy_index] if definition != null else {"position":Vector3(28,0.1,enemy_index*16),"facing":PI}
		var enemy := FACTORY.spawn(record,self,position_data.position,1,position_data.facing)
		if enemy == null: return false
		actors.append(enemy)
		if not _inside_level(enemy): last_error = "敌方碰撞体超出战场边界。"; return false
	await get_tree().physics_frame
	await get_tree().physics_frame
	for actor: Node3D in actors: FACTORY.activate(actor)
	cursor.set_cursor_world_position(actors[0].get_combat_anchor().global_position)
	camera.global_position = cursor.get_mouse_ground_position()
	ready_for_combat = true
	return true

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
			for slot: Array in object.slots:
				var offset := Basis(Vector3.UP,yaw)*Vector3(float(slot[0])*float(object.scale[0]),0,float(slot[1])*float(object.scale[1]))
				_deployment.append({"position":origin+offset,"facing":deg_to_rad(float(object.facing))+yaw})
		elif object.type=="enemy":
			var species: String = monster_config_definitions.get(object.monster_config_id,"")
			if not FACTORY.DEFINITIONS.has(species): return false
			enemy_definitions.append(species)
			_enemy_positions.append({"position":origin,"facing":deg_to_rad(float(object.facing))+yaw})
	if _deployment.is_empty() or enemy_definitions.is_empty(): return false
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
	if ended or not ready_for_combat: return
	elapsed += delta
	if elapsed<1.0: return
	var allies := 0
	var enemies := 0
	for actor: Node3D in actors:
		if not is_instance_valid(actor) or not actor.is_combat_alive(): continue
		var anchor: Node3D = actor.get_combat_anchor()
		if anchor == null or anchor.global_position.y < defeat_below_y: continue
		if actor.get_faction_id()==0: allies+=1
		else: enemies+=1
	if allies==0: finish("defeat")
	elif enemies==0: finish("victory")

func finish(outcome: String) -> void:
	if ended: return
	ended = true
	var damage := {}
	for actor: Node3D in actors:
		if not is_instance_valid(actor) or actor.get_faction_id()!=0: continue
		var parts := {}
		for part: PhysicalBodyPart3D in actor.find_children("*","PhysicalBodyPart3D",true,false):
			parts[str(part.get_meta(&"creature_part_key",str(part.name)))] = {"hp":part.current_hp,"max_hp":part.max_hp,"broken":part.is_broken}
		damage[str(actor.get_meta(&"creature_instance_id"))] = parts
	finished.emit({"battle_id":battle_id,"outcome":outcome,"reward":20 if outcome=="victory" else 0,"parts":damage,"duration":elapsed})

