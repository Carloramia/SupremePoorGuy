extends Node
## Render saved creature visuals without entering any physics or controller nodes into the tree.
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const IMAGE_SIZE := Vector2i(512,384)
var _cache: Dictionary = {}
var _pending: Dictionary = {}
var _queue: Array[Dictionary] = []
var _busy := false
var _placeholder: ImageTexture

func _ready() -> void: process_mode = Node.PROCESS_MODE_ALWAYS

func request(portrait: Control, record: Dictionary) -> void:
	if not FACTORY.DEFINITIONS.has(record.get("definition_id","")): return
	var artwork := portrait.get_node("Artwork") as TextureRect
	if _placeholder == null:
		var image := Image.create(IMAGE_SIZE.x,IMAGE_SIZE.y,false,Image.FORMAT_RGBA8)
		image.fill(Color.WHITE)
		_placeholder = ImageTexture.create_from_image(image)
	var key := "%s:%s:%s" % [record.definition_id,record.get("template_hash",""),hash(record.get("poses",{}))]
	portrait.set_meta(&"creature_portrait_key",key)
	artwork.texture = _cache.get(key,_placeholder)
	portrait.use_reference_examples = false
	if _cache.has(key) or DisplayServer.get_name()=="headless": return
	if _pending.has(key):
		_pending[key].targets.append(weakref(portrait))
		return
	var job := {"key":key,"record":record.duplicate(true),"targets":[weakref(portrait)]}
	_pending[key] = job
	_queue.append(job)
	if not _busy: _render_next.call_deferred()

func _render_next() -> void:
	if _busy: return
	_busy = true
	while not _queue.is_empty():
		var job: Dictionary = _queue.pop_front()
		var texture := await _capture(job.record)
		_pending.erase(job.key)
		if texture == null: continue
		_cache[job.key] = texture
		for target: WeakRef in job.targets:
			var portrait := target.get_ref() as Control
			if is_instance_valid(portrait) and portrait.is_inside_tree() and portrait.get_meta(&"creature_portrait_key")==job.key:
				portrait.get_node("Artwork").texture = texture
	_busy = false

func _build_preview(record: Dictionary) -> Dictionary:
	var model := Node3D.new()
	model.name = "CreaturePortraitVisuals"
	var result := {"model":model,"bounds":AABB(),"visuals":0}
	var scene := load(FACTORY.DEFINITIONS[record.definition_id].scene) as PackedScene
	if scene == null: return result
	var actor := scene.instantiate()
	for node: Node in actor.find_children("*","",true,false):
		if node is PhysicalBodyPart3D:
			var collider := node.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if collider != null and collider.shape != null: collider.shape = collider.shape.duplicate()
			node.prepare_generated_geometry()
	# Saved internal model transforms take precedence over automatic fitting.
	for path: String in record.get("poses",{}):
		var node := actor.get_node_or_null(NodePath(path)) as Node3D
		if node != null: node.transform = FACTORY.unpack_transform(record.poses[path])
	for node: Node in actor.find_children("*","",true,false):
		if not (node is MeshInstance3D or node is Sprite3D): continue
		if node is MeshInstance3D and node.mesh == null: continue
		if node is Sprite3D and node.texture == null: continue
		var current: Node = node
		var pose := Transform3D.IDENTITY
		var visible := true
		var is_part := false
		while current != actor and current != null:
			if current is Node3D:
				visible = visible and current.visible
				pose = current.transform*pose
			if current is PhysicalBodyPart3D: is_part = true
			current = current.get_parent()
		if not visible or not is_part: continue
		var copy := node.duplicate(0) as GeometryInstance3D
		for child: Node in copy.get_children():
			copy.remove_child(child)
			child.free()
		copy.set_script(null)
		copy.top_level = false
		copy.layers = 1
		copy.transform = pose
		model.add_child(copy)
		var bounds: AABB = pose*copy.get_aabb()
		result.bounds = bounds if result.visuals==0 else AABB(result.bounds).merge(bounds)
		result.visuals += 1
	actor.free()
	return result

func _capture(record: Dictionary) -> ImageTexture:
	var preview := _build_preview(record)
	var model: Node3D = preview.model
	if preview.visuals == 0:
		model.free()
		push_warning("[creature_portrait] No saved visuals for "+str(record.definition_id))
		return null
	var viewport := SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.own_world_3d = true
	viewport.process_mode = Node.PROCESS_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_4X
	add_child(viewport)
	viewport.add_child(model)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color.WHITE
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.8
	viewport.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-20,-25,0)
	light.shadow_enabled = false
	viewport.add_child(light)
	var bounds: AABB = preview.bounds
	var extent := maxf(bounds.size.y,bounds.size.x*float(IMAGE_SIZE.y)/IMAGE_SIZE.x)*1.12
	var distance := maxf(bounds.size.z,1.0)+extent*2.0
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = maxf(extent,0.1)
	camera.near = 0.01
	camera.far = distance+bounds.size.z+100.0
	viewport.add_child(camera)
	camera.position = bounds.get_center()+Vector3(0,0,distance)
	camera.look_at(bounds.get_center(),Vector3.UP)
	camera.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	viewport.queue_free()
	if image == null or image.is_empty(): return null
	return ImageTexture.create_from_image(image)
