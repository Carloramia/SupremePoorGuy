extends SceneTree

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var path := "res://Scenes/Creatures/Characters/Generate_Spider.tscn"
	var actor = load(path).instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor.generate_creature())
	actor.get_node("SpiderGenerator")._clear_generated_preview()
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true
	var damage: Node = actor.get_node_or_null("CharacterDamageController3D")
	if damage != null:
		actor.remove_child(damage)
		damage.free()
	actor.generate_on_ready = true
	var scene := PackedScene.new()
	assert(scene.pack(actor) == OK)
	assert(ResourceSaver.save(scene, path) == OK)
	# Preserve the shared character base after packing the generated editor preview.
	var content := FileAccess.get_file_as_string(path)
	var header := content.substr(0, content.find("\n"))
	content = content.replace(header, header + "\n\n[ext_resource type=\"PackedScene\" path=\"res://Scenes/Creatures/Characters/_BaseGeneratedCreature.tscn\" id=\"spider_character_base\"]")
	var pattern := RegEx.new()
	pattern.compile('(?m)^\\[node name="GenerateSpider"[^\\n]*')
	content = pattern.sub(content, '[node name="GenerateSpider" instance=ExtResource("spider_character_base")]\ngenerate_on_ready = true')
	var components := ["GeneratedLegStepMovementController3D", "CreatureRecoveryStateMachine3D", "CreatureActionController3D"]
	for index: int in range(components.size()):
		pattern.compile('(?m)^\\[node name="' + components[index] + '"[^\\n]*')
		content = pattern.sub(content, '[node name="' + components[index] + '" parent="." index="' + str(index) + '"]')
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	actor.free()
	await process_frame
	print("PASS: saved inherited Generate_Spider with frozen editor preview.")
	quit()
