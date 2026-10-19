extends SceneTree
const FACTORY = preload("res://Scripts/Application/CreatureFactory.gd")
const RENDERER = preload("res://Scripts/Application/CreaturePortraitRenderer.gd")
const PORTRAIT = preload("res://Modules/PaperUI/Scenes/UI/Components/MonsterPortrait.tscn")
var failed := false
func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)

func run() -> void:
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var renderer := RENDERER.new()
	root.add_child(renderer)
	var controllers_before := get_nodes_in_group(&"npc_state_machines").size()
	var parts_before := get_nodes_in_group(&"physical_body_parts").size()
	for id: String in FACTORY.DEFINITIONS:
		var record := FACTORY.template(id)
		var preview: Dictionary = renderer._build_preview(record)
		var model: Node3D = preview.model
		check(preview.visuals>0 and AABB(preview.bounds).size.x>0.0 and AABB(preview.bounds).size.y>0.0,"Every registered species has visible saved geometry: "+id)
		# Dummy headless rendering cannot inspect every authored mesh material; keep geometry checks off-tree.
		for node: Node in model.get_children():
			check(node is MeshInstance3D or node is Sprite3D,"Preview contains only visible render geometry")
			check(node.get_script()==null and node.get_child_count()==0,"Preview never runs scene scripts or includes controller/debug children")
			check(node.layers==1,"Every saved visual is visible to the portrait camera")
		check(model.find_children("*","PhysicsBody3D",true,false).is_empty() and model.find_children("*","Joint3D",true,false).is_empty(),"Portraits contain no physical bodies or joints")
		check(preview.head_visuals > 0, "Registered species have visible Head geometry: " + id)
		var framing: Dictionary = renderer._framing(preview)
		var head: AABB = preview.head_bounds
		var aspect := float(renderer.IMAGE_SIZE.x) / renderer.IMAGE_SIZE.y
		var area_ratio: float = head.size.x * head.size.y / (framing.extent * framing.extent * aspect)
		check(Vector3(framing.center).is_equal_approx(head.get_center()), "Portrait centers on the visible head: " + id)
		check(area_ratio <= renderer.HEAD_AREA_RATIO + 0.001, "Head occupies at most the target area: " + id)
		check(head.size.y * 1.12 <= framing.extent + 0.001 and head.size.x * 1.12 <= framing.extent * aspect + 0.001, "The head fits without cropping: " + id)
		print("CREATURE_PORTRAIT_FRAMING species=", id, " head=", head, " area_ratio=", area_ratio)
		print("CREATURE_PORTRAIT_GEOMETRY species=",id," visuals=",preview.visuals," bounds=",preview.bounds)
		model.free()
	var record := FACTORY.template("wolf")
	var changed := record.duplicate(true)
	for path: String in changed.poses:
		if path == "GeneratedParts":
			changed.poses[path][9] += 25.0
			changed.poses[path][10] += 5.0
	var original_preview: Dictionary = renderer._build_preview(record)
	var changed_preview: Dictionary = renderer._build_preview(changed)
	check(AABB(original_preview.bounds).size.is_equal_approx(AABB(changed_preview.bounds).size),"Saved pose offsets do not rescale the portrait model")
	check((AABB(changed_preview.bounds).position-AABB(original_preview.bounds).position).is_equal_approx(Vector3(25,5,0)),"Preview honors the individual's saved part hierarchy transforms")
	check((Vector3(renderer._framing(changed_preview).center)-Vector3(renderer._framing(original_preview).center)).is_equal_approx(Vector3(25,5,0)), "Head framing follows saved hierarchy offsets")
	var framing := renderer._framing({"bounds":AABB(Vector3(-50,-50,-50),Vector3.ONE*100),"head_bounds":AABB(Vector3(8,4,0),Vector3(4,3,1)),"head_visuals":1})
	check(is_equal_approx(4.0*3.0/(framing.extent*framing.extent*(512.0/384.0)),0.25), "Head area remains 25 percent regardless of body size")
	check(Vector3(framing.center).is_equal_approx(Vector3(10,5.5,0.5)), "Body bounds do not shift a valid head focus")
	var scaled := renderer._framing({"bounds":AABB(Vector3.ZERO,Vector3.ONE*10),"head_bounds":AABB(Vector3(16,8,0),Vector3(8,6,2)),"head_visuals":1})
	check(is_equal_approx(scaled.extent,framing.extent*2.0), "Uniform head scaling preserves its picture area")
	var fallback := renderer._framing({"bounds":AABB(Vector3.ZERO,Vector3(8,3,1)),"head_visuals":0})
	check(Vector3(fallback.center).is_equal_approx(Vector3(4,1.5,0.5)) and is_equal_approx(fallback.extent,6.72), "Missing heads retain the original full-body framing")
	original_preview.model.free()
	changed_preview.model.free()
	var portrait := PORTRAIT.instantiate()
	root.add_child(portrait)
	renderer.request(portrait,record)
	check(portrait.get_node("Artwork").texture!=null and not portrait.use_reference_examples,"Real creature records replace prototype reference art immediately")
	if DisplayServer.get_name()=="headless":
		check(renderer._queue.is_empty(),"Headless simulations never schedule GPU screenshots")
	check(get_nodes_in_group(&"npc_state_machines").size()==controllers_before and get_nodes_in_group(&"physical_body_parts").size()==parts_before,"Portrait generation never registers gameplay controllers or parts")
	portrait.free()
	renderer.free()
	if not failed: print("CREATURE_PORTRAIT_VALIDATION_PASSED")
	quit(1 if failed else 0)
