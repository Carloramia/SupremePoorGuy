extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_Ratkin.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor.generate_creature())
	var generator: Node = actor.get_node("RatkinGenerator")
	# Persist the default per-part rules so their modes remain editable in Inspector.
	if generator.part_scene_rules.is_empty():
		for part: Node in actor.get_node("GeneratedParts").get_children():
			if not part is PhysicalBodyPart3D: continue
			var key := str(part.get_meta("generated_part_key"))
			var rule = generator.get_part_scene_rule(str(part.get_meta("generated_part_type", "")), key, key)
			if rule != null: generator.part_scene_rules.append(rule)
		var defaults = load(generator._get_defaults_path())
		defaults.parameters["part_scene_rules"] = generator.part_scene_rules
		assert(ResourceSaver.save(defaults, generator._get_defaults_path()) == OK)
	var generator_scene := PackedScene.new()
	assert(generator_scene.pack(generator) == OK)
	var generator_path := "res://Scenes/Creatures/Generators/RatkinGenerator.tscn"
	assert(ResourceSaver.save(generator_scene, generator_path) == OK)
	var generator_content := FileAccess.get_file_as_string(generator_path)
	var generator_header := generator_content.substr(0, generator_content.find("\n"))
	generator_content = generator_content.replace(generator_header, generator_header + "\n\n[ext_resource type=\"PackedScene\" path=\"res://Scenes/Creatures/Generators/_BaseCreatureGenerator.tscn\" id=\"ratkin_generator_base\"]")
	var generator_pattern := RegEx.new()
	generator_pattern.compile('(?m)^\\[node name="RatkinGenerator"[^\\n]*')
	generator_content = generator_pattern.sub(generator_content, '[node name="RatkinGenerator" instance=ExtResource("ratkin_generator_base")]')
	var generator_file := FileAccess.open(generator_path, FileAccess.WRITE)
	generator_file.store_string(generator_content)
	generator_file.close()
	generator._clear_generated_preview()
	for node: Node in actor.get_node("GeneratedParts").get_children():
		if node is RigidBody3D: node.freeze = true
	# Do not serialize runtime-only damage coordinators or debug trackers.
	var damage: Node = actor.get_node_or_null("CharacterDamageController3D")
	if damage != null:
		actor.remove_child(damage)
		damage.free()
	actor.generate_on_ready = true
	var scene := PackedScene.new()
	assert(scene.pack(actor) == OK)
	assert(ResourceSaver.save(scene, "res://Scenes/Creatures/Characters/Generate_Ratkin.tscn") == OK)
	# Runtime packing flattens an inherited root. Restore the shared base and
	# keep only overrides for the three components already owned by that base.
	var path := "res://Scenes/Creatures/Characters/Generate_Ratkin.tscn"
	var content := FileAccess.get_file_as_string(path)
	var header := content.substr(0, content.find("\n"))
	content = content.replace(header, header + "\n\n[ext_resource type=\"PackedScene\" path=\"res://Scenes/Creatures/Characters/_BaseGeneratedCreature.tscn\" id=\"ratkin_base\"]")
	var pattern := RegEx.new()
	pattern.compile('(?m)^\\[node name="GenerateRatkin"[^\\n]*')
	content = pattern.sub(content, '[node name="GenerateRatkin" instance=ExtResource("ratkin_base")]\ngenerate_on_ready = true')
	var components := ["GeneratedLegStepMovementController3D", "CreatureRecoveryStateMachine3D", "CreatureActionController3D"]
	for i in range(components.size()):
		pattern.compile('(?m)^\\[node name="' + components[i] + '"[^\\n]*')
		content = pattern.sub(content, '[node name="' + components[i] + '" parent="." index="' + str(i) + '"]')
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	actor.free()
	await process_frame
	print("PASS: authored Ratkin scene with frozen editor-visible Parts and inherited generated-character base.")
	quit()

