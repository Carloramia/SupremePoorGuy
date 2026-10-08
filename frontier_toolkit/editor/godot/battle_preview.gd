extends ScenarioController

# Export adapter: geometry/physics and authoring metadata only, no battle rules.
var map_data: Dictionary
var asset_data: Dictionary

func _ready() -> void:
	map_data = definition.metadata.editor_data.map
	asset_data = definition.metadata.editor_data.assets
	build_scene()
	super._ready()
	var overlay := CanvasLayer.new()
	add_child(overlay)
	var help := Label.new()
	help.position = Vector2(22, 20)
	help.text = definition.display_name + "\n地编预览 · 中键平移 / 滚轮缩放\n空气墙与效果区已生成；游戏规则由外部系统接入"
	help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(help)

func v2(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

func hex_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	var start := -PI * 0.5 if map_data.orientation == "pointy" else 0.0
	for index in range(6): points.append(Vector2(cos(start + index * PI / 3.0), sin(start + index * PI / 3.0)) * float(map_data.radius))
	return points

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 1.0
	return result

func build_scene() -> void:
	camera_controller = ScenarioCameraController.new()
	camera_controller.name = "CameraRig"
	add_child(camera_controller)
	interaction_controller = ScenarioInteractionController.new()
	interaction_controller.name = "InteractionController"
	add_child(interaction_controller)
	occlusion_controller = ScenarioOcclusionController.new()
	occlusion_controller.name = "OcclusionController"
	add_child(occlusion_controller)
	var environment_node := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("253c2e")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("c5d0b0")
	environment.ambient_light_energy = 0.85
	environment_node.environment = environment
	add_child(environment_node)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	add_child(light)
	var polygon := hex_points()
	var mesh := ImmediateMesh.new()
	var ground_material := material(Color(map_data.ground_color))
	var ground_asset: String = map_data.get("ground_asset", "")
	if asset_data.has(ground_asset): ground_material.albedo_texture = load(asset_data[ground_asset].path)
	var ground_shader := Shader.new()
	ground_shader.code = """shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
uniform vec4 color : source_color = vec4(0.4, 0.5, 0.35, 1.0);
uniform float feather = 0.8;
uniform vec2 corners[6];
uniform sampler2D ground_texture : source_color;
uniform bool use_texture = false;
varying vec2 ground_position;
void vertex() { ground_position = VERTEX.xz; }
void fragment() {
    float edge = 10000.0;
    for (int i = 0; i < 6; i++) {
        vec2 a = corners[i]; vec2 b = corners[(i + 1) % 6]; vec2 line = b - a;
        vec2 nearest = a + line * clamp(dot(ground_position - a, line) / dot(line, line), 0.0, 1.0);
        edge = min(edge, length(ground_position - nearest));
    }
    ALBEDO = color.rgb * (use_texture ? texture(ground_texture, UV).rgb : vec3(1.0));
    ROUGHNESS = 1.0;
    ALPHA = feather > 0.001 ? smoothstep(0.0, feather, edge) : 1.0;
}
"""
	var edge_material := ShaderMaterial.new()
	edge_material.render_priority = -10
	edge_material.shader = ground_shader
	edge_material.set_shader_parameter("color", Color(map_data.ground_color))
	edge_material.set_shader_parameter("feather", float(map_data.edge_feather))
	edge_material.set_shader_parameter("corners", polygon)
	if ground_material.albedo_texture:
		edge_material.set_shader_parameter("ground_texture", ground_material.albedo_texture)
		edge_material.set_shader_parameter("use_texture", true)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, ground_material)
	var faces := PackedVector3Array()
	for index in range(6):
		for point in [Vector2.ZERO, polygon[(index + 1) % 6], polygon[index]]:
			mesh.surface_set_normal(Vector3.UP)
			mesh.surface_set_uv(point / (float(map_data.radius) * 2.0) + Vector2.ONE * 0.5)
			mesh.surface_add_vertex(Vector3(point.x, 0, point.y))
			faces.append(Vector3(point.x, 0, point.y))
	mesh.surface_end()
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.add_to_group("scenario_ground")
	add_child(ground)
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = edge_material
	ground.add_child(visual)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	var ground_collision := CollisionShape3D.new()
	ground_collision.shape = shape
	ground.add_child(ground_collision)
	build_background()
	var wall_root := Node3D.new()
	wall_root.name = "AirWalls"
	add_child(wall_root)
	for index in range(6):
		var a := polygon[index]
		var b := polygon[(index + 1) % 6]
		var middle := (a + b) * 0.5
		var wall := StaticBody3D.new()
		wall.name = "Wall" + str(index)
		wall.position = Vector3(middle.x, float(map_data.wall.height) * 0.5, middle.y)
		wall.rotation.y = -atan2(b.y - a.y, b.x - a.x)
		wall.collision_layer = int(map_data.wall.layer)
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D"
		var box := BoxShape3D.new()
		box.size = Vector3(a.distance_to(b) + float(map_data.wall.thickness), float(map_data.wall.height), float(map_data.wall.thickness))
		collision.shape = box
		wall.add_child(collision)
		wall_root.add_child(wall)
	if map_data.natural_border:
		for index in range(6):
			var a := polygon[index]
			var b := polygon[(index + 1) % 6]
			var count := maxi(1, int(a.distance_to(b) / 1.5))
			for step in range(count):
				var position_2d := a.lerp(b, float(step) / count)
				var rock := MeshInstance3D.new()
				var stone := CylinderMesh.new()
				stone.top_radius = 0.35
				stone.bottom_radius = 0.7
				stone.height = 0.7 + (step % 3) * 0.2
				stone.radial_segments = 5
				rock.mesh = stone
				rock.material_override = material(Color("737d61"))
				rock.position = Vector3(position_2d.x, stone.height * 0.5, position_2d.y)
				rock.rotation.y = step * 0.7
				add_child(rock)
	var objects := Node3D.new()
	objects.name = "Objects"
	add_child(objects)
	for object: Dictionary in map_data.objects: build_object(object, objects)
	var navigation_root := Node3D.new()
	navigation_root.name = "NavigationRoot"
	add_child(navigation_root)

func build_background() -> void:
	var plane := MeshInstance3D.new()
	plane.name = "SoftBackground"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2.ONE * float(map_data.radius) * 5.0
	plane.mesh = mesh
	plane.position.y = -0.08
	var shader := Shader.new()
	shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
uniform sampler2D background_texture : source_color, filter_linear_mipmap;
uniform float blur = 0.01;
uniform vec4 tint : source_color = vec4(0.3, 0.4, 0.25, 1.0);
void fragment() {
    vec3 color = vec3(0.0);
    for (int x = -2; x <= 2; x++) for (int y = -2; y <= 2; y++) color += texture(background_texture, UV + vec2(float(x), float(y)) * blur).rgb;
    ALBEDO = color / 25.0 * tint.rgb;
}
"""
	var shader_material := ShaderMaterial.new()
	shader_material.shader = shader
	var noise := NoiseTexture2D.new()
	noise.width = 256
	noise.height = 256
	noise.noise = FastNoiseLite.new()
	var asset: String = map_data.get("background_asset", "")
	shader_material.set_shader_parameter("background_texture", load(asset_data[asset].path) if asset_data.has(asset) else noise)
	shader_material.set_shader_parameter("blur", float(map_data.background_blur) / 1000.0)
	plane.material_override = shader_material
	add_child(plane)

func build_object(object: Dictionary, parent_node: Node3D) -> void:
	var node := Node3D.new()
	node.name = object.id
	node.position = Vector3(float(object.position[0]), float(object.height), float(object.position[1]))
	node.rotation.y = -deg_to_rad(float(object.rotation))
	node.scale = Vector3(float(object.scale[0]), 1, float(object.scale[1]))
	node.set_meta("editor_object", object.duplicate(true))
	parent_node.add_child(node)
	var visual_data: Dictionary = object.visual
	if asset_data.has(visual_data.asset) and bool(visual_data.visible) and object.type != "deployment":
		var sprite := Sprite3D.new()
		sprite.render_priority = 1
		sprite.name = "Visual"
		sprite.texture = load(asset_data[visual_data.asset].path)
		sprite.pixel_size = 1.0
		sprite.modulate.a = float(visual_data.opacity)
		sprite.scale = Vector3(float(visual_data.size[0]) / sprite.texture.get_width(), float(visual_data.size[1]) / sprite.texture.get_height(), 1)
		sprite.no_depth_test = false
		if object.type in ["mud", "pit", "web", "thorns", "decoration", "broken_barricade", "edge_decoration"]:
			sprite.rotation.x = -PI * 0.5
			sprite.position.y = 0.03 + int(visual_data.z_index) * 0.001
		else:
			sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			sprite.position.y = float(visual_data.size[1]) * 0.5
		node.add_child(sprite)
	if object.get("collision", {}).get("enabled", false):
		var body := StaticBody3D.new()
		body.name = "EntityCollision"
		body.collision_layer = int(object.collision.get("layer", 1))
		node.add_child(body)
		add_shape(body, object.collision)
	if object.get("region", {}).get("enabled", false):
		var area := Area3D.new()
		area.name = "DeploymentRegion" if object.type == "deployment" else "EffectRegion"
		area.collision_layer = 0
		area.collision_mask = 1
		area.set_meta("editor_effect", object.duplicate(true))
		node.add_child(area)
		var region_data: Dictionary = object.region.duplicate(true)
		if object.type == "web":
			region_data["base_height"] = float(object.min_height)
			region_data["height"] = maxf(0.01, float(object.max_height) - float(object.min_height))
		add_shape(area, region_data)
	if object.type == "deployment":
		for index in range(object.slots.size()):
			var marker := Marker3D.new()
			marker.name = "Slot" + str(index)
			marker.position = Vector3(float(object.slots[index][0]), 0, float(object.slots[index][1]))
			marker.rotation.y = deg_to_rad(float(object.facing))
			node.add_child(marker)
	if object.type == "enemy": node.set_meta("monster_config_id", object.monster_config_id)
	if object.get("click_area", {}).get("enabled", false):
		var area := Area3D.new()
		area.name = "InteractionRegion"
		area.set_meta("editor_interaction", object.duplicate(true))
		node.add_child(area)
		add_shape(area, object.click_area)

func add_shape(parent_node: Node3D, data: Dictionary) -> void:
	# Concave 2D outlines are decomposed, rather than silently filled by a hull.
	if data.shape == "polygon":
		var outline := PackedVector2Array()
		for point: Array in data.points: outline.append(v2(point))
		for part in Geometry2D.decompose_polygon_in_convex(outline):
			var collision_part := CollisionShape3D.new()
			var shape_part := ConvexPolygonShape3D.new()
			var vertices := PackedVector3Array()
			var bottom := float(data.get("base_height", 0)) - float(data.get("depth", 0))
			for point: Vector2 in part:
				vertices.append(Vector3(point.x, bottom, point.y))
				vertices.append(Vector3(point.x, bottom + maxf(0.01, float(data.height)) + float(data.get("depth", 0)), point.y))
			shape_part.points = vertices
			collision_part.shape = shape_part
			collision_part.position = Vector3(float(data.offset[0]), 0, float(data.offset[1]))
			collision_part.rotation.y = -deg_to_rad(float(data.rotation))
			parent_node.add_child(collision_part)
		return
	var collision := CollisionShape3D.new()
	var height := maxf(0.01, float(data.height))
	if data.shape == "polygon":
		var shape := ConvexPolygonShape3D.new()
		var points := PackedVector3Array()
		for point: Array in data.points:
			points.append(Vector3(float(point[0]), 0, float(point[1])))
			points.append(Vector3(float(point[0]), height, float(point[1])))
		shape.points = points
		collision.shape = shape
	else:
		if data.shape == "circle":
			var shape := CylinderShape3D.new()
			shape.height = height
			shape.radius = 0.5
			collision.shape = shape
			collision.scale = Vector3(float(data.size[0]), 1, float(data.size[1]))
		else:
			var shape := BoxShape3D.new()
			shape.size = Vector3(float(data.size[0]), height, float(data.size[1]))
			collision.shape = shape
		collision.position.y = height * 0.5
	collision.position.x = float(data.offset[0])
	collision.position.z = float(data.offset[1])
	collision.position.y += float(data.get("base_height", 0)) - float(data.get("depth", 0)) * 0.5
	collision.rotation.y = -deg_to_rad(float(data.rotation))
	parent_node.add_child(collision)
