extends RefCounted
const Sight=preload("res://Modules/HexFrontier/MapSight.gd")
const Taxonomy=preload("res://Modules/HexFrontier/MonsterTaxonomy.gd")
## Art-independent hex contract. Event/enemy IDs stay external system references.
var document:Dictionary={}
var cells:Dictionary={}
var sites:Array=[]
var roads:Array=[]
var grid:Dictionary={}
var bounds:=Rect2()
var wall_kinds:Dictionary={}
var art_surfaces:Array=[]
var art_site_ids:Dictionary={}

func load_layout(path:String="res://Content/Maps/HexFrontier_20261019/hex_layout.json") -> String:
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:return "布局 JSON 无效"
	return set_document(parsed)

func set_document(value:Dictionary) -> String:
	if value.get("format","")!="frontier_hex_layout" or value.get("version",0)!=1:return "布局版本不兼容"
	if not value.get("grid") is Dictionary or not value.get("bounds") is Dictionary:return "缺少网格或边界"
	if not value.get("cells") is Array or not value.get("sites") is Array or not value.get("roads") is Array:return "缺少布局数据"
	value=Taxonomy.upgrade_layout(value)
	value=value.duplicate(true)
	var spawn_site_id:=str(value.get("spawn_site_id","layout_summoning_hut"))
	for site in value.get("sites",[]):
		if site is Dictionary and site.get("id","")==spawn_site_id:
			value["spawn"]=site.position.duplicate();value["spawn_site_id"]=spawn_site_id
			var visual:Dictionary=site.get("visual",{})
			for asset in value.get("assets",[]):
				if asset.id!=visual.get("asset_id",""):continue
				var width:=float(visual.width);var height:=width*float(asset.height)/float(asset.width)*float(visual.get("height_scale",1))
				var anchor:=v(visual.get("anchor",asset.get("anchor",[.5,1])));var entry:=v(value.get("spawn_site_anchor",[0.33125,0.8263119402908841]))
				var offset:=((entry-anchor)*Vector2(width,height)).rotated(deg_to_rad(float(visual.get("rotation",0))))+v(visual.get("offset",[0,0]))
				value["spawn"]=[site.position[0]+offset.x,site.position[1]+offset.y];break
			break
	if not _point(value.grid.get("origin")) or not _point(value.bounds.get("position")) or not _point(value.bounds.get("size")) or not _point(value.get("spawn")):return "坐标无效"
	var width=value.grid.get("cell_width",0)
	if not _number(width) or float(width)<32 or float(width)>1024:return "格子尺寸无效"
	if value.cells.size()>150000 or value.sites.size()>5000 or value.roads.size()>5000:return "布局数量超过上限"
	var next_bounds:=Rect2(v(value.bounds.position),v(value.bounds.size))
	if next_bounds.size.x<=0 or next_bounds.size.y<=0 or not next_bounds.has_point(v(value.spawn)):return "起点或范围无效"
	var keys:Dictionary={}
	for cell in value.cells:
		if not cell is Dictionary or not _number(cell.get("q")) or not _number(cell.get("r")):return "蜂窝坐标无效"
		var key:=Vector2i(int(cell.q),int(cell.r))
		if keys.has(key) or cell.get("region","") not in ["forest","spider","sparse","grass","pit","desert"] or cell.get("feature","") not in ["","river","wall","breakable","bridge"]:return "蜂窝规则无效"
		keys[key]=cell
		if cell.get("control","") not in ["","allowed","outside","breakable"]:return "边缘控制状态无效"
		for field in ["control_event_id","control_condition_ref"]:
			if cell.has(field) and not cell[field] is String:return "边缘破坏引用必须为文本"
	var ids:Dictionary={}
	for site in value.sites:
		if not site is Dictionary or not _point(site.get("position")) or not _number(site.get("radius")) or float(site.radius)<0:return "点位坐标或范围无效"
		if site.get("id","")=="" or ids.has(site.id) or site.get("kind","") not in ["camp","house","town","event","destructible","decoration"]:return "点位标识或种类无效"
		ids[site.id]=true
		if not _number(site.get("difficulty",0)) or float(site.get("difficulty",0))!=int(site.get("difficulty",0)) or int(site.get("difficulty",0)) not in [0,1,2,3]:return "难度必须为三级"
		if int(site.get("difficulty",0))==3 and site.get("auto_trigger",false):return "三级不能自动遭遇"
		for role in ["primary","secondary"]:
			if site.get(role+"_type","") not in Taxonomy.TYPES+["","unassigned"] or site.get(role+"_size","") not in Taxonomy.SIZES:return "怪物类型或尺寸无效"
			if site.has(role+"_grouped") and not site[role+"_grouped"] is bool:return "群体设置必须为布尔值"
		if Taxonomy.duplicate_roles(site):return "复合主副组不能完全相同"
		if not str(site.get("secondary_type","")).is_empty() and not (int(site.difficulty)==3 or int(site.difficulty)==2 and site.get("sublevel","")=="upper"):return "复合点位需为二级高段或三级"
	for road in value.roads:
		if not road is Dictionary or not road.get("points") is Array or road.points.size()<2 or not _number(road.get("width")) or float(road.width)<=0:return "道路无效"
		for point in road.points:
			if not _point(point):return "道路节点无效"
	document=value.duplicate(true);grid=document.grid;sites=document.sites;roads=document.roads;bounds=next_bounds
	cells={}
	for cell in document.cells:cells[Vector2i(int(cell.q),int(cell.r))]=cell
	wall_kinds=Sight.wall_kinds(cells)
	art_surfaces=Sight.art_surfaces(document);art_site_ids={}
	for surface in art_surfaces:art_site_ids[surface.site_id]=true
	return ""

static func _number(value:Variant) -> bool:return (value is float or value is int) and is_finite(float(value))
static func _point(value:Variant) -> bool:return value is Array and value.size()==2 and _number(value[0]) and _number(value[1])
static func v(value:Array) -> Vector2:return Vector2(float(value[0]),float(value[1]))

func center(key:Vector2i) -> Vector2:
	var radius:=float(grid.cell_width)/2
	return v(grid.origin)+Vector2(1.5*radius*key.x,sqrt(3)*radius*(key.y+key.x/2.0))

func axial(point:Vector2) -> Vector2i:
	var local:Vector2=(point-v(grid.origin))/(float(grid.cell_width)/2)
	var q:=local.x*2/3;var r:=-local.x/3+sqrt(3)*local.y/3;var s:=-q-r
	var Q:=roundi(q);var R:=roundi(r);var S:=roundi(s)
	var dq:=absf(Q-q);var dr:=absf(R-r);var ds:=absf(S-s)
	if dq>dr and dq>ds:Q=-R-S
	elif dr>ds:R=-Q-S
	return Vector2i(Q,R)

func polygon(key:Vector2i) -> PackedVector2Array:
	var points:=PackedVector2Array();var p:=center(key)
	for i in 6:points.append(p+Vector2.from_angle(i*TAU/6)*float(grid.cell_width)/2)
	return points

func cell_at(point:Vector2) -> Dictionary:return cells.get(axial(point),{})

func terrain_kind(key:Vector2i) -> String:
	return str(wall_kinds.get(key,"mountain")) if cells.get(key,{}).get("feature","")=="wall" else ""

func uses_art_boundary(cell:Dictionary) -> bool:
	if cell.get("mountain_manual_rule",false) or cell.get("mountain_ids",[]).is_empty():return false
	for id in cell.mountain_ids:
		if not art_site_ids.has(id):return false
	return true

func crosses_art(from:Vector2,to:Vector2) -> bool:
	for surface in art_surfaces:
		if surface.blocks_movement and (not Sight.visible(from,to,[surface]) or Sight.contains_surface(surface,to)):return true
	return false

func sight_occluders(from:Vector2,to:Vector2,radius:float=0) -> Array:
	var area:=Rect2(from,Vector2.ZERO).expand(to).grow(radius+float(grid.cell_width))
	var a:=axial(area.position);var b:=axial(area.end)
	var result:Array=[]
	for surface in art_surfaces:
		if surface.blocks_vision and surface._bounds.intersects(area):result.append(surface)
	for q in range(mini(a.x,b.x)-1,maxi(a.x,b.x)+2):
		var top:=axial(Vector2(center(Vector2i(q,0)).x,area.position.y)).y
		var bottom:=axial(Vector2(center(Vector2i(q,0)).x,area.end.y)).y
		for r in range(top-1,bottom+2):
			var key:=Vector2i(q,r)
			if terrain_kind(key)=="mountain" and not uses_art_boundary(cells.get(key,{})):result.append(Sight.occluder(polygon(key)))
	return result

func line_of_sight(from:Vector2,to:Vector2) -> bool:
	return Sight.visible(from,to,sight_occluders(from,to))

func visible(from:Vector2,to:Vector2) -> bool:
	return from.distance_to(to)<=float(document.vision_radius) and line_of_sight(from,to)

func blocked(point:Vector2,destroyed:Array=[]) -> bool:
	if not bounds.has_point(point):return true
	for surface in art_surfaces:
		if surface.blocks_movement and Sight.contains_surface(surface,point):return true
	var cell:=cell_at(point);var feature:=str(cell.get("feature",""))
	if feature=="wall" and uses_art_boundary(cell):feature=""
	if cell.get("control","")=="outside":return true
	if cell.get("control","")=="breakable" and edge_id(axial(point)) not in destroyed:return true
	if feature=="bridge":return false
	# Imported narrow bridge paths also cross the sampled river cells.
	if feature=="river":
		for road in roads+document.get("crossings",[]):
			if not road.get("bridge",false):continue
			for i in range(1,road.points.size()):
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point,v(road.points[i-1]),v(road.points[i])))<=float(road.width)/2:return false
	return feature in ["wall","river"] or feature=="breakable" and cell_id(axial(point)) not in destroyed

static func cell_id(key:Vector2i) -> String:return "hex_cell_%d_%d"%[key.x,key.y]
static func edge_id(key:Vector2i) -> String:return "hex_edge_%d_%d"%[key.x,key.y]

func break_control(key:Vector2i,has_monster:bool,enabled_conditions:Array=[]) -> Dictionary:
	var cell:Dictionary=cells.get(key,{})
	if cell.get("control","")!="breakable":return {"ok":false,"reason":"该格不是橙色可破坏边缘"}
	var condition:=str(cell.get("control_condition_ref","has_monster"))
	if condition in ["has_monster","cond_has_monster"] and not has_monster:return {"ok":false,"reason":"需要先持有怪物"}
	if condition not in ["","has_monster","cond_has_monster"] and condition not in enabled_conditions:return {"ok":false,"reason":"尚未满足条件："+condition}
	return {"ok":true,"id":edge_id(key),"event_id":str(cell.get("control_event_id","")),"condition_ref":condition,"layer":"control"}

func break_cell(key:Vector2i,has_monster:bool,enabled_conditions:Array=[]) -> Dictionary:
	var cell:Dictionary=cells.get(key,{})
	if cell.get("feature","")!="breakable":return {"ok":false,"reason":"该格不是可破坏通路"}
	var condition:=str(cell.get("condition_ref",""))
	if condition in ["has_monster","cond_has_monster"] and not has_monster:return {"ok":false,"reason":"需要先持有怪物"}
	if condition not in ["","has_monster","cond_has_monster"] and condition not in enabled_conditions:return {"ok":false,"reason":"尚未满足条件："+condition}
	return {"ok":true,"id":cell_id(key),"event_id":str(cell.get("event_id","")),"condition_ref":condition}

func encounter(from:Vector2,to:Vector2,latched:Array=[]) -> Dictionary:
	for site in sites:
		if site.kind!="camp" or int(site.get("difficulty",0))>=3 or not site.get("auto_trigger",false):continue
		var position:=v(site.position);var radius:=float(site.radius)
		if not line_of_sight(to,position):continue
		if site.id in latched:
			if to.distance_to(position)>radius:latched.erase(site.id)
			continue
		if from.distance_to(position)>radius and position.distance_to(Geometry2D.get_closest_point_to_segment(position,from,to))<=radius:
			latched.append(site.id);return site
	return {}
