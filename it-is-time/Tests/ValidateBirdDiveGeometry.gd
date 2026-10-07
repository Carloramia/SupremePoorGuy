extends SceneTree
const DATA = preload("res://Scripts/Creatures/BirdDiveAttackData.gd")
var failed := false
func check(value: bool, label: String) -> void:
	if not value: failed = true; push_error(label)
func _initialize() -> void:
	var data := DATA.new()
	check(data.evaluate_target_geometry(Vector3.ZERO,Vector3(5,-1.5,0)).hit,"Shallow dive must ignore old absolute height threshold")
	check(data.evaluate_target_geometry(Vector3.ZERO,Vector3(10,-8,3)).hit,"Valid angle must ignore old absolute Z threshold")
	check(data.evaluate_target_geometry(Vector3.ZERO,Vector3(-10,-8,-3)).hit,"Both X directions must be valid")
	check(not data.evaluate_target_geometry(Vector3.ZERO,Vector3(10,-1,0)).hit,"Insufficient depression must reject")
	check(not data.evaluate_target_geometry(Vector3.ZERO,Vector3(3,-8,10)).hit,"Large horizontal angle must reject")
	check(not data.evaluate_target_geometry(Vector3.ZERO,Vector3(5,8,0)).hit,"Target above the bird must reject")
	check(data.evaluate_target_geometry(Vector3.ZERO,Vector3(0,-10,0)).hit,"Vertical downward dive must be defined")
	check(not data.evaluate_target_geometry(Vector3.ZERO,Vector3.ZERO).hit,"Coincident positions must reject")
	var ray := Vector3(1,-1,0).normalized()
	check(data.evaluate_target_geometry(Vector3.ZERO,ray*40).hit,"Maximum distance boundary must pass")
	check(not data.evaluate_target_geometry(Vector3.ZERO,ray*40.1).hit,"Maximum distance must reject outside")
	check(not data.evaluate_target_geometry(Vector3.ZERO,ray*0.05).hit,"Minimum distance must reject inside")
	data.maximum_depression_angle_degrees = 60
	check(not data.evaluate_target_geometry(Vector3.ZERO,Vector3(0,-10,0)).hit,"Maximum depression must be configurable")
	data.maximum_depression_angle_degrees = 10
	check(not data.is_valid(),"Inverted angular interval must reject configuration")
	data.maximum_depression_angle_degrees = 90
	data.maximum_horizontal_angle_degrees = 30
	var boundary := Vector3(cos(deg_to_rad(30)), -tan(deg_to_rad(15)),sin(deg_to_rad(30)))*10
	check(data.evaluate_target_geometry(Vector3.ZERO,boundary).hit,"Exact angle boundaries must pass")
	check(not data.evaluate_target_geometry(Vector3(INF,0,0),Vector3.ZERO).hit,"Nonfinite geometry must reject")
	print("BIRD_DIVE_GEOMETRY_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
