extends RefCounted
const PATH := "res://Content/Maps/HexFrontier_20261019/hex_layout.json"
static var _document: Dictionary = {}
static func document() -> Dictionary:
	if _document.is_empty():
		var model:=preload("res://Modules/HexFrontier/HexMapData.gd").new()
		if model.load_layout(PATH).is_empty(): _document=model.document
	return _document
static func initial() -> Dictionary:
	return {"version":1,"layout_sha256":FileAccess.get_sha256(PATH),"player":document().spawn.duplicate(),"discovered":[],"visited":[],"destroyed":[],"cleared":[],"travel_distance":0.0,"game_day":1.0,"explored_png":""}
static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("version")!=1 or value.get("layout_sha256")!=FileAccess.get_sha256(PATH): return false
	var p: Variant=value.get("player")
	if not p is Array or p.size()!=2: return false
	for coordinate: Variant in p:
		if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)): return false
	var d:=document()
	if not Rect2(Vector2(d.bounds.position[0],d.bounds.position[1]),Vector2(d.bounds.size[0],d.bounds.size[1])).has_point(Vector2(p[0],p[1])): return false
	for key: String in ["discovered","visited","destroyed","cleared"]:
		if not preload("res://Scripts/Application/NewPlayerTasks.gd")._string_list(value.get(key)): return false
	for key: String in ["travel_distance","game_day"]:
		if not preload("res://Scripts/Events/StoryEventService.gd").number(value.get(key)): return false
	if value.has("destruction_jobs"):
		if not value.destruction_jobs is Dictionary: return false
		for id: Variant in value.destruction_jobs:
			if not id is String or not preload("res://Scripts/Events/StoryEventService.gd").number(value.destruction_jobs[id]) or float(value.destruction_jobs[id])>60: return false
	return value.get("explored_png") is String and value.explored_png.length()<8000000

static func axial(point: Vector2) -> Vector2i:
	var g: Dictionary=document().grid
	var radius: float=float(g.cell_width)/2
	var x: float=(point.x-float(g.origin[0]))/radius
	var y: float=(point.y-float(g.origin[1]))/radius
	var q:=2*x/3; var r: float=-x/3+sqrt(3)*y/3; var s: float=-q-r
	var a:=roundi(q); var b:=roundi(r); var c:=roundi(s)
	if absf(a-q)>absf(b-r) and absf(a-q)>absf(c-s): a=-b-c
	elif absf(b-r)>absf(c-s): b=-a-c
	return Vector2i(a,b)

static func rain_active(data: Dictionary) -> bool:
	var weather: Dictionary=data.get("story_weather",{})
	if weather.is_empty() or not data.has("hex_map"): return false
	var day: float=data.get("story_events",{}).get("clock",{}).get("day",1.0)
	if not weather.get("permanent",false) and day>=float(weather.get("expires_day",0)): return false
	var center:=Vector2.ZERO
	for site: Dictionary in document().sites:
		if site.id=="layout_red_altar": center=Vector2(site.position[0],site.position[1]); break
	var p: Array=data.hex_map.player
	var delta:=axial(Vector2(p[0],p[1]))-axial(center)
	return maxi(maxi(absi(delta.x),absi(delta.y)),absi(delta.x+delta.y))<=2
