extends SceneTree

var configuration: Dictionary
var output: String = "res://editor/exports"
var assets: Dictionary = {}
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var source := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--source="): source = argument.trim_prefix("--source=")
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=").trim_suffix("/")
	if not output.begins_with("res://editor/") or ".." in output:
		push_error("Output must stay within res://editor/")
		quit(1)
		return
	if not FileAccess.file_exists(source):
		push_error("Source JSON does not exist")
		quit(1)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
	if not parsed is Dictionary or parsed.get("format") != "frontier-map-editor" or parsed.get("version") != 1:
		push_error("Unsupported editor configuration")
		quit(1)
		return
	configuration = parsed
	preflight()
	if not errors.is_empty():
		for message in errors: push_error(message)
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	prepare_assets()
	var source_file := FileAccess.open(output.path_join("initial_configuration.json"), FileAccess.WRITE)
	if not source_file:
		push_error("Cannot write output")
		quit(1)
		return
	source_file.store_string(JSON.stringify(configuration, "\t"))
	source_file.close()
	for map: Dictionary in configuration.maps:
		if map.kind == "exploration": export_world(map)
		else: export_battle(map)
	for message in errors: push_error(message)
	print("EDITOR IMPORT: ", configuration.maps.size(), " maps; ", errors.size(), " errors; output=", output)
	quit(0 if errors.is_empty() else 1)

func preflight() -> void:
	var ids: Dictionary = {}
	for asset: Dictionary in configuration.get("assets", []):
		assets[asset.id] = asset
		if not asset.get("data", "").is_empty():
			if not String(asset.data).begins_with("data:image/"): errors.append("Invalid embedded asset: " + asset.id)
		elif not ResourceLoader.exists(asset.get("path", "")):
			errors.append("Asset not found: " + String(asset.id) + " → " + String(asset.get("path", "")))
	for map: Dictionary in configuration.get("maps", []):
		if not safe_id(String(map.get("id", ""))): errors.append("Invalid map ID")
		if ids.has(map.id): errors.append("Duplicate ID: " + map.id)
		ids[map.id] = true
		if map.kind not in ["battle", "exploration"]: errors.append("Unsupported map kind")
		for object: Dictionary in map.objects:
			if not safe_id(String(object.get("id", ""))): errors.append("Invalid object ID")
			if ids.has(object.id): errors.append("Duplicate ID: " + object.id)
			ids[object.id] = true
			if not object.get("target_scene", "").is_empty() and not ResourceLoader.exists(object.target_scene): errors.append("Target scene missing for " + object.id + ": " + object.target_scene)
			if not object.get("native_definition_path", "").is_empty() and not ResourceLoader.exists(object.native_definition_path): errors.append("Definition missing for " + object.id)
			if object.type == "indestructible" and (object.has("destroy_reward") or object.get("broken_asset", "") != ""): errors.append("Indestructible obstacle has destruction data: " + object.id)

func safe_id(value: String) -> bool:
	return not value.is_empty() and value.validate_node_name() == value and not "/" in value and not "\\" in value and not ".." in value

func prepare_assets() -> void:
	DirAccess.make_dir_recursive_absolute(output.path_join("assets"))
	for asset: Dictionary in assets.values():
		if asset.get("data", "").is_empty(): continue
		var encoded: String = asset.data
		var separator := encoded.find(",")
		var image := Image.new()
		var buffer := Marshalls.base64_to_raw(encoded.substr(separator + 1))
		var result := ERR_INVALID_DATA
		if encoded.begins_with("data:image/png"): result = image.load_png_from_buffer(buffer)
		elif encoded.begins_with("data:image/jpeg"): result = image.load_jpg_from_buffer(buffer)
		elif encoded.begins_with("data:image/webp"): result = image.load_webp_from_buffer(buffer)
		elif encoded.begins_with("data:image/svg+xml"): result = image.load_svg_from_buffer(buffer)
		if result != OK:
			errors.append("Cannot decode embedded image: " + asset.id)
			continue
		# Store ImageTexture as .tres so headless import needs no second PNG scan.
		var texture := ImageTexture.create_from_image(image)
		var path := output.path_join("assets").path_join(String(asset.id).validate_filename() + ".tres")
		save_resource(texture, path)
		asset["path"] = path

func asset_texture(id: String) -> Texture2D:
	if not assets.has(id): return null
	return load(assets[id].get("path", "")) as Texture2D

func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func save_resource(resource: Resource, path: String) -> void:
	if ResourceSaver.save(resource, path) != OK: errors.append("Cannot save resource: " + path)

func stamp_owners(node: Node, root_node: Node) -> void:
	for child in node.get_children():
		child.owner = root_node
		stamp_owners(child, root_node)

func export_world(map: Dictionary) -> void:
	var directory := output.path_join(map.id)
	DirAccess.make_dir_recursive_absolute(directory)
	var definition := WorldMapDefinition.new()
	var native: Dictionary = map.native
	definition.map_id = map.id
	definition.display_name = map.name
	definition.width = int(native.width)
	definition.height = int(native.height)
	definition.hex_size = float(native.hex_size)
	for coordinate: Array in native.get("disabled_hexes", []): definition.disabled_hexes.append(Vector2i(int(coordinate[0]), int(coordinate[1])))
	definition.default_spawn_id = native.default_spawn_id
	definition.spawns = {}
	for id: String in native.get("spawns", {}): definition.spawns[id] = v2(native.spawns[id])
	definition.spawns[String(definition.default_spawn_id)] = v2(map.spawn)
	definition.discovery_radius = float(native.discovery_radius)
	definition.interaction_radius = float(native.interaction_radius)
	definition.vision_radius = float(map.fog.radius)
	definition.generator_config = native.get("generator_config", {}).duplicate(true)
	definition.editor_data = {"version": 1, "map": map.duplicate(true), "assets": assets.duplicate(true), "catalogs": configuration.catalogs.duplicate(true)}
	save_resource(definition, directory.path_join("WorldDefinition.tres"))
	var root_node := Node2D.new()
	root_node.name = map.id
	root_node.set_script(load("res://world_map/core/world_map_controller.gd"))
	root_node.set("definition", definition)
	root_node.set("save_path", "user://editor_" + map.id + "_save.json")
	var obstacles := Node2D.new()
	obstacles.name = "Obstacles"
	root_node.add_child(obstacles)
	var roads := Node2D.new()
	roads.name = "Roads"
	root_node.add_child(roads)
	var locations := WorldMapLocationManager.new()
	locations.name = "Locations"
	root_node.add_child(locations)
	var decorations := Node2D.new()
	decorations.name = "EditorVisuals"
	root_node.add_child(decorations)
	for object: Dictionary in map.objects:
		if object.type == "road":
			var road := WorldMapRoad.new()
			road.name = object.id
			road.position = v2(object.position)
			road.rotation_degrees = float(object.rotation)
			road.scale = v2(object.scale)
			var points := PackedVector2Array()
			for point: Array in object.points: points.append(v2(point))
			road.center_line = points
			road.road_width = float(object.width)
			road.snap_margin = float(object.get("snap_margin", 24))
			road.speed_multiplier = float(object.get("speed_multiplier", 1.5))
			road.priority = float(object.get("native_priority", 10))
			roads.add_child(road)
		elif object.type == "indestructible" and object.get("collision", {}).get("enabled", false):
			var polygon := Polygon2D.new()
			polygon.name = object.id
			polygon.polygon = polygon_for_shape(object.collision)
			polygon.position = v2(object.position)
			polygon.rotation_degrees = float(object.rotation)
			polygon.scale = v2(object.scale)
			polygon.color = Color(object.visual.tint)
			obstacles.add_child(polygon)
		elif object.type in ["house", "town", "camp"]:
			var location := WorldMapLocation.new()
			location.name = object.id
			location.location_id = object.id
			location.position = v2(object.position)
			location.interaction_offset = v2(object.get("interaction_offset", [0, 35]))
			location.interaction_radius = float(object.get("interaction_radius", 42))
			location.discovery_radius = float(object.discovery.radius)
			var data := LocationDefinition.new()
			if object.get("native_definition_path", "") != "": data = load(object.native_definition_path).duplicate(true)
			data.type_id = object.get("native_type_id", "settlement" if object.type == "town" else "battle" if object.type == "camp" else "event")
			data.display_name = object.name
			data.icon = asset_texture(object.visual.asset)
			data.repeatable = bool(object.get("repeatable", false))
			data.completion_behavior = ["KEEP", "HIDE_SESSION", "REMOVE_PERMANENTLY", "RESPAWNABLE"].find(object.get("completion_behavior", "KEEP")) as LocationDefinition.CompletionBehavior
			var ui_type := "Settlement" if data.type_id == "settlement" else "Battle" if data.type_id == "battle" else "Resource" if data.type_id == "resource" else "Event"
			data.interaction_ui_scene = load("res://world_map/ui/" + ui_type + "Panel.tscn")
			if object.get("target_scene", "") != "": data.scenario_scene = load(object.target_scene)
			data.encounter_data.merge({"editor_object": object.duplicate(true)}, true)
			save_resource(data, directory.path_join(String(object.id) + ".tres"))
			location.definition = data
			locations.add_child(location)
		elif object.type not in ["reveal_area", "destructible", "traversable"]:
			var sprite := Sprite2D.new()
			sprite.name = object.id
			sprite.texture = asset_texture(object.visual.asset)
			if sprite.texture:
				sprite.position = v2(object.position)
				sprite.rotation_degrees = float(object.rotation)
				sprite.scale = v2(object.visual.size) / sprite.texture.get_size() * v2(object.scale)
				sprite.modulate.a = float(object.visual.opacity)
				sprite.visible = bool(object.visual.visible)
				sprite.z_index = int(object.visual.z_index)
				decorations.add_child(sprite)
			else: sprite.free()
	# Keep condition-based obstacles as authoring records; the game adapter owns
	# destruction/crossing and their scoped connection gates, not static nav holes.
	for area_data: Dictionary in native.get("custom_speed_areas", []):
		var area := WorldMapSpeedArea.new()
		area.name = area_data.name
		area.position = v2(area_data.position)
		area.speed_multiplier = float(area_data.multiplier)
		area.priority = float(area_data.priority)
		area.tint = Color(area_data.tint)
		for points_data: Array in area_data.polygons:
			var collision := CollisionPolygon2D.new()
			var points := PackedVector2Array()
			for point: Array in points_data: points.append(v2(point))
			collision.polygon = points
			area.add_child(collision)
		root_node.add_child(area)
	var overlay := Node.new()
	overlay.name = "ScenarioOverlay"
	overlay.set_script(load("res://integration/scenario_overlay.gd"))
	root_node.add_child(overlay)
	stamp_owners(root_node, root_node)
	var packed := PackedScene.new()
	packed.pack(root_node)
	save_resource(packed, directory.path_join(String(map.id) + ".tscn"))
	root_node.free()

func polygon_for_shape(shape: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	if shape.shape == "polygon":
		for point: Array in shape.points: points.append(v2(point))
	elif shape.shape == "circle":
		for index in range(32): points.append(Vector2(cos(index * TAU / 32.0), sin(index * TAU / 32.0)) * v2(shape.size) * 0.5)
	else:
		for point in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]: points.append(point * v2(shape.size))
	for index in range(points.size()): points[index] = points[index].rotated(deg_to_rad(float(shape.rotation))) + v2(shape.offset)
	return points

func export_battle(map: Dictionary) -> void:
	var directory := output.path_join(map.id)
	DirAccess.make_dir_recursive_absolute(directory)
	var definition := SceneDefinition.new()
	definition.scene_id = map.id
	definition.display_name = map.name
	definition.camera_bounds = Rect2(-float(map.radius), -float(map.radius), float(map.radius) * 2.0, float(map.radius) * 2.0)
	definition.default_camera_size = float(map.radius) * 1.8
	definition.min_camera_size = float(map.radius) * 0.6
	definition.max_camera_size = float(map.radius) * 2.2
	definition.default_scene_mode = SceneMode.Mode.COMBAT
	definition.metadata["editor_data"] = {"version": 1, "map": map.duplicate(true), "assets": assets.duplicate(true), "catalogs": configuration.catalogs.duplicate(true)}
	save_resource(definition, directory.path_join("SceneDefinition.tres"))
	var root_node := Node3D.new()
	root_node.name = map.id
	root_node.set_script(load("res://editor/godot/battle_preview.gd"))
	root_node.set("definition", definition)
	var packed := PackedScene.new()
	packed.pack(root_node)
	save_resource(packed, directory.path_join(String(map.id) + ".tscn"))
	root_node.free()
