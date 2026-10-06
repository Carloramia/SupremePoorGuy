extends SceneTree
const GENERATOR = preload("res://Scripts/Creatures/Generators/BirdGenerator.gd")
var failed := false

func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	var generator := GENERATOR.new()
	generator.feathers_enabled = true
	generator.feather_spacing = 0.15
	generator.feather_tip_alignment_enabled = true
	var blocks: Array[Dictionary] = []
	for section: String in ["Root","Middle","Tip"]:
		var size := Vector3(0.6,2.0,0.08)
		blocks.append({"section":section,"size":size,"feathers":generator._plan_feathers(size,0.0)})
	generator._arrange_feather_edge(blocks)
	var tips := PackedVector3Array()
	var offset := 0.0
	var last_angle := INF
	for block: Dictionary in blocks:
		for feather: Dictionary in block.feathers:
			var root: Vector3 = feather.transform.origin+Vector3(0,offset+block.size.y*0.5,0)
			var tip: Vector3 = root+feather.transform.basis.y*feather.size.y
			tips.append(tip)
			check(tip.distance_to(feather.spread_endpoint)<0.0001,"Planned geometry must reach the sampled edge")
			if block.section == "Tip":
				var angle := rad_to_deg(acos(clampf(feather.transform.basis.y.dot(Vector3.UP),-1,1)))
				check(angle<=last_angle+0.1,"Tip feathers must increasingly align toward the wing tip")
				last_angle = angle
		offset += block.size.y
	check(blocks[-1].feathers[-1].transform.basis.y.dot(Vector3.UP)>0.99999,"Final feather must align exactly with wing +Y")
	var minimum := INF
	var maximum := 0.0
	for index: int in range(1,tips.size()):
		var gap := tips[index].distance_to(tips[index-1])
		minimum = minf(minimum,gap)
		maximum = maxf(maximum,gap)
	print("[feather_edge_test] gap_min=",minimum," gap_max=",maximum," terminal_angle=",last_angle)
	check(maximum/minimum<1.1,"Endpoints must be approximately equally spaced along the curve")
	# Disable tip alignment/fan: equal-length feathers create a straight trailing edge.
	generator.feather_tip_alignment_enabled = false
	generator.feather_spread_degrees = 0.0
	generator.feather_tip_length_multiplier = 1.0
	generator._arrange_feather_edge(blocks)
	var start: Vector3 = blocks[0].feathers[0].spread_endpoint
	var end: Vector3 = blocks[-1].feathers[-1].spread_endpoint
	for block: Dictionary in blocks:
		for feather: Dictionary in block.feathers:
			check((Vector3(feather.spread_endpoint)-start).cross(end-start).length()<0.001,"Straight-edge settings must produce a line")
	generator.free()
	print("FEATHER_SPREAD_EDGE_","FAILED" if failed else "PASSED")
	quit(1 if failed else 0)
