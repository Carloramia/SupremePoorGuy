@tool
extends RefCounted
## Uses native property access so non-tool weapon scripts can be edited safely.

const CONTAINER := &"GripPoints"
const MANAGED := &"weapon_grip_markers"
const INDEX := &"weapon_grip_index"
const SETTINGS = preload("res://Scripts/Items/ItemGripSettings.gd")

static func is_weapon(object: Object) -> bool:
	if not object is RigidBody3D: return false
	var script := object.get_script() as Script
	while script != null:
		if script.resource_path in ["res://Scripts/Items/SampleWeapon3D.gd", "res://Scripts/Items/SampleItem3D.gd"]: return true
		script = script.get_base_script()
	return false

static func weapon_for_marker(marker: Object) -> Node3D:
	if not marker is Marker3D or not marker.has_meta(INDEX): return null
	var container: Node = marker.get_parent()
	if container != null and container.get_meta(MANAGED,false) and is_weapon(container.get_parent()):
		var weapon: Node3D = container.get_parent()
		var index := int(marker.get_meta(INDEX))
		if index >= 0 and index < int(weapon.get("grip_point_count")): return weapon
	return null

static func marker_for(weapon: Node3D, index: int) -> Marker3D:
	var container := weapon.get_node_or_null(NodePath(CONTAINER))
	if container == null: return null
	for child: Node in container.get_children():
		if child is Marker3D and int(child.get_meta(INDEX,-1)) == index: return child
	return null

static func capture(weapon: Node3D) -> Dictionary:
	var container := weapon.get_node_or_null(NodePath(CONTAINER)) as Node3D
	var poses: Array[Transform3D] = []
	var stored: Variant = weapon.get("grip_point_poses")
	if stored is Array: poses.assign(stored)
	var arms: Array[NodePath] = []
	var stored_arms: Variant = weapon.get("grip_point_arm_paths")
	if stored_arms is Array: arms.assign(stored_arms)
	var settings: Array[ItemGripSettings] = []
	var stored_settings: Variant = weapon.get("grip_point_settings")
	if stored_settings is Array: settings.assign(stored_settings)
	var markers := {}
	var names := {}
	if container != null:
		for child: Node in container.get_children():
			if not child is Marker3D or not child.has_meta(INDEX): continue
			var index := int(child.get_meta(INDEX))
			markers[index] = child.transform
			names[index] = child.name
	return {"count":weapon.get("grip_point_count"),"active":weapon.get("active_grip_point"),"poses":poses,"arms":arms,"settings":settings,
		"local":weapon.get("attachment_local_position"),"angle":weapon.get("item_rotation"),"has_point":weapon.get("has_attachment_point"),
		"markers":markers,"names":names,"container_present":container != null,
		"container_pose":container.transform if container != null else Transform3D.IDENTITY}

static func prepare(weapon: Node3D, operation: StringName, value: int = -1, arm_path: NodePath = NodePath()) -> Dictionary:
	var container := weapon.get_node_or_null(NodePath(CONTAINER))
	if container != null and (not container is Node3D or not container.get_meta(MANAGED,false)):
		return {"error":"GripPoints 名称已被其他节点占用，请先重命名该节点。"}
	var before := capture(weapon)
	var after := before.duplicate(true)
	if operation == &"count": after.count = maxi(value,0)
	var count := int(after.count)
	var seed := Transform3D(Basis(Vector3.BACK,float(before.angle)),Vector3(before.local))
	var poses: Array[Transform3D] = []
	poses.assign(after.poses)
	while poses.size() < count: poses.append(seed)
	after.poses = poses
	var arms: Array[NodePath] = []
	arms.assign(after.arms)
	while arms.size() < count: arms.append(NodePath())
	if operation == &"arm":
		if value < 0 or value >= count: return {"error":"该持握点当前未启用。"}
		if arm_path.is_absolute() or arm_path.get_subname_count() > 0:
			return {"error":"请填写角色内部的 Arm 名称或相对路径，不使用绝对路径或属性路径。"}
		for index: int in arm_path.get_name_count():
			if arm_path.get_name(index) == &"..": return {"error":"Arm 路径应从角色根节点开始，不使用 ../。"}
		arms[value] = arm_path
	after.arms = arms
	var settings: Array[ItemGripSettings] = []
	settings.assign(after.settings)
	while settings.size() < count: settings.append(SETTINGS.new())
	for index: int in count:
		if settings[index] == null: settings[index] = SETTINGS.new()
	after.settings = settings
	after.active = clampi(value if operation == &"select" else int(after.active),0,maxi(count-1,0))
	if operation == &"read":
		if count == 0: return {"error":"请先将持握点数量设为 1 或更多。"}
		if value >= count: return {"error":"该持握点当前未启用。"}
		for index: int in count:
			if value >= 0 and index != value: continue
			var marker := marker_for(weapon,index)
			if marker == null: return {"error":"缺少第 %d 个 Marker，请先点击生成/同步按钮。" % (index+1)}
			var pose := weapon.global_transform.affine_inverse()*marker.global_transform
			if not pose.origin.is_finite() or not pose.basis.is_finite(): return {"error":"Marker 坐标或角度无效。"}
			var angles := pose.basis.orthonormalized().get_euler()
			if not pose.basis.get_scale().is_equal_approx(Vector3.ONE) or absf(angles.x)>0.0001 or absf(angles.y)>0.0001:
				return {"error":"持握 Marker 只支持绕武器局部 Z 轴旋转，请保持 X/Y 旋转为 0、缩放为 1。"}
			poses[index] = Transform3D(Basis(Vector3.BACK,angles.z),pose.origin)
	# Retain inactive markers: deleting inherited scene nodes cannot be saved safely.
	var markers: Dictionary = before.markers.duplicate()
	var names: Dictionary = before.names.duplicate()
	var container_pose: Transform3D = before.container_pose
	for index: int in count:
		markers[index] = before.markers.get(index,container_pose.affine_inverse()*poses[index])
		names[index] = before.names.get(index,StringName("GripPoint_%02d" % (index+1)))
		if container != null:
			var occupied := container.get_node_or_null(NodePath(names[index]))
			if occupied != null and occupied != marker_for(weapon,index): return {"error":"持握 Marker 名称与现有子节点冲突。"}
	after.markers = markers
	after.names = names
	after.container_present = count > 0 or not markers.is_empty()
	if count > 0:
		var selected: Transform3D = poses[after.active]
		after.local = selected.origin
		after.angle = selected.basis.get_euler().z
		after.has_point = true
	return {"before":before,"after":after}

static func apply(weapon: Node3D, state: Dictionary, scene_owner: Node) -> void:
	weapon.set("grip_point_count",state.count)
	weapon.set("active_grip_point",state.active)
	var poses: Array[Transform3D] = []
	poses.assign(state.poses)
	weapon.set("grip_point_poses",poses)
	var arms: Array[NodePath] = []
	arms.assign(state.arms)
	weapon.set("grip_point_arm_paths",arms)
	var settings: Array[ItemGripSettings] = []
	settings.assign(state.settings)
	weapon.set("grip_point_settings",settings)
	weapon.set("attachment_local_position",state.local)
	weapon.set("item_rotation",state.angle)
	weapon.set("has_attachment_point",state.has_point)
	var container := weapon.get_node_or_null(NodePath(CONTAINER)) as Node3D
	if container == null and state.container_present:
		container = Node3D.new()
		container.name = CONTAINER
		container.set_meta(MANAGED,true)
		weapon.add_child(container)
		container.owner = scene_owner
	if container == null: return
	container.transform = state.container_pose
	container.visible = int(state.count) > 0
	for child: Node in container.get_children():
		if child is Marker3D and child.has_meta(INDEX) and not state.markers.has(int(child.get_meta(INDEX))):
			container.remove_child(child)
			child.queue_free()
	for index: int in state.markers:
		var marker := marker_for(weapon,index)
		if marker == null:
			marker = Marker3D.new()
			marker.name = state.names[index]
			marker.set_meta(INDEX,index)
			container.add_child(marker)
			marker.owner = scene_owner
		marker.transform = state.markers[index]
		marker.visible = index < int(state.count)
	if not state.container_present and container.get_child_count() == 0:
		weapon.remove_child(container)
		container.queue_free()
