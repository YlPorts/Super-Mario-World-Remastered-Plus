extends Node

# BUILD 52: use DisplayServer.file_dialog_show directly on Android.
# BUILD 51 proved the UI and script worked, but FileDialog.popup_* never opened
# the Android picker on the test phone. This version calls Android's Storage
# Access Framework directly and receives a content:// URI in the callback.

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
var native_picker_supported := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	status_label = get_node("RomPanel/Content/Status")
	heartbeat_label = get_node("DebugPanel/DebugContent/Heartbeat")
	last_event_label = get_node("DebugPanel/DebugContent/LastEvent")
	api_label = get_node("DebugPanel/DebugContent/ApiStatus")
	select_button = get_node("RomPanel/Content/SelectRomButton")
	file_dialog = get_node("RomFileDialog")
	success_label = get_node("Success")

	# Desktop-only fallback. Android uses DisplayServer.file_dialog_show below.
	file_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.use_native_dialog = false
	file_dialog.filters = PackedStringArray(["*.sfc,*.smc;Super Nintendo ROM;application/octet-stream"])

	native_picker_supported = DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	set_process(true)
	status_label.text = "SCRIPT ACTIVE. Tap SELECT ROM to open Android SAF."
	heartbeat_label.text = "BUILD 52 ACTIVE - HEARTBEAT 0"
	last_event_label.text = "LAST: ready"
	api_label.text = "ANDROID SAF FEATURE: %s" % str(native_picker_supported)
	print("[BUILD52] READY native_file_dialog=", native_picker_supported)

	if _saved_rom_is_valid():
		status_label.text = "Saved ROM verified. Starting the game..."
		api_label.text = "ROM: saved baserom.sfc is valid"
		call_deferred("_launch_game")


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.5:
		elapsed = 0.0
		heartbeat += 1
		heartbeat_label.text = "BUILD 52 ACTIVE - HEARTBEAT %d" % heartbeat


func _on_select_button_down() -> void:
	last_event_label.text = "LAST: SELECT ROM button_down"
	_open_picker()


func _on_select_pressed() -> void:
	# button_down already opens it. This is a keyboard/gamepad fallback.
	if not dialog_open:
		last_event_label.text = "LAST: SELECT ROM pressed"
		_open_picker()


func _open_picker() -> void:
	if dialog_open or busy or launched:
		return
	dialog_open = true
	status_label.modulate = Color.WHITE
	status_label.text = "CALLING ANDROID STORAGE ACCESS FRAMEWORK..."
	api_label.text = "SAF: calling DisplayServer.file_dialog_show"

	if OS.has_feature("android"):
		if not native_picker_supported:
			dialog_open = false
			_show_picker_error("This Android export reports no native file-dialog support.")
			return

		var filters = PackedStringArray([
			"*.sfc,*.smc;Super Nintendo ROM;application/octet-stream",
		])
		var callback = Callable(self, "_on_native_picker_result")
		var open_error = DisplayServer.file_dialog_show(
			"Select Super Mario World ROM",
			"",
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			filters,
			callback
		)
		last_event_label.text = "LAST: native API returned %d (%s)" % [open_error, error_string(open_error)]
		api_label.text = "SAF RETURN: %d / %s" % [open_error, error_string(open_error)]
		print("[BUILD52] file_dialog_show returned ", open_error, " ", error_string(open_error))
		if open_error != OK:
			dialog_open = false
			_show_picker_error("Android rejected the native picker call: %s" % error_string(open_error))
		else:
			status_label.text = "ANDROID ACCEPTED THE PICKER REQUEST. Waiting for selection..."
		return

	# Desktop fallback used for local testing.
	file_dialog.popup_centered_ratio(0.95)


func _on_native_picker_result(status, selected_paths, selected_filter_index) -> void:
	dialog_open = false
	last_event_label.text = "LAST: SAF callback status=%s filter=%s" % [str(status), str(selected_filter_index)]
	print("[BUILD52] SAF callback status=", status, " paths=", selected_paths)
	if not status or selected_paths == null or selected_paths.size() == 0:
		status_label.text = "No ROM selected. Tap SELECT ROM to try again."
		api_label.text = "SAF CALLBACK: canceled or empty"
		return
	var uri = str(selected_paths[0])
	api_label.text = "SAF URI RECEIVED: %s" % uri.left(90)
	_receive_path(uri, "Android SAF")


func _on_file_selected(path: String) -> void:
	dialog_open = false
	_receive_path(path, "desktop FileDialog")


func _on_file_dialog_canceled() -> void:
	dialog_open = false
	status_label.text = "Picker closed. Tap SELECT ROM to try again."
	last_event_label.text = "LAST: picker canceled"
	api_label.text = "PICKER: canceled normally"


func _receive_path(path: String, callback_name: String) -> void:
	if busy or launched:
		return
	last_event_label.text = "LAST: %s returned a file" % callback_name
	api_label.text = "ROM URI/PATH: %s" % path.left(100)
	print("[BUILD52] selected: ", path)
	call_deferred("_import_selected_rom", path)


func _import_selected_rom(path: String) -> void:
	if busy or launched:
		return
	busy = true
	select_button.disabled = true
	status_label.modulate = Color.WHITE
	status_label.text = "Reading selected ROM URI..."
	api_label.text = "FILEACCESS: opening returned URI"

	var source = FileAccess.open(path, FileAccess.READ)
	if source == null:
		_fail_import("SAF returned the file, but FileAccess could not read its URI. Error %d." % FileAccess.get_open_error())
		return

	var size = source.get_length()
	var data = source.get_buffer(size)
	source.close()
	if data.size() == 0:
		_fail_import("The selected file is empty or Android returned no readable bytes.")
		return

	status_label.text = "Validating %d bytes..." % data.size()
	var context = HashingContext.new()
	var start_error = context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		_fail_import("Could not start ROM validation: %s" % error_string(start_error))
		return
	context.update(data)
	var digest = context.finish().hex_encode()
	api_label.text = "SHA-256: %s" % digest
	print("[BUILD52] bytes=", data.size(), " sha256=", digest)

	if not _hash_is_supported(digest):
		_fail_import("ROM read correctly, but its SHA-256 is unsupported: %s" % digest)
		return

	var destination = FileAccess.open("user://baserom.sfc", FileAccess.WRITE)
	if destination == null:
		_fail_import("The ROM could not be copied into private app storage.")
		return
	destination.store_buffer(data)
	destination.close()

	if not _saved_rom_is_valid():
		_fail_import("The copied ROM failed final verification.")
		return

	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		settings_manager.settings_file["rom_display_name"] = path.get_file()
		settings_manager.save_settings()

	status_label.text = "ROM VERIFIED AND SAVED. Starting the game..."
	last_event_label.text = "LAST: valid ROM imported through SAF"
	api_label.text = "GAME: loading title screen"
	success_label.show()
	print("[BUILD52] ROM verified; launching title screen")
	var timer = get_tree().create_timer(0.7)
	timer.timeout.connect(_launch_game)


func _show_picker_error(message: String) -> void:
	status_label.modulate = Color(1.0, 0.42, 0.42, 1.0)
	status_label.text = message
	api_label.text = "PICKER ERROR: %s" % message
	print("[BUILD52] picker error: ", message)


func _fail_import(message: String) -> void:
	busy = false
	select_button.disabled = false
	status_label.modulate = Color(1.0, 0.42, 0.42, 1.0)
	status_label.text = message
	last_event_label.text = "LAST: ROM import failed"
	api_label.text = "ROM ERROR: %s" % message
	print("[BUILD52] import failed: ", message)


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
	status_label.modulate = Color.WHITE
	status_label.text = "Loading title screen..."
	api_label.text = "GAME: change_scene_to_file"
	print("[BUILD52] changing to title screen")
	var change_error = get_tree().change_scene_to_file("res://Instances/UI/Menus/title_screen.tscn")
	if change_error != OK:
		launched = false
		busy = false
		select_button.disabled = false
		_fail_import("Could not load title screen: %s" % error_string(change_error))
