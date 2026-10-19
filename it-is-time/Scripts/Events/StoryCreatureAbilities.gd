extends Node
## Extra head and magic eye act against actual alive opposing physical Parts.
var record: Dictionary
var elapsed := 0.0
var eye_timer := 0.0
var bite_timer := 0.0
var actor: Node3D
var head: PhysicalBodyPart3D

func _ready() -> void:
	actor=get_parent()
	for part: Node in actor.find_children("*","PhysicalBodyPart3D",true,false):
		if str(part.get_meta(&"generated_part_key",part.name))==("ExtraHead" if record.definition_id=="two_head_wolf" else "Head"): head=part; break
	if head==null and record.get("magic_eye",false): head=actor.get_combat_anchor() as PhysicalBodyPart3D
	if record.get("magic_eye",false) and head!=null:
		var eye := MeshInstance3D.new()
		eye.name="MagicEye"
		var sphere := SphereMesh.new(); sphere.radius=.25; sphere.height=.5; eye.mesh=sphere
		var material := StandardMaterial3D.new(); material.albedo_color=Color("8d54eb"); material.emission_enabled=true; material.emission=Color("8d54eb")
		eye.material_override=material; eye.position=Vector3(.3,.3,.5); head.add_child(eye)

func _physics_process(delta: float) -> void:
	var host: Node = actor.get_parent()
	if host.get("ready_for_combat")!=true or host.get("ended")==true or head==null or head.is_broken or not actor.is_combat_alive(): return
	eye_timer+=delta; bite_timer+=delta
	var target: Node3D
	var distance := INF
	for other: Node3D in host.actors:
		if other==actor or not is_instance_valid(other) or not other.is_combat_alive() or other.get_faction_id()==actor.get_faction_id(): continue
		var candidate := head.global_position.distance_to(other.get_combat_anchor().global_position)
		if candidate<distance: distance=candidate; target=other
	if target==null: return
	if record.get("magic_eye",false) and eye_timer>=6.0 and distance<=140.0:
		if _strike(target,true): eye_timer=0.0
	if record.definition_id=="two_head_wolf" and bite_timer>=2.4 and distance<=12.0:
		if _strike(target,false): bite_timer=0.0

func _strike(target: Node3D, beam: bool) -> bool:
	var body: PhysicalBodyPart3D
	for part: Node in target.find_children("*","PhysicalBodyPart3D",true,false):
		if not part.is_broken and (body==null or "Torso" in str(part.name)): body=part
	if body==null: return false
	if beam:
		var query := PhysicsRayQueryParameters3D.create(head.global_position,body.global_position)
		var exclude: Array[RID]=[]
		for part: Node in actor.find_children("*","PhysicalBodyPart3D",true,false): exclude.append(part.get_rid())
		query.exclude=exclude
		var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
		if not hit.is_empty() and hit.collider!=body and not target.is_ancestor_of(hit.collider): return false
	var damage: float = actor.get_node("/root/DamageService").apply_armor(float(record.attack),body.armor)
	body.apply_damage(damage,head)
	if beam:
		var visual := MeshInstance3D.new()
		var mesh := ImmediateMesh.new(); mesh.surface_begin(Mesh.PRIMITIVE_LINES); mesh.surface_add_vertex(head.global_position); mesh.surface_add_vertex(body.global_position); mesh.surface_end()
		visual.mesh=mesh
		var material := StandardMaterial3D.new(); material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED; material.albedo_color=Color("c688ff"); visual.material_override=material
		actor.get_parent().add_child(visual)
		visual.create_tween().tween_callback(visual.queue_free).set_delay(.18)
	return true
