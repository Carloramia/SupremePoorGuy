extends SceneTree

const MANIFEST = "res://Assets/3DResources/Creatures/Bird/Metadata/model_manifest.json"

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var console := root.get_node_or_null("RuntimeConsole")
	if console != null: console.set("auto_getlogs_enabled",false)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	assert(int(manifest.model_count) == 80)
	var by_set := {1:0,2:0,3:0}
	var seen := {}
	for r: Dictionary in manifest.models:
		assert(not seen.has(r.key))
		seen[r.key] = true
		by_set[int(r.set)] += 1
		var packed := load(r.physical_scene) as PackedScene
		assert(packed != null,str(r.key))
		var part := packed.instantiate() as RigidBody3D
		assert(part != null and part.get_script().resource_path == "res://Scripts/Creatures/PhysicalBodyParts.gd")
		part.freeze = true
		part.collision_layer = 0
		part.collision_mask = 0
		root.add_child(part)
		assert(int(part.get("geometry_mode")) == 1)
		assert(part.get("paper_volume_enabled") and part.get("mesh_visible") and not part.get("sprite_visible"))
		var tags: Array = part.get("tags")
		assert(tags.size() == r.tags.size())
		for i: int in tags.size(): assert(int(tags[i]) == int(r.tags[i]))
		var incoming := part.get_node("JointIn") as Marker3D
		var outgoing := part.get_node("JointOut") as Marker3D
		assert(incoming != null and outgoing != null and incoming.position.is_zero_approx())
		var target := Vector3(r.joint_out_local[0],r.joint_out_local[1],r.joint_out_local[2])
		assert(outgoing.position.distance_to(target) < 0.00001)
		var paper := part.get_node("Model/PaperVolume") as MeshInstance3D
		assert(paper != null and paper.visible and paper.mesh.get_surface_count() == 3)
		assert(not part.get_node("MeshInstance3D").visible)
		assert(is_equal_approx(paper.scale.z,float(r.thickness)))
		var material := paper.mesh.surface_get_material(0) as StandardMaterial3D
		assert(material != null and material.albedo_texture != null)
		assert(material.albedo_texture.resource_path == str(r.texture))
		var front: Array = paper.mesh.surface_get_arrays(0)
		var back: Array = paper.mesh.surface_get_arrays(1)
		var vertices: PackedVector3Array = front[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = front[Mesh.ARRAY_INDEX]
		assert(vertices.size() == 4 and indices.size() == 6)
		var cross := (vertices[indices[1]]-vertices[indices[0]]).cross(vertices[indices[2]]-vertices[indices[0]])
		assert(cross.z < 0.0,"Front must use Godot clockwise winding")
		assert(front[Mesh.ARRAY_TEX_UV] == back[Mesh.ARRAY_TEX_UV])
		assert(front[Mesh.ARRAY_NORMAL][0].z > 0.9 and back[Mesh.ARRAY_NORMAL][0].z < -0.9)
		var collision := part.get_node("CollisionShape3D") as CollisionShape3D
		assert(collision != null and collision.shape is ConvexPolygonShape3D)
		var low := Vector3(INF,INF,INF)
		var high := Vector3(-INF,-INF,-INF)
		for point: Vector3 in collision.shape.points:
			assert(point.is_finite())
			low = low.min(point)
			high = high.max(point)
		assert(is_equal_approx(high.z-low.z,float(r.thickness)*2.0),"Collision must be 2x visual thickness")
		assert(low.z < 0 and high.z > 0)
		var expected := Vector2(r.visible_world_size[0],r.visible_world_size[1])
		assert(absf((high.x-low.x)-expected.x) < 0.10 and absf((high.y-low.y)-expected.y) < 0.10)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		assert(document.append_from_file(r.glb,state) == OK)
		var glb := document.generate_scene(state)
		assert(glb != null)
		var glb_meshes := glb.find_children("*","MeshInstance3D",true,false)
		assert(glb_meshes.size() == 1)
		var glb_mesh := glb_meshes[0] as MeshInstance3D
		assert(glb_mesh.mesh.get_surface_count() == 3)
		assert(is_equal_approx(glb_mesh.mesh.get_aabb().size.z*glb_mesh.scale.z,float(r.thickness)))
		glb.free()
		part.free()
		print("BIRD_VALIDATED ",r.key)
	assert(by_set == {1:28,2:31,3:21})
	for v: int in range(1,4):
		var preview: PackedScene = load("res://Assets/3DResources/Creatures/Bird/Previews/Bird%dPartsPreview.tscn" % v)
		assert(preview != null)
		var gallery := preview.instantiate()
		assert(gallery.find_children("*","RigidBody3D",true,false).size() == int(by_set[v]))
		gallery.free()
	print("PASS: 80 Bird inherited Parts, solid GLBs, clockwise faces, UVs, tags, markers, collision profiles and 3 galleries.")
	quit()
