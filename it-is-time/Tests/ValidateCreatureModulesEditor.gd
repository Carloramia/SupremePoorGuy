@tool
extends SceneTree

const ATTACHMENT = preload("res://Scripts/Creatures/Modules/CreatureModuleAttachment.gd")

func _initialize() -> void: run.call_deferred()

func run() -> void:
	assert(Engine.is_editor_hint(),"Run with --editor")
	var actor: Node3D = load("res://Scenes/Creatures/Characters/Examples/Generate_ModularBeast.tscn").instantiate()
	root.add_child(actor)
	assert(actor.generate_creature())
	assert(actor.has_node("GeneratedParts/Torso/Module_indicator"))
	assert(actor.has_node("GeneratedParts/Module_pendant__Attachment"))
	assert(actor._capture_manual_layout())
	var entry: ATTACHMENT = actor.module_attachments[1]
	assert(entry.captured_scene!=null)
	assert(entry.get("reset_capture_button") is Callable)
	assert(entry.get("reset_capture_button").is_valid())
	assert(actor.generate_creature())
	var packed := PackedScene.new()
	assert(packed.pack(actor)==OK)
	var restored: Node3D = packed.instantiate()
	root.add_child(restored)
	assert(restored.generate_creature())
	assert(restored.get_node("GeneratedParts/Module_pendant__Attachment/CollisionShape3D").shape!=null)
	restored.free()
	entry.get("reset_capture_button").call()
	assert(entry.captured_scene==null)
	assert(actor.generate_creature())
	actor.free()
	print("ValidateCreatureModulesEditor PASSED")
	quit()
