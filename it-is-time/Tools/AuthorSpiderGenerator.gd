extends SceneTree
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path := "res://Scenes/Creatures/Generators/SpiderGenerator.tscn"
	var generator = load(path).instantiate()
	root.add_child(generator)
	assert(generator.generate_torso())
	var scene := PackedScene.new()
	assert(scene.pack(generator) == OK)
	assert(ResourceSaver.save(scene, path) == OK)
	var content := FileAccess.get_file_as_string(path)
	var header := content.substr(0, content.find("\n"))
	content = content.replace(header, header + "\n\n[ext_resource type=\"PackedScene\" path=\"res://Scenes/Creatures/Generators/_BaseCreatureGenerator.tscn\" id=\"spider_base\"]")
	var pattern := RegEx.new()
	pattern.compile('(?m)^\\[node name="SpiderGenerator"[^\\n]*')
	content = pattern.sub(content, '[node name="SpiderGenerator" instance=ExtResource("spider_base")]')
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	generator.free()
	await process_frame
	print("PASS: saved SpiderGenerator with editor-visible framework and inherited base.")
	quit()
