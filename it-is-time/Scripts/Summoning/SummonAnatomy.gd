extends RefCounted
## Deterministic anatomy additions, executed before the actor enters the scene tree.
static func root_pose(node: Node3D, root: Node3D) -> Transform3D:
	var pose := node.transform
	var parent := node.get_parent()
	while parent != root and parent is Node3D:
		pose = parent.transform * pose
		parent = parent.get_parent()
	return pose

static func valid(settings: Dictionary) -> bool:
	for key: String in settings:
		if key not in ["scale","extra_limb_pairs"]: return false
	var size: Variant = settings.get("scale",1.0)
	var pairs: Variant = settings.get("extra_limb_pairs",0)
	return (size is float or size is int) and is_finite(float(size)) and float(size)>=0.1 and float(size)<=3.0 and (pairs is float or pairs is int) and float(pairs)==floor(float(pairs)) and int(pairs) in [0,1,2,3]

static func apply(actor: Node3D, settings: Dictionary) -> bool:
	if not valid(settings): return false
	var parts: Array[PhysicalBodyPart3D] = []
	var limbs: Array[PhysicalBodyPart3D] = []
	var torso: PhysicalBodyPart3D
	for node: Node in actor.find_children("*","",true,false):
		if not node is PhysicalBodyPart3D: continue
		parts.append(node)
		if 0 in node.tags and (torso==null or node.mass>torso.mass): torso=node
		if 5 in node.tags or 12 in node.tags: limbs.append(node)
	var pair_count := int(settings.get("extra_limb_pairs",0))
	if pair_count>0:
		if torso==null or limbs.is_empty(): return false
		var graph := {}
		for part: PhysicalBodyPart3D in parts:
			if part.tags.any(func(tag): return tag in [1,2,4,5,12]): graph[part]=[]
		var connections: Array[Joint3D] = []
		for node: Node in actor.find_children("*","Joint3D",true,false):
			var first := node.get_node_or_null(node.node_a) as PhysicalBodyPart3D
			var second := node.get_node_or_null(node.node_b) as PhysicalBodyPart3D
			connections.append(node)
			if graph.has(first) and graph.has(second): graph[first].append(second); graph[second].append(first)
		var branches: Array = []
		var visited := {}
		for start: PhysicalBodyPart3D in limbs:
			if visited.has(start): continue
			var branch: Array[PhysicalBodyPart3D] = [start]
			visited[start]=true
			var cursor := 0
			while cursor<branch.size():
				for neighbor: PhysicalBodyPart3D in graph[branch[cursor]]:
					if not visited.has(neighbor): branch.append(neighbor); visited[neighbor]=true
				cursor+=1
			branches.append(branch)
		var extras := Node3D.new()
		extras.name = "SummonExtraLimbs"
		actor.add_child(extras)
		for index: int in pair_count*2:
			var branch: Array = branches[index%branches.size()]
			var group := Node3D.new()
			group.name="ExtraLimb%d" % index
			extras.add_child(group)
			var copies := {}
			var shift := Vector3(0.35*(1+index/2),0.20,0.35 if index%2==0 else -0.35)
			for source: PhysicalBodyPart3D in branch:
				var limb := source.duplicate(Node.DUPLICATE_SCRIPTS) as PhysicalBodyPart3D
				limb.scene_file_path=""
				limb.name=source.name
				for child: Node in limb.find_children("*","",true,false):
					if is_instance_valid(child) and child is Joint3D: child.free()
				group.add_child(limb)
				var pose := root_pose(source,actor)
				pose.origin+=shift
				limb.transform=pose
				limb.set_meta(&"generated_part_key","summon_extra_%d_%s" % [index,source.name])
				copies[source]=limb
				parts.append(limb)
			var attached := false
			for source: Joint3D in connections:
				var first := source.get_node_or_null(source.node_a) as PhysicalBodyPart3D
				var second := source.get_node_or_null(source.node_b) as PhysicalBodyPart3D
				if not copies.has(first) and not copies.has(second): continue
				if not copies.has(first) and (first==null or 0 not in first.tags): continue
				if not copies.has(second) and (second==null or 0 not in second.tags): continue
				var joint := PinJoint3D.new()
				joint.name="Joint%d" % group.get_child_count()
				group.add_child(joint)
				joint.position=root_pose(source,actor).origin+shift
				joint.node_a=joint.get_path_to(copies.get(first,first))
				joint.node_b=joint.get_path_to(copies.get(second,second))
				joint.exclude_nodes_from_collision=true
				attached = attached or not copies.has(first) or not copies.has(second)
			if not attached: extras.free(); return false
	var factor := float(settings.get("scale",1.0))
	if not is_equal_approx(factor,1.0):
		var poses := {}
		for node: Node in actor.find_children("*","",true,false):
			if node is PhysicalBodyPart3D or node is Joint3D: poses[node]=root_pose(node,actor)
		for node: Node3D in poses:
			var pose: Transform3D = poses[node]
			pose.origin *= factor
			var parent_pose := Transform3D.IDENTITY
			if node.get_parent()!=actor: parent_pose=root_pose(node.get_parent(),actor)
			node.transform = parent_pose.affine_inverse()*pose
		for part: PhysicalBodyPart3D in parts:
			part.mass = maxf(0.001,part.mass*pow(factor,3.0))
			for child: Node in part.get_children():
				if child is Node3D and not child is PhysicalBodyPart3D and not child is Joint3D: child.scale *= factor
	return true
