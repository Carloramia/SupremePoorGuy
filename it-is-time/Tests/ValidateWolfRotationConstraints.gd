extends SceneTree
func _initialize(): call_deferred("run")
func run():
 var floor_body=StaticBody3D.new()
 var collider=CollisionShape3D.new()
 var box=BoxShape3D.new()
 box.size=Vector3(100,1,100)
 collider.shape=box
 floor_body.add_child(collider)
 floor_body.position.y=-0.5
 root.add_child(floor_body)
 for scene in ["Generate_Wolf","Generate_Wolf_NPC"]:
  var actor=load("res://Scenes/Creatures/Characters/"+scene+".tscn").instantiate()
  actor.generate_on_ready=false
  root.add_child(actor)
  actor.process_mode=Node.PROCESS_MODE_DISABLED
  var move=actor.get_node("GeneratedLegStepMovementController3D")
  assert(not move._get_gait_data().world_rotation_constraints_enabled,"World rotation locks must be disabled in the Wolf preset")
  move.slow_gait_data=move.slow_gait_data.duplicate()
  move.slow_gait_data.world_rotation_constraints_enabled=true
  var originals={}
  for body in actor.get_node("GeneratedParts").get_children():
   if body is RigidBody3D:
    body.freeze=true
    originals[body]=Vector2(float(body.axis_lock_angular_x),float(body.axis_lock_angular_y))
  move._segment_heading_initialized=true
  move._segment_goal_yaw=0.0
  move._update_foot_heading_constraints()
  for body in originals:
   assert(body.axis_lock_angular_x and body.axis_lock_angular_y)
  assert(move._wolf_rotation_diagnostics.state=="locked")
  move._segment_goal_yaw=PI
  move._update_foot_heading_constraints()
  for body in originals:
   assert(body.axis_lock_angular_x)
   assert(body.axis_lock_angular_y==bool(originals[body].y))
  assert(move._wolf_rotation_diagnostics.state=="turning")
  move._segment_goal_yaw=0.0
  var limb=actor.get_node("GeneratedParts/ForeLeg_1_Limb_1")
  var rest=limb.global_basis
  limb.freeze=false
  limb.global_basis=Basis(Vector3.UP,deg_to_rad(20))*rest
  move._update_foot_heading_constraints()
  assert(move._wolf_rotation_diagnostics.state=="aligning" and not limb.axis_lock_angular_y)
  limb.global_basis=rest
  limb.angular_velocity=Vector3(0,deg_to_rad(10),0)
  move._update_foot_heading_constraints()
  assert(not limb.axis_lock_angular_y,"Do not lock a still-spinning part")
  limb.angular_velocity=Vector3.ZERO
  move._update_foot_heading_constraints()
  assert(limb.axis_lock_angular_y)
  limb.is_broken=true
  move._update_foot_heading_constraints()
  assert(not move._wolf_rotation_locks.has(limb))
  assert(limb.axis_lock_angular_x==bool(originals[limb].x) and limb.axis_lock_angular_y==bool(originals[limb].y))
  limb.is_broken=false
  move._update_foot_heading_constraints()
  move.recovery_control_active=true
  move._update_foot_heading_constraints()
  assert(move._wolf_rotation_locks.is_empty())
  for body in originals:
   assert(Vector2(float(body.axis_lock_angular_x),float(body.axis_lock_angular_y))==originals[body])
  move.recovery_control_active=false
  for foot in move._legs:
   foot.global_position.y-=move._get_foot_world_position(foot).y
  await physics_frame
  for foot in move._legs: foot.freeze=false
  move._begin_ground_probe_frame()
  move._segment_goal_yaw=PI
  assert(move.try_start_turn_step(move._legs[0],move._legs[0].global_position+Vector3.RIGHT,0.12,0.2))
  var profile=move._current_step.extra.automatic_profile
  assert(profile.position_gain<=move._get_gait_data().maximum_tracking_gain)
  assert(profile.step_acceleration<=move._get_gait_data().maximum_tracking_acceleration)
  assert(move._active_step_duration>=move._get_gait_data().minimum_safe_swing_time)
  move._update_foot_heading_constraints()
  move._get_gait_data().world_rotation_constraints_enabled=false
  move._update_foot_heading_constraints()
  assert(move._wolf_rotation_locks.is_empty())
  move._get_gait_data().world_rotation_constraints_enabled=true
  actor.free()
 print("PASS: Wolf/NPC world X/Y locks, Y-only turning release, alignment/speed gate, broken/recovery restoration, disable and safe turn-step profile.")
 quit()
