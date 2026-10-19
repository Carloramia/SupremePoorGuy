extends SceneTree

const HOLES := {
	"R": {"upper":Vector2(931.0787062,625.4030548),"lower":Vector2(151.5922392,159.8541985)},
	"L": {"upper":Vector2(113.5138914,175.3428364),"lower":Vector2(654.7993505,887.8164616)},
}

func _initialize() -> void: run.call_deferred()

## The front mesh has affine texture UVs; project the measured texture hole into its midplane.
func hole_position(body: Node3D, pixel: Vector2) -> Vector3:
	var visual := body.get_node("Model/PaperVolume") as MeshInstance3D
	var texture := (visual.mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture
	var target := pixel/Vector2(texture.get_size())
	var arrays := visual.mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for second: int in range(1,uv.size()):
		var x := uv[second]-uv[0]
		if x.is_zero_approx(): continue
		for third: int in range(second+1,uv.size()):
			var y := uv[third]-uv[0]
			var determinant := x.cross(y)
			if absf(determinant)<0.000001: continue
			var delta := target-uv[0]
			var point := vertices[0]+(vertices[second]-vertices[0])*delta.cross(y)/determinant+(vertices[third]-vertices[0])*x.cross(delta)/determinant
			point.z = 0.0
			return visual.to_global(point)
	assert(false,"No affine UV basis")
	return Vector3.ZERO

func verify(actor: Node3D, phase: String) -> void:
	for side: String in ["R","L"]:
		var upper := actor.get_node("GeneratedParts/Arm_"+side+"_Limb_2") as Node3D
		var lower := actor.get_node("GeneratedParts/Arm_"+side+"_Limb_1") as Node3D
		var joint: Generic6DOFJoint3D
		for candidate: Joint3D in actor.get_node("GeneratedParts/Joints").get_children():
			if candidate.get_node_or_null(candidate.node_a)==upper and candidate.get_node_or_null(candidate.node_b)==lower: joint=candidate
		assert(joint != null)
		var a: Transform3D = joint.get_meta(&"generated_joint_frame_a")
		var b: Transform3D = joint.get_meta(&"generated_joint_frame_b")
		var first := hole_position(upper,HOLES[side].upper)
		var second := hole_position(lower,HOLES[side].lower)
		assert(joint.global_position.distance_to(first.lerp(second,0.5))<0.00001)
		assert(first.distance_to(joint.global_position)<0.01 and second.distance_to(joint.global_position)<0.01)
		assert(upper.to_global(a.origin).distance_to(lower.to_global(b.origin))<0.00001)
		assert(upper.get_node("JointOut_"+str(lower.name)).global_position.distance_to(joint.global_position)<0.00001)
		assert(lower.get_node("JointIn_"+str(upper.name)).global_position.distance_to(joint.global_position)<0.00001)
		var pose := lower.global_transform
		var local_hole := lower.to_local(second)
		var maximum_gap := 0.0
		for degrees: float in [-90.0,-45.0,0.0,45.0,90.0]:
			var rotation := Basis(Vector3.BACK,deg_to_rad(degrees))
			lower.global_transform = Transform3D(rotation*pose.basis,joint.global_position+rotation*(pose.origin-joint.global_position))
			maximum_gap = maxf(maximum_gap,first.distance_to(lower.to_global(local_hole)))
			assert(upper.to_global(a.origin).distance_to(lower.to_global(b.origin))<0.00001)
		lower.global_transform = pose
		assert(maximum_gap<0.02,"Visual holes must stay together throughout elbow rotation")
		print("HUMAN_ELBOW_ALIGNMENT actor=",actor.name," phase=",phase," side=",side," upper_error=",first.distance_to(joint.global_position)," lower_error=",second.distance_to(joint.global_position)," rotation_maximum_gap=",maximum_gap)

func run() -> void:
	PhysicsServer3D.set_active(false)
	root.get_node("RuntimeConsole").auto_getlogs_enabled = false
	var audio := root.get_node("CombatAudio")
	audio.settings=audio.settings.duplicate()
	audio.settings.enabled=false
	for file: String in ["Generate_Human.tscn","Generate_Human_NPC.tscn","Human/Armed/Generate_Human_Spear1_NPC.tscn"]:
		var actor := load("res://Scenes/Creatures/Characters/"+file).instantiate() as Node3D
		actor.generate_on_ready=false
		actor.initial_weapon_scene=null
		actor.process_mode=Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		verify(actor,"saved")
		assert(actor.build_manual_layout()!=null)
		assert(actor.generate_creature())
		await process_frame
		verify(actor,"regenerated")
		actor.queue_free()
		await process_frame
		await process_frame
	print("HUMAN_ELBOW_ALIGNMENT_PASSED")
	quit()
