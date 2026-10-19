extends Node3D

const HISTORY_COLOR := Color(0.05,0.9,1.0)
const PREVIEW_COLOR := Color(1.0,0.55,0.05)
const TURN_COLOR := Color(0.9,0.2,1.0)
const UPDATE_INTERVAL := 0.2
var enabled := false
var filter := ""
var _elapsed := 0.0
var _meshes: Dictionary = {}
var _material: StandardMaterial3D

func _ready() -> void:
	process_physics_priority = 1000
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Diagnostic overlay remains visible under the creature, without affecting physics.
	_material.no_depth_test = true
	set_physics_process(enabled)

func set_enabled(value: bool, actor_filter: String = "") -> void:
	enabled = value
	filter = actor_filter
	_elapsed = UPDATE_INTERVAL
	set_physics_process(value)
	_clear()

func _clear() -> void:
	for mesh: MeshInstance3D in _meshes.values(): mesh.free()
	_meshes.clear()

func _matches(actor: Node) -> bool:
	return filter.is_empty() or filter.to_lower() == "all" or str(actor.name).to_lower() == filter.to_lower() \
		or str(actor.get_path()) == filter or str(actor.get_instance_id()) == filter

func _physics_process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < UPDATE_INTERVAL: return
	_elapsed = 0.0
	var seen := {}
	for controller: Node3D in get_tree().get_nodes_in_group(&"snake_movement_controllers"):
		if controller.is_queued_for_deletion() or not _matches(controller.get_parent()): continue
		var snapshot: Dictionary = controller.get_ground_path_debug_snapshot()
		if snapshot.is_empty(): continue
		var id := controller.get_instance_id()
		seen[id] = true
		if not _meshes.has(id):
			var instance := MeshInstance3D.new()
			instance.top_level = true
			instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			instance.material_override = _material
			add_child(instance)
			_meshes[id] = instance
		_meshes[id].mesh = _build_mesh(snapshot,controller.get_world_3d().direct_space_state)
	for id in _meshes.keys():
		if seen.has(id): continue
		_meshes[id].free()
		_meshes.erase(id)

func _project_to_terrain(point: Vector3, snapshot: Dictionary, space: PhysicsDirectSpaceState3D) -> Dictionary:
	var exclusions: Array[RID] = snapshot.excludes.duplicate()
	var query := PhysicsRayQueryParameters3D.create(Vector3(point.x,snapshot.ray_top,point.z),Vector3(point.x,snapshot.ray_bottom,point.z),0xffffffff,exclusions)
	for attempt: int in 8:
		var hit := space.intersect_ray(query)
		if hit.is_empty(): return {}
		if hit.collider is StaticBody3D or hit.collider is AnimatableBody3D:
			return {"position":Vector3(hit.position)+Vector3(hit.normal)*0.035,"normal":hit.normal}
		exclusions.append(hit.rid)
		query.exclude = exclusions
	return {}

func _build_mesh(snapshot: Dictionary, space: PhysicsDirectSpaceState3D) -> ImmediateMesh:
	var mesh := ImmediateMesh.new()
	var terrain: Array[Dictionary] = []
	for point: Vector3 in snapshot.points: terrain.append(_project_to_terrain(point,snapshot,space))
	var started := false
	for i: int in terrain.size()-1:
		var a: Dictionary = terrain[i]
		var b: Dictionary = terrain[i+1]
		if a.is_empty() or b.is_empty(): continue
		var direction: Vector3 = Vector3(b.position)-Vector3(a.position)
		if direction.is_zero_approx(): continue
		if not started:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			started = true
		var side_a := direction.cross(Vector3(a.normal)).normalized()*float(snapshot.line_width)*0.5
		var side_b := direction.cross(Vector3(b.normal)).normalized()*float(snapshot.line_width)*0.5
		var color := HISTORY_COLOR if float(snapshot.distances[i]) <= float(snapshot.progress) else PREVIEW_COLOR
		for vertex: Vector3 in [a.position-side_a,a.position+side_a,b.position+side_b,a.position-side_a,b.position+side_b,b.position-side_b]:
			mesh.surface_set_color(color)
			mesh.surface_add_vertex(vertex)
	for marker: Dictionary in snapshot.get("turns",[]):
		var hit := _project_to_terrain(marker.position,snapshot,space)
		if hit.is_empty(): continue
		var forward: Vector3 = Vector3(marker.facing).slide(hit.normal).normalized()
		if forward.is_zero_approx(): continue
		if not started:
			mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			started = true
		var size: float = maxf(float(snapshot.line_width)*6.0,0.3)
		var side := forward.cross(Vector3(hit.normal)).normalized()*size*0.5
		var center: Vector3 = hit.position+Vector3(hit.normal)*0.015
		for vertex: Vector3 in [center+forward*size,center-forward*size*0.5+side,center-forward*size*0.5-side]:
			mesh.surface_set_color(TURN_COLOR)
			mesh.surface_add_vertex(vertex)
	if started: mesh.surface_end()
	return mesh
