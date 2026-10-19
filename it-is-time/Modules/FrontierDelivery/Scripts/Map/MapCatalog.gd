extends RefCounted
## Immutable converted authoring data. Runtime progress belongs to PrototypeState.
static var _index: Dictionary = {}
static var _maps: Dictionary = {}
static var version := "20261015"
static var _indexes := {}
static var _version_maps := {}
static var _hex_keys := {}
static var _colliders: Array = []
static var _colliders_ready := false
static var _roles: Dictionary = {}
static var _locations: Dictionary = {}
static var _collider_cells: Dictionary = {}
const COLLIDER_CELL_SIZE := 128.0

static func select_version(value: String) -> void:
	assert(value in ["20261015","20261019"])
	if value==version: return
	version=value
	_index={}; _maps={}; _roles={}; _locations={}; _colliders=[]; _colliders_ready=false; _collider_cells={}

static func is_hex() -> bool:
	return version=="20261019"

static func hex_cell_keys(value: String) -> Dictionary:
	if not _hex_keys.has(value):
		var keys := {}
		for cell: Dictionary in world(value).get("hex_cells",[]): keys["%d,%d" % [int(cell.q),int(cell.r)]]=true
		_hex_keys[value]=keys
	return _hex_keys[value]

static func location_for_version(id: String, value: String) -> Dictionary:
	for object: Dictionary in world(value).objects:
		if object.id==id or object.get("location_id","")==id: return object
	return {}

static func objects_in_role(role: String) -> Array:
	if _roles.is_empty():
		_roles={"reveals":[],"discoverable":[],"encounters":[],"roads":[],"interactive":[],"obstacles":[]}
		for object in world().objects:
			_locations[object.id]=object
			if not str(object.get("location_id","")).is_empty():_locations[object.location_id]=object
			if object.type=="reveal_area":_roles.reveals.append(object)
			if object.type=="road":_roles.roads.append(object)
			if object.has("discovery"):_roles.discoverable.append(object)
			if object.type=="camp" and object.get("encounter",{}).get("enabled",false):_roles.encounters.append(object)
			if object.type in ["camp","house","town","destructible"]:_roles.interactive.append(object)
			if object.type in ["destructible","traversable","indestructible"]:_roles.obstacles.append(object)
	return _roles.get(role,[])

static func colliders() -> Array:
	if not _colliders_ready:
		for object in world().objects:
			if object.get("collision",{}).get("enabled",false):_colliders.append(object.duplicate(true))
			if object.get("tree_collision",{}).get("enabled",false):
				for member in object.get("tree_cluster",{}).get("members",[]):
					if not member.get("collision",{}).get("enabled",false):continue
					var shape:Dictionary=member.collision.duplicate(true)
					shape.size=[shape.size[0]*object.tree_collision.get("radius_scale",1),shape.size[1]*object.tree_collision.get("radius_scale",1)]
					_colliders.append({"id":object.id,"member_id":member.id,"collision":shape,"_world_transform":object_transform(object)*object_transform(member)})
		for collider in _colliders:
			var shape:Dictionary=collider.collision
			var polygon:=PackedVector2Array()
			var half:=v(shape.size)/2.0
			var points:Array=shape.points.duplicate() if shape.shape=="polygon" else []
			if shape.shape=="circle":
				for i in 64:points.append([cos(TAU*i/64)*half.x,sin(TAU*i/64)*half.y])
			elif points.is_empty():points=[[-half.x,-half.y],[half.x,-half.y],[half.x,half.y],[-half.x,half.y]]
			for point in points:polygon.append(world_point(collider,v(point).rotated(deg_to_rad(shape.rotation))+v(shape.offset)))
			collider._polygon=polygon
			collider._bounds=shape_world_bounds(collider,shape)
			var bounds:Rect2=collider._bounds.grow(float(world().get("player_radius",6)))
			var begin:=Vector2i((bounds.position/COLLIDER_CELL_SIZE).floor())
			var end:=Vector2i((bounds.end/COLLIDER_CELL_SIZE).floor())
			for x in range(begin.x,end.x+1):
				for y in range(begin.y,end.y+1):
					var cell:=Vector2i(x,y)
					if not _collider_cells.has(cell):_collider_cells[cell]=[]
					_collider_cells[cell].append(collider)
		_colliders_ready=true
	return _colliders

static func colliders_at(point: Vector2) -> Array:
	colliders()
	return _collider_cells.get(Vector2i((point/COLLIDER_CELL_SIZE).floor()),[])

static func collider_contains(collider: Dictionary,point: Vector2,radius: float=0) -> bool:
	if not collider._bounds.grow(radius).has_point(point):return false
	# Keep the editor's analytic ellipse/polygon test for the point itself.
	if shape_contains(collider.collision,local_point(collider,point)):return true
	if radius<=0:return false
	var polygon:PackedVector2Array=collider._polygon
	for i in polygon.size():
		if distance_to_segment(point,polygon[i],polygon[(i+1)%polygon.size()])<=radius:return true
	return false

static func object_transform(object: Dictionary) -> Transform2D:
	return Transform2D(deg_to_rad(object.rotation),v(object.scale),0.0,v(object.position))

static func shape_world_bounds(object: Dictionary,shape: Dictionary) -> Rect2:
	var points:Array=shape.points if shape.shape=="polygon" else []
	if points.is_empty():
		var half:=v(shape.size)/2.0
		points=[[-half.x,-half.y],[half.x,-half.y],[half.x,half.y],[-half.x,half.y]]
	var rect:=Rect2()
	for i in points.size():
		var point:=world_point(object,v(points[i]).rotated(deg_to_rad(shape.rotation))+v(shape.offset))
		if i==0:rect=Rect2(point,Vector2.ZERO)
		else:rect=rect.expand(point)
	return rect

static func index(value: String = "") -> Dictionary:
	var selected := version if value.is_empty() else value
	if not _indexes.has(selected):
		var path := "res://Content/Maps/FrontierEditor_20261019/Runtime/index.json" if selected=="20261019" else "res://Content/Maps/FrontierDelivery_20261015/Data/Maps/index.json"
		_indexes[selected] = JSON.parse_string(FileAccess.get_file_as_string(path))
	return _indexes[selected]

static func map_data(id: String, value: String = "") -> Dictionary:
	var selected := version if value.is_empty() else value
	var catalog := index(selected)
	if not catalog.maps.has(id):
		return {}
	var key := selected+":"+id
	if not _version_maps.has(key):
		_version_maps[key] = JSON.parse_string(FileAccess.get_file_as_string(catalog.maps[id].data))
	return _version_maps[key]

static func world(value: String = "") -> Dictionary:
	return map_data("frontier_layout",value)

static func object_art(object: Dictionary,broken := false) -> Dictionary:
	var policy:Dictionary=index().get("world_art",{})
	var id:=str(policy.get("broken_assets" if broken else "object_assets",{}).get(object.id,""))
	if not id.is_empty():return policy.assets[id]
	return index().assets.get(object.get("broken_asset","") if broken else object.visual.asset,{})

static func location(id: String) -> Dictionary:
	objects_in_role("interactive")
	return _locations.get(id,{})

static func location_name(id: String) -> String:
	var object := location(id)
	return str(object.get("name", "边境行旅图"))

static func location_tags(id: String) -> String:
	var object := location(id)
	var terrain := str(object.get("terrain_id", ""))
	if terrain.is_empty():
		terrain = str(object.get("encounter", {}).get("terrain_id", ""))
	if terrain.is_empty():
		terrain = str(map_data(object.get("battle_map_id", "")).get("theme", ""))
	return "【森林】" if "forest" in terrain or "spider" in terrain or terrain == "tree" else "【荒原】"

static func catalog_entry(category: String, id: String) -> Dictionary:
	for entry in index().catalogs.get(category, []):
		if entry.id == id:
			return entry
	return {}

static func v(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))

static func local_point(object: Dictionary, point: Vector2) -> Vector2:
	if object.has("_world_transform"):return object._world_transform.affine_inverse()*point
	return (point-v(object.position)).rotated(-deg_to_rad(object.rotation))/v(object.scale)

static func world_point(object: Dictionary, point: Vector2) -> Vector2:
	if object.has("_world_transform"):return object._world_transform*point
	return (point*v(object.scale)).rotated(deg_to_rad(object.rotation))+v(object.position)

static func shape_contains(shape: Dictionary, point: Vector2) -> bool:
	if not shape.get("enabled", false):
		return false
	point = (point-v(shape.offset)).rotated(-deg_to_rad(shape.rotation))
	var half := v(shape.size)/2.0
	match shape.shape:
		"circle": return (point/half).length_squared() <= 1.0
		"polygon":
			var points := PackedVector2Array()
			for p in shape.points:
				points.append(v(p))
			return Geometry2D.is_point_in_polygon(point, points)
		_: return absf(point.x) <= half.x and absf(point.y) <= half.y

static func distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	return point.distance_to(Geometry2D.get_closest_point_to_segment(point, a, b))

static func road_speed(point: Vector2) -> float:
	var multiplier := 1.0
	for object in objects_in_role("roads"):
		var local := local_point(object, point)
		for i in range(1, object.points.size()):
			if distance_to_segment(local,v(object.points[i-1]),v(object.points[i])) <= float(object.width)/2.0:
				multiplier = maxf(multiplier,float(object.speed_multiplier))
	return multiplier
