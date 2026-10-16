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
