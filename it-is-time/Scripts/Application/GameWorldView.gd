@tool
extends "res://Modules/PaperUI/Scripts/UI/WorldView.gd"

var summon_animation_settings: Resource = preload("res://Resources/Application/DefaultSummonAnimation.tres")
var summon_assembly: SubViewportContainer
var _summon_records: Array = []

func play_summon(records: Array) -> void:
	_summon_records = records.duplicate(true)
	erupt()

func configure(new_mode: String, id: String, units: Array) -> void:
	if new_mode != "eruption":
		running = false
		_clear_summon()
	super.configure(new_mode,id,units)

func erupt() -> void:
	_clear_summon()
	super.erupt()
	summon_assembly = preload("res://Scripts/Application/SummonAssemblyView.gd").new()
	summon_assembly.settings = summon_animation_settings
	add_child(summon_assembly)
	summon_assembly.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	summon_assembly.finished.connect(skip_eruption)
	summon_assembly.begin(_summon_records)

func set_summon_paused(value: bool) -> void:
	if is_instance_valid(summon_assembly): summon_assembly.set_paused(value)

func skip_eruption() -> void:
	if not running: return
	running = false
	_clear_summon()
	eruption_finished.emit()

func _clear_summon() -> void:
	if is_instance_valid(summon_assembly):
		summon_assembly.stop()
		summon_assembly.queue_free()
	summon_assembly = null

func _process(delta: float) -> void:
	if running and is_instance_valid(summon_assembly):
		elapsed += delta
		summon_assembly.advance(delta)

func _layout() -> void:
	hide_location_hint()
	$Backdrop.hide()
	for marker: Button in markers: marker.hide()
	if is_instance_valid(summon_book): summon_book.hide()
	queue_redraw()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO,size),Style.PAPER)

