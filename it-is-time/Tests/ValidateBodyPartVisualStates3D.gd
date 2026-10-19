extends SceneTree

const STATE = preload("res://Scripts/Creatures/BodyPartVisualState3D.gd")
const SNAPSHOT = preload("res://Scripts/Creatures/Generators/ManualPartSnapshot.gd")

class Commands extends Node:
	var direction:=Vector3.ZERO
	func get_movement_direction() -> Vector3: return direction
	func get_generated_facing_direction(_delta:float) -> Vector3: return Vector3.RIGHT
	func is_jump_requested() -> bool: return false
	func is_fast_requested() -> bool: return false

func _initialize() -> void: call_deferred("run")

func physics_snapshot(part: PhysicalBodyPart3D) -> Dictionary:
	var collision := part.get_node("CollisionShape3D") as CollisionShape3D
	return {"id":part.get_instance_id(),"pose":part.transform,"shape":collision.shape,
		"collision_pose":collision.transform,"points":collision.shape.points if collision.shape is ConvexPolygonShape3D else collision.shape.size,
		"mass":part.mass,"hp":part.current_hp,"broken":part.is_broken,"tags":part.tags.duplicate(),
		"velocity":part.linear_velocity,"angular_velocity":part.angular_velocity,
		"in":part.get_node("JointIn").transform,"out":part.get_node("JointOut").transform}

func assert_same(actual: Dictionary, expected: Dictionary) -> void:
	for key: String in expected: assert(actual[key]==expected[key],"Visual change altered physics: "+key)

func verify_hand(record: Dictionary) -> void:
	var scene := load(record.physical_scene) as PackedScene
	var part := scene.instantiate() as PhysicalBodyPart3D
	part.freeze = true
	root.add_child(part)
	var untouched := scene.instantiate() as PhysicalBodyPart3D
	untouched.freeze = true
	root.add_child(untouched)
	var visual := part.get_node("Model/PaperVolume") as MeshInstance3D
	var authored_mesh := visual.mesh
	var authored_pose := visual.transform
	part.current_hp=83.0
	part.linear_velocity=Vector3(0.2,0.3,0.4)
	part.angular_velocity=Vector3(-0.1,0.2,0.3)
	var before := physics_snapshot(part)
	assert(part.get_available_visual_states()==[&"open",&"grip"])
	var last_state: Array[StringName] = []
	part.visual_state_changed.connect(func(value: StringName) -> void: last_state.append(value))
	for pose: StringName in [&"open",&"grip",&"open",&"grip"]:
		assert(part.set_visual_state(pose))
		assert(part.get_visual_state()==pose and last_state[-1]==pose)
		assert(visual.mesh.resource_path.ends_with(str(record.name)+str(pose).capitalize()+".res"))
		assert_same(physics_snapshot(part),before)
		assert(untouched.get_node("Model/PaperVolume").mesh==authored_mesh)
		assert(visual.global_transform.origin.is_equal_approx(part.get_node("JointIn").global_position))
		part.prepare_generated_geometry()
		assert_same(physics_snapshot(part),before)
		assert(visual.global_transform.origin.is_equal_approx(part.get_node("JointIn").global_position))
		var front := visual.mesh.surface_get_material(0) as StandardMaterial3D
		var back := visual.mesh.surface_get_material(1) as ShaderMaterial
		assert(front.albedo_texture.resource_path==record.states[str(pose)].palm)
		assert(back.get_shader_parameter(&"back_texture").resource_path==record.states[str(pose)].back)
		var uv_front: PackedVector2Array = visual.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var uv_back: PackedVector2Array = visual.mesh.surface_get_arrays(1)[Mesh.ARRAY_TEX_UV]
		for i: int in uv_front.size(): assert(uv_back[i].is_equal_approx(Vector2(1-uv_front[i].x,uv_front[i].y)))
	var active_mesh := visual.mesh
	assert(not part.set_visual_state(&"missing"))
	assert(visual.mesh==active_mesh and part.get_visual_state()==&"grip")
	assert(part.set_visual_state(&""))
	assert(visual.mesh==authored_mesh and visual.transform==authored_pose)
	assert_same(physics_snapshot(part),before)
	var snapshot := SNAPSHOT.capture(part,1.0,record.physical_scene)
	assert(snapshot.properties.visual_states.size()==2)
	var regenerated := scene.instantiate() as PhysicalBodyPart3D
	assert(SNAPSHOT.apply_to(regenerated,snapshot,2.0,record.physical_scene))
	regenerated.freeze=true
	root.add_child(regenerated)
	assert(regenerated.set_visual_state(&"grip"))
	assert(regenerated.get_node("Model/PaperVolume").global_position.is_equal_approx(regenerated.get_node("JointIn").global_position))
	assert(regenerated.set_visual_state(&""))
	assert(regenerated.get_node("Model/PaperVolume").mesh==authored_mesh)
	var initialized := scene.instantiate() as PhysicalBodyPart3D
	initialized.initial_visual_state=&"grip"
	initialized.freeze=true
	root.add_child(initialized)
	assert(initialized.get_visual_state()==&"grip")
	assert(initialized.set_visual_state(&""))
	assert(initialized.get_node("Model/PaperVolume").mesh==authored_mesh)
	for node: Node in [part,untouched,regenerated,initialized]: node.free()
	print("HAND_STATE_PASS ",record.name)

func verify_box() -> void:
	var part := load("res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn").instantiate() as PhysicalBodyPart3D
	part.freeze=true
	part.sprite_visible=true
	for key: String in ["JointIn","JointOut"]:
		var marker:=Marker3D.new()
		marker.name=key
		part.add_child(marker)
	root.add_child(part)
	var state := STATE.new()
	state.state_name=&"test"
	state.mesh=SphereMesh.new()
	state.visual_transform.origin=Vector3(0.1,0.2,0.3)
	part.visual_states=[state]
	var visual := part.get_node("MeshInstance3D") as MeshInstance3D
	var original:=visual.transform
	var before:=physics_snapshot(part)
	assert(part.set_visual_state(&"test"))
	var changed:=visual.transform
	part.prepare_generated_geometry()
	assert(visual.transform==changed)
	assert_same(physics_snapshot(part),before)
	assert(not part.get_node("Sprite3D").visible)
	assert(part.set_visual_state(&""))
	assert(visual.transform==original and part.get_node("Sprite3D").visible)
	part.free()

func verify_generated() -> void:
	for file: String in ["Generate_Human.tscn","Generate_Human_NPC.tscn"]:
		var actor := load("res://Scenes/Creatures/Characters/"+file).instantiate() as Node3D
		actor.set("generate_on_ready",false)
		actor.process_mode=Node.PROCESS_MODE_DISABLED
		root.add_child(actor)
		var hand := actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
		var before := physics_snapshot(hand)
		var socket := hand.get_node("ItemSocket3D") as Node3D
		var socket_pose := socket.transform
		var joints := actor.get_node("GeneratedParts/Joints").get_children()
		var joint_poses: Array[Transform3D] = []
		for joint: Node3D in joints: joint_poses.append(joint.transform)
		assert(hand.set_visual_state(&"grip"))
		var grip: BodyPartVisualState3D = hand.visual_states.filter(func(state): return state.state_name == &"grip")[0]
		assert(hand.get_node("Model/PaperVolume").to_global(grip.mesh_anchor).is_equal_approx(hand.get_node(grip.anchor_path).global_position))
		assert_same(physics_snapshot(hand),before)
		assert(socket.transform==socket_pose)
		for i: int in joints.size(): assert(joints[i].transform==joint_poses[i])
		assert(hand.set_visual_state(&""))
		actor.free()

func verify_walking_switches() -> void:
	var floor_body:=StaticBody3D.new()
	var collision:=CollisionShape3D.new()
	var box:=BoxShape3D.new()
	box.size=Vector3(100,1,100)
	collision.shape=box
	floor_body.add_child(collision)
	floor_body.position.y=-0.5
	root.add_child(floor_body)
	var actor:=load("res://Scenes/Creatures/Characters/Generate_Human.tscn").instantiate() as Node3D
	actor.set("generate_on_ready",false)
	root.add_child(actor)
	var commands:=Commands.new()
	actor.add_child(commands)
	actor.get_node("GeneratedLegStepMovementController3D").command_source=commands
	for tick:int in 180: await physics_frame
	var torso:=actor.get_node("GeneratedParts/Torso") as PhysicalBodyPart3D
	var hand:=actor.get_node("GeneratedParts/Arm_R") as PhysicalBodyPart3D
	var start:=torso.global_position
	commands.direction=Vector3.RIGHT
	for tick:int in 180:
		if tick%20==0:
			var before:=physics_snapshot(hand)
			assert(hand.set_visual_state(&"open" if tick%40==0 else &"grip"))
			assert_same(physics_snapshot(hand),before)
		await physics_frame
	assert(torso.global_position.x>start.x+1.0)
	assert(torso.global_basis.y.dot(Vector3.UP)>0.8)
	assert(hand.set_visual_state(&""))
	print("WALKING_STATE_SWITCH_PASS displacement=",torso.global_position-start)
	actor.free()
	floor_body.free()

func run() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Human/Metadata/hand_state_models.json"))
	for record: Dictionary in data.models: verify_hand(record)
	verify_box()
	verify_generated()
	await verify_walking_switches()
	await process_frame
	print("PASS: all 10 hands, two-sided pose resources, body/shape/HP/velocity/markers unchanged, independent instances, reset, invalid state, 2x snapshot, initial state, box visuals and generated Human/NPC sockets/joints.")
	quit()
