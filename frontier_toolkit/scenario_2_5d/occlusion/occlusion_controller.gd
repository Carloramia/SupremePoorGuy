class_name ScenarioOcclusionController
extends Node

@export var camera: Camera3D
@export_flags_3d_physics var occluder_mask: int = 2
@export_range(0.05, 1.0) var blocked_alpha: float = 0.22
var targets: Array[Node3D] = []
var active_occluders: Array[ScenarioOccluder3D] = []
var enabled: bool = true

func register_occlusion_target(target: Node3D) -> void:
	if is_instance_valid(target) and not targets.has(target):
		targets.append(target)

func unregister_occlusion_target(target: Node3D) -> void:
	targets.erase(target)

func _physics_process(_delta: float) -> void:
	update_occlusion()

func update_occlusion() -> void:
	var next: Array[ScenarioOccluder3D] = []
	if enabled and is_instance_valid(camera):
		for target in targets.duplicate():
			if not is_instance_valid(target):
				targets.erase(target)
				continue
			# Orthographic rays are parallel. Camera-position rays would be incorrect at screen edges.
			var screen := camera.unproject_position(target.global_position)
			var origin := camera.project_ray_origin(screen)
			var excluded: Array[RID] = []
			while true:
				var query := PhysicsRayQueryParameters3D.create(origin, target.global_position, occluder_mask, excluded)
				query.collide_with_areas = true
				var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
				if hit.is_empty():
					break
				excluded.append(hit.rid)
				if hit.collider is ScenarioOccluder3D and not next.has(hit.collider):
					next.append(hit.collider)
	for old in active_occluders:
		if is_instance_valid(old) and not next.has(old):
			old.restore_fade()
	for occluder in next:
		occluder.set_fade_amount(blocked_alpha)
	active_occluders = next

func _exit_tree() -> void:
	for occluder in active_occluders:
		if is_instance_valid(occluder):
			occluder.restore_fade()
