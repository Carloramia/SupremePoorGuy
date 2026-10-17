extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	for variant: int in [1,2]:
		if "--rat1-only" in OS.get_cmdline_user_args() and variant!=1: continue
		var path := "res://Scenes/Creatures/Characters/Generate_Rat_%d.tscn" % variant
		var actor = load(path).instantiate()
		actor.generate_on_ready = false
		actor.get_node("CreatureActionController3D").actions.clear()
		root.add_child(actor)
		assert(actor.generate_creature(), "Rats generation failed")
		actor.get_node("RatsGenerator")._clear_generated_preview()
		for node: Node in actor.get_node("GeneratedParts").get_children():
			if node is RigidBody3D: node.freeze = true
		var damage: Node = actor.get_node_or_null("CharacterDamageController3D")
		if damage != null:
			actor.remove_child(damage)
			damage.free()
		actor.generate_on_ready = true
		var packed := PackedScene.new()
		assert(packed.pack(actor)==OK)
		assert(ResourceSaver.save(packed,path)==OK)
		var content := FileAccess.get_file_as_string(path)
		var first_line := content.get_slice("\n",0)
		content = content.replace(first_line,first_line+'\n\n[ext_resource type="PackedScene" path="res://Scenes/Creatures/Characters/_BaseRats.tscn" id="rats_base"]')
		var pattern := RegEx.new()
		pattern.compile('(?m)^\\[node name="GenerateRat'+str(variant)+'"[^\\n]*')
		content = pattern.sub(content,'[node name="GenerateRat'+str(variant)+'" instance=ExtResource("rats_base")]\ngenerate_on_ready = true')
		var components := ["GeneratedLegStepMovementController3D","CreatureRecoveryStateMachine3D","CreatureActionController3D","RatsGenerator","WolfAttackController3D"]
		for index: int in components.size():
			pattern.compile('(?m)^\\[node name="'+components[index]+'"[^\\n]*')
			content = pattern.sub(content,'[node name="'+components[index]+'" parent="." index="'+str(index)+'"]')
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string(content)
		file.close()
		print("RATS_AUTHORED variant=",variant," parts=",actor.get_node("GeneratedParts").get_child_count()-1)
		actor.free()
		packed=null
		await process_frame
	print("PASS: requested Rats scenes authored with frozen editor-visible parts and inherited common components.")
	quit()
