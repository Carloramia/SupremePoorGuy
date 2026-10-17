extends "res://Scripts/Items/SampleWeapon3D.gd"
## Rigid bow arms with two tension-only strings and an independent string-center mass.
@export_group("Bow Ammunition")
@export var ammunition_scene: PackedScene
@export_group("Bow Holding")
## Cancel only the bow's weight while held, retaining its mass and inertia.
@export var held_gravity_compensation_enabled := true
@export_group("Bow String")
@export_range(0.0,1000.0,1.0,"or_greater") var string_stiffness := 80.0
@export_range(0.0,20.0,0.1,"or_greater") var string_damping := 2.0
@export_range(0.0,0.1,0.001) var string_preload_ratio := 0.02
@export_range(0.1,1000.0,1.0,"or_greater") var string_maximum_force := 250.0
@export_range(0.01,10.0,0.01,"or_greater") var maximum_draw_distance := 1.5:
	set(value):
		maximum_draw_distance = maxf(value,0.01)
		if is_instance_valid(_guide): _guide.set_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,-maximum_draw_distance)
var string_forces: Array[Vector3] = []
var _center: RigidBody3D
var _rest_center := Vector3.ZERO
var _segments: Array[Dictionary] = []
var _last_holder: RigidBody3D
var _was_visible := true
var _guide: Generic6DOFJoint3D
var _guide_holder: RigidBody3D
## Negative releases the string; a controller requests displacement using physical force.
var draw_target_distance := -1.0
var _force_frame := -1
var _applied_draw_distance := -1.0
var _holder_reaction_enabled := false
var _force_holder_center := Vector3.ZERO
var _draw_force := Vector3.ZERO
var _draw_force_point := Vector3.ZERO
var _compensation_force := Vector3.ZERO
var _compensation_point := Vector3.ZERO

func get_equipment_basis(socket_basis: Basis) -> Basis:
	# Hand artwork scale must not resize the bow, its colliders or spring anchors.
	return socket_basis.orthonormalized()

func apply_selected_grip_point() -> bool:
	return active_grip_point == 0 and super.apply_selected_grip_point()

func select_grip_point(index: int) -> bool:
	return index == 0 and super.select_grip_point(index)

func _ready() -> void:
	super._ready()
	_center = get_node("StringCenterBody")
	_guide = get_node("StringGuide")
	_rest_center = get_node("StringCenter").position
	var pose := _center.global_transform
	_center.top_level = true
	_center.global_transform = pose
	for label: String in ["Upper","Lower"]:
		var tip := get_node("BowArm_"+label+"/Tip") as Marker3D
		_segments.append({"tip":tip,"visual":get_node("String_"+label),"length":tip.global_position.distance_to(to_global(_rest_center))})
	process_physics_priority = -20
	reset_string()

func reset_string() -> void:
	if not is_instance_valid(_center): return
	for segment: Dictionary in _segments:
		segment.length = segment.tip.global_position.distance_to(to_global(_rest_center))
	_center.global_transform = Transform3D(global_basis.orthonormalized(),to_global(_rest_center))
	var holder := super.get_grip_reaction_body(0)
	_center.linear_velocity = _point_velocity(holder,_center.global_position)
	_center.angular_velocity = Vector3.ZERO
	_center.sleeping = false
	_update_string_visuals()
	_guide_holder = null
	_configure_guide(holder)

func _configure_guide(holder: RigidBody3D) -> void:
	if not is_instance_valid(_guide) or not is_visible_in_tree(): return
	if not PhysicsServer3D.body_get_space(holder.get_rid()).is_valid() or not PhysicsServer3D.body_get_space(_center.get_rid()).is_valid(): return
	_guide.node_a = NodePath()
	_guide.node_b = NodePath()
	_guide.global_transform = Transform3D(global_basis.orthonormalized(),to_global(_rest_center))
	for axis: String in ["x","y","z"]:
		_guide.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT,true)
		_guide.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT,-maximum_draw_distance if axis=="x" else 0.0)
		_guide.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT,0.0)
		_guide.call("set_flag_"+axis,Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT,true)
		_guide.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT,0.0)
		_guide.call("set_param_"+axis,Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT,0.0)
	_guide.node_a = _guide.get_path_to(holder)
	_guide.node_b = _guide.get_path_to(_center)
	_guide_holder = holder

func _sync_attachment() -> void:
	if not is_instance_valid(_center): return
	var holder := super.get_grip_reaction_body(0)
	var shown := is_visible_in_tree()
	if holder != _last_holder or shown != _was_visible: reset_string()
	if shown and holder!=_guide_holder: _configure_guide(holder)
	if not shown and is_instance_valid(_guide):
		_guide.node_a = NodePath()
		_guide.node_b = NodePath()
		_guide_holder = null
	_center.freeze = not shown
	if not shown: _center.linear_velocity = Vector3.ZERO
	_last_holder = holder
	_was_visible = shown

func get_grip_target_pose(index: int) -> Transform3D:
	if index != 1 or not is_instance_valid(_center): return super.get_grip_target_pose(index)
	_sync_attachment()
	return Transform3D(global_basis*grip_point_poses[index].basis.inverse(),_center.global_position)

func get_grip_reaction_body(index: int) -> RigidBody3D:
	if index == 1:
		_sync_attachment()
		return _center if is_instance_valid(_center) else null
	return super.get_grip_reaction_body(index)

func _point_velocity(body: RigidBody3D, point: Vector3) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	var center := body.to_global(state.center_of_mass_local if state != null else body.center_of_mass)
	return body.linear_velocity+body.angular_velocity.cross(point-center)

## The pose servo also reads this load to avoid compensating the same weight twice.
func get_held_gravity_compensation() -> Dictionary:
	if not held_gravity_compensation_enabled or not is_instance_valid(rigid_attachment_holder): return {}
	var holder := rigid_attachment_holder
	if holder.is_queued_for_deletion() or not holder.is_inside_tree() or holder.freeze or not is_visible_in_tree() or rigid_attachment_load.is_empty(): return {}
	if holder.get("is_broken")==true: return {}
	if not PhysicsServer3D.body_get_space(holder.get_rid()).is_valid(): return {}
	var state := PhysicsServer3D.body_get_direct_state(holder.get_rid())
	if state==null: return {}
	return {"body":holder,"point":holder.to_global(rigid_attachment_load.center),"force":-state.total_gravity*float(rigid_attachment_load.mass)}

func _spring_force(tip: Vector3, tip_velocity: Vector3, rest_length: float, holder: RigidBody3D, delta: float) -> Vector3:
	var offset := tip-_center.global_position
	var length := offset.length()
	var extension := length-rest_length
	if extension <= 0.0 or length <= 0.000001: return Vector3.ZERO
	var direction := offset/length
	var stretch_speed := (_center.linear_velocity-tip_velocity).dot(-direction)
	var inverse_mass := 1.0/_center.mass+(0.0 if holder.freeze else 1.0/holder.mass)
	# Implicit damping for both strings keeps a light string center stable at the physics tick rate.
	var denominator := 1.0+2.0*inverse_mass*(string_damping*delta+string_stiffness*delta*delta)
	var tension := clampf((string_stiffness*extension+string_damping*stretch_speed)/denominator,0.0,string_maximum_force)
	return direction*tension

func _physics_process(delta: float) -> void:
	_sync_attachment()
	_force_frame = Engine.get_physics_frames()
	_applied_draw_distance = draw_target_distance
	_holder_reaction_enabled = false
	_draw_force = Vector3.ZERO
	_compensation_force = Vector3.ZERO
	var compensation := get_held_gravity_compensation()
	if not compensation.is_empty():
		compensation.body.apply_force(compensation.force,Vector3(compensation.point)-compensation.body.global_position)
		_compensation_force = compensation.force
		_compensation_point = compensation.point
	string_forces.clear()
	if not is_instance_valid(_center) or _center.freeze or not PhysicsServer3D.body_get_space(_center.get_rid()).is_valid(): return
	var holder := super.get_grip_reaction_body(0)
	var holder_state := PhysicsServer3D.body_get_direct_state(holder.get_rid())
	_force_holder_center = holder.to_global(holder_state.center_of_mass_local if holder_state!=null else holder.center_of_mass)
	_holder_reaction_enabled = not holder.freeze
	for segment: Dictionary in _segments:
		var tip: Vector3 = segment.tip.global_position
		segment.force_point = tip
		var force := _spring_force(tip,_point_velocity(holder,tip),float(segment.length)*(1.0-string_preload_ratio),holder,delta)
		string_forces.append(force)
		_center.apply_central_force(force)
		if not holder.freeze: holder.apply_force(-force,tip-holder.global_position)
	if draw_target_distance >= 0.0:
		var target := get_draw_target(draw_target_distance)
		var omega := TAU*6.0
		var relative := _center.linear_velocity-_point_velocity(holder,target)
		var acceleration := ((target-_center.global_position)*omega*omega-relative*(2.0*omega+omega*omega*delta))/(1.0+2.0*omega*delta+omega*omega*delta*delta)
		# The drawing actuator must also carry the strings' static tension.
		var tension := Vector3.ZERO
		for force: Vector3 in string_forces: tension += force
		var drive := (acceleration*_center.mass-tension).project(global_basis.x.normalized()).limit_length(string_maximum_force)
		_draw_force = drive
		_draw_force_point = target
		_center.apply_central_force(drive)
		if not holder.freeze: holder.apply_force(-drive,target-holder.global_position)
	_update_string_visuals()

func get_draw_target(distance: float) -> Vector3:
	return to_global(_rest_center)-global_basis.x.normalized()*clampf(distance,0.0,maximum_draw_distance)

func get_rest_grip_distance() -> float:
	return to_global(attachment_local_position).distance_to(to_global(_rest_center))

func get_string_center() -> RigidBody3D:
	return _center

func get_string_diagnostics() -> Dictionary:
	if not is_inside_tree() or not is_instance_valid(_center) or not _center.is_inside_tree(): return {}
	var position := to_local(_center.global_position)
	var compensation := get_held_gravity_compensation()
	var springs: Array[Dictionary] = []
	var spring_force := Vector3.ZERO
	var spring_torque := Vector3.ZERO
	for index: int in _segments.size():
		var segment: Dictionary = _segments[index]
		var force := string_forces[index] if index<string_forces.size() else Vector3.ZERO
		var reaction := -force if _holder_reaction_enabled else Vector3.ZERO
		var point: Vector3 = segment.get("force_point",Vector3.ZERO)
		var torque := (point-_force_holder_center).cross(reaction)
		spring_force += reaction
		spring_torque += torque
		springs.append({"segment":str(segment.tip.get_parent().name),"force_on_center":force,"force_on_holder":reaction,"point":point,"torque_on_holder":torque})
	var draw_reaction := -_draw_force if _holder_reaction_enabled else Vector3.ZERO
	var draw_torque := (_draw_force_point-_force_holder_center).cross(draw_reaction)
	var compensation_torque := (_compensation_point-_force_holder_center).cross(_compensation_force)
	return {"center_local":position,"plane_drift":absf(position.z),"draw_target_distance":draw_target_distance,
		"maximum_draw_distance":maximum_draw_distance,"guide_active":is_instance_valid(_guide_holder) and not _guide.node_a.is_empty(),
		"force_physics_frame":_force_frame,"applied_draw_distance":_applied_draw_distance,"holder_reaction_enabled":_holder_reaction_enabled,"holder_center_of_mass":_force_holder_center,
		"center_position":_center.global_position,"center_velocity":_center.linear_velocity,"springs":springs,
		"draw_force_on_center":_draw_force,"draw_reaction_force_on_holder":draw_reaction,"draw_force_point":_draw_force_point,"draw_reaction_torque_on_holder":draw_torque,
		"spring_reaction_force_on_holder":spring_force,"spring_reaction_torque_on_holder":spring_torque,
		"total_script_force_on_holder":spring_force+draw_reaction+_compensation_force,"total_script_torque_on_holder":spring_torque+draw_torque+compensation_torque,
		"force_scope":"bow_script_only_excludes_joint_and_contact_solver_impulses",
		"held_gravity_compensation":{"enabled":held_gravity_compensation_enabled,"active":not compensation.is_empty(),"force":compensation.get("force",Vector3.ZERO),"point":compensation.get("point",Vector3.ZERO),"mass":rigid_attachment_load.get("mass",0.0),"applied_force":_compensation_force,"applied_point":_compensation_point,"applied_torque":compensation_torque}}

func _update_string_visuals() -> void:
	get_node("StringCenter").global_position = _center.global_position
	get_node("GripPoints/GripPoint_02").global_position = _center.global_position
	for segment: Dictionary in _segments:
		var tip: Vector3 = segment.tip.global_position
		var offset := tip-_center.global_position
		var length := offset.length()
		var visual: MeshInstance3D = segment.visual
		visual.visible = mesh_visible and length>0.00001
		if length<=0.00001: continue
		var orientation := Basis(Quaternion(Vector3.UP,offset/length))
		orientation.y *= length
		visual.global_transform = Transform3D(orientation,(_center.global_position+tip)*0.5)
