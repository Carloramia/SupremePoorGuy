extends Node3D

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

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

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_items.resize(capacity)
	_torso = get_node_or_null(torso_path) as RigidBody3D
	_arm = get_node_or_null(arm_path) as RigidBody3D
	_item_socket = get_node_or_null(item_socket_path) as Marker3D
	_configure_pickup_radius()
	if _inventory_ui.has_method("bind_inventory"):
		_inventory_ui.call("bind_inventory", self)
	inventory_changed.emit(_items.duplicate(), _selected_slot)

func _physics_process(_delta: float) -> void:
	if not _rigid_attachment_snapshot.is_empty() and not is_instance_valid(_equipped_item):
		_remove_rigid_attachment(null)
	if is_instance_valid(_torso):
		_pickup_area.global_position = _torso.global_position

func _unhandled_input(event: InputEvent) -> void:
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

## Spawn equipment directly into an empty slot, without proximity pickup or slot toggling.
func equip_initial_weapon(scene: PackedScene) -> bool:
	if scene == null or is_instance_valid(_equipped_item): return false
	var slot := _find_empty_slot()
	if slot < 0: return false
	var instance := scene.instantiate()
	if not instance is SampleWeapon3D:
		instance.free()
		_reject_pickup("Initial equipment scene must inherit SampleWeapon3D.")
		return false
	var weapon := instance as SampleWeapon3D
	var holder: RigidBody3D
	var preferred := get_parent().get_node_or_null(NodePath(weapon.preferred_holder_name)) if not weapon.preferred_holder_name.is_empty() else null
	if _is_available_initial_holder(preferred): holder = preferred
	if holder == null:
		for part: Node in get_parent().find_children("*","PhysicalBodyPart3D",true,false):
			if _is_available_initial_holder(part): holder = part; break
	if holder == null:
		weapon.free()
		_reject_pickup("No living Arm with a swing binding is available.")
		return false
	weapon.preferred_holder_name = StringName(str(get_parent().get_path_to(holder)))
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

func _is_available_initial_holder(part: Node) -> bool:
	return part is PhysicalBodyPart3D and not part.is_broken and not part.is_queued_for_deletion() and PhysicalBodyPart3D.BodyPartTag.Arm in part.tags and not part.arm_swing_bindings.is_empty()

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
	var holder := _resolve_holder(item)
	var socket := _resolve_item_socket(holder)
	if not is_instance_valid(item) or not is_instance_valid(holder) or not is_instance_valid(socket):
		return
	_equipped_item = item
	_equipped_holder = holder
	item.visible = true
	var item_basis := socket.global_basis
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
	_log_attachment_state("equipped", item, holder, socket)
	_log_attachment_after_physics(item, holder, socket)

func _unequip_current_item() -> void:
	if is_instance_valid(_equipped_item):
		_unequip_item(_equipped_item)
	else:
		_remove_rigid_attachment(null)
	_equipped_item = null
	_equipped_holder = null

func _unequip_item(item: SampleItem3D) -> void:
	_remove_rigid_attachment(item)
	_remove_character_collision_exceptions(item)
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
	if not is_instance_valid(part) or part != _equipped_holder or not is_instance_valid(_equipped_item):
		return
	_drop_equipped_item()

func _drop_equipped_item() -> void:
	var item := _equipped_item
	if not is_instance_valid(item):
		return
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
	item.reparent(get_tree().current_scene if get_tree().current_scene != null else get_tree().root, true)
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
		_equipped_collision_exceptions.append({
			&"body": body,
			&"body_had_exception": body_had_exception,
			&"item_had_exception": item_had_exception,
		})
	if attachment_debug_logging:
		print(
			"[item_collision] item=%s character=%s ignored_body_count=%d"
			% [item.name, character.name, _equipped_collision_exceptions.size()]
		)

func _remove_character_collision_exceptions(item: SampleItem3D) -> void:
	for record: Dictionary in _equipped_collision_exceptions:
		var body := record.get(&"body") as PhysicsBody3D
		if not is_instance_valid(body) or not is_instance_valid(item):
			continue
		if not bool(record.get(&"body_had_exception", false)):
			body.remove_collision_exception_with(item)
		if not bool(record.get(&"item_had_exception", false)):
			item.remove_collision_exception_with(body)
	_equipped_collision_exceptions.clear()

## Merge physical shapes into the holder; the item remains only as visuals and item data.
func _create_rigid_attachment(item: SampleItem3D, holder: RigidBody3D) -> void:
	var holder_center := _get_body_center_of_mass(holder)
	var item_center := holder.to_local(item.to_global(_get_body_center_of_mass(item)))
	_rigid_attachment_snapshot = {
		"holder": holder, "mass": holder.mass, "inertia": holder.inertia,
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
	item.reparent(holder, true)
	if attachment_debug_logging:
		print("[item_rigid_attachment] item=%s holder=%s shapes=%d combined_mass=%.3f center=%s" % [
			item.name, holder.name, _rigid_attachment_shapes.size(), total_mass, holder.center_of_mass])

func _get_body_center_of_mass(body: RigidBody3D) -> Vector3:
	if body.center_of_mass_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
		return body.center_of_mass
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	return state.center_of_mass_local if state != null else Vector3.ZERO

func _remove_rigid_attachment(item: SampleItem3D) -> void:
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
	if is_instance_valid(item):
		item.rigid_attachment_holder = null
		item.reparent(_inventory_items, true)
	_rigid_attachment_snapshot.clear()

func _resolve_holder(item: SampleItem3D) -> RigidBody3D:
	if is_instance_valid(item) and not item.preferred_holder_name.is_empty():
		var preferred := get_parent().get_node_or_null(NodePath(item.preferred_holder_name)) as RigidBody3D
		if is_instance_valid(preferred):
			return preferred
	return _arm

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
