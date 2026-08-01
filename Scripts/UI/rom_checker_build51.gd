extends Node

# BUILD 51 starts from the exact minimal picker structure that worked on the
# test phone. It avoids packed-array constants and Android notification names
# at script-load time, then validates, stores and launches after selection.

var status_label
var heartbeat_label
var last_event_label
var api_label
var select_button
var file_dialog
var success_label
var elapsed := 0.0
var heartbeat := 0
var dialog_open := false
var busy := false
var launched := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	status_label = get_node("RomPanel/Content/Status")
	heartbeat_label = get_node("DebugPanel/DebugContent/Heartbeat")
	last_event_label = get_node("DebugPanel/DebugContent/LastEvent")
	api_label = get_node("DebugPanel/DebugContent/ApiStatus")
	select_button = get_node("RomPanel/Content/SelectRomButton")
	file_dialog = get_node("RomFileDialog")
	success_label = get_node("Success")

	file_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.sfc,*.smc;Super Nintendo ROM"])

	if file_dialog.has_signal("files_selected"):
		var multi_callback = Callable(self, "_on_files_selected")
		if not file_dialog.is_connected("files_selected", multi_callback):
			file_dialog.connect("files_selected", multi_callback)

	set_process(true)
	set_process_input(true)
	status_label.text = "SCRIPT ACTIVE. Select your legal Super Mario World ROM."
	heartbeat_label.text = "BUILD 51 ACTIVE - HEARTBEAT 0"
	last_event_label.text = "LAST: ready"
	api_label.text = "ROM: waiting for selection"
	print("[BUILD51] READY")

	if _saved_rom_is_valid():
		status_label.text = "Saved ROM verified. Starting the game..."
		api_label.text = "ROM: saved baserom.sfc is valid"
		call_deferred("_launch_game")


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.5:
		elapsed = 0.0
		heartbeat += 1
		heartbeat_label.text = "BUILD 51 ACTIVE - HEARTBEAT %d" % heartbeat


func _input(event: InputEvent) -> void:
	if busy or launched:
		return
	if event is InputEventScreenTouch and event.pressed:
		last_event_label.text = "LAST: touch down at %s" % str(event.position)
		if select_button.get_global_rect().has_point(event.position):
			_open_picker("raw touch down")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		last_event_label.text = "LAST: mouse down at %s" % str(event.position)
		if select_button.get_global_rect().has_point(event.position):
			_open_picker("raw mouse down")


func _on_select_button_down() -> void:
	last_event_label.text = "LAST: SELECT ROM button_down received"
	_open_picker("button_down signal")


func _on_select_pressed() -> void:
	last_event_label.text = "LAST: SELECT ROM pressed received"
	_open_picker("pressed signal")


func _open_picker(source: String) -> void:
	if dialog_open or busy or launched:
		return
	dialog_open = true
	status_label.text = "TOUCH RECEIVED. Opening Android file picker..."
	api_label.text = "PICKER: popup requested from %s" % source
	print("[BUILD51] opening picker from ", source)
	file_dialog.popup_centered_ratio(0.95)


func _on_file_selected(path: String) -> void:
	_receive_path(path, "file_selected")


func _on_files_selected(paths) -> void:
	if paths == null or paths.size() == 0:
		dialog_open = false
		status_label.text = "No file was returned. Press SELECT ROM and try again."
		api_label.text = "PICKER: files_selected was empty"
		return
	_receive_path(str(paths[0]), "files_selected")


func _receive_path(path: String, callback_name: String) -> void:
	dialog_open = false
	if busy or launched:
		return
	last_event_label.text = "LAST: %s callback received" % callback_name
	api_label.text = "ROM: selected %s" % path.get_file()
	print("[BUILD51] selected path: ", path)
	call_deferred("_import_selected_rom", path)


func _on_file_dialog_canceled() -> void:
	dialog_open = false
	status_label.text = "Picker closed. Press SELECT ROM to try again."
	last_event_label.text = "LAST: canceled callback received"
	api_label.text = "PICKER: canceled normally"
	print("[BUILD51] picker canceled")


func _import_selected_rom(path: String) -> void:
	if busy or launched:
		return
	busy = true
	select_button.disabled = true
	status_label.text = "Reading and validating selected ROM..."
	api_label.text = "ROM: opening selected file"

	var source = FileAccess.open(path, FileAccess.READ)
	if source == null:
		_fail_import("Android selected the file, but Godot could not read it. Move it to Downloads and try again.")
		return

	var size = source.get_length()
	var data = source.get_buffer(size)
	source.close()
	if data.size() == 0:
		_fail_import("The selected file is empty or could not be read.")
		return

	var context = HashingContext.new()
	var start_error = context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		_fail_import("Could not start ROM validation.")
		return
	context.update(data)
	var digest = context.finish().hex_encode()
	api_label.text = "ROM: SHA-256 %s" % digest
	print("[BUILD51] bytes=", data.size(), " sha256=", digest)

	if not _hash_is_supported(digest):
		_fail_import("Unsupported ROM. Use an original supported Super Mario World .sfc/.smc dump.")
		return

	var destination = FileAccess.open("user://baserom.sfc", FileAccess.WRITE)
	if destination == null:
		_fail_import("The ROM could not be copied into private app storage.")
		return
	destination.store_buffer(data)
	destination.close()

	if not _saved_rom_is_valid():
		_fail_import("The copied ROM failed its final verification.")
		return

	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		settings_manager.settings_file["rom_display_name"] = path.get_file()
		settings_manager.save_settings()

	status_label.text = "ROM VERIFIED AND SAVED. Starting the game..."
	last_event_label.text = "LAST: valid ROM imported"
	api_label.text = "GAME: loading title screen"
	success_label.show()
	print("[BUILD51] ROM verified; launching title screen")
	var timer = get_tree().create_timer(0.7)
	timer.timeout.connect(_launch_game)


func _fail_import(message: String) -> void:
	busy = false
	select_button.disabled = false
	status_label.text = message
	status_label.modulate = Color(1.0, 0.42, 0.42, 1.0)
	last_event_label.text = "LAST: ROM import failed"
	api_label.text = "ROM ERROR: %s" % message
	print("[BUILD51] import failed: ", message)


func _saved_rom_is_valid() -> bool:
	if not FileAccess.file_exists("user://baserom.sfc"):
		return false
	return _hash_is_supported(FileAccess.get_sha256("user://baserom.sfc"))


func _hash_is_supported(digest: String) -> bool:
	if digest == "0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b":
		return true
	if digest == "5e3d55b019dd012e8db1498dda06b63ad1a304787625402b511e6d525946beaf":
		return true
	if digest == "d70c9c7716ad12c674fc7dd744736aa48d4d7b4237f58066be620fda26024872":
		return true
	if digest == "c6808e082ab343be554d07f2b3eb157c3c5134b364a2ffb3806a67f17e0992d0":
		return true
	if digest == "a6549142be41d0c9efceaaddd7010341cbac8438f612f4eda410590128a03ea5":
		return true
	if digest == "b5be1dba3012b6811a5660fbf2981cb23cdd1e48f845a42df00f0f55b19f0392":
		return true
	if digest == "5cc54b1e5c8d3c7701a5e20514145c3b36f15f26fe0a4fe6d2e43677e4b4eda9":
		return true
	return false


func _launch_game() -> void:
	if launched:
		return
	launched = true
	busy = false
	select_button.disabled = true
	status_label.text = "Loading title screen..."
	api_label.text = "GAME: change_scene_to_file"
	print("[BUILD51] changing to title screen")
	var change_error = get_tree().change_scene_to_file("res://Instances/UI/Menus/title_screen.tscn")
	if change_error != OK:
		launched = false
		busy = false
		select_button.disabled = false
		_fail_import("Could not load the title screen: %s" % error_string(change_error))
