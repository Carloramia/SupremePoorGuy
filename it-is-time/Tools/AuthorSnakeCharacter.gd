extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var path := "res://Scenes/Creatures/Characters/Generate_Snake.tscn"
	var actor := (load(path) as PackedScene).instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor.generate_creature())
	# Store only the physical preview on the character, avoiding nested generator preview conflicts.
	actor.get_node("SnakeGenerator")._clear_generated_preview()
	var movement := actor.get_node_or_null("SnakeMovementController3D")
	if movement != null: movement.cancel_action(&"authoring")
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true
	var damage := actor.get_node_or_null("CharacterDamageController3D")
	if damage != null:
		actor.remove_child(damage)
		damage.free()
	actor.generate_on_ready = true
	var overall: float = actor.get_node("SnakeGenerator").overall_scale
	var packed := PackedScene.new()
	assert(packed.pack(actor) == OK)
	assert(ResourceSaver.save(packed, path) == OK)
	var content := FileAccess.get_file_as_string(path)
	var header := content.substr(0, content.find("\n"))
	content = content.replace(header, header + "\n\n[ext_resource type=\"PackedScene\" path=\"res://Scenes/Creatures/Characters/_SampleCharacter.tscn\" id=\"snake_character_base\"]")
	var pattern := RegEx.new()
	assert(pattern.compile('(?m)^\\[node name="GenerateSnake"[^\\n]*') == OK)
	content = pattern.sub(content, '[node name="GenerateSnake" instance=ExtResource("snake_character_base")]')
	# Packing can omit a script-default value even when the inherited generator scene uses another value.
	var start := content.find('[node name="SnakeGenerator"')
	var end := content.find("\n[node ", start + 1)
	if end < 0: end = content.length()
	var block := content.substr(start, end - start)
	assert(pattern.compile("(?m)^overall_scale =[^\\n]*\\n") == OK)
	block = pattern.sub(block, "")
	var newline := block.find("\n")
	block = block.insert(newline + 1, "overall_scale = %s\n" % overall)
	content = content.substr(0, start) + block + content.substr(end)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	actor.free()
	await process_frame
	print("PASS: saved Generate_Snake physical editor preview, inherited character base and generator reference.")
	quit()
