extends Node3D

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
const MULTI_GRIP = preload("res://Scripts/Items/EquipmentMultiGrip3D.gd")

signal inventory_changed(items: Array, selected_slot: int)
signal pickup_rejected(reason: String)

@export_range(1, 16, 1) var capacity: int = 4
@export var inventory_ui_enabled: bool = true
@export var pickup_action: StringName = &"EPressed"
@export var slot_actions: Array[StringName] = [&"1", &"2", &"3", &"4"]
@export_range(0.5, 50.0, 0.5, "or_greater") var pickup_radius: float = 6.0
@export var attachment_debug_logging: bool = true
@export var torso_path: NodePath = NodePath("../Torso")
@export var arm_path: NodePath = NodePath("../Arm_R")
@export var item_socket_path: NodePath = NodePath("../Arm_R/ItemSocket3D")

@onready var _pickup_area: Area3D = $PickupArea3D
@onready var _pickup_shape: CollisionShape3D = $PickupArea3D/CollisionShape3D
@onready var _inventory_items: Node3D = $InventoryItems
@onready var _inventory_ui: CanvasLayer = $InventoryBarUI

var _items: Array[SampleItem3D] = []
var _selected_slot: int = 0
var _equipped_item: SampleItem3D
var _equipped_holder: RigidBody3D
var _rigid_attachment_snapshot: Dictionary = {}
var _rigid_attachment_shapes: Array[CollisionShape3D] = []
var _equipped_collision_exceptions: Array[Dictionary] = []
var _torso: RigidBody3D
var _arm: RigidBody3D
var _item_socket: Marker3D
var _multi_grips := MULTI_GRIP.new()
var _support_grips_dirty := false
var _character_control_enabled := true

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"weapon_grip_inventories")
	_items.resize(capacity)
	refresh_physics_query_cache()
	_configure_pickup_radius()
	if _inventory_ui.has_method("bind_inventory"):
		_inventory_ui.call("bind_inventory", self)
	inventory_changed.emit(_items.duplicate(), _selected_slot)

func refresh_physics_query_cache() -> void:
	var next_arm := get_node_or_null(arm_path) as RigidBody3D
	var holder_changed := _arm != next_arm
	# Restore merged weapon geometry before a generated holder is replaced.
	var expected_holder := next_arm
	if is_instance_valid(_equipped_item) and not _equipped_item.get_grip_arm_path().is_empty():
		expected_holder = _resolve_grip_arm(_equipped_item.get_grip_arm_path())
	if is_instance_valid(_equipped_item) and _equipped_holder != expected_holder:
		_unequip_item(_equipped_item)
	_torso = get_node_or_null(torso_path) as RigidBody3D
	_arm = next_arm
	_item_socket = get_node_or_null(item_socket_path) as Marker3D
	if holder_changed and is_instance_valid(_arm): _equip_selected_item()

func _physics_process(delta: float) -> void:
	if not _rigid_attachment_snapshot.is_empty() and not is_instance_valid(_equipped_item):
		_trace_weapon_grip_event("item_deleted")
		_remove_rigid_attachment(null)
	if is_instance_valid(_torso):
		_pickup_area.global_position = _torso.global_position
	if not _character_control_enabled or get_tree().paused: return
	if get_parent().has_method("is_temporarily_ragdolled") and get_parent().is_temporarily_ragdolled(): return
	if is_instance_valid(_equipped_item) and is_instance_valid(_equipped_holder):
		if _support_grips_dirty:
			_multi_grips.configure(self, _equipped_item, _equipped_holder)
			_support_grips_dirty = false
		_multi_grips.update(delta)

func cancel_player_actions() -> void:
	_multi_grips.release()
	_support_grips_dirty = true

func suspend_idle_grip_pose() -> void:
	_multi_grips.suspend_idle_pose()

func set_character_control_enabled(value: bool) -> void:
	_character_control_enabled = value
	if not value: cancel_player_actions()

func _exit_tree() -> void:
	_multi_grips.release()

func _unhandled_input(event: InputEvent) -> void:
	if not _character_control_enabled: return
	if not PLAYER_CONTEXT.input_allowed(self): return
	if get_parent().has_node("NPCStateMachine3D") and PLAYER_CONTEXT.controlled_character(self) != get_parent(): return
	if PLAYER_CONTEXT.controller(self) != null: return
	if _is_external_interface_open():
		return
	if event.is_action_pressed(pickup_action) and not event.is_echo():
		get_viewport().set_input_as_handled()
		try_pick_up_nearest_item()
		return
	for slot_index: int in range(mini(capacity, slot_actions.size())):
		if event.is_action_pressed(slot_actions[slot_index]) and not event.is_echo():
			get_viewport().set_input_as_handled()
			select_slot(slot_index)
			return

func try_pick_up_nearest_item() -> bool:
	var empty_slot := _find_empty_slot()
	if empty_slot < 0:
		_reject_pickup("Inventory is full.")
		return false
	var nearest: SampleItem3D
	var nearest_distance := INF
	for body: Node3D in _pickup_area.get_overlapping_bodies():
		var item := body as SampleItem3D
		if item == null or not item.is_pickable():
			continue
		var distance := item.global_position.distance_squared_to(_pickup_area.global_position)
		if distance < nearest_distance:
			nearest = item
			nearest_distance = distance
	if nearest == null:
		_reject_pickup("No pickable item is in range.")
		return false
	_store_item(nearest, empty_slot)
	return true

func select_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= capacity:
		return
	if _selected_slot == slot_index:
		_selected_slot = -1
		_unequip_current_item()
	else:
		_selected_slot = slot_index
		_equip_selected_item()
	inventory_changed.emit(_items.duplicate(), _selected_slot)

func get_items() -> Array[SampleItem3D]:
	return _items.duplicate()

func get_selected_slot() -> int:
	return _selected_slot

func get_equipped_item() -> SampleItem3D:
	return _equipped_item

func refresh_equipped_item_attachment(item: SampleItem3D) -> bool:
	if item != _equipped_item: return false
	_equip_selected_item()
	return _equipped_item == item

func can_equip_weapon_grip(weapon: SampleWeapon3D, index: int) -> bool:
	return can_equip_item_grip(weapon, index)

func can_equip_item_grip(item: SampleItem3D, index: int) -> bool:
	if not item.is_grip_enabled(index): return false
	var path := item.get_grip_arm_path(index)
	return path.is_empty() or _resolve_grip_arm(path) != null

## Read-only: never create sockets, rebind equipment or change attacks while diagnosing.
func get_weapon_grip_diagnostics() -> Dictionary:
	var equipped := is_instance_valid(_equipped_item) and not _equipped_item.is_queued_for_deletion()
	var item: SampleItem3D = _equipped_item if equipped else null
	if item == null and _selected_slot >= 0 and _selected_slot < _items.size() and is_instance_valid(_items[_selected_slot]):
		item = _items[_selected_slot]
	var row := {"time_ms": Time.get_ticks_msec(), "physics_frame": Engine.get_physics_frames(),
		"slot": _selected_slot + 1, "equipped": equipped,
		"state": "equipped" if equipped else ("selected_not_equipped" if item != null else ("item_missing" if not _rigid_attachment_snapshot.is_empty() else "empty")),
		"holder_valid": is_instance_valid(_equipped_holder), "merged_shapes": 0}
	for shape: CollisionShape3D in _rigid_attachment_shapes:
		if is_instance_valid(shape) and not shape.is_queued_for_deletion() and not shape.disabled:
			row.merged_shapes += 1
	if item == null: return row
	row.merge({"item": str(item.get_path()) if item.is_inside_tree() else str(item.name),
		"item_id": item.get_instance_id(), "scene": item.scene_file_path,
		"has_attachment_point": item.has_attachment_point, "attachment_local": item.attachment_local_position,
		"rotation_degrees": rad_to_deg(item.item_rotation), "item_mass": item.mass,
		"item_frozen": item.freeze, "item_collision_layer": item.collision_layer, "item_collision_mask": item.collision_mask})
	var valid_grip := item.active_grip_point >= 0 and item.active_grip_point < item.grip_point_count and item.active_grip_point < item.grip_point_poses.size()
	row.merge({"grip_mode": "multiple" if item.grip_point_count > 0 else "legacy", "requested_arm": str(item.get_grip_arm_path()),
		"grip_count": item.grip_point_count, "grip_point": item.active_grip_point+1 if item.grip_point_count > 0 else 0,
		"grip_pose_valid": valid_grip, "grips": _multi_grips.rows.duplicate(true), "idle_pose": _multi_grips.idle_pose_diagnostics.duplicate(true)})
	if valid_grip:
		var pose := item.grip_point_poses[item.active_grip_point]
		row.grip_pose_valid = pose.origin.is_finite() and pose.basis.is_finite()
		if row.grip_pose_valid:
			row.grip_data_matches = item.has_attachment_point and pose.origin.is_equal_approx(item.attachment_local_position) and is_equal_approx(pose.basis.get_euler().z, item.item_rotation)
	if item is SampleWeapon3D:
		var preset: LimbSwingPresetBase = item.get_arm_attack_preset()
		row.damage_window = item.swing_damage_active
		row.attack_preset = preset.resource_path if preset != null else "unarmed_fallback"
	if not equipped or not is_instance_valid(_equipped_holder): return row
	var holder := _equipped_holder
	row.merge({"holder": str(holder.get_path()) if holder.is_inside_tree() else str(holder.name),
		"holder_id": holder.get_instance_id(), "holder_mass": holder.mass,
		"rigid_bound": item.rigid_attachment_holder == holder and item.get_parent() == holder and not _rigid_attachment_snapshot.is_empty(),
		"ignored_body_count": _equipped_collision_exceptions.size()})
	if holder is PhysicalBodyPart3D:
		row.holder_broken = holder.is_broken
		row.holder_visual_state = holder.get_visual_state()
	if not _rigid_attachment_snapshot.is_empty():
		row.mass_error = holder.mass - float(_rigid_attachment_snapshot.mass) - item.mass
	var socket := holder.get_node_or_null("ItemSocket3D") as Marker3D
	row.socket_valid = is_instance_valid(socket) and socket.is_inside_tree() and not socket.is_queued_for_deletion()
	if not row.socket_valid or not item.is_inside_tree(): return row
	var attachment_world := item.to_global(item.attachment_local_position if item.has_attachment_point else Vector3.ZERO)
	var expected_basis := item.get_equipment_basis(socket.global_basis)
	if item.has_attachment_point: expected_basis *= Basis(Vector3.BACK, item.item_rotation)
	row.merge({"socket_world": socket.global_position, "attachment_world": attachment_world,
		"error": attachment_world - socket.global_position, "error_length": attachment_world.distance_to(socket.global_position),
		"rotation_error_degrees": rad_to_deg(expected_basis.orthonormalized().get_rotation_quaternion().angle_to(item.global_basis.orthonormalized().get_rotation_quaternion()))})
	for grip: Dictionary in row.grips:
		if grip.role == "primary": grip.merge({"error_length": row.error_length, "target_world": attachment_world, "socket_world": socket.global_position})
	return row

func _trace_weapon_grip_event(event: String) -> void:
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if console != null: console.log_weapon_grip_event(self, event)

## Spawn equipment directly into an empty slot, without proximity pickup or slot toggling.
func equip_initial_weapon(scene: PackedScene) -> bool:
	return _equip_initial_item(scene, true)

func equip_initial_item(scene: PackedScene) -> bool:
	return _equip_initial_item(scene, false)

func _equip_initial_item(scene: PackedScene, weapon_only: bool) -> bool:
	if scene == null or is_instance_valid(_equipped_item): return false
	var slot := _find_empty_slot()
	if slot < 0: return false
	var instance := scene.instantiate()
	if not instance is SampleItem3D or (weapon_only and not instance is SampleWeapon3D):
		instance.free()
		_reject_pickup("Initial equipment scene has an incompatible item type.")
		return false
	var weapon := instance as SampleItem3D
	if weapon.grip_point_count > 0 and not weapon.apply_selected_grip_point():
		weapon.free()
		_reject_pickup("Primary grip is disabled, missing or invalid.")
		return false
	var holder: RigidBody3D
	var grip_arm := weapon.get_grip_arm_path()
	if not grip_arm.is_empty():
		holder = _resolve_grip_arm(grip_arm)
		if holder == null:
			weapon.free()
			_reject_pickup("Configured grip Arm is missing, ambiguous, not an Arm or broken: " + str(grip_arm))
			return false
	else:
		var preferred := get_parent().get_node_or_null(NodePath(weapon.preferred_holder_name)) if not weapon.preferred_holder_name.is_empty() else null
		if _is_available_initial_holder(preferred, weapon is SampleWeapon3D): holder = preferred
		if holder == null:
			for part: Node in get_parent().find_children("*","PhysicalBodyPart3D",true,false):
				if _is_available_initial_holder(part, weapon is SampleWeapon3D): holder = part; break
	if holder == null:
		weapon.free()
		_reject_pickup("No living Arm is available for initial equipment.")
		return false
	if grip_arm.is_empty(): weapon.preferred_holder_name = StringName(str(get_parent().get_path_to(holder)))
	# Freeze before entering the tree, so equipment cannot fall during initialization.
	weapon.freeze = true
	_inventory_items.add_child(weapon)
	var has_collision := false
	for node: Node in weapon.get_children():
		if node is CollisionShape3D and node.shape != null and not node.disabled: has_collision = true; break
	if not has_collision:
		weapon.queue_free()
		_reject_pickup("Initial weapon has no active CollisionShape3D; export a built weapon scene.")
		return false
	_selected_slot = slot
	_store_item(weapon,slot)
	print("[npc_equipment] character=",get_parent().get_path()," slot=",slot," holder=",holder.name," weapon_scene=",scene.resource_path)
	return _equipped_item == weapon

func _is_available_initial_holder(part: Node, require_swing: bool = true) -> bool:
	return part is PhysicalBodyPart3D and not part.is_broken and not part.is_queued_for_deletion() and PhysicalBodyPart3D.BodyPartTag.Arm in part.tags and (not require_swing or not part.arm_swing_bindings.is_empty())

func _store_item(item: SampleItem3D, slot_index: int) -> void:
	item.set_meta(&"inventory_collision_layer", item.collision_layer)
	item.set_meta(&"inventory_collision_mask", item.collision_mask)
	item.can_be_picked_up = false
	item.freeze = true
	item.sleeping = true
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.collision_layer = 0
	item.collision_mask = 0
	item.visible = false
	item.reparent(_inventory_items, true)
	_items[slot_index] = item
	if _selected_slot == slot_index:
		_equip_selected_item()
	inventory_changed.emit(_items.duplicate(), _selected_slot)
	_generate_item_icon(item)

func _generate_item_icon(item: SampleItem3D) -> void:
	if not inventory_ui_enabled: return
	await item.create_item_image()
	if is_instance_valid(item):
		inventory_changed.emit(_items.duplicate(), _selected_slot)

func _equip_selected_item() -> void:
	_unequip_current_item()
	if _selected_slot < 0 or _selected_slot >= _items.size():
		return
	var item := _items[_selected_slot]
	if is_instance_valid(item) and item.grip_point_count > 0 and not item.apply_selected_grip_point():
		_trace_weapon_grip_event("equip_failed_invalid_primary_grip")
		return
	var holder := _resolve_holder(item)
	var socket := _resolve_item_socket(holder)
	if not is_instance_valid(item) or not is_instance_valid(holder) or not is_instance_valid(socket):
		if is_instance_valid(item):
			_trace_weapon_grip_event("equip_failed_missing_holder" if not is_instance_valid(holder) else "equip_failed_missing_socket")
		return
	_equipped_item = item
	_equipped_holder = holder
	item.visible = true
	var item_basis := item.get_equipment_basis(socket.global_basis)
	if item.has_attachment_point:
		item_basis *= Basis(Vector3.BACK, item.item_rotation)
	var attachment_offset := (
		item_basis * item.attachment_local_position
		if item.has_attachment_point
		else Vector3.ZERO
	)
	item.global_transform = Transform3D(
		item_basis,
		socket.global_position - attachment_offset
	)
	item.linear_velocity = holder.linear_velocity
	item.angular_velocity = holder.angular_velocity
	item.collision_layer = int(item.get_meta(&"inventory_collision_layer", 1))
	item.collision_mask = int(item.get_meta(&"inventory_collision_mask", 1))
	item.freeze = false
	item.sleeping = false
	if item is SampleWeapon3D:
		var damage_controller := get_parent().get_node_or_null("CharacterDamageController3D")
		var team_id := int(damage_controller.get("team_id")) if damage_controller != null else 0
		(item as SampleWeapon3D).set_wielder(get_parent(), team_id)
	_add_character_collision_exceptions(item)
	_create_rigid_attachment(item, holder)
	_multi_grips.configure(self, item, holder)
	_support_grips_dirty = false
	var swing := get_parent().get_node_or_null("LimbSwingController3D")
	if swing != null: swing.refresh_weapon_presets()
	_log_attachment_state("equipped", item, holder, socket)
	_log_attachment_after_physics(item, holder, socket)
	_trace_weapon_grip_event("equipped")

func _unequip_current_item() -> void:
	var was_equipped := is_instance_valid(_equipped_item)
	if is_instance_valid(_equipped_item):
		_unequip_item(_equipped_item)
	else:
		_remove_rigid_attachment(null)
	_equipped_item = null
	_equipped_holder = null
	if was_equipped: _trace_weapon_grip_event("unequipped")

func _unequip_item(item: SampleItem3D) -> void:
	_trace_weapon_grip_event("unequip_begin")
	# Restore the Bow's nested pose override before releasing the auxiliary grip's springs.
	if is_instance_valid(_equipped_holder) and _equipped_holder.has_meta(&"equipment_bow_pose_driver"):
		var bow_driver: Variant = _equipped_holder.get_meta(&"equipment_bow_pose_driver")
		if is_instance_valid(bow_driver): bow_driver.release_weapon_pose()
	var swing := get_parent().get_node_or_null("LimbSwingController3D")
	if swing != null and is_instance_valid(_equipped_holder): swing.cancel_attacks_for_holder(_equipped_holder)
	_remove_rigid_attachment(item)
	if swing != null: swing.refresh_weapon_presets()
	if not is_instance_valid(item):
		return
	item.freeze = true
	item.sleeping = true
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.collision_layer = 0
	item.collision_mask = 0
	item.visible = false

func notify_weapon_swing_started() -> void:
	if _equipped_item is SampleWeapon3D:
		(_equipped_item as SampleWeapon3D).begin_damage_swing()

func notify_weapon_swing_finished() -> void:
	if _equipped_item is SampleWeapon3D:
		(_equipped_item as SampleWeapon3D).end_damage_swing()

func handle_part_broken(part: PhysicalBodyPart3D) -> void:
	_multi_grips.release_part(part)
	if not is_instance_valid(part) or part != _equipped_holder or not is_instance_valid(_equipped_item):
		return
	_drop_equipped_item()

func _drop_equipped_item() -> void:
	var item := _equipped_item
	if not is_instance_valid(item):
		return
	_trace_weapon_grip_event("holder_broken_drop")
	var slot_index := _items.find(item)
	var drop_transform := item.global_transform
	var drop_linear_velocity := _equipped_holder.linear_velocity if is_instance_valid(_equipped_holder) else Vector3.ZERO
	var drop_angular_velocity := _equipped_holder.angular_velocity if is_instance_valid(_equipped_holder) else Vector3.ZERO
	if is_instance_valid(_equipped_holder):
		var holder_center := _equipped_holder.to_global(_get_body_center_of_mass(_equipped_holder))
		var item_center := item.to_global(_get_body_center_of_mass(item))
		drop_linear_velocity += drop_angular_velocity.cross(item_center - holder_center)
	_unequip_item(item)
	_equipped_item = null
	_equipped_holder = null
	if slot_index >= 0:
		_items[slot_index] = null
		if _selected_slot == slot_index:
			_selected_slot = -1
	item.reparent(PLAYER_CONTEXT.level(self), true)
	item.global_transform = drop_transform
	item.visible = true
	item.freeze = false
	item.sleeping = false
	item.can_be_picked_up = true
	item.collision_layer = int(item.get_meta(&"inventory_collision_layer", 1))
	item.collision_mask = int(item.get_meta(&"inventory_collision_mask", 1))
	item.linear_velocity = drop_linear_velocity
	item.angular_velocity = drop_angular_velocity
	inventory_changed.emit(_items.duplicate(), _selected_slot)
	print("[inventory] dropped_broken_holder_item item=%s" % item.name)

func _add_character_collision_exceptions(item: SampleItem3D) -> void:
	_equipped_collision_exceptions.clear()
	var character := get_parent()
	if not is_instance_valid(character) or not is_instance_valid(item):
		return
	for node: Node in character.find_children("*", "PhysicsBody3D", true, false):
		var body := node as PhysicsBody3D
		if body == null or body == item or body is SampleItem3D:
			continue
		var body_had_exception := item in body.get_collision_exceptions()
		var item_had_exception := body in item.get_collision_exceptions()
		if not body_had_exception:
			body.add_collision_exception_with(item)
		if not item_had_exception:
			item.add_collision_exception_with(body)
		var record := {
			&"body": body,
			&"body_had_exception": body_had_exception,
			&"item_had_exception": item_had_exception,
		}
		# Merged item shapes belong to the primary body, so item-RID exceptions alone do not protect auxiliary hands.
		if is_instance_valid(_equipped_holder) and body != _equipped_holder:
			var holder_had := body in _equipped_holder.get_collision_exceptions()
			var body_had := _equipped_holder in body.get_collision_exceptions()
			record.merge({"holder": _equipped_holder, "holder_rid": _equipped_holder.get_rid(), "body_rid": body.get_rid(),
				"holder_had_body": holder_had, "body_had_holder": body_had})
			if not holder_had: _equipped_holder.add_collision_exception_with(body)
			if not body_had: body.add_collision_exception_with(_equipped_holder)
		_equipped_collision_exceptions.append(record)
	if attachment_debug_logging:
		print(
			"[item_collision] item=%s character=%s ignored_body_count=%d"
			% [item.name, character.name, _equipped_collision_exceptions.size()]
		)

func _remove_character_collision_exceptions(item: SampleItem3D) -> void:
	for record: Dictionary in _equipped_collision_exceptions:
		var body := record.get(&"body") as PhysicsBody3D
		if record.has("holder"):
			if is_instance_valid(record.holder) and not record.holder_had_body:
				PhysicsServer3D.body_remove_collision_exception(record.holder.get_rid(), record.body_rid)
			if is_instance_valid(body) and not record.body_had_holder:
				PhysicsServer3D.body_remove_collision_exception(body.get_rid(), record.holder_rid)
		if not is_instance_valid(body):
			continue
		if not bool(record.get(&"body_had_exception", false)):
			if is_instance_valid(item):
				body.remove_collision_exception_with(item)
			elif _rigid_attachment_snapshot.has("item_rid"):
				# A deleted weapon's RID can still remain in Jolt's collision exception set.
				PhysicsServer3D.body_remove_collision_exception(body.get_rid(), _rigid_attachment_snapshot.item_rid)
		if is_instance_valid(item) and not bool(record.get(&"item_had_exception", false)):
			item.remove_collision_exception_with(body)
	_equipped_collision_exceptions.clear()

## Merge physical shapes into the holder; the item remains only as visuals and item data.
func _create_rigid_attachment(item: SampleItem3D, holder: RigidBody3D) -> void:
	var holder_center := _get_body_center_of_mass(holder)
	var item_center := holder.to_local(item.to_global(_get_body_center_of_mass(item)))
	_rigid_attachment_snapshot = {
		"holder": holder, "item_rid": item.get_rid(), "mass": holder.mass, "inertia": holder.inertia,
		"center_mode": holder.center_of_mass_mode, "center": holder.center_of_mass,
		"resolved_center": holder_center,
	}
	for node: Node in item.get_children():
		if not node is CollisionShape3D or node.is_queued_for_deletion():
			continue
		var original := node as CollisionShape3D
		if original.disabled or original.shape == null:
			continue
		var collision := CollisionShape3D.new()
		collision.name = "EquippedItem_" + str(original.name)
		collision.shape = original.shape
		collision.set_meta(&"equipped_item", item)
		holder.add_child(collision)
		collision.global_transform = original.global_transform
		_rigid_attachment_shapes.append(collision)
	var total_mass := holder.mass + item.mass
	holder.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	holder.center_of_mass = (holder_center * holder.mass + item_center * item.mass) / total_mass
	holder.mass = total_mass
	holder.linear_velocity += holder.angular_velocity.cross(holder.global_basis * (holder.center_of_mass - holder_center))
	# Recalculate inertia from the complete compound geometry around the combined center.
	holder.inertia = Vector3.ZERO
	item.freeze = true
	item.sleeping = true
	item.collision_layer = 0
	item.collision_mask = 0
	item.rigid_attachment_holder = holder
	item.rigid_attachment_load = {"mass":item.mass,"center":item_center}
	item.set_meta(&"equipment_inventory", self)
	item.reparent(holder, true)
	if item is SampleWeapon3D and holder is PhysicalBodyPart3D and &"grip" in holder.get_available_visual_states():
		var previous_state: StringName = holder.get_visual_state()
		if holder.set_visual_state(&"grip"):
			_rigid_attachment_snapshot["holder_visual_state"] = previous_state
	if attachment_debug_logging:
		print("[item_rigid_attachment] item=%s holder=%s shapes=%d combined_mass=%.3f center=%s" % [
			item.name, holder.name, _rigid_attachment_shapes.size(), total_mass, holder.center_of_mass])

func _get_body_center_of_mass(body: RigidBody3D) -> Vector3:
	if body.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		return body.center_of_mass
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	return state.center_of_mass_local if state != null else Vector3.ZERO

func _remove_rigid_attachment(item: SampleItem3D) -> void:
	_multi_grips.release()
	_support_grips_dirty = false
	_remove_character_collision_exceptions(item)
	if _rigid_attachment_snapshot.is_empty():
		return
	for collision: CollisionShape3D in _rigid_attachment_shapes:
		if is_instance_valid(collision):
			# Remove from the body immediately; queue_free alone leaves shapes active this frame.
			collision.get_parent().remove_child(collision)
			collision.queue_free()
	_rigid_attachment_shapes.clear()
	var holder := _rigid_attachment_snapshot.holder as RigidBody3D
	if is_instance_valid(holder):
		var old_center := holder.center_of_mass
		var restored_center: Vector3 = _rigid_attachment_snapshot.resolved_center
		holder.linear_velocity += holder.angular_velocity.cross(holder.global_basis * (restored_center - old_center))
		holder.mass = _rigid_attachment_snapshot.mass
		holder.inertia = _rigid_attachment_snapshot.inertia
		holder.center_of_mass_mode = _rigid_attachment_snapshot.center_mode
		holder.center_of_mass = _rigid_attachment_snapshot.center
		# Restore only the appearance owned by equipment, preserving other visual overrides.
		if holder is PhysicalBodyPart3D and _rigid_attachment_snapshot.has("holder_visual_state") and holder.get_visual_state() == &"grip":
			holder.set_visual_state(_rigid_attachment_snapshot.holder_visual_state)
	if is_instance_valid(item):
		item.rigid_attachment_holder = null
		item.rigid_attachment_load.clear()
		item.remove_meta(&"equipment_inventory")
		item.reparent(_inventory_items, true)
	_rigid_attachment_snapshot.clear()

func _resolve_holder(item: SampleItem3D) -> RigidBody3D:
	if is_instance_valid(item) and not item.get_grip_arm_path().is_empty():
		return _resolve_grip_arm(item.get_grip_arm_path())
	if is_instance_valid(item) and not item.preferred_holder_name.is_empty():
		var preferred := get_parent().get_node_or_null(NodePath(item.preferred_holder_name)) as RigidBody3D
		if is_instance_valid(preferred):
			return preferred
	return _arm

func _resolve_grip_arm(path: NodePath) -> PhysicalBodyPart3D:
	if path.is_empty() or path.is_absolute() or path.get_subname_count() > 0: return null
	var actor := get_parent()
	var candidate := actor.get_node_or_null(path)
	# A bare part name also works for generated characters with nested GeneratedParts.
	if candidate == null and path.get_name_count() == 1:
		for part: Node in actor.find_children("*", "PhysicalBodyPart3D", true, false):
			if str(part.name) != str(path): continue
			if candidate != null: return null
			candidate = part
	if not candidate is PhysicalBodyPart3D or not actor.is_ancestor_of(candidate): return null
	if candidate.is_queued_for_deletion() or candidate.is_broken or PhysicalBodyPart3D.BodyPartTag.Arm not in candidate.tags: return null
	return candidate

func _resolve_item_socket(holder: RigidBody3D) -> Marker3D:
	if not is_instance_valid(holder):
		return null
	var existing := holder.get_node_or_null("ItemSocket3D") as Marker3D
	if is_instance_valid(existing):
		return existing
	var socket := Marker3D.new()
	socket.name = "ItemSocket3D"
	if is_instance_valid(_item_socket):
		socket.transform = _item_socket.transform
	holder.add_child(socket)
	return socket

func _find_empty_slot() -> int:
	for index: int in range(_items.size()):
		if not is_instance_valid(_items[index]):
			return index
	return -1

func _configure_pickup_radius() -> void:
	if not is_instance_valid(_pickup_shape) or _pickup_shape.shape is not SphereShape3D:
		push_warning("Inventory pickup area requires a SphereShape3D.")
		return
	var sphere := _pickup_shape.shape.duplicate() as SphereShape3D
	sphere.radius = pickup_radius
	_pickup_shape.shape = sphere

func _log_attachment_after_physics(
	item: SampleItem3D,
	holder: RigidBody3D,
	socket: Marker3D
) -> void:
	if not attachment_debug_logging:
		return
	await get_tree().physics_frame
	await get_tree().physics_frame
	if item == _equipped_item and is_instance_valid(holder) and is_instance_valid(socket):
		_log_attachment_state("after_2_physics_frames", item, holder, socket)

func _log_attachment_state(
	stage: String,
	item: SampleItem3D,
	holder: RigidBody3D,
	socket: Marker3D
) -> void:
	if not attachment_debug_logging:
		return
	var attachment_world := item.global_transform * item.attachment_local_position
	var error := attachment_world - socket.global_position
	print(
		("[item_attachment] stage=%s item=%s holder=%s canvas=%s local=%s item_rotation_deg=%.3f "
		+ "socket_world=%s attachment_world=%s error=%s error_length=%.6f item_origin=%s")
		% [
			stage,
			item.name,
			holder.name,
			item.attachment_canvas_position,
			item.attachment_local_position,
			rad_to_deg(item.item_rotation),
			socket.global_position,
			attachment_world,
			error,
			error.length(),
			item.global_position,
		]
	)

func _reject_pickup(reason: String) -> void:
	pickup_rejected.emit(reason)
	print("[inventory] pickup_rejected reason=", reason)

func _is_external_interface_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"ui_interface_2d"):
		if node is CanvasLayer and (node as CanvasLayer).visible and not node.is_queued_for_deletion():
			return true
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	return console != null and console.has_method("is_console_open") and bool(console.call("is_console_open"))
