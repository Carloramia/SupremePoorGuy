extends SceneTree
func _initialize() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Wolf/Metadata/model_manifest.json"))
	for record: Dictionary in manifest.models:
		var path: String = record.physical_scene
		var content := FileAccess.get_file_as_string(path)
		if content.contains("metadata/wolf_forward_axis"): continue
		content = content.replace("metadata/pivot_is_initial_estimate = true", "metadata/pivot_is_initial_estimate = true\nmetadata/wolf_forward_axis = \"+X\"")
		content = content.replace('[node name="CollisionShape3D" parent="." index="0"]', '[node name="CollisionShape3D" parent="." index="0"]\nrotation = Vector3(0, 3.141592653589793, 0)')
		var lines := content.split("\n")
		var marker := false
		for index: int in lines.size():
			if lines[index].begins_with("[node"):
				marker = lines[index].contains('name="JointIn"') or lines[index].contains('name="JointOut"')
				if lines[index].begins_with('[node name="Model" '): lines[index] += "\nrotation = Vector3(0, 3.141592653589793, 0)"
			elif marker and lines[index].begins_with("position = Vector3("):
				var values := lines[index].trim_prefix("position = Vector3(").trim_suffix(")").split(",")
				lines[index] = "position = Vector3(%s, %s, %s)" % [-float(values[0]),float(values[1]),-float(values[2])]
		var file := FileAccess.open(path,FileAccess.WRITE)
		file.store_string("\n".join(lines))
		file.close()
	print("PASS: Wolf physical geometry and markers face +X without rotating body frames.")
	quit()
