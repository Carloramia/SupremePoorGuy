@tool
extends Control
const Style = preload("res://Scripts/UI/UIStyle.gd")
const Portrait = preload("res://Scripts/UI/MonsterPortrait.gd")
signal location_clicked(id: String, kind: String)
signal ritual_requested
signal eruption_finished
var mode := "world"
var location := "grassland"
var elapsed := 0.0
var running := false
var markers: Array[Button] = []
var team: Array = []
var summon_book: Button
var hovered_marker: Button
var location_previews: Dictionary = {}
var unavailable_events: Array = []
const DEFAULT_TAGS = {"grassland":"【草原】【干旱】","forest":"【森林】【潮湿】","desert":"【沙漠】【沙】"}
const LOCATIONS = [
	{"id":"grassland", "name":"荒原兽群", "kind":"battle", "point":Vector2(0.25,0.61)},
	{"id":"forest", "name":"蛛树守卫", "kind":"battle", "point":Vector2(0.62,0.3)},
	{"id":"desert", "name":"沙丘遗迹", "kind":"battle", "point":Vector2(0.8,0.67)},
	{"id":"traveler", "name":"旅人手记", "kind":"event", "point":Vector2(0.37,0.26)}
]

func _ready() -> void:
	$LocationHint.minimum_size_changed.connect(_position_location_hint)
	for i in LOCATIONS.size():
		var place: Dictionary = LOCATIONS[i]
		var button := get_node(["Grassland","Forest","Desert","Traveler"][i]) as Button
		button.tooltip_text = "" if place.kind == "battle" else "查看事件"
		button.pressed.connect(func(): location_clicked.emit(place.id,place.kind))
		if place.kind == "battle":
			button.mouse_entered.connect(func(): show_location_hint(place.id,button))
			button.mouse_exited.connect(hide_location_hint)
		markers.append(button)
	summon_book = %SummonBookButton
	summon_book.pressed.connect(func(): ritual_requested.emit())
	resized.connect(_layout)
	_layout()

func _layout() -> void:
	hide_location_hint()
	$Backdrop.visible = mode == "world"
	for i in markers.size():
		markers[i].visible = mode == "world" and LOCATIONS[i].id not in unavailable_events
	if is_instance_valid(summon_book):
		# The left bookmark is the single visible summoning entry.
		summon_book.visible = false
	queue_redraw()

func set_location_previews(previews: Dictionary) -> void:
	location_previews = previews.duplicate(true)

func set_unavailable_events(ids: Array) -> void:
	unavailable_events = ids.duplicate()
	_layout()

func show_location_hint(id: String, marker: Button) -> void:
	if Engine.is_editor_hint() or mode != "world" or marker.disabled or not marker.is_visible_in_tree():
		return
	var card: Control = $LocationHint
	var info: Dictionary = location_previews.get(id,{})
	for place in LOCATIONS:
		if place.id == id:
			card.get_node("%Title").text = place.name
	card.get_node("%Summary").text = "%s\n怪物种类：%s\n数量概况：%s" % [info.get("tags",DEFAULT_TAGS.get(id,"")),info.get("types","待侦察"),info.get("abundance","待侦察")]
	hovered_marker = marker
	card.show()
	card.reset_size()
	_position_location_hint.call_deferred()

func _position_location_hint() -> void:
	if not is_instance_valid(hovered_marker):
		return
	var card: Control = $LocationHint
	card.reset_size()
	var point := hovered_marker.position + Vector2(hovered_marker.size.x+8,0)
	if point.x + card.size.x > size.x-8:
		point.x = hovered_marker.position.x-card.size.x-8
	point.x = clampf(point.x,8,maxf(8,size.x-card.size.x-8))
	point.y = clampf(point.y,8,maxf(8,size.y-card.size.y-8))
	card.position = point

func hide_location_hint() -> void:
	hovered_marker = null
	var card := get_node_or_null("LocationHint") as Control
	if card:
		card.hide()

func configure(new_mode: String, id: String, units: Array) -> void:
	mode = new_mode
	location = id
	team = units
	_layout()

func erupt() -> void:
	mode = "eruption"
	elapsed = 0
	running = true
	_layout()

func skip_eruption() -> void:
	if running:
		running = false
		eruption_finished.emit()

func _process(delta: float) -> void:
	if running:
		elapsed += delta
		queue_redraw()
		if elapsed >= 2.8:
			running = false
			eruption_finished.emit()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Style.PAPER)
	# Deliberately hand-arranged backdrop; not a movement implementation.
	var green := Color("c0c6a1")
	if mode == "world":
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO,Vector2(size.x*0.6,0),size*Vector2(0.55,0.5),size*Vector2(0.15,0.85),Vector2(0,size.y)]),green)
		draw_colored_polygon(PackedVector2Array([Vector2(size.x*0.47,0),Vector2(size.x,0),size*Vector2(1,0.56),size*Vector2(0.61,0.55)]),Color("9eac8e"))
		var river := PackedVector2Array()
		for i in 33:
			var y := size.y*i/32
			river.append(Vector2(size.x*(0.48+0.08*sin(i*0.24)),y))
		draw_polyline(river,Color("819eaa"),18,true)
		for i in 13:
			var p := size*Vector2(0.56+fmod(i*0.073,0.4),0.06+fmod(i*0.047,0.35))
			_tree(p,18)
		for i in 5:
			var p := size*Vector2(0.09+i*0.07,0.12+sin(i)*0.03)
			draw_colored_polygon(PackedVector2Array([p+Vector2(-20,18),p+Vector2(0,-25),p+Vector2(25,18)]),Color("a7a28f"))
		draw_line(size*Vector2(0.43,0.53),size*Vector2(0.56,0.53),Style.INK,9,true)
	else:
		var color: Color = {"grassland":Color("b4bd95"),"forest":Color("9eaf94"),"desert":Color("ddc493")}.get(location,green)
		draw_rect(Rect2(Vector2.ZERO,size),color)
		for i in 12:
			var p := size*Vector2(fmod(0.12+i*0.117,0.93),0.1+fmod(i*0.223,0.7))
			if location == "forest":
				_tree(p,25)
			else:
				draw_arc(p,18,0,PI,12,color.darkened(0.15),2,true)
		if mode == "battle":
			draw_dashed_line(Vector2(size.x*0.5,30),Vector2(size.x*0.5,size.y-30),Style.PAPER,2,10)
			for i in 3:
				draw_circle(size*Vector2(0.76,0.3+i*0.19),22,Style.RED)
			for i in team.size():
				draw_circle(size*Vector2(0.22+(i%2)*0.12,0.26+floor(i/2.0)*0.22),20,Style.TEAL)
	if mode == "eruption":
		var center := size*Vector2(0.5,0.72)
		var t := clampf(elapsed/2.8,0,1)
		for ring in 3:
			draw_arc(center,48+ring*21+sin(elapsed*4)*4,0,TAU,64,Color(0.88,0.7,0.35,1-t*0.5),3,true)
		for i in 42:
			var phase := fmod(t+i/42.0,1.0)
			var x := sin(i*2.4+elapsed)*phase*110
			var p := center+Vector2(x,-sin(phase*PI)*size.y*0.55)
			draw_line(p,p+Vector2(3,12),Color(0.94,0.84,0.54,1-phase),3,true)
		if t < 0.5:
			var cocoon := Vector2(28,44)*sin(t*PI)
			draw_set_transform(center-Vector2(0,35),0,Vector2(1,1.5))
			draw_circle(Vector2.ZERO,cocoon.x,Style.GOLD.lightened(0.25))
			draw_set_transform(Vector2.ZERO)
		else:
			var burst := (t-0.5)*2
			for shard in 16:
				var direction := Vector2.from_angle(shard*TAU/16)
				draw_line(center+direction*burst*130,center+direction*(burst*130+14),Color(1,0.85,0.5,1-burst),3,true)
			for i in 3:
				var reveal := clampf((t-0.52-i*0.12)*5,0,1)
				if reveal > 0:
					var p := center+Vector2((i-1)*90,-reveal*130)
					draw_circle(p,18+12*reveal,Style.TEAL.lightened(i*0.12))
	# Paper edge and copper rivets belong to the same visual grammar as the UI.
	draw_rect(Rect2(Vector2(2,2),size-Vector2(4,4)),Style.GOLD,false,3)
	for p in [Vector2(12,12),Vector2(size.x-12,12),Vector2(12,size.y-12),size-Vector2(12,12)]:
		draw_circle(p,4,Style.GOLD)

func _tree(p: Vector2, radius: float) -> void:
	draw_line(p,p+Vector2(0,25),Style.INK,4,true)
	draw_colored_polygon(PackedVector2Array([p+Vector2(-radius,12),p+Vector2(0,-radius*1.6),p+Vector2(radius,12)]),Color("52745b"))
