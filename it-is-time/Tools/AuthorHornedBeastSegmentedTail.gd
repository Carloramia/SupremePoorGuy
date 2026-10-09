extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor = load("res://Scenes/Creatures/Characters/Generate_HornedBeast.tscn").instantiate()
	actor.generate_on_ready = false
	actor.name = "GenerateHornedBeastSegmentedTail"
	actor.get_node("HornedBeastGenerator").use_segmented_tail = true
	root.add_child(actor)
	assert(actor.generate_creature())
	var generator: Node = actor.get_node("HornedBeastGenerator")
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
	assert(not FileAccess.file_exists("res://Scenes/Creatures/Characters/Generate_HornedBeast_SegmentedTail.tscn"))
	assert(ResourceSaver.save(scene, "res://Scenes/Creatures/Characters/Generate_HornedBeast_SegmentedTail.tscn") == OK)
	# Runtime packing flattens an inherited root. Restore the shared base and
	# keep only overrides for the three components already owned by that base.
	var path := "res://Scenes/Creatures/Characters/Generate_HornedBeast_SegmentedTail.tscn"
	var content := FileAccess.get_file_as_string(path)
	content = content.replace("[gd_scene format=3]", "[gd_scene format=3]\n\n[ext_resource type=\"PackedScene\" path=\"res://Scenes/Creatures/Characters/_BaseGeneratedCreature.tscn\" id=\"horned_base\"]")
	var pattern := RegEx.new()
	pattern.compile('(?m)^\\[node name="GenerateHornedBeastSegmentedTail"[^\\n]*')
	content = pattern.sub(content, '[node name="GenerateHornedBeastSegmentedTail" instance=ExtResource("horned_base")]\ngenerate_on_ready = true')
	var components := ["GeneratedLegStepMovementController3D", "CreatureRecoveryStateMachine3D", "CreatureActionController3D"]
	for i in range(components.size()):
		pattern.compile('(?m)^\\[node name="' + components[i] + '"[^\\n]*')
		content = pattern.sub(content, '[node name="' + components[i] + '" parent="." index="' + str(i) + '"]')
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	actor.free()
	await process_frame
	print("PASS: authored new segmented-tail HornedBeast scene with frozen editor-visible Parts and inherited generated-character base.")
	quit()

