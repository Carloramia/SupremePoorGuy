@tool
extends RefCounted
const MODULE = preload("res://Scripts/Creatures/Modules/CreatureModule3D.gd")
const ATTACHMENT = preload("res://Scripts/Creatures/Modules/CreatureModuleAttachment.gd")
const SNAPSHOT = preload("res://Scripts/Creatures/Generators/ManualPartSnapshot.gd")
const GEOMETRY = preload("res://Scripts/Creatures/Generators/GeneratedPartGeometry.gd")
const RULE = preload("res://Scripts/Creatures/Generators/GeneratedPartSceneRule.gd")
const PREFIXES := ["linear_limit_","linear_spring_","linear_motor_","angular_limit_","angular_spring_","angular_motor_"]

static func _rigid_pose(pose: Transform3D) -> bool:
	return pose.is_finite() and pose.basis.determinant()>0.0 and pose.basis.is_equal_approx(pose.basis.orthonormalized())

static func _socket_pose(host: PhysicalBodyPart3D, path: NodePath) -> Variant:
	if path.is_empty(): return Transform3D.IDENTITY
	var socket := host.get_node_or_null(path) as Marker3D
	if socket == null or not host.is_ancestor_of(socket): return null
	var pose := SNAPSHOT.relative_transform(socket,host)
	if not pose.is_finite(): return null
	pose.basis = pose.basis.orthonormalized()
	return pose

static func joint_settings(joint: Generic6DOFJoint3D, scale_factor: float = 1.0) -> Dictionary:
	var result := {}
	for property: Dictionary in joint.get_property_list():
		var key := str(property.name)
		if not PREFIXES.any(func(prefix: String) -> bool: return key.begins_with(prefix)): continue
		var value: Variant = joint.get(key)
		if (key.begins_with("linear_limit_") and (key.ends_with("/lower_distance") or key.ends_with("/upper_distance"))) or (key.begins_with("linear_spring_") and key.ends_with("/equilibrium_point")): value = float(value)*scale_factor
		result[key] = value
	return result

static func _apply_settings(joint: Generic6DOFJoint3D, settings: Dictionary) -> void:
	for key: String in settings: joint.set(key,settings[key])

static func restore_joint_settings(container: Node) -> void:
	var joints := container.get_node_or_null("Joints")
	if joints == null: return
	for joint: Node in joints.get_children():
		if joint is Generic6DOFJoint3D and joint.has_meta(&"module_joint_settings"):
			if joint.is_inside_tree() and PhysicsServer3D.joint_get_type(joint.get_rid())==PhysicsServer3D.JOINT_TYPE_MAX: continue
			_apply_settings(joint,joint.get_meta(&"module_joint_settings"))

static func _role(body: PhysicalBodyPart3D) -> String:
	var tags := PhysicalBodyPart3D.BodyPartTag
	for entry: Array in [[tags.SubTorso,"Torso"],[tags.ForeLeg,"ForeLeg"],[tags.Leg,"Leg"],[tags.Arm,"Arm"],[tags.ArmLimb,"ArmLimb"],[tags.LegLimb,"Limb"],[tags.WingLimb,"WingLimb"],[tags.Wing,"Wing"],[tags.Feather,"Feather"],[tags.Head,"Head"],[tags.Torso,"Torso"],[tags.Tail,"Tail"],[tags.Horn,"Horn"]]:
		if entry[0] in body.tags: return entry[1]
	return "Attachment"

static func _scale_part(body: PhysicalBodyPart3D, factor: float, depth: float) -> bool:
	var source := str(body.get_meta(&"generated_scene_path",body.scene_file_path))
	var snapshot := SNAPSHOT.capture(body,1.0,source)
	if snapshot.is_empty() or not SNAPSHOT.apply_to(body,snapshot,factor,source): return false
	if body.geometry_mode == body.GeometryMode.BOX_FIT:
		body.collision_thickness = depth
		body.prepare_generated_geometry()
	else:
		var bounds := GEOMETRY.bounds(body,false)
		var rule := RULE.new()
		rule.size_mode = RULE.SizeMode.KEEP_SIZE
		if GEOMETRY.fit(body,bounds.size,rule,"",depth).size==Vector3.ZERO: return false
		# KEEP_SIZE fits about the bounds center; modules retain their authored local origin.
		for node: Node in body.get_children():
			if node is Node3D: node.position += bounds.get_center()
	var final_bounds := GEOMETRY.bounds(body,false)
	return final_bounds.position.is_finite() and final_bounds.size.is_finite() and final_bounds.size.x>0.0 and final_bounds.size.y>0.0 and final_bounds.size.z>0.0

static func _binding_paths(body: PhysicalBodyPart3D, names: Dictionary, joints: Dictionary, template: bool) -> void:
	var bindings: Array[ArmSwingBinding] = []
	for binding: ArmSwingBinding in body.arm_swing_bindings:
		if binding == null: continue
		var copy := binding.duplicate() as ArmSwingBinding
		for key: String in ["joint_path","drive_body_path"]:
			var path: NodePath = binding.get(key)
			var target := body.get_node_or_null(path) if not path.is_empty() else null
			if names.has(target): copy.set(key,NodePath("../"+str(names[target])))
			elif joints.has(target): copy.set(key,NodePath(("../../Joints/" if template else "../Joints/")+str(joints[target])))
		var followers: Array[NodePath] = []
		for path: NodePath in binding.follower_paths:
			var target := body.get_node_or_null(path)
			followers.append(NodePath("." if target==body else "../"+str(names[target])) if names.has(target) else path)
		copy.follower_paths = followers
		bindings.append(copy)
	body.arm_swing_bindings = bindings

static func assemble(character: Node3D, container: Node3D, attachments: Array, generator: Node3D) -> String:
	var ids := {}
	for entry: Variant in attachments:
		if not entry is ATTACHMENT: return "Module attachment is empty or has an invalid resource type."
		if not entry.enabled: continue
		var id := str(entry.instance_id)
		if not id.is_valid_identifier() or ids.has(id): return "Missing/duplicate module ID; use letters, digits and underscores: "+id
		ids[id] = true
		if entry.get_template()==null or entry.module_scene==null: return "Module scene is missing: "+id
		if not _rigid_pose(entry.mount_offset) or not is_finite(entry.size_multiplier) or entry.size_multiplier<=0.0: return "Invalid module offset/scale: "+id
		var host: PhysicalBodyPart3D
		for body: Node in container.get_children():
			if body is PhysicalBodyPart3D and not body.has_meta(&"generated_module_id") and str(body.get_meta(&"generated_part_key",body.name))==entry.host_part_key: host = body; break
		if host==null or host.is_broken: return "Module host PartKey is missing/broken: "+entry.host_part_key
		var socket: Variant = _socket_pose(host,entry.host_socket)
		if socket==null: return "Module socket must be a Marker3D below its host Part: "+id
		var instance: Node = entry.get_template().instantiate()
		if instance==null: return "Could not instantiate module scene: "+id
		if not instance is MODULE:
			instance.free(); return "Module root must inherit _SampleModule: "+id
		var module := instance as MODULE
		var error := _assemble_one(character,container,host,module,entry,socket,generator)
		if not error.is_empty():
			if module.get_parent()==null: module.free()
			return id+": "+error
	return ""

static func _assemble_one(character: Node3D, container: Node3D, host: PhysicalBodyPart3D, module: MODULE, entry: ATTACHMENT, socket: Transform3D, generator: Node3D) -> String:
	for path: NodePath in module.required_components:
		if character.get_node_or_null(path)==null: return "Required character component is missing: "+str(path)
	var mount := module.get_node_or_null("MountPoint") as Marker3D
	var source_parts := module.get_node_or_null("Parts")
	var source_joints := module.get_node_or_null("Joints")
	if not source_parts is Node3D or not source_joints is Node3D: return "Module needs Parts and Joints containers (both may be empty)."
	if not _rigid_pose(SNAPSHOT.relative_transform(source_parts,module)) or not _rigid_pose(SNAPSHOT.relative_transform(source_joints,module)): return "Parts/Joints containers must have unit scale."
	if mount==null or not _rigid_pose(mount.transform) or not _rigid_pose(module.transform): return "MountPoint/root must have a finite unit-scale transform."
	var bodies: Array[PhysicalBodyPart3D] = []
	var names := {}
	var poses := {}
	var id := str(entry.instance_id)
	var prefix := "Module_"+id+"__"
	if source_parts!=null:
		for node: Node in source_parts.get_children():
			if not node is PhysicalBodyPart3D or not _rigid_pose(node.transform): return "Parts must contain unit-scale PhysicalBodyPart3D instances."
			if container.has_node(NodePath(prefix+str(node.name))): return "Generated Part name already exists: "+prefix+str(node.name)
			bodies.append(node)
			names[node] = prefix+str(node.name)
			poses[node] = SNAPSHOT.relative_transform(node,module)
	if module.find_children("*","PhysicsBody3D",true,false).size()!=bodies.size(): return "Physics bodies must be direct PhysicalBodyPart3D children of Parts."
	var root_body := module.get_node_or_null(module.root_part_path) as PhysicalBodyPart3D if not module.root_part_path.is_empty() else null
	if not bodies.is_empty() and (root_body not in bodies or module.mount_joint==null or not module.mount_joint.is_valid()): return "A physical module needs Root Part Path and valid Mount Joint settings."
	var joint_rows: Array[Dictionary] = []
	var joint_names := {}
	if source_joints!=null:
		for node: Node in source_joints.get_children():
			if not node is Generic6DOFJoint3D or not _rigid_pose(node.transform): return "Joints must contain Generic6DOFJoint3D nodes."
			if node.name==&"Mount": return "The internal joint name Mount is reserved for the external attachment."
			var a := node.get_node_or_null(node.node_a) as PhysicalBodyPart3D
			var b := node.get_node_or_null(node.node_b) as PhysicalBodyPart3D
			if a not in bodies or b not in bodies or a==b: return "An internal joint has missing/foreign endpoints."
			joint_rows.append({"joint":node,"a":a,"b":b,"pose":SNAPSHOT.relative_transform(node,module),"local_name":str(node.name)})
			joint_names[node] = prefix+str(node.name)
	if module.find_children("*","Joint3D",true,false).size()!=joint_rows.size(): return "All physical joints must be inside Joints."
	# Each physical body must connect to the one external root.
	var visited := {}
	if root_body!=null: visited[root_body] = true
	for _pass: int in bodies.size():
		for row: Dictionary in joint_rows:
			if visited.has(row.a): visited[row.b] = true
			if visited.has(row.b): visited[row.a] = true
	if visited.size()!=bodies.size(): return "Physical module contains disconnected Parts."
	var factor := float(generator.overall_scale)*entry.size_multiplier
	var offset := entry.mount_offset
	offset.origin *= float(generator.overall_scale)
	var mount_pose := host.transform*socket*offset
	var module_pose := mount_pose*Transform3D(Basis.from_scale(Vector3.ONE*factor),Vector3.ZERO)*mount.transform.affine_inverse()
	for body: PhysicalBodyPart3D in bodies: _binding_paths(body,names,joint_names,false)
	for body: PhysicalBodyPart3D in bodies:
		var local_name := str(body.name)
		if not _scale_part(body,factor,float(generator.part_width)*float(generator.overall_scale)): return "Part has invalid model/collision geometry: "+local_name
		var source := str(body.get_meta(&"generated_scene_path",body.scene_file_path))
		body.owner = null
		body.get_parent().remove_child(body)
		body.name = names[body]
		var pose: Transform3D = module_pose*Transform3D(poses[body])
		pose.basis = pose.basis.orthonormalized()
		body.transform = pose
		body.freeze = true
		var role := _role(body)
		var type := "LegLimb" if role=="Limb" else role
		if role in ["Wing","WingLimb"]: type = str(body.get_meta(&"generated_part_type","WingRoot"))
		var size := GEOMETRY.bounds(body,false).size
		var density: float = character.mass_density if character.density_data==null else character.density_data.get_density(type,character.mass_density)
		var mass := size.x*size.y*size.z*density
		body.mass = clampf(mass,character.minimum_feather_mass if role=="Feather" else character.minimum_part_mass,character.maximum_part_mass) if character.mass_limits_enabled else mass
		body.linear_damp = character.part_linear_damping
		body.angular_damp = character.part_angular_damping
		body.set_meta(&"generated_module_id",str(entry.instance_id))
		body.set_meta(&"module_part_name",local_name)
		body.set_meta(&"generated_part_key","Module/"+id+"/"+local_name)
		body.set_meta(&"generated_scene_path",source)
		body.set_meta(&"generated_role",role)
		body.set_meta(&"generated_part_type",type)
		body.set_meta(&"generated_size",size)
		body.set_meta(&"generated_framework_size",size)
		body.set_meta(&"generated_density",density)
		container.add_child(body)
	var joints := container.get_node("Joints")
	for row: Dictionary in joint_rows:
		var joint: Generic6DOFJoint3D = row.joint
		var settings := joint_settings(joint,factor)
		joint.owner = null
		joint.get_parent().remove_child(joint)
		joint.name = joint_names[joint]
		var pose: Transform3D = module_pose*Transform3D(row.pose)
		pose.basis = pose.basis.orthonormalized()
		joint.transform = pose
		_apply_settings(joint,settings)
		_finish_joint(joint,row.a,row.b,id,row.local_name,joints)
	if root_body!=null:
		var joint := Generic6DOFJoint3D.new()
		joint.name = prefix+"Mount"
		joint.transform = mount_pose
		module.mount_joint.apply_to(joint,factor)
		if not module.captured_mount_joint_settings.is_empty():
			_apply_settings(joint,_scaled_settings(module.captured_mount_joint_settings,factor))
		_finish_joint(joint,host,root_body,id,"Mount",joints)
		joint.set_meta(&"module_mount_joint",true)
	module.name = "Module_"+id
	# Parts/Joints now live in the character; a saved module root must not recreate them.
	module.scene_file_path = ""
	module.set_meta(&"generated_module_root",true)
	module.set_meta(&"generated_module_id",id)
	module.set_meta(&"module_scale",factor)
	module.transform = host.transform.affine_inverse()*module_pose
	host.add_child(module)
	print("[generated_module] staged id=%s host=%s parts=%d joints=%d" % [id,entry.host_part_key,bodies.size(),joint_rows.size()+(1 if root_body!=null else 0)])
	return ""

static func _scaled_settings(settings: Dictionary, factor: float) -> Dictionary:
	var result := settings.duplicate(true)
	for key: String in result:
		if (key.begins_with("linear_limit_") and (key.ends_with("/lower_distance") or key.ends_with("/upper_distance"))) or (key.begins_with("linear_spring_") and key.ends_with("/equilibrium_point")): result[key] = float(result[key])*factor
	return result

static func _finish_joint(joint: Generic6DOFJoint3D, a: PhysicalBodyPart3D, b: PhysicalBodyPart3D, id: String, local_name: String, joints: Node) -> void:
	joint.node_a = NodePath("../../"+str(a.name))
	joint.node_b = NodePath("../../"+str(b.name))
	joint.exclude_nodes_from_collision = true
	joint.set_meta(&"generated_module_id",id)
	joint.set_meta(&"module_joint_name",local_name)
	joint.set_meta(&"generated_connection_kind",joint.get_meta(&"generated_connection_kind","Module"))
	joint.set_meta(&"generated_rest_b_relative_a",a.basis.get_rotation_quaternion().inverse()*b.basis.get_rotation_quaternion())
	joint.set_meta(&"generated_joint_frame_a",a.transform.affine_inverse()*joint.transform)
	joint.set_meta(&"generated_joint_frame_b",b.transform.affine_inverse()*joint.transform)
	joint.set_meta(&"module_joint_settings",joint_settings(joint))
	joints.add_child(joint)

static func set_owners(container: Node, owner: Node) -> void:
	for body: Node in container.get_children():
		if body is PhysicalBodyPart3D and body.has_meta(&"generated_module_id"):
			body.owner = owner
			if not body.scene_file_path.is_empty(): owner.set_editable_instance(body,true)
			else:
				for node: Node in body.find_children("*","",true,false): node.owner = owner
		for module: Node in body.get_children():
			if not module.has_meta(&"generated_module_root"): continue
			module.owner = owner
			for node: Node in module.find_children("*","",true,false): node.owner = owner

## Capture into separate template instances; the base manual layout never contains module Parts.
static func capture(container: Node3D, attachments: Array, overall_scale: float) -> Dictionary:
	var pending := []
	var ids := {}
	for entry: Variant in attachments:
		if not entry is ATTACHMENT: return {"ok":false,"error":"Invalid module attachment resource."}
		if not entry.enabled: continue
		var id := str(entry.instance_id)
		if not id.is_valid_identifier() or ids.has(id): return {"ok":false,"error":"Missing/duplicate module ID: "+id}
		ids[id] = true
		var modules := container.find_children("Module_"+str(entry.instance_id),"Node3D",true,false)
		var live: MODULE
		for node: Node in modules:
			if node is MODULE and node.get_meta(&"generated_module_id","")==str(entry.instance_id): live = node; break
		if live==null: return {"ok":false,"error":"Module was not generated; regenerate before capture: "+str(entry.instance_id)}
		var host := live.get_parent() as PhysicalBodyPart3D
		var factor := float(live.get_meta(&"module_scale",1.0))
		if host==null or host.is_broken or not is_finite(factor) or factor<=0.0: return {"ok":false,"error":"Module host/scale is invalid: "+id}
		if not live.has_node("Parts") or not live.has_node("Joints") or not live.has_node("MountPoint"): return {"ok":false,"error":"Module containers/MountPoint were removed: "+id}
		# Do not reinstantiate the original scene: its Parts have already been moved out.
		var clone := live.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_SIGNALS) as MODULE
		clone.scene_file_path = ""
		clone.transform = Transform3D.IDENTITY
		var parts := clone.get_node("Parts")
		var joints := clone.get_node("Joints")
		var names := {}
		var joint_names := {}
		for body: Node in container.get_children():
			if body is PhysicalBodyPart3D and body.get_meta(&"generated_module_id","")==str(entry.instance_id): names[body] = str(body.get_meta(&"module_part_name"))
		for joint: Node in container.get_node("Joints").get_children():
			if joint is Generic6DOFJoint3D and joint.get_meta(&"generated_module_id","")==str(entry.instance_id) and not joint.has_meta(&"module_mount_joint"): joint_names[joint] = str(joint.get_meta(&"module_joint_name"))
		for body: PhysicalBodyPart3D in names:
			if body.is_broken: clone.free(); return {"ok":false,"error":"Cannot capture a broken module Part."}
			var copy := body.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS | Node.DUPLICATE_SIGNALS) as PhysicalBodyPart3D
			copy.scene_file_path = ""
			var original_bindings: Array[ArmSwingBinding] = body.arm_swing_bindings
			_binding_paths(body,names,joint_names,true)
			copy.arm_swing_bindings = body.arm_swing_bindings
			body.arm_swing_bindings = original_bindings
			var source := str(body.get_meta(&"generated_scene_path",body.scene_file_path))
			var snapshot := SNAPSHOT.capture(body,factor,source)
			if snapshot.is_empty() or not SNAPSHOT.apply_to(copy,snapshot,1.0,source): clone.free(); copy.free(); return {"ok":false,"error":"Invalid module Part snapshot."}
			copy.name = names[body]
			var pose := live.global_transform.affine_inverse()*body.global_transform
			pose.basis = pose.basis.orthonormalized()
			copy.transform = pose
			copy.freeze = true
			parts.add_child(copy)
		var socket_pose: Variant = _socket_pose(host,entry.host_socket)
		if socket_pose==null: clone.free(); return {"ok":false,"error":"Module socket was removed."}
		var mount_world: Transform3D = live.global_transform*live.get_node("MountPoint").transform
		mount_world.basis = mount_world.basis.orthonormalized()
		var offset: Transform3D = (host.global_transform*Transform3D(socket_pose)).affine_inverse()*mount_world
		offset.origin /= overall_scale
		for joint: Node in container.get_node("Joints").get_children():
			if not joint is Generic6DOFJoint3D or joint.get_meta(&"generated_module_id","")!=str(entry.instance_id): continue
			var a := joint.get_node_or_null(joint.node_a)
			var b := joint.get_node_or_null(joint.node_b)
			if (joint.has_meta(&"module_mount_joint") and (a!=host or not names.has(b))) or (not joint.has_meta(&"module_mount_joint") and (not names.has(a) or not names.has(b))):
				clone.free(); return {"ok":false,"error":"Module joint endpoints changed outside its own Parts: "+id}
			var pose: Transform3D = live.global_transform.affine_inverse()*joint.global_transform
			pose.basis = pose.basis.orthonormalized()
			if joint.has_meta(&"module_mount_joint"):
				clone.root_part_path = NodePath("Parts/"+str(names[b]))
				clone.get_node("MountPoint").transform = pose
				clone.captured_mount_joint_settings = joint_settings(joint,1.0/factor)
				var socket: Variant = _socket_pose(host,entry.host_socket)
				if socket==null: clone.free(); return {"ok":false,"error":"Module socket was removed."}
				offset = (host.global_transform*Transform3D(socket)).affine_inverse()*joint.global_transform
				offset.origin /= overall_scale
				continue
			var copy := joint.duplicate(Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS) as Generic6DOFJoint3D
			copy.name = joint_names[joint]
			copy.transform = pose
			copy.node_a = NodePath("../../Parts/"+str(names[joint.get_node(joint.node_a)]))
			copy.node_b = NodePath("../../Parts/"+str(names[joint.get_node(joint.node_b)]))
			_apply_settings(copy,joint_settings(joint,1.0/factor))
			joints.add_child(copy)
		# This is a complete snapshot, not a second instance of its original hierarchy.
		for node: Node in clone.find_children("*","",true,false):
			node.scene_file_path = ""
			node.owner = clone
		var packed := PackedScene.new()
		var error := packed.pack(clone)
		clone.free()
		if error!=OK: return {"ok":false,"error":"Could not pack module snapshot."}
		pending.append({"entry":entry,"scene":packed,"offset":offset})
	return {"ok":true,"pending":pending}
