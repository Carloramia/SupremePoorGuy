extends SceneTree

const EDIT = preload("res://addons/weapon_workshop/grip_edit.gd")
const INSPECTOR = preload("res://addons/weapon_workshop/grip_inspector.gd")
const WEAPON := "res://Scenes/Items/Weapons/Human/Human5Spear.tscn"
var failed := false

func _initialize() -> void: call_deferred("run")

func check(value: bool, message: String) -> void:
	if value: return
	failed = true
	push_error(message)

func run() -> void:
	var weapon := load(WEAPON).instantiate() as Node3D
	weapon.set("freeze",true)
	root.add_child(weapon)
	var original_position: Vector3 = weapon.get("attachment_local_position")
	var original_rotation: float = weapon.get("item_rotation")
	var transaction := EDIT.prepare(weapon,&"count",3)
	check(not transaction.has("error"),"Editor can configure inherited, non-tool weapons")
	EDIT.apply(weapon,transaction.after,weapon)
	check(weapon.get("grip_point_count") == 3,"Count must create three grip points")
	check(weapon.get("attachment_local_position") == original_position and is_equal_approx(weapon.get("item_rotation"),original_rotation),"First point must preserve the legacy grip")
	var arm_edit := EDIT.prepare(weapon,&"arm",0,^"Arm_L")
	EDIT.apply(weapon,arm_edit.after,weapon)
	check(weapon.get("grip_point_arm_paths")[0] == ^"Arm_L","Each Marker has an independent target Arm")
	EDIT.apply(weapon,arm_edit.before,weapon)
	check(weapon.get("grip_point_arm_paths")[0].is_empty(),"Undo restores the previous Arm mapping")
	EDIT.apply(weapon,arm_edit.after,weapon)
	for index: int in [1,2]: EDIT.apply(weapon,EDIT.prepare(weapon,&"arm",index,^"Arm_R").after,weapon)
	check(EDIT.prepare(weapon,&"arm",0,^"/root/OtherActor/Arm_R").has("error") and EDIT.prepare(weapon,&"arm",0,^"../Arm_R").has("error"),"Editor rejects paths outside the owning character")
	for index: int in 3:
		var marker := EDIT.marker_for(weapon,index)
		check(marker != null and marker.owner == weapon,"Every grip requires a saved, owned Marker3D")
		marker.position = Vector3(index+0.25,index*0.5,0.1*index)
		marker.rotation.z = deg_to_rad(index*30.0-20.0)
	check(EDIT.is_weapon(weapon) and EDIT.weapon_for_marker(EDIT.marker_for(weapon,1)) == weapon,"Recognize inherited weapons and individual Marker ownership")
	if Engine.is_editor_hint():
		var inspector := INSPECTOR.new()
		check(inspector._can_handle(weapon) and inspector._can_handle(EDIT.marker_for(weapon,1)),"Root and Marker inspectors must both expose the editor controls")
	check(weapon.get("attachment_local_position") == original_position,"Moving a Marker must not commit before pressing Read")
	var read := EDIT.prepare(weapon,&"read")
	check(not read.has("error"),"Read all Marker transforms")
	EDIT.apply(weapon,read.after,weapon)
	var stored: Array = weapon.get("grip_point_poses")
	for index: int in 3:
		check(stored[index].origin.is_equal_approx(EDIT.marker_for(weapon,index).position),"Each point stores its own position")
		check(is_equal_approx(stored[index].basis.get_euler().z,EDIT.marker_for(weapon,index).rotation.z),"Each point stores its own equipment rotation")
	EDIT.apply(weapon,read.before,weapon)
	check(weapon.get("attachment_local_position") == original_position,"Undo restores previous data")
	check(EDIT.marker_for(weapon,0).position != original_position,"Undo Read preserves the manually edited Marker")
	EDIT.apply(weapon,read.after,weapon)
	EDIT.apply(weapon,EDIT.prepare(weapon,&"select",1).after,weapon)
	check(weapon.get("attachment_local_position") == stored[1].origin,"Selected point drives Attachment Local Position")
	check(is_equal_approx(weapon.get("item_rotation"),stored[1].basis.get_euler().z),"Selected point drives Item Rotation")
	var single := EDIT.marker_for(weapon,2)
	single.position += Vector3(0.4,0.2,0)
	EDIT.apply(weapon,EDIT.prepare(weapon,&"read",2).after,weapon)
	check(weapon.get("grip_point_poses")[2].origin == single.position,"An individual Marker button updates just that point")
	check(weapon.get("attachment_local_position") == stored[1].origin,"Reading an inactive point must retain the selected grip")
	stored = weapon.get("grip_point_poses")
	single.rotation.x = 0.2
	check(EDIT.prepare(weapon,&"read").has("error"),"Reject unsupported X/Y grip rotations without changing saved data")
	single.rotation.x = 0
	var shrink := EDIT.prepare(weapon,&"count",1)
	EDIT.apply(weapon,shrink.after,weapon)
	check(not EDIT.marker_for(weapon,1).visible and weapon.get("active_grip_point") == 0,"Shrinking count hides inactive Markers and clamps selection")
	check(weapon.get("grip_point_arm_paths").size() == 3 and weapon.get("grip_point_arm_paths")[2] == ^"Arm_R","Shrinking retains inactive Arm mappings")
	check(EDIT.weapon_for_marker(EDIT.marker_for(weapon,1)) == null,"Inactive inherited Markers must not expose active-grip controls")
	EDIT.apply(weapon,shrink.before,weapon)
	check(EDIT.marker_for(weapon,2).position == single.position and weapon.get("active_grip_point") == 1,"Undo count restores both data and Marker poses")
	var directory := "res://.godot/weapon_grip_validation_editor" if Engine.is_editor_hint() else "res://.godot/weapon_grip_validation"
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory+"/weapon.tscn"
	var packed := PackedScene.new()
	check(packed.pack(weapon) == OK and ResourceSaver.save(packed,path) == OK,"Grip markers and data must serialize into the weapon scene")
	verify_inherited(path,directory)
	weapon.free()
	var restored := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var reloaded := restored.instantiate() as Node3D
	reloaded.set("freeze",true)
	root.add_child(reloaded)
	check(reloaded.get("grip_point_count") == 3 and reloaded.get("active_grip_point") == 1,"Reload preserves count and selection")
	check(reloaded.get("grip_point_arm_paths") == [^"Arm_L",^"Arm_R",^"Arm_R"],"Save/reload preserves every Marker Arm assignment")
	check(EDIT.marker_for(reloaded,2).position == stored[2].origin,"Reload preserves all independently edited Marker positions")
	check(reloaded.get("attachment_local_position") == stored[1].origin,"Reload retains the chosen grip")
	var zero := EDIT.prepare(reloaded,&"count",0)
	EDIT.apply(reloaded,zero.after,reloaded)
	check(not reloaded.get_node("GripPoints").visible and reloaded.get("attachment_local_position") == stored[1].origin,"Zero points restores legacy Attachment behavior and hides the markers")
	reloaded.free()
	if not Engine.is_editor_hint(): await verify_equipment(restored)
	DirAccess.remove_absolute(path)
	print("WEAPON_GRIP_POINTS_", "FAILED" if failed else "PASSED", " editor=",Engine.is_editor_hint())
	quit(1 if failed else 0)

func verify_inherited(parent_path: String, directory: String) -> void:
	var path := directory+"/child.tscn"
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string('[gd_scene format=3]\n[ext_resource type="PackedScene" path="%s" id="1"]\n[node name="ChildWeapon" instance=ExtResource("1")]\ngrip_point_count = 1\nactive_grip_point = 0\n' % parent_path)
	file.close()
	var child := load(path).instantiate() as Node3D
	root.add_child(child)
	EDIT.apply(child,EDIT.prepare(child,&"sync").after,child)
	EDIT.apply(child,EDIT.prepare(child,&"arm",0,^"Arm_R").after,child)
	check(EDIT.marker_for(child,1) != null and not EDIT.marker_for(child,1).visible,"Inherited extra Markers are hidden instead of deleting inherited nodes")
	var packed := PackedScene.new()
	check(packed.pack(child) == OK and ResourceSaver.save(packed,path) == OK,"Save grip overrides in an inherited weapon")
	child.free()
	var restored := ResourceLoader.load(path,"",ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	child = restored.instantiate() as Node3D
	root.add_child(child)
	check(child.get("grip_point_count") == 1 and not EDIT.marker_for(child,1).visible,"Inherited count and visibility overrides survive reloading")
	check(child.get("grip_point_arm_paths")[0] == ^"Arm_R","Inherited weapons can override Arm mappings independently")
	child.free()
	DirAccess.remove_absolute(path)

func verify_equipment(scene: PackedScene) -> void:
	var actor := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(actor)
	for body: RigidBody3D in actor.find_children("*","RigidBody3D",true,false): body.freeze = true
	for component: Node in actor.get_children(): component.set_physics_process(false)
	var inventory := actor.get_node("InventoryController3D")
	inventory.inventory_ui_enabled = false
	inventory.attachment_debug_logging = false
	check(inventory.equip_initial_weapon(scene),"Existing inventory can equip a multi-grip weapon")
	var item := inventory.get_equipped_item() as SampleWeapon3D
	var holder := item.rigid_attachment_holder
	var socket := holder.get_node("ItemSocket3D") as Marker3D
	check(item.to_global(item.grip_point_poses[1].origin).distance_to(socket.global_position) < 0.0001,"Initial equipment aligns the selected grip")
	var mass := holder.mass
	var shape_count: int = inventory._rigid_attachment_shapes.size()
	var swing := actor.get_node("LimbSwingController3D") as LimbSwingController3D
	check(swing.begin_charge(0),"Charge with the old grip")
	swing.add_charge_time(0,0.6)
	swing.release_charge(0)
	check(item.swing_damage_active,"Attack opens the old weapon window")
	check(item.select_grip_point(2),"Runtime API switches grip")
	check(not item.swing_damage_active and swing._active_damage_swings == 0,"Rebinding safely cancels the previous attack")
	check(item.to_global(item.grip_point_poses[2].origin).distance_to(socket.global_position)<0.0001,"New grip must remain exactly at the hand socket")
	check(item.global_basis.is_equal_approx(socket.global_basis*item.grip_point_poses[2].basis),"Equipment uses the new grip's independent Z angle")
	check(is_equal_approx(holder.mass,mass) and inventory._rigid_attachment_shapes.size() == shape_count,"Rebinding must not duplicate mass or collision shapes")
	check(not item.select_grip_point(100) and item.active_grip_point == 2,"Invalid selection must leave the active grip unchanged")
	actor.queue_free()
	await process_frame
