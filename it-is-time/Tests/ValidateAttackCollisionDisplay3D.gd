extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/_SampleCharacter.tscn")
const PART = preload("res://Scenes/Creatures/Bodyparts/PhysicalTestCreatureParts/TestCreature_Part.tscn")
const TEMPORARY = preload("res://Scripts/Items/TemporaryAttackHitbox3D.gd")
const SNAKE = preload("res://Scripts/Items/SnakeBiteHitbox3D.gd")
const WAVE = preload("res://Scenes/VFX/StompShockwave3D.tscn")
var failed := false
var display: Node

func _initialize() -> void: call_deferred("run")
func check(value: bool, message: String) -> void:
	if not value: failed = true; push_error(message)

func outline(source: Node, index: int = 0) -> MeshInstance3D:
	return display._meshes.get("%d:%d" % [source.get_instance_id(),index])

func actor(parent: Node, at: Vector3) -> Node3D:
	var character := CHARACTER.instantiate()
	character.require_head_and_torso_connectivity = false
	var body := PART.instantiate() as PhysicalBodyPart3D
	body.name = "Head"
	body.tags.assign([PhysicalBodyPart3D.BodyPartTag.Torso,PhysicalBodyPart3D.BodyPartTag.Head])
	body.freeze = true
	body.damage_number_scene = null
	character.add_child(body)
	parent.add_child(character)
	character.position = at
	return character

func run() -> void:
	var console := root.get_node("RuntimeConsole")
	console.auto_getlogs_enabled = false
	check(console._attack_collision_display == null,"Attack overlay is off and unallocated by default")
	check(console.execute_command("help").contains("showattackboxes [on|off|status]"),"Help lists the new command")
	check(console.execute_command("showattackboxes invalid").begins_with("Usage:"),"Invalid arguments are rejected")
	check(console.execute_command("showattackboxes on extra").begins_with("Usage:"),"Extra arguments are rejected")
	check(console.execute_command("showattackboxes status").contains("disabled"),"Status does not enable drawing")
	console.execute_command("showattackboxes off")
	check(console._attack_collision_display == null,"Status and off do not allocate drawing nodes")
	var level := Node3D.new()
	root.add_child(level)
	current_scene = level
	var source := actor(level,Vector3(4,2,1))
	var head: PhysicalBodyPart3D = source.get_node("Head")
	var temporary := TEMPORARY.new()
	temporary.setup(head,source,Vector3(2,1,0.5),Vector3(1,0,0),1.0)
	source.add_child(temporary)
	temporary.update_hitbox(1.0/60.0,false)
	var original_layer := head.collision_layer
	var original_mask := head.collision_mask
	var original_shape_count := head.get_shape_owners().size()
	check(console.execute_command("showattackboxes on").contains("enabled"),"Command enables all attack shapes")
	display = console._attack_collision_display
	display.set_process(false)
	check(outline(temporary) != null and display._meshes.size()==1,"Disabled query-only damage boxes are still drawn")
	check(outline(temporary).global_transform.is_equal_approx(temporary.pose()),"Query box follows the actual body and local damage offset")
	check(outline(temporary).material_override==display._inactive_material,"Inactive temporary volumes are orange")
	check(outline(temporary).mesh.get_surface_count()==1 and outline(temporary).mesh.surface_get_primitive_type(0)==Mesh.PRIMITIVE_LINES,"Only wire outlines are drawn; filled debug surfaces never cover the creature")
	var cached_mesh := outline(temporary).mesh
	display._process(0.0)
	check(outline(temporary).mesh==cached_mesh,"Unchanged shapes reuse their wire geometry")
	check(temporary._debug_shape.disabled and head.get_shape_owners().size()==original_shape_count,"Drawing never enables query-only solver shapes")
	temporary.update_hitbox(1.0/60.0,true)
	display._process(0.0)
	check(outline(temporary).material_override==display._active_material,"Actual damaging window is red")
	check(display._active_material.no_depth_test,"Attack outlines remain visible behind opaque models")
	temporary.box.size = Vector3(3,2,1)
	display._process(0.0)
	check(outline(temporary).mesh.get_aabb().size.is_equal_approx(temporary.box.size),"Changing a shape resource updates the outline geometry")
	var snake := SNAKE.new()
	snake.head = head
	snake.setup(head,source,Vector3.ONE,Vector3(0.5,0.2,0),1.0)
	source.add_child(snake)
	snake.update_hitbox(1.0/60.0,true)
	display._process(0.0)
	check(outline(snake).global_transform.is_equal_approx(snake.pose()),"Snake mouth uses its Head pose")
	var cone := BirdDiveWeapon3D.new()
	source.add_child(cone)
	cone.attach_to_head(head,1.5,0.5)
	display._process(0.0)
	check(outline(cone)!=null and outline(cone).global_transform.is_equal_approx(cone.attached_shape.global_transform),"Head-attached convex dive cones are drawn at the real collider")
	check(outline(cone).mesh.get_surface_count()>0,"Convex shapes produce an actual wire mesh")
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200,1,200)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	level.add_child(floor_body)
	await physics_frame
	await physics_frame
	var charge := ChargeWeapon3D.new()
	source.add_child(charge)
	charge.attach_to_body(head,2.0,0.5)
	charge.update_ground_box(1.0,1,false)
	display._process(0.0)
	check(outline(charge)!=null and outline(charge).material_override==display._inactive_material,"Ground charge box is visible before its damage window")
	var previous_center := charge.attached_shape.global_position
	head.global_position.x += 3.0
	charge.update_ground_box(1.0,1,true)
	display._process(0.0)
	check(outline(charge).global_transform.is_equal_approx(charge._debug_query.transform),"Charge displays the actual swept query transform")
	check(outline(charge).mesh.get_aabb().size.x>charge.attached_shape.shape.size.x+2.9,"Fast charge draws the expanded sweep, not just its final box")
	check(outline(charge).global_position.is_equal_approx((previous_center+charge.attached_shape.global_position)*0.5),"Charge sweep covers both physics-frame positions")
	var weapon := SampleWeapon3D.new()
	weapon.freeze = true
	var weapon_shape := CollisionShape3D.new()
	weapon_shape.shape = BoxShape3D.new()
	weapon_shape.shape.size = Vector3(0.5,4,0.2)
	weapon_shape.position = Vector3(1,1,1)
	weapon.add_child(weapon_shape)
	level.add_child(weapon)
	display._process(0.0)
	check(outline(weapon)==null,"Idle regular weapons do not clutter the attack overlay")
	weapon.begin_damage_swing()
	display._process(0.0)
	check(outline(weapon).global_transform.is_equal_approx(weapon_shape.global_transform),"Ordinary active weapon colliders are drawn")
	var merged := CollisionShape3D.new()
	merged.shape = weapon_shape.shape
	merged.position = Vector3(-1,2,0.5)
	merged.rotation.z = 0.4
	merged.set_meta(&"equipped_item",weapon)
	head.add_child(merged)
	weapon.rigid_attachment_holder = head
	display._process(0.0)
	check(weapon.get_attack_debug_shapes().size()==1 and outline(weapon).global_transform.is_equal_approx(merged.global_transform),"Merged equipment uses hand-owned weapon shapes and excludes the hand's own collider")
	weapon.end_damage_swing()
	display._process(0.0)
	check(outline(weapon)==null,"Ending a regular swing removes its outline immediately")
	var settings := preload("res://Scripts/VFX/StompShockwaveData.gd").new()
	settings.radius = 8.0
	settings.duration = 2.0
	settings.require_line_of_sight = false
	var wave := WAVE.instantiate()
	wave.setup(settings,source,Vector3(5,0,0),Vector3.UP,50.0)
	level.add_child(wave)
	wave.set_physics_process(false)
	wave._physics_process(0.5)
	display._process(0.0)
	check(outline(wave)!=null and outline(wave).global_position==wave.contact,"Shockwave shows its spherical damage range at the contact point")
	check(absf(outline(wave).mesh.get_aabb().size.x-4.0)<0.01,"Shockwave radius follows elapsed expansion time")
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(64,64)
	level.add_child(viewport)
	var other := actor(viewport,Vector3.ZERO)
	var other_box := TEMPORARY.new()
	other_box.setup(other.get_node("Head"),other,Vector3.ONE,Vector3.ZERO,1.0)
	other.add_child(other_box)
	other_box.update_hitbox(1.0/60.0,false)
	display._process(0.0)
	check(outline(other_box).get_world_3d()==other_box.get_world_3d() and outline(other_box).get_viewport()==viewport,"Battle SubViewport attacks are drawn inside the correct 3D world")
	check(outline(temporary).get_world_3d()==temporary.get_world_3d(),"Separate viewports do not mix attack outlines")
	other.reparent(level,true)
	display._process(0.0)
	check(outline(other_box).get_viewport()==other_box.get_viewport(),"Moving an attack to another viewport moves its outline too")
	head.rotation.z += 0.25
	paused = true
	display._process(0.0)
	check(outline(temporary).global_transform.is_equal_approx(temporary.pose()),"Paused battles retain correctly positioned debug volumes")
	console.execute_command("showattackboxes off")
	check(display._meshes.is_empty() and not display.is_processing(),"Off clears every viewport and disables polling even while paused")
	paused = false
	check(console.execute_command("showattackboxes").contains("enabled"),"Bare command toggles drawing")
	display.set_process(false)
	check(head.collision_layer==original_layer and head.collision_mask==original_mask,"Drawing leaves gameplay collision masks unchanged")
	temporary.dispose()
	display._process(0.0)
	check(outline(temporary)==null,"Queued temporary attacks leave no stale outline")
	other.free()
	display._process(0.0)
	check(display._meshes.size()>0,"Removing one source does not clear unrelated attacks")
	level.free()
	display._process(0.0)
	check(display._meshes.is_empty(),"Scene replacement safely clears freed sources and viewports")
	check(console.execute_command("showattackboxes status").contains("enabled"),"Display preference survives scene replacement")
	console.execute_command("showattackboxes off")
	if not failed: print("ATTACK_COLLISION_DISPLAY_3D_VALIDATION_PASSED")
	quit(1 if failed else 0)
