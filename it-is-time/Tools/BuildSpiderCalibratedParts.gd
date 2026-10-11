extends SceneTree

func _initialize() -> void: call_deferred("run")

func warp(pixel: Vector2, r: Dictionary) -> Vector2:
	var delta := pixel - Vector2(r.origin_pixel[0], r.origin_pixel[1])
	var t := delta.dot(Vector2(r.axis_pixel[0], r.axis_pixel[1]))
	var x := delta.dot(Vector2(r.across_pixel[0], r.across_pixel[1]))
	var length: float = r.source_span
	var a: float = r.breakpoints[1]
	var b: float = r.breakpoints[2]
	var blend := clampf((t-a)/(b-a),0,1)
	var scale := lerpf(r.scales[0],r.scales[1],blend)
	var y: float
	if t <= a: y = t*r.scales[0]
	elif t >= b: y = r.calibrated_span+(t-length)*r.scales[1]
	else: y = lerpf(r.values[1],r.values[2],blend)
	# Leave both end rings unchanged; compress only the central shaft.
	var shaft := sin(PI*blend)
	x *= scale*lerpf(1,r.shaft_compression,shaft)
	var ring_band := 0.075
	var outside_band := float(r.calibrated_width)*0.5-ring_band
	if absf(x)>ring_band: x=signf(x)*(ring_band+outside_band*tanh((absf(x)-ring_band)/outside_band))
	var point := Vector2(x,y-float(r.calibrated_span)*0.5)
	return point if r.name == "UpperLeg" else -point

func clip(poly: Array[Vector2], r: Dictionary, threshold: float, keep_above: bool, perpendicular: bool = false) -> Array[Vector2]:
	var output: Array[Vector2] = []
	var origin := Vector2(r.origin_pixel[0],r.origin_pixel[1])
	var axis := Vector2(r.axis_pixel[0],r.axis_pixel[1])
	if perpendicular: axis = Vector2(r.across_pixel[0],r.across_pixel[1])
	for index: int in poly.size():
		var a := poly[index]
		var b := poly[(index+1)%poly.size()]
		var da := (a-origin).dot(axis)-threshold
		var db := (b-origin).dot(axis)-threshold
		var inside_a := da >= 0 if keep_above else da <= 0
		var inside_b := db >= 0 if keep_above else db <= 0
		if inside_a: output.append(a)
		if inside_a != inside_b: output.append(a.lerp(b,da/(da-db)))
	return output

func run() -> void:
	var visuals_only := "--visuals-only" in OS.get_cmdline_user_args()
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Assets/3DResources/Creatures/Spider/Metadata/generator_calibration.json"))
	for r: Dictionary in data.models:
		var original := load(r.volume_mesh) as ArrayMesh
		var result := ArrayMesh.new()
		var rect: Array[Vector2] = [Vector2.ZERO,Vector2(0,r.texture_size[1]),Vector2(r.texture_size[0],r.texture_size[1]),Vector2(r.texture_size[0],0)]
		var lo := INF
		var hi := -INF
		for p: Vector2 in rect:
			var t := (p-Vector2(r.origin_pixel[0],r.origin_pixel[1])).dot(Vector2(r.axis_pixel[0],r.axis_pixel[1]))
			lo = minf(lo,t)
			hi = maxf(hi,t)
		var cuts: Array[float] = [lo,hi,0,float(r.source_span),float(r.breakpoints[1]),float(r.breakpoints[2])]
		for i: int in range(1,65): cuts.append(lerpf(lo,hi,float(i)/65))
		cuts.sort()
		var across := Vector2(r.across_pixel[0],r.across_pixel[1])
		var origin := Vector2(r.origin_pixel[0],r.origin_pixel[1])
		var umin := INF
		var umax := -INF
		for p: Vector2 in rect:
			umin=minf(umin,(p-origin).dot(across))
			umax=maxf(umax,(p-origin).dot(across))
		var ucuts: Array[float] = [umin,umax,0]
		for i: int in range(1,33): ucuts.append(lerpf(umin,umax,float(i)/33))
		for scale: float in r.scales:
			for distance: float in [-0.075,-0.05,0.05,0.075]: ucuts.append(distance/scale)
		ucuts.sort()
		for front: bool in [true,false]:
			var vertices := PackedVector3Array()
			var uv := PackedVector2Array()
			var normals := PackedVector3Array()
			var indices := PackedInt32Array()
			for i: int in range(cuts.size()-1):
				var strip := clip(clip(rect,r,cuts[i],true),r,cuts[i+1],false)
				for u: int in range(ucuts.size()-1):
					var poly := clip(clip(strip,r,ucuts[u],true,true),r,ucuts[u+1],false,true)
					if poly.size()<3: continue
					var offset := vertices.size()
					for pixel: Vector2 in poly:
						var point := warp(pixel,r)
						vertices.append(Vector3(point.x,point.y,0.5 if front else -0.5))
						uv.append(pixel/Vector2(r.texture_size[0],r.texture_size[1]))
						normals.append(Vector3.BACK if front else Vector3.FORWARD)
					for j: int in range(1,poly.size()-1):
						var cross := (vertices[offset+j]-vertices[offset]).cross(vertices[offset+j+1]-vertices[offset]).z
						if absf(cross)<0.00000001: continue
						# Godot front faces use clockwise winding viewed from outside.
						indices.append_array([offset,offset+j,offset+j+1] if (cross<0)==front else [offset,offset+j+1,offset+j])
			var arrays: Array = []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=vertices
			arrays[Mesh.ARRAY_NORMAL]=normals
			arrays[Mesh.ARRAY_TEX_UV]=uv
			arrays[Mesh.ARRAY_INDEX]=indices
			result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			result.surface_set_material(result.get_surface_count()-1,original.surface_get_material(0 if front else 1))
		var sides := original.surface_get_arrays(2)
		var side_vertices: PackedVector3Array = sides[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = sides[Mesh.ARRAY_NORMAL]
		var side_indices: PackedInt32Array = sides[Mesh.ARRAY_INDEX]
		for i: int in side_vertices.size():
			var p := side_vertices[i]
			var pixel := Vector2(p.x,-p.y)/float(r.units_per_texture_pixel)+Vector2(r.pivot_pixel[0],r.pivot_pixel[1])
			var xy := warp(pixel,r)
			side_vertices[i]=Vector3(xy.x,xy.y,p.z)
		# Pixel-to-calibrated XY reverses the original mesh's XY orientation.
		for i: int in range(0,side_indices.size(),3):
			var swap := side_indices[i+1]
			side_indices[i+1]=side_indices[i+2]
			side_indices[i+2]=swap
		for quad: int in side_vertices.size()/4:
			var i := quad*6
			var a := side_vertices[side_indices[i]]
			var n := -(side_vertices[side_indices[i+1]]-a).cross(side_vertices[side_indices[i+2]]-a).normalized()
			for j: int in 4: normals[quad*4+j]=n
		sides[Mesh.ARRAY_VERTEX]=side_vertices
		sides[Mesh.ARRAY_NORMAL]=normals
		sides[Mesh.ARRAY_INDEX]=side_indices
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,sides)
		result.surface_set_material(2,original.surface_get_material(2))
		DirAccess.make_dir_recursive_absolute(str(r.calibrated_mesh).get_base_dir())
		assert(ResourceSaver.save(result,r.calibrated_mesh)==OK)
		var hull := PackedVector2Array()
		for p: Array in r.silhouette: hull.append(warp(Vector2(p[0],p[1]),r))
		hull=Geometry2D.convex_hull(hull)
		var points := PackedVector3Array()
		for z: float in [-0.04,0.04]:
			for p: Vector2 in hull: points.append(Vector3(p.x,p.y,z))
		var model := Node3D.new()
		model.name="SpiderCalibrated"+str(r.name)
		var volume := MeshInstance3D.new()
		volume.name="PaperVolume"
		volume.mesh=result
		volume.scale.z=0.08
		model.add_child(volume)
		volume.owner=model
		var glb := "res://Assets/3DResources/Creatures/Spider/Models/Calibrated/"+str(r.category)+"/"+str(r.name)+".glb"
		DirAccess.make_dir_recursive_absolute(glb.get_base_dir())
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		assert(doc.append_from_scene(model,state)==OK)
		assert(doc.write_to_filesystem(state,glb)==OK)
		model.free()
		if visuals_only:
			print("SPIDER_VISUALS ",r.category,"/",r.name)
			continue
		var incoming := Vector3(0, float(r.calibrated_span)*0.5,0)
		var outgoing := -incoming
		var tags := "5" if r.name == "UpperLeg" else "1"
		var text := '[gd_scene format=3]\n[ext_resource type="PackedScene" path="res://Scenes/Creatures/Bodyparts/_PhysicalSampleBodyParts.tscn" id="base"]\n[ext_resource type="ArrayMesh" path="%s" id="mesh"]\n[sub_resource type="ConvexPolygonShape3D" id="shape"]\nresource_local_to_scene = true\npoints = %s\n[node name="SpiderCalibrated%s" instance=ExtResource("base")]\ngeometry_mode = 1\ncustom_model_path = NodePath("Model")\npaper_volume_enabled = true\npaper_volume_thickness = 0.08\nsprite_visible = false\nmesh_visible = true\ntags = Array[int]([%s])\nmetadata/source_png = "%s"\nmetadata/connector_hole_diameter = 0.1\nmetadata/fit_leg_connector_span = true\n[node name="CollisionShape3D" parent="." index="0"]\nposition = Vector3(0,0,0)\nshape = SubResource("shape")\n[node name="Model" type="Node3D" parent="."]\n[node name="PaperVolume" type="MeshInstance3D" parent="Model"]\nmesh = ExtResource("mesh")\nscale = Vector3(1,1,0.08)\nmetadata/flat_collision_depth = 0.08\n[node name="JointIn" type="Marker3D" parent="."]\nposition = %s\n[node name="JointOut" type="Marker3D" parent="."]\nposition = %s\n' % [r.calibrated_mesh,var_to_str(points),r.name,tags,r.source,var_to_str(incoming),var_to_str(outgoing)]
		DirAccess.make_dir_recursive_absolute(str(r.calibrated_scene).get_base_dir())
		var file := FileAccess.open(r.calibrated_scene,FileAccess.WRITE)
		file.store_string(text)
		file.close()
		print("SPIDER_CALIBRATED ",r.category,"/",r.name)
	print("PASS: 16 calibrated volumes and GLBs; original textures retained. PhysicalParts retained: ",visuals_only)
	quit()
