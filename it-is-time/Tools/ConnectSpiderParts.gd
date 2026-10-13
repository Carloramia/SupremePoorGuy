extends SceneTree
const RULE = preload("res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var path := "res://Scenes/Creatures/Generators/SpiderGenerator.tscn"
	var generator: Node = load(path).instantiate()
	var rules: Array[RULE] = []
	var associations := {}
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/model_manifest.json"))
	var holes: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/generator_source_holes.json"))
	for key: String in ["Torso_Front","Torso_Rear","Head"]:
		var rule := RULE.new()
		rule.part_key=key
		rule.part_name=key
		rule.part_type="Head" if key=="Head" else "Torso"
		var asset := "Head/Head" if key=="Head" else ("Torso/FrontTorso" if key=="Torso_Front" else "Torso/RearTorso")
		var source_path := "res://Scenes/Creatures/Bodyparts/Spider/"+asset+".tscn"
		var record: Dictionary
		for candidate: Dictionary in manifest.models:
			if candidate.physical_scene==source_path: record=candidate
		var source_holes: Array = holes[record.volume_mesh].holes
		var markers := {}
		if key=="Torso_Front":
			for i: int in 4: markers["SpiderRoot_%d" % [i+1]]=source_holes[[1,5,4,0][i]].pixel
			markers.JointOut=source_holes[3].pixel
			markers.JointIn=source_holes[2].pixel
		elif key=="Torso_Rear":
			markers.JointIn=source_holes[1].pixel
			markers.JointOut=source_holes[0].pixel
		else: markers.JointIn=source_holes[0].pixel
		var variant := "res://Scenes/Creatures/Bodyparts/Spider/Calibrated/"+asset+".tscn"
		var content := '[gd_scene format=3]\n[ext_resource type="PackedScene" path="%s" id="base"]\n[node name="SpiderCalibratedBody" instance=ExtResource("base")]\n' % source_path
		for marker: String in markers:
			var pixel: Array = markers[marker]
			var position := Vector3(pixel[0]-record.pivot_pixel[0],record.pivot_pixel[1]-pixel[1],0)*float(record.units_per_texture_pixel)
			content += ('[node name="%s" type="Marker3D" parent="."]\n' if marker.begins_with("SpiderRoot_") else '[node name="%s" parent="."]\n') % marker
			content += "position = %s\n" % var_to_str(position)
		DirAccess.make_dir_recursive_absolute(variant.get_base_dir())
		var output := FileAccess.open(variant,FileAccess.WRITE)
		output.store_string(content)
		output.close()
		rule.part_scene=load(variant)
		rule.size_mode=RULE.SizeMode.FIT_BOX if key=="Torso_Front" else RULE.SizeMode.FIT_UNIFORM
		rule.align_connectors_to_frame=key=="Head"
		rules.append(rule)
		associations[key]=rule.part_scene.resource_path
	for side: int in 2:
		for pair: int in 4:
			var prefix := "Leg_%d" % [side*4+pair+1]
			var asset_side := ("Left" if side==0 else "Right")+"_%d" % [pair+1]
			for upper: bool in [true,false]:
				var rule := RULE.new()
				rule.part_key=prefix+("_Limb_1" if upper else "")
				rule.part_name=rule.part_key
				rule.part_type="LegLimb" if upper else "Leg"
				var variant_directory := "FrameFitted" if FileAccess.file_exists("res://Assets/3DResources/Creatures/Spider/Metadata/frame_fitted_manifest.json") else "Calibrated"
				rule.part_scene=load("res://Scenes/Creatures/Bodyparts/Spider/"+variant_directory+"/Legs/"+asset_side+("/UpperLeg.tscn" if upper else "/LowerLeg.tscn"))
				rule.use_joint_markers=true
				rule.align_connectors_to_frame=true
				rules.append(rule)
				associations[rule.part_key]=rule.part_scene.resource_path
	var preset := load("res://Resources/Generators/SpiderGeneratorDefaults.tres")
	preset.parameters["part_scene_rules"]=rules
	assert(ResourceSaver.save(preset)==OK)
	var text := FileAccess.get_file_as_string(path)
	var cleanup := RegEx.new()
	cleanup.compile('(?m)^\\[ext_resource[^\\n]* id="spider_(?:part_[0-9]+|rule)"\\]\\r?\\n|^part_scene_rules = [^\\n]*\\r?\\n')
	text=cleanup.sub(text,"",true)
	var ext := ""
	for i: int in rules.size():
		var rule_path := "res://Resources/Generators/SpiderParts/"+rules[i].part_key+".tres"
		DirAccess.make_dir_recursive_absolute(rule_path.get_base_dir())
		assert(ResourceSaver.save(rules[i],rule_path)==OK)
		ext += '[ext_resource type="Resource" path="%s" id="spider_part_%d"]\n' % [rule_path,i]
	ext += '[ext_resource type="Script" path="res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd" id="spider_rule"]\n'
	var insert_at := text.find("[sub_resource")
	text=text.insert(insert_at,ext+"\n")
	var root_at := text.find('[node name="SpiderGenerator"')
	var line_end := text.find("\n",root_at)
	var references := PackedStringArray()
	for i: int in rules.size(): references.append('ExtResource("spider_part_%d")' % i)
	text=text.insert(line_end+1,'part_scene_rules = Array[ExtResource("spider_rule")](['+", ".join(references)+'])\n')
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(text)
	file.close()
	file=FileAccess.open("res://Assets/3DResources/Creatures/Spider/Metadata/generator_part_mapping.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(associations,"  "))
	file.close()
	generator.free()
	print("PASS: saved 19 persistent Spider scene rules and defaults.")
	quit()
