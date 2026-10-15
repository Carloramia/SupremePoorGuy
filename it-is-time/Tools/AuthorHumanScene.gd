extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	assert(actor.generate_creature())
	actor.get_node("HumanGenerator")._clear_generated_preview()
	for part: Node in actor.get_node("GeneratedParts").get_children():
		if part is RigidBody3D: part.freeze = true
	var damage: Node = actor.get_node_or_null("CharacterDamageController3D")
	if damage != null:
		actor.remove_child(damage)
		damage.free()
	actor.generate_on_ready = true
	var scene := PackedScene.new()
	assert(scene.pack(actor) == OK)
	var path := "res://Scenes/Creatures/Characters/Generate_Human.tscn"
	assert(ResourceSaver.save(scene,path) == OK)
	# Packing a live root flattens inheritance; keep the common character scene.
	var content := FileAccess.get_file_as_string(path)
	var header := content.substr(0,content.find("\n"))
	content = content.replace(header,header + '\n\n[ext_resource type="PackedScene" path="res://Scenes/Creatures/Characters/_BaseGeneratedCreature.tscn" id="human_base"]')
	var pattern := RegEx.new()
	pattern.compile('(?m)^\\[node name="GenerateHuman"[^\\n]*')
	content = pattern.sub(content,'[node name="GenerateHuman" instance=ExtResource("human_base")]\ngenerate_on_ready = true')
	var components := ["GeneratedLegStepMovementController3D", "CreatureRecoveryStateMachine3D", "CreatureActionController3D"]
	for index: int in components.size():
		pattern.compile('(?m)^\\[node name="' + components[index] + '"[^\\n]*')
		content = pattern.sub(content,'[node name="' + components[index] + '" parent="." index="' + str(index) + '"]')
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(content)
	file.close()
	actor.free()
	print("PASS: Authored editor-visible Human assembly with inherited character root.")
	quit()
