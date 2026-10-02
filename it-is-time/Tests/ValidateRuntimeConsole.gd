extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var console := root.get_node("RuntimeConsole")
	assert(not console.is_console_open())
	console.set_console_open(true)
	assert(console.is_console_open())
	console.set_console_open(false)
	assert(console.execute_command("unknown") == "Unknown command: unknown")
	assert(console.execute_command("trackmotion").ends_with("enabled."))
	assert(console.is_motion_tracking_enabled())
	assert(console.execute_command("trackmotion").ends_with("disabled."))
	assert(not console.is_motion_tracking_enabled())
	print("RUNTIME_LOG_DIRECTORY=%s" % console.get_runtime_log_directory())
	print("LOG_ARCHIVE_OUTPUT_DIRECTORY=%s" % console.get_archive_output_directory())

	var test_root := "res://Tests/.runtime_console_test"
	var log_root := test_root.path_join("logs")
	var output_root := test_root.path_join("output")
	assert(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(log_root)) == OK)
	var test_log_path := log_root.path_join("runtime-test.log")
	var test_log := FileAccess.open(test_log_path, FileAccess.WRITE)
	assert(test_log != null)
	test_log.store_string("runtime console archive validation\n")
	test_log.close()

	var archive_path: String = console.create_logs_archive(output_root, log_root)
	assert(not archive_path.is_empty())
	assert(FileAccess.file_exists(archive_path))
	var reader := ZIPReader.new()
	assert(reader.open(archive_path) == OK)
	var archived_files := reader.get_files()
	assert("logs/runtime-test.log" in archived_files)
	assert("archive_manifest.txt" in archived_files)
	reader.close()

	DirAccess.remove_absolute(archive_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_log_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(log_root))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(output_root))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_root))
	print("RUNTIME_CONSOLE_VALIDATION_PASSED")
	quit()
