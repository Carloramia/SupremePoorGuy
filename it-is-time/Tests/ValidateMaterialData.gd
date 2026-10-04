extends SceneTree

func _initialize() -> void:
	var material := load("res://Resources/Materials/TestMaterial.tres") as Resource
	assert(material != null)
	assert(material.get_script().get_base_script() == load("res://Scripts/Materials/_SampleMaterial.gd"))
	assert(material.material_id == &"TestMaterial")
	assert(material.display_name == "TestMaterial")
	assert(material.icon != null)
	assert(material.get_display_texture() != null)
	assert(is_equal_approx(material.cell_size, 0.64))
	assert(is_equal_approx(material.mass_per_cell, 0.25))
	assert(is_equal_approx(material.collision_thickness, 0.2))
	print("MATERIAL_DATA_VALIDATION_PASSED")
	quit()
