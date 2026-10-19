extends SceneTree
## Run without --headless for actual GPU screenshots / --write-movie capture.
var lab: Node3D
var frame_index := -3
var capture_dir := "D:/Documents/gamejam/outputs/summon_vfx_preview/godot_capture"
var profiles := [[2, 3.2], [5, 3.2], [12, 3.2], [20, 3.2]]
var compare_pacing := false
var segment_frames := 240

func _initialize() -> void:
	call_deferred("setup")

func setup() -> void:
	root.content_scale_size = Vector2i(1440, 900)
	DisplayServer.window_set_size(Vector2i(1440, 900))
	lab = load("res://Scenes/Tests/SummonAssemblyLab.tscn").instantiate()
	lab.auto_play = false
	root.add_child(lab)
	if "--template" in OS.get_cmdline_user_args():
		profiles = [[lab.default_template.count, lab.default_template.height]]
		capture_dir += "/template"
	if "--pacing" in OS.get_cmdline_user_args():
		compare_pacing = true
		segment_frames = 150
		profiles = [[12, 3.2], [12, 3.2]]
		capture_dir += "/pacing"
	DirAccess.make_dir_recursive_absolute(capture_dir)
	process_frame.connect(tick)

func tick() -> void:
	frame_index += 1
	if frame_index < 0: return
	var segment: int = frame_index / segment_frames
	if segment >= profiles.size():
		quit()
		return
	var local_frame := frame_index % segment_frames
	if local_frame == 0:
		if compare_pacing:
			lab.controls.get_node("Pacing").select(segment)
			lab._pace_setting_changed(segment)
		lab.preset(profiles[segment][0], profiles[segment][1])
		lab.effect.paused = true
		print("SUMMON_PACING_CAPTURE mode=", lab._pace_label, " units=", profiles[segment][0], " duration=", lab.effect.duration)
	lab.effect.seek(float(local_frame) / 30.0)
	if local_frame == 210:
		lab._cycle_selection()
	if local_frame in [30, 75, 105, 120, 150, 180, 225]:
		await RenderingServer.frame_post_draw
		var file := "%s/profile_%d_frame_%03d.png" % [capture_dir, segment, local_frame]
		root.get_texture().get_image().save_png(file)
		print("SUMMON_CAPTURE ", file)
