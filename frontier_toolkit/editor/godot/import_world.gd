extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func normalise(value: Variant) -> Variant:
	if value is Vector2 or value is Vector2i: return [value.x, value.y]
	if value is Color: return "#" + value.to_html(false)
	if value is StringName: return String(value)
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value: result[String(key)] = normalise(value[key])
		return result
	if value is Array or value is PackedVector2Array:
		var result: Array = []
		for item: Variant in value: result.append(normalise(item))
		return result
	return value

func run() -> void:
	var source := "res://world_map/demo/WorldMapDemo.tscn"
	var destination := "res://editor/examples/FrontierImported.mapproject.json"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="): source = argument.trim_prefix("--source=")
		if argument.begins_with("--output="): destination = argument.trim_prefix("--output=")
	if not destination.begins_with("res://editor/") or ".." in destination:
		push_error("Import destination must be inside editor/")
		quit(1)
		return
	var packed := load(source) as PackedScene
	if not packed:
		quit(1)
		return
	var root_node := packed.instantiate() as WorldMapController
	if not root_node:
		push_error("Source must use WorldMapController")
		quit(1)
		return
	var project: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://editor/examples/Frontier.mapproject.json"))
	var map: Dictionary = project.maps[0]
	var templates: Dictionary = {}
	for object: Dictionary in map.objects: templates[object.type] = object.duplicate(true)
	map.objects = []
	var definition := root_node.definition
	map.id = String(definition.map_id)
	map.name = definition.display_name
	map.spawn = normalise(definition.spawn_position())
	map.bounds = {"position": normalise(definition.world_rect().position), "size": normalise(definition.world_rect().size)}
	map.native = {"source_scene": source, "definition_path": definition.resource_path, "map_id": String(definition.map_id), "width": definition.width, "height": definition.height, "hex_size": definition.hex_size,
		"disabled_hexes": normalise(definition.disabled_hexes), "default_spawn_id": String(definition.default_spawn_id), "spawns": normalise(definition.spawns), "discovery_radius": definition.discovery_radius,
		"interaction_radius": definition.interaction_radius, "vision_radius": definition.vision_radius, "generator_config": normalise(definition.generator_config), "custom_speed_areas": []}
	map.fog.radius = definition.vision_radius
	var obstacles := root_node.get_node_or_null("Obstacles")
	if obstacles:
		for child in obstacles.get_children():
			if not child is Polygon2D: continue
			var object: Dictionary = templates.indestructible.duplicate(true)
			object.id = String(child.name).to_snake_case()
			object.name = child.name
			object.position = normalise(child.position)
			object.rotation = child.rotation_degrees
			object.scale = normalise(child.scale)
			object.visual.tint = normalise(child.color)
			object.native_obstacle = true
			object.collision.shape = "polygon"
			object.collision.points = normalise(child.polygon)
			map.objects.append(object)
	var roads := root_node.get_node_or_null("Roads")
	if roads:
		for child in roads.get_children():
			if not child is WorldMapRoad: continue
			var object: Dictionary = templates.road.duplicate(true)
			object.id = String(child.name).to_snake_case()
			object.name = child.name
			object.position = normalise(child.position)
			object.rotation = child.rotation_degrees
			object.scale = normalise(child.scale)
			object.points = normalise(child.center_line)
			object.width = child.road_width
			object.snap_margin = child.snap_margin
			object.speed_multiplier = child.speed_multiplier
			object.native_priority = child.priority
			map.objects.append(object)
	var locations := root_node.get_node_or_null("Locations")
	if locations:
		for child in locations.get_children():
			if not child is WorldMapLocation or not child.definition: continue
			var data: LocationDefinition = child.definition
			var kind := "town" if data.type_id == &"settlement" else "camp" if data.type_id == &"battle" else "house"
			var object: Dictionary = templates[kind].duplicate(true)
			object.id = String(child.location_id)
			object.name = data.display_name
			object.position = normalise(child.position)
			object.interaction_offset = normalise(child.interaction_offset)
			object.interaction_radius = child.interaction_radius if child.interaction_radius >= 0 else definition.interaction_radius
			object.discovery.radius = child.discovery_radius if child.discovery_radius >= 0 else definition.discovery_radius
			object.discovery.initially_visible = false
			object.event_id = ""
			object.target_scene = data.scenario_scene.resource_path if data.scenario_scene else ""
			object.native_type_id = String(data.type_id)
			object.native_definition_path = data.resource_path
			object.native_encounter_data = normalise(data.encounter_data)
			object.repeatable = data.repeatable
			var behavior: int = child.completion_behavior_override if child.completion_behavior_override >= 0 else int(data.completion_behavior)
			object.completion_behavior = ["KEEP", "HIDE_SESSION", "REMOVE_PERMANENTLY", "RESPAWNABLE"][behavior]
			if kind == "camp":
				object.battle_map_id = ""
				object.blocking_obstacle_ids = []
				object.deployment_id = ""
				object.enemy_config_id = ""
				object.post_event_id = ""
			map.objects.append(object)
	for child in root_node.get_children():
		if child is WorldMapSpeedArea and not child is WorldMapRoad:
			var polygons: Array = []
			for shape in child.get_children():
				if shape is CollisionPolygon2D: polygons.append(normalise(shape.polygon))
			map.native.custom_speed_areas.append({"name": String(child.name), "position": normalise(child.position), "multiplier": child.speed_multiplier, "priority": child.priority, "tint": normalise(child.tint), "polygons": polygons})
	DirAccess.make_dir_recursive_absolute(destination.get_base_dir())
	var file := FileAccess.open(destination, FileAccess.WRITE)
	file.store_string(JSON.stringify(project, "\t"))
	file.close()
	print("Imported ", map.objects.size(), " native objects → ", destination, "; camps require explicit battle bindings before export")
	root_node.free()
	quit()
