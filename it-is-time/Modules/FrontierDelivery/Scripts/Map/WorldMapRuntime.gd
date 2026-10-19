extends RefCounted
const Catalog = preload("res://Modules/FrontierDelivery/Scripts/Map/MapCatalog.gd")
signal diagnostic_event(event: String, detail: Dictionary)
var diagnostic_logging := false
var data: Dictionary
var party_count := 0
var completed_story_ids: Array[String] = []
var busy := false
var rng := RandomNumberGenerator.new()
var hex: RefCounted
var visible_hexes := {}
var explored_hexes := {}
var _visible_origin := Vector2.INF

func _init(snapshot: Dictionary = {}) -> void:
	rng.randomize()
	data = {"version":1,"map_id":"frontier_layout","map_version":Catalog.version,"player":Catalog.world().spawn.duplicate(),"samples":[],"discovered":[],"destroyed":[],"cleared":[],"encounter_latched":[],"battle_serial":0,"active_battle":{},"pending_battle_setup":{},"battle_receipts":{},"enabled_conditions":[],"visited":[]}
	if Catalog.is_hex():
		hex=preload("res://Scripts/Application/HexWorldNavigation.gd").new(Catalog.world())
		data.explored_cells=[]
	if valid_snapshot(snapshot):
		data.merge(snapshot.duplicate(true),true)
		# Existing exploration outside a newly authored opening area remains unlocked.
		if not snapshot.has("opening_unlocked") and not _inside_opening(player()):data.opening_unlocked=true
	for id: String in data.get("explored_cells",[]): explored_hexes[id]=true
	# A reload resumes exploration at its stored position; it never fabricates a battle result.
	_record(Catalog.v(data.player),Catalog.v(data.player))

static func valid_snapshot(value: Dictionary) -> bool:
	if int(value.get("version",0)) != 1 or value.get("map_id","") != "frontier_layout":return false
	var selected: Variant = value.get("map_version","20261015")
	if not selected is String or selected not in ["20261015","20261019"]: return false
	var player = value.get("player")
	if not player is Array or player.size()!=2:return false
	for coordinate in player:
		if not (coordinate is float or coordinate is int) or not is_finite(float(coordinate)):return false
	var map := Catalog.world(selected)
	var bounds := Rect2(Catalog.v(map.bounds.position),Catalog.v(map.bounds.size))
	if not bounds.has_point(Catalog.v(player)):return false
	for key in ["samples","discovered","destroyed","cleared","encounter_latched","visited","enabled_conditions"]:
		if not value.get(key,[]) is Array:return false
	for sample in value.get("samples",[]):
		if not sample is Array or sample.size()!=4:return false
		for number in sample:
			if not (number is float or number is int) or not is_finite(float(number)):return false
	if not value.get("active_battle",{}) is Dictionary or not value.get("battle_receipts",{}) is Dictionary:return false
	for key in ["discovered","destroyed","cleared","encounter_latched","visited","enabled_conditions"]:
		for id in value.get(key,[]):
			if not id is String:return false
	var serial=value.get("battle_serial",0)
	if value.has("opening_unlocked") and not value.opening_unlocked is bool:return false
	if not (serial is int or serial is float) or not is_finite(float(serial)) or float(serial)<0:return false
	var active:Dictionary=value.get("active_battle",{})
	var setup=value.get("pending_battle_setup",{})
	if not setup is Dictionary:return false
	if not setup.is_empty():
		if not active.is_empty() or setup.get("kind","") not in ["clear","encounter"] or not setup.get("location_id") is String:return false
		var site:=Catalog.location_for_version(setup.location_id,selected)
		if site.is_empty() or site.type!="camp":return false
	if not active.is_empty():
		for key in ["request_id","location_id","battle_map_id","kind"]:
			if not active.get(key) is String or active[key].is_empty():return false
		if Catalog.location_for_version(active.location_id,selected).is_empty() or Catalog.map_data(active.battle_map_id,selected).get("kind","")!="battle" or active.kind not in ["clear","encounter","story"]:return false
		if active.kind=="story":
			if active.get("combat_mode") not in ["party","spectator"] or not active.get("event_id") is String: return false
			if active.combat_mode=="spectator":
				for key: String in ["side_a_roster","side_b_roster"]:
					if not active.get(key) is String or active[key].is_empty(): return false
			var factory = preload("res://Scripts/Application/CreatureFactory.gd")
			for key: String in (["enemy_definitions_snapshot","side_a_definitions_snapshot"] if active.combat_mode=="spectator" else ["enemy_definitions_snapshot"]):
				if not active.get(key) is Array or active[key].is_empty(): return false
				for species: Variant in active[key]:
					if not species is String or not factory.DEFINITIONS.has(species): return false
			if not active.get("enemy_anatomy",{}) is Dictionary or not factory.ANATOMY.valid(active.get("enemy_anatomy",{})): return false
		if not active.get("party_ids") is Array: return false
		if active.party_ids.is_empty() and not (active.kind=="story" and active.combat_mode=="spectator"):return false
		var seen:Array=[]
		for id in active.party_ids:
			if not id is String or id.is_empty() or id in seen:return false
			seen.append(id)
	for receipt in value.get("battle_receipts",{}).values():
		if not receipt is Dictionary or receipt.get("outcome","") not in ["victory","defeat","retreat","draw"]:return false
	if selected=="20261019":
		var explored: Variant = value.get("explored_cells",[])
		if not explored is Array or explored.size()>map.hex_cells.size(): return false
		for id: Variant in explored:
			if not id is String or not Catalog.hex_cell_keys(selected).has(id): return false
			var pieces: PackedStringArray=id.split(",")
			if pieces.size()!=2 or not pieces[0].is_valid_int() or not pieces[1].is_valid_int(): return false
	return true

func snapshot() -> Dictionary:
	return data.duplicate(true)

func restore_snapshot(value: Dictionary) -> void:
	data=value.duplicate(true)
	_visible_origin=Vector2.INF
	explored_hexes.clear()
	for id: String in data.get("explored_cells",[]): explored_hexes[id]=true

func _diagnostic(event: String, detail: Dictionary) -> void:
	if diagnostic_logging: diagnostic_event.emit(event,detail)

func player() -> Vector2:
	return Catalog.v(data.player)

func condition(id: String) -> bool:
	if id.is_empty():return true
	var rule := Catalog.catalog_entry("conditions",id)
	if rule.get("kind","") == "monster_count":return party_count >= int(rule.get("minimum",1))
	return id in data.enabled_conditions

func visibility(point: Vector2) -> String:
	var map := Catalog.world()
	if hex!=null:
		_update_hex_visibility()
		var id: String=hex.key(hex.axial(point))
		if not map.fog.enabled or (player().distance_to(point)<=float(map.fog.radius) and hex.line_of_sight(player(),point)): return "visible"
		return "explored" if explored_hexes.has(id) else "unknown"
	if not map.fog.enabled or player().distance_to(point)<=float(map.fog.radius):return "visible"
	for segment in data.samples:
		if Catalog.distance_to_segment(point,Vector2(segment[0],segment[1]),Vector2(segment[2],segment[3]))<=float(map.fog.radius):return "explored"
	var state := str(map.fog.default_state)
	for object in Catalog.objects_in_role("reveals"):
		if Catalog.shape_contains(object.region,Catalog.local_point(object,point)):state="explored"
	for stroke in map.fog.paint:
		var hit := Catalog.v(stroke.points[0]).distance_to(point)<=float(stroke.radius)
		for i in range(1,stroke.points.size()):
			hit = hit or Catalog.distance_to_segment(point,Catalog.v(stroke.points[i-1]),Catalog.v(stroke.points[i]))<=float(stroke.radius)
		if hit:
			if stroke.state=="reset":
				state=str(map.fog.default_state)
				for object in Catalog.objects_in_role("reveals"):
					if Catalog.shape_contains(object.region,Catalog.local_point(object,point)):state="explored"
			else:state=stroke.state
	return state

func known(object: Dictionary) -> bool:
	return object.type=="town" or object.get("discovery",{}).get("known",false) or object.get("discovery",{}).get("initially_visible",false)

func object_visible(object: Dictionary) -> bool:
	# Dedicated event icons disappear, but shared towns and the summon hut stay.
	if object.get("type","")!="town" and object.get("location_id","")!="summoning_hut" and object.get("event_id","") in completed_story_ids and object.get("event_links",[]).is_empty(): return false
	if not object.has("discovery"):return true
	return known(object) or (visibility(Catalog.v(object.position))!="unknown" and (not object.discovery.get("condition_ref","") or object.id in data.discovered))

func interaction_error(object: Dictionary, require_near := true) -> String:
	if busy:return "正在转场，请稍候。"
	if object.is_empty():return "地点不存在。"
	if visibility(Catalog.v(object.position))!="visible" or not object_visible(object):return "需要先探索到当前视野内。"
	if not condition(object.get("condition_ref","")):return "尚未满足地点条件。"
	for obstacle in Catalog.objects_in_role("obstacles"):
		if (obstacle.id in object.get("blocking_obstacle_ids",[]) or object.id in obstacle.get("blocked_ids",[])) and obstacle.id not in data.destroyed:return "请先清除关联路障。"
	var target := Catalog.world_point(object,Catalog.v(object.get("interaction_offset",[0,0])))
	if require_near and player().distance_to(target)>float(object.get("interaction_radius",42))+5:return "请靠近地点后交互。"
	return ""

func blocked(point: Vector2) -> bool:
	var map := Catalog.world()
	if not Rect2(Catalog.v(map.bounds.position),Catalog.v(map.bounds.size)).has_point(point):return true
	if hex!=null:
		hex.sync(data,party_count)
		return not hex.can_pass(hex.axial(point))
	if opening_locked() and not _inside_opening(point):return true
	for collider in Catalog.colliders_at(point):
		if collider.id not in data.destroyed and Catalog.collider_contains(collider,point,float(map.get("player_radius",6))):return true
	return false

func _inside_opening(point: Vector2) -> bool:
	var shape:Dictionary=Catalog.world().get("opening_area",{}).get("region",{})
	if not shape.get("enabled",false):return true
	var radius:=float(Catalog.world().get("player_radius",6))
	if not Catalog.shape_contains(shape,point):return false
	for i in 8:
		if not Catalog.shape_contains(shape,point+Vector2.from_angle(TAU*i/8)*radius):return false
	return true

func opening_locked() -> bool:
	var area:Dictionary=Catalog.world().get("opening_area",{})
	if not area.get("region",{}).get("enabled",false) or data.get("opening_unlocked",false):return false
	if condition(str(area.get("unlock_condition_ref",""))):
		if area.get("unlock_permanent",true):data.opening_unlocked=true
		if area.get("unlock_permanent",true): _diagnostic("opening_unlocked",{"condition_ref":area.get("unlock_condition_ref","")})
		return false
	return true

func _movement_blocked(point: Vector2,from: Vector2) -> bool:
	if hex!=null:
		if not Rect2(Catalog.v(Catalog.world().bounds.position),Catalog.v(Catalog.world().bounds.size)).has_point(point): return true
		return blocked(point) and hex.axial(point)!=hex.axial(from)
	if opening_locked() and not _inside_opening(point) and _inside_opening(from):return true
	var map:=Catalog.world()
	if not Rect2(Catalog.v(map.bounds.position),Catalog.v(map.bounds.size)).has_point(point):return true
	var radius:=float(map.get("player_radius",6))
	for collider in Catalog.colliders_at(point):
		if collider.id in data.destroyed:continue
		# A save made before a collider existed can walk out of that collider.
		if Catalog.collider_contains(collider,point,radius) and not Catalog.collider_contains(collider,from,radius):return true
	return false

func move_to(point: Vector2) -> Dictionary:
	if busy or not data.pending_battle_setup.is_empty():return {}
	var from := player()
	var count:=maxi(1,ceili(from.distance_to(point)/maxf(1,float(Catalog.world().get("player_radius",6))/2)))
	var last:=from
	for i in range(1,count+1):
		var step:=from.lerp(point,float(i)/count)
		if _movement_blocked(step,from):
			_diagnostic("movement_blocked",{"from":[from.x,from.y],"attempted":[point.x,point.y],"blocked_at":[step.x,step.y]})
			var high:=step
			for attempt in 8:
				var middle:Vector2=(last+high)/2
				if _movement_blocked(middle,from):high=middle
				else:last=middle
			point=last
			break
		last=step
	if from.is_equal_approx(point):return {}
	data.player=[point.x,point.y]
	_record(from,point)
	for object in Catalog.objects_in_role("encounters"):
		var rule: Dictionary = object.get("encounter",{})
		if not rule.get("enabled",false):continue
		if object.id in data.cleared:
			_encounter_suppressed(object,from,point,"camp_cleared")
			continue
		if rule.get("requires_unblocked_entry",false) and not entry_unblocked(object):
			_encounter_suppressed(object,from,point,"entry_blocked")
			continue
		var center := Catalog.v(object.position)
		var radius := float(rule.diameter)/2.0
		if object.id in data.encounter_latched:
			if point.distance_to(center)>radius:
				data.encounter_latched.erase(object.id)
				_diagnostic("encounter_exited",{"location_id":object.id,"radius":radius})
			continue
		if from.distance_to(center)>radius and Catalog.distance_to_segment(center,from,point)<=radius:
			# Roll once on entry; stay latched until actual exit, including failed rolls.
			data.encounter_latched.append(object.id)
			var roll := rng.randf()
			var triggered := roll<float(rule.probability)
			_diagnostic("encounter_roll",{"location_id":object.id,"event_id":rule.get("event_id",object.get("event_id","")),"radius":radius,"probability":rule.probability,"roll":roll,"triggered":triggered,"latched":true,"battle_map_id":rule.get("battle_map_id",object.get("battle_map_id","")),"enemy_config_id":rule.get("enemy_config_id",object.get("enemy_config_id",""))})
			if triggered:return {"location_id":object.id,"kind":"encounter"}
	return {}

func _encounter_suppressed(object: Dictionary, from: Vector2, to: Vector2, reason: String) -> void:
	if not diagnostic_logging: return
	var centre := Catalog.v(object.position)
	var radius := float(object.encounter.diameter)*0.5
	if from.distance_to(centre)>radius and Catalog.distance_to_segment(centre,from,to)<=radius:
		_diagnostic("encounter_suppressed",{"location_id":object.id,"reason":reason,"radius":radius})

func _record(from: Vector2,to: Vector2) -> void:
	if data.samples.is_empty():data.samples.append([from.x,from.y,to.x,to.y])
	elif from.distance_to(to)>0:
		var previous: Array=data.samples.back()
		var start:=Vector2(previous[0],previous[1]);var end:=Vector2(previous[2],previous[3])
		if end.is_equal_approx(from) and (end-start).normalized().dot((to-from).normalized())>.999 and start.distance_to(to)<800:
			previous[2]=to.x;previous[3]=to.y
		else:data.samples.append([from.x,from.y,to.x,to.y])
	if hex!=null: _update_hex_visibility()
	for object in Catalog.objects_in_role("discoverable"):
		if object.has("discovery") and object.id not in data.discovered and condition(object.discovery.get("condition_ref","")) and Catalog.distance_to_segment(Catalog.v(object.position),from,to)<=float(Catalog.world().fog.radius):
			if hex!=null and visibility(Catalog.v(object.position))!="visible": continue
			data.discovered.append(object.id)
			_diagnostic("location_discovered",{"location_id":object.id,"condition_ref":object.discovery.get("condition_ref","")})

func destroy_obstacle(id: String) -> bool:
	var object := Catalog.location(id)
	if hex!=null:
		hex.sync(data,party_count)
		if object.get("type")!="destructible" or id in data.destroyed or not condition(object.get("condition_ref","")) or hex.axial(player()) not in hex.obstacle_neighbors(object): return false
		data.destroyed.append(id)
		_diagnostic("obstacle_destroyed",{"location_id":id,"cells":object.get("destruction",{}).get("cells",[])})
		return true
	if object.is_empty() or object.type!="destructible" or not interaction_error(object,bool(object.get("requires_near_interaction",false))).is_empty() or player().distance_to(Catalog.v(object.position))>float(Catalog.world().fog.radius):return false
	if id not in data.destroyed:data.destroyed.append(id)
	return true

func _update_hex_visibility() -> void:
	if hex==null or player().distance_to(_visible_origin)<12: return
	_visible_origin=player()
	visible_hexes=hex.visible_cells(player(),float(Catalog.world().fog.radius))
	for id: String in visible_hexes:
		if not explored_hexes.has(id):
			explored_hexes[id]=true
			data.explored_cells.append(id)

func entry_unblocked(object: Dictionary) -> bool:
	for obstacle in Catalog.objects_in_role("obstacles"):
		if (obstacle.id in object.get("blocking_obstacle_ids",[]) or object.id in obstacle.get("blocked_ids",[])) and obstacle.id not in data.destroyed:return false
	return true

func begin_battle(id: String,kind: String,party_ids: Array) -> Dictionary:
	var object := Catalog.location(id)
	if busy or object.is_empty() or party_ids.is_empty():return {}
	if kind=="encounter" and object.get("encounter",{}).get("requires_unblocked_entry",false) and not entry_unblocked(object):return {}
	if kind!="encounter" and not interaction_error(object).is_empty():return {}
	var config: Dictionary=object.get("encounter",{}) if kind=="encounter" else object
	var map_id:=str(config.get("battle_map_id",object.get("battle_map_id","")))
	if Catalog.map_data(map_id).is_empty():return {}
	data.battle_serial+=1
	var request={"request_id":"map_%d_%d" % [Time.get_unix_time_from_system(),data.battle_serial],"location_id":id,"kind":kind,"battle_map_id":map_id,"enemy_config_id":config.get("enemy_config_id",object.get("enemy_config_id","")),"event_id":config.get("event_id",object.get("event_id","")),"deployment_id":object.get("deployment_id",""),"party_ids":party_ids.duplicate(),"return_position":data.player.duplicate(),"source_map_id":data.map_id}
	data.active_battle=request.duplicate(true)
	busy=true
	return request

func cancel_battle() -> void:
	data.active_battle={}
	busy=false

func complete_battle(result: Dictionary) -> bool:
	var request: Dictionary=data.active_battle
	if request.is_empty() or result.get("request_id","")!=request.request_id or not result.get("outcome","") in ["victory","defeat","retreat","draw"] or data.battle_receipts.has(request.request_id):return false
	if result.outcome=="draw" and not (request.kind=="story" and request.get("combat_mode")=="spectator"): return false
	if result.outcome=="victory" and (request.kind=="clear" or (request.kind=="story" and request.get("event_id")=="QST_SIDE_002_001" and request.get("clear_location_on_victory",false))) and request.location_id not in data.cleared:data.cleared.append(request.location_id)
	data.battle_receipts[request.request_id]=result.duplicate(true)
	return true
