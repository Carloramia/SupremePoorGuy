@tool
extends Control
## Editable illustration slots. Reference examples are not generated monster appearances.
@export_enum("人形", "兽形", "蛇形") var form: String = "兽形":
	set(value):
		form = value
		_sync_reference()
		queue_redraw()
@export var tint: Color = Color("839b78"):
	set(value):
		tint = value
		queue_redraw()
var _last_artwork: Texture2D
@export_group("Reference examples (prototype only)")
@export var use_reference_examples := true
@export var human_reference: Texture2D
@export var beast_reference: Texture2D
@export var snake_reference: Texture2D

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	_sync_reference()

func _process(_delta: float) -> void:
	_sync_reference()
	var artwork := get_node_or_null("Artwork") as TextureRect
	if artwork != null and artwork.texture != _last_artwork:
		_last_artwork = artwork.texture
		queue_redraw()

func _sync_reference() -> void:
	var reference := get_node_or_null("ReferenceArt") as TextureRect
	var caption := get_node_or_null("ReferenceCaption") as Label
	var artwork := get_node_or_null("Artwork") as TextureRect
	if reference == null or caption == null:
		return
	var candidate: Texture2D = beast_reference
	if form == "人形":
		candidate = human_reference
	elif form == "蛇形":
		candidate = snake_reference
	var show_reference := use_reference_examples and candidate != null and (artwork == null or artwork.texture == null)
	if reference.texture != candidate or reference.visible != show_reference:
		reference.texture = candidate
		reference.visible = show_reference
		caption.visible = show_reference
		queue_redraw()

func _draw() -> void:
	var artwork := get_node_or_null("Artwork") as TextureRect
	if artwork != null and artwork.texture != null:
		return
	var reference := get_node_or_null("ReferenceArt") as TextureRect
	if reference != null and reference.visible and reference.texture != null:
		return
	var origin := size * Vector2(0.5, 0.56)
	var s := minf(size.x / 240.0, size.y / 180.0)
	draw_set_transform(origin, 0, Vector2.ONE*s)
	_shadow_ellipse(Vector2(0,64), Vector2(75,10), Color(0.15,0.22,0.2,0.12))
	if form == "蛇形":
		for i in range(6, -1, -1):
			var p := Vector2(i*20-60, sin(i*0.8)*13+10)
			draw_circle(p, 20-i, tint)
			draw_arc(p, 20-i, 0, TAU, 20, Color("263b3b"), 3, true)
		_head(Vector2(-75,-14), 25)
	elif form == "人形":
		_piece(PackedVector2Array([Vector2(-24,-25),Vector2(28,-25),Vector2(22,28),Vector2(-22,28)]))
		for sign_value in [-1,1]:
			_piece(PackedVector2Array([Vector2(sign_value*16,22),Vector2(sign_value*30,22),Vector2(sign_value*34,60),Vector2(sign_value*13,60)]))
			_piece(PackedVector2Array([Vector2(sign_value*24,-22),Vector2(sign_value*37,-18),Vector2(sign_value*53,18),Vector2(sign_value*37,24)]))
		_head(Vector2(0,-48), 26)
	else:
		_piece(PackedVector2Array([Vector2(-58,-28),Vector2(40,-30),Vector2(61,12),Vector2(25,31),Vector2(-60,19)]))
		for x in [-40,30]:
			_piece(PackedVector2Array([Vector2(x,15),Vector2(x+18,15),Vector2(x+12,59),Vector2(x-7,59)]))
		_piece(PackedVector2Array([Vector2(45,-13),Vector2(92,-35),Vector2(71,0)]))
		_head(Vector2(-70,-35), 28)
	for p in [Vector2(-20,0),Vector2(20,3)]:
		draw_circle(p,5,Color("bc8942"))
		draw_arc(p,5,0,TAU,12,Color("263b3b"),2,true)
	draw_set_transform(Vector2.ZERO)

func _shadow_ellipse(center: Vector2, radius: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 32:
		points.append(center + Vector2(cos(i*TAU/32),sin(i*TAU/32))*radius)
	draw_colored_polygon(points,color)

func _piece(points: PackedVector2Array) -> void:
	draw_colored_polygon(points,tint)
	var line := points.duplicate()
	line.append(points[0])
	draw_polyline(line,Color("263b3b"),4,true)

func _head(p: Vector2, radius: float) -> void:
	draw_circle(p,radius,tint.lightened(0.12))
	draw_arc(p,radius,0,TAU,24,Color("263b3b"),4,true)
	_piece(PackedVector2Array([p+Vector2(-20,-17),p+Vector2(-25,-42),p+Vector2(-2,-24)]))
	draw_circle(p+Vector2(-9,-3),5,Color("263b3b"))
	draw_line(p+Vector2(-15,13),p+Vector2(10,16),Color("263b3b"),3,true)
