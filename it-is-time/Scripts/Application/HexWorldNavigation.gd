extends RefCounted
## Authoring coordinates and six-neighbour traversal, independent of visual sprites.
const DIRECTIONS := [Vector2i(1,0),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(0,-1),Vector2i(1,-1)]
const SIGHT = preload("res://Scripts/Application/HexMapSight.gd")
var grid: Dictionary
var art_surfaces: Array = []
var art_cells := {}
var cells := {}
var ids := {}
var mountains := {}
var nav := AStar2D.new()
var destroyed := {}
var conditions: Array = []
var party_count := 0
var _signature := ""

func _init(world: Dictionary) -> void:
	grid = world.hex_grid
	for cell: Dictionary in world.hex_cells:
		var coordinate := Vector2i(int(cell.q),int(cell.r))
		cells[coordinate] = cell
		ids[coordinate] = ids.size()
		nav.add_point(ids[coordinate],centre(coordinate))
	for coordinate: Vector2i in cells:
		for direction: Vector2i in DIRECTIONS:
			var other := coordinate+direction
			if ids.has(other) and not nav.are_points_connected(ids[coordinate],ids[other]):
				nav.connect_points(ids[coordinate],ids[other])
	var remaining := {}
	for coordinate: Vector2i in cells:
		if cells[coordinate].get("feature","")=="wall": remaining[coordinate]=true
	while not remaining.is_empty():
		var pending: Array = [remaining.keys()[0]]
		remaining.erase(pending[0])
		var component: Array = []
		var pit := true
		while not pending.is_empty():
			var coordinate: Vector2i = pending.pop_back()
			component.append(coordinate)
			pit = pit and cells[coordinate].region=="pit" and cells[coordinate].get("wall_material","")!="source_mountain"
			for direction: Vector2i in DIRECTIONS:
				if remaining.erase(coordinate+direction): pending.append(coordinate+direction)
		if not pit or component.size()>7:
			for coordinate: Vector2i in component: mountains[coordinate]=true
	for spec: Dictionary in world.get("mountain_surfaces",[]):
		var rings: Array = []
		for ring: Array in spec.get("rings",[spec.polygon]):
			var points := PackedVector2Array()
			for point: Array in ring: points.append(Vector2(point[0],point[1]))
			rings.append(points)
		var surface: Dictionary=SIGHT.occluder_rings(rings)
		surface["site_id"]=spec.id
		art_surfaces.append(surface)
		for id: String in spec.cells: art_cells[parse_key(id)]=true
	# Precise contours replace sampled mountain cells, while explicit manual walls remain.
	for coordinate: Vector2i in art_cells:
		if not cells.get(coordinate,{}).get("mountain_manual_rule",false): mountains.erase(coordinate)
	if not art_surfaces.is_empty():
		for coordinate: Vector2i in cells:
			for direction: Vector2i in DIRECTIONS:
				var other := coordinate+direction
				if ids.has(other) and nav.are_points_connected(ids[coordinate],ids[other]) and crosses_art(centre(coordinate),centre(other)):
					nav.disconnect_points(ids[coordinate],ids[other])

func centre(coordinate: Vector2i) -> Vector2:
	var radius := float(grid.cell_width)*0.5
	return Vector2(float(grid.origin[0])+1.5*radius*coordinate.x,float(grid.origin[1])+sqrt(3.0)*radius*(coordinate.y+coordinate.x*0.5))

func axial(point: Vector2) -> Vector2i:
	var local := (point-Vector2(float(grid.origin[0]),float(grid.origin[1])))/(float(grid.cell_width)*0.5)
	var q := 2.0*local.x/3.0
	var r := -local.x/3.0+sqrt(3.0)*local.y/3.0
	var s := -q-r
	var rounded_q := roundi(q)
	var rounded_r := roundi(r)
	var rounded_s := roundi(s)
	if absf(rounded_q-q)>absf(rounded_r-r) and absf(rounded_q-q)>absf(rounded_s-s): rounded_q=-rounded_r-rounded_s
	elif absf(rounded_r-r)>absf(rounded_s-s): rounded_r=-rounded_q-rounded_s
	return Vector2i(rounded_q,rounded_r)

func key(coordinate: Vector2i) -> String:
	return "%d,%d" % [coordinate.x,coordinate.y]

func parse_key(value: String) -> Vector2i:
	var parts := value.split(",")
	return Vector2i(int(parts[0]),int(parts[1])) if parts.size()==2 else Vector2i(-100000,-100000)

func polygon(coordinate: Vector2i) -> PackedVector2Array:
	var result := PackedVector2Array()
	for index: int in 6: result.append(centre(coordinate)+Vector2.from_angle(index*TAU/6)*float(grid.cell_width)*0.5)
	return result

func sync(snapshot: Dictionary, owned_count: int) -> void:
	var signature := str(snapshot.destroyed)+str(snapshot.enabled_conditions)+str(owned_count)
	if signature==_signature: return
	_signature=signature
	destroyed.clear()
	for id: String in snapshot.destroyed: destroyed[id]=true
	conditions=snapshot.enabled_conditions
	party_count=owned_count
	for coordinate: Vector2i in cells: nav.set_point_disabled(ids[coordinate],not can_pass(coordinate))

func condition(id: String) -> bool:
	return id.is_empty() or (party_count>0 if id=="has_monster" else id in conditions)

func can_pass(coordinate: Vector2i) -> bool:
	if not cells.has(coordinate): return false
	var cell: Dictionary = cells[coordinate]
	var feature: String = cell.get("feature","")
	var control: String = cell.get("control","")
	if control=="outside" or feature=="river": return false
	if feature=="wall" and (not art_cells.has(coordinate) or cell.get("mountain_manual_rule",false)): return false
	if inside_art(centre(coordinate)): return false
	var owners: Array = cell.get("obstacle_ids",[])
	for id: String in owners:
		if not destroyed.has(id): return false
	if (feature=="breakable" or control=="breakable") and owners.is_empty(): return false
	if not condition(str(cell.get("condition_ref",""))): return false
	if control!="breakable" and not condition(str(cell.get("control_condition_ref",""))): return false
	return true

func route(from: Vector2, target: Vector2, allow_adjacent := false) -> PackedVector2Array:
	if inside_art(target) and not allow_adjacent: return PackedVector2Array()
	var start := axial(from)
	var finish := axial(target)
	var candidates: Array[Vector2i] = [finish]
	if (not can_pass(finish) or inside_art(target)) and allow_adjacent:
		candidates.clear()
		for direction: Vector2i in DIRECTIONS: candidates.append(finish+direction)
	var result := _best_route(start,candidates)
	if not result.is_empty() and can_pass(finish) and not crosses_art(result[-1],target): result.append(target)
	elif start==finish and can_pass(start): result.append(target)
	return result

func obstacle_neighbors(object: Dictionary) -> Array[Vector2i]:
	var occupied := {}
	for id: String in object.get("destruction",{}).get("cells",[]): occupied[parse_key(id)]=true
	if occupied.is_empty(): occupied[axial(Vector2(float(object.position[0]),float(object.position[1])))]=true
	var result: Array[Vector2i] = []
	for coordinate: Vector2i in occupied:
		for direction: Vector2i in DIRECTIONS:
			var next := coordinate+direction
			if not occupied.has(next) and can_pass(next) and next not in result: result.append(next)
	return result

func obstacle_route(from: Vector2, object: Dictionary) -> PackedVector2Array:
	return _best_route(axial(from),obstacle_neighbors(object))

func _best_route(start: Vector2i, candidates: Array[Vector2i]) -> PackedVector2Array:
	if not ids.has(start): return PackedVector2Array()
	var was_disabled := nav.is_point_disabled(ids[start])
	nav.set_point_disabled(ids[start],false)
	var best := PackedVector2Array()
	var best_distance := INF
	for candidate: Vector2i in candidates:
		if not can_pass(candidate): continue
		var points := nav.get_point_path(ids[start],ids[candidate])
		if not points.is_empty():
			var distance := 0.0
			for index: int in range(1,points.size()): distance+=points[index-1].distance_to(points[index])
			if distance<best_distance: best=points; best_distance=distance
	nav.set_point_disabled(ids[start],was_disabled)
	return best

func line_of_sight(from: Vector2, to: Vector2) -> bool:
	if not SIGHT.visible(from,to,sight_occluders(from,to)): return false
	var finish := axial(to)
	var steps := maxi(1,ceili(from.distance_to(to)/(float(grid.cell_width)*0.18)))
	for index: int in range(1,steps+1):
		var coordinate := axial(from.lerp(to,float(index)/steps))
		if mountains.has(coordinate) and coordinate!=finish: return false
	return true

func inside_art(point: Vector2) -> bool:
	for surface: Dictionary in art_surfaces:
		if surface._bounds.has_point(point) and SIGHT.contains_surface(surface,point): return true
	return false

func crosses_art(from: Vector2, to: Vector2) -> bool:
	return not SIGHT.visible(from,to,art_surfaces)

func sight_occluders(from: Vector2, to: Vector2, radius := 0.0) -> Array:
	var area := Rect2(from,Vector2.ZERO).expand(to).grow(radius+float(grid.cell_width))
	var result: Array = []
	for surface: Dictionary in art_surfaces:
		if surface._bounds.intersects(area): result.append(surface)
	var first := axial(area.position)
	var last := axial(area.end)
	for q: int in range(mini(first.x,last.x)-1,maxi(first.x,last.x)+2):
		var x := centre(Vector2i(q,0)).x
		var top := axial(Vector2(x,area.position.y)).y
		var bottom := axial(Vector2(x,area.end.y)).y
		for r: int in range(top-1,bottom+2):
			var coordinate := Vector2i(q,r)
			if mountains.has(coordinate): result.append(SIGHT.occluder(polygon(coordinate)))
	return result

func visible_cells(from: Vector2, radius: float) -> Dictionary:
	var origin := axial(from)
	var extent := ceili(radius/(float(grid.cell_width)*0.75))+1
	var result := {}
	for q: int in range(-extent,extent+1):
		for r: int in range(-extent,extent+1):
			var coordinate := origin+Vector2i(q,r)
			if cells.has(coordinate) and centre(coordinate).distance_to(from)<=radius and line_of_sight(from,centre(coordinate)):
				result[key(coordinate)]=true
	return result

func vision_polygon(from: Vector2, radius: float) -> PackedVector2Array:
	if not art_surfaces.is_empty():
		var occluders := sight_occluders(from,from,radius)
		var result := PackedVector2Array()
		for index: int in 256:
			var direction := Vector2.from_angle(TAU*index/256)
			result.append(from+direction*SIGHT.ray_distance(from,from+direction*radius,occluders))
		return result
	if mountains.has(axial(from)): return PackedVector2Array()
	var edges: Array = []
	for coordinate: Vector2i in mountains:
		if centre(coordinate).distance_to(from)>radius+float(grid.cell_width): continue
		var points := polygon(coordinate)
		for index: int in 6: edges.append([points[index],points[(index+1)%6]])
	var result := PackedVector2Array()
	for index: int in 256:
		var endpoint := from+Vector2.from_angle(TAU*index/256)*radius
		var nearest := endpoint
		for edge: Array in edges:
			var hit: Variant=Geometry2D.segment_intersects_segment(from,endpoint,edge[0],edge[1])
			if hit is Vector2 and from.distance_squared_to(hit)<from.distance_squared_to(nearest): nearest=hit
		result.append(nearest)
	return result
