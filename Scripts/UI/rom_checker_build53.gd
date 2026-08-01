extends Node

# BUILD 53: Android SAF picker + ContentResolver stream copy.
# The picker returns content:// URIs, which are not filesystem paths. Android
# ContentResolver opens the URI and android.os.FileUtils copies its stream into
# user://baserom.sfc before normal Godot validation and launch.

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

	file_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.use_native_dialog = false
	file_dialog.filters = PackedStringArray(["*.sfc,*.smc;Super Nintendo ROM;application/octet-stream"])

	native_picker_supported = DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	set_process(true)
	status_label.text = "SCRIPT ACTIVE. Select your legal Super Mario World ROM."
	heartbeat_label.text = "BUILD 53 ACTIVE - HEARTBEAT 0"
	last_event_label.text = "LAST: ready"
	api_label.text = "SAF=%s • AndroidRuntime=%s" % [str(native_picker_supported), str(Engine.has_singleton("AndroidRuntime"))]
	print("[BUILD53] READY native_file_dialog=", native_picker_supported, " AndroidRuntime=", Engine.has_singleton("AndroidRuntime"))

	if _saved_rom_is_valid():
		status_label.text = "Saved ROM verified. Starting the game..."
		api_label.text = "ROM: saved baserom.sfc is valid"
		call_deferred("_launch_game")


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.5:
		elapsed = 0.0
		heartbeat += 1
		heartbeat_label.text = "BUILD 53 ACTIVE - HEARTBEAT %d" % heartbeat


func _on_select_button_down() -> void:
	last_event_label.text = "LAST: SELECT ROM button_down"
	_open_picker()


func _on_select_pressed() -> void:
	if not dialog_open:
		last_event_label.text = "LAST: SELECT ROM pressed"
		_open_picker()


func _open_picker() -> void:
	if dialog_open or busy or launched:
		return
	dialog_open = true
	status_label.modulate = Color.WHITE
	status_label.text = "Opening Android file picker..."
	api_label.text = "SAF: calling DisplayServer.file_dialog_show"

	if OS.has_feature("android"):
		if not native_picker_supported:
			dialog_open = false
			_fail_import("This Android export reports no native file-dialog support.")
			return

		var filters = PackedStringArray(["*.sfc,*.smc;Super Nintendo ROM;application/octet-stream"])
		var open_error = DisplayServer.file_dialog_show(
			"Select Super Mario World ROM",
			"",
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			filters,
			Callable(self, "_on_native_picker_result")
		)
		last_event_label.text = "LAST: SAF returned %d (%s)" % [open_error, error_string(open_error)]
		api_label.text = "SAF RETURN: %d / %s" % [open_error, error_string(open_error)]
		if open_error != OK:
			dialog_open = false
			_fail_import("Android rejected the picker call: %s" % error_string(open_error))
		else:
			status_label.text = "Choose the ROM in Android's file picker."
		return

	file_dialog.popup_centered_ratio(0.95)


func _on_native_picker_result(status, selected_paths, selected_filter_index) -> void:
	dialog_open = false
	last_event_label.text = "LAST: SAF callback status=%s filter=%s" % [str(status), str(selected_filter_index)]
	if not status or selected_paths == null or selected_paths.size() == 0:
		status_label.text = "No ROM selected. Tap SELECT ROM to try again."
		api_label.text = "SAF CALLBACK: canceled or empty"
		return
	var uri = str(selected_paths[0])
	api_label.text = "SAF URI: %s" % uri.left(90)
	call_deferred("_import_selected_rom", uri)


func _on_file_selected(path: String) -> void:
	dialog_open = false
	call_deferred("_import_selected_rom", path)


func _on_file_dialog_canceled() -> void:
	dialog_open = false
	status_label.text = "Picker closed. Tap SELECT ROM to try again."
	last_event_label.text = "LAST: picker canceled"
	api_label.text = "PICKER: canceled normally"


func _import_selected_rom(path: String) -> void:
	if busy or launched:
		return
	busy = true
	select_button.disabled = true
	status_label.modulate = Color.WHITE

	if path.begins_with("content://"):
		status_label.text = "Copying Android content URI into private app storage..."
		var copy_result = _copy_android_content_uri(path)
		if not bool(copy_result.get("success", false)):
			_fail_import(str(copy_result.get("message", "Unknown Android URI copy error.")))
			return
		last_event_label.text = "LAST: ContentResolver copied %d bytes" % int(copy_result.get("bytes", 0))
		api_label.text = "ANDROID COPY: %d bytes • SDK %d" % [int(copy_result.get("bytes", 0)), int(copy_result.get("sdk", 0))]
	else:
		status_label.text = "Copying selected filesystem ROM..."
		var source = FileAccess.open(path, FileAccess.READ)
		if source == null:
			_fail_import("Could not read selected file. Error %d." % FileAccess.get_open_error())
			return
		var data = source.get_buffer(source.get_length())
		source.close()
		var destination = FileAccess.open("user://baserom.sfc", FileAccess.WRITE)
		if destination == null:
			_fail_import("Could not create the private ROM copy.")
			return
		destination.store_buffer(data)
		destination.close()

	_validate_private_rom(path)


func _copy_android_content_uri(uri_text: String) -> Dictionary:
	if not Engine.has_singleton("AndroidRuntime"):
		return {"success": false, "message": "AndroidRuntime is unavailable; ContentResolver cannot open the URI."}

	var version_class = JavaClassWrapper.wrap("android.os.Build$VERSION")
	var sdk = int(version_class.SDK_INT)
	if sdk < 29:
		return {"success": false, "message": "This URI-copy route requires Android 10 or newer. Detected SDK %d." % sdk, "sdk": sdk}

	var runtime = Engine.get_singleton("AndroidRuntime")
	var context = runtime.getApplicationContext()
	var resolver = context.getContentResolver()
	var uri_class = JavaClassWrapper.wrap("android.net.Uri")
	var uri_object = uri_class.parse(uri_text)
	var exception_message = _take_java_exception("Uri.parse")
	if not exception_message.is_empty():
		return {"success": false, "message": exception_message, "sdk": sdk}

	var input_stream = resolver.openInputStream(uri_object)
	exception_message = _take_java_exception("ContentResolver.openInputStream")
	if not exception_message.is_empty():
		return {"success": false, "message": exception_message, "sdk": sdk}
	if input_stream == null:
		return {"success": false, "message": "ContentResolver returned a null input stream.", "sdk": sdk}

	var target_path = ProjectSettings.globalize_path("user://baserom.sfc")
	if FileAccess.file_exists("user://baserom.sfc"):
		DirAccess.remove_absolute(target_path)

	var output_class = JavaClassWrapper.wrap("java.io.FileOutputStream")
	var output_stream = output_class.FileOutputStream(target_path, false)
	exception_message = _take_java_exception("FileOutputStream")
	if not exception_message.is_empty() or output_stream == null:
		input_stream.close()
		return {"success": false, "message": exception_message if not exception_message.is_empty() else "Could not create private output stream.", "sdk": sdk}

	var file_utils = JavaClassWrapper.wrap("android.os.FileUtils")
	var copied = file_utils.copy(input_stream, output_stream)
	exception_message = _take_java_exception("android.os.FileUtils.copy")

	output_stream.flush()
	var flush_exception = _take_java_exception("FileOutputStream.flush")
	output_stream.close()
	input_stream.close()

	if not exception_message.is_empty():
		return {"success": false, "message": exception_message, "sdk": sdk}
	if not flush_exception.is_empty():
		return {"success": false, "message": flush_exception, "sdk": sdk}
	if int(copied) <= 0:
		return {"success": false, "message": "Android copied zero bytes from the selected URI.", "sdk": sdk}
	return {"success": true, "bytes": int(copied), "sdk": sdk}


func _take_java_exception(stage: String) -> String:
	var exception = JavaClassWrapper.get_exception()
	if exception == null:
		return ""
	return "%s failed: %s" % [stage, str(exception)]


func _validate_private_rom(original_path: String) -> void:
	if not FileAccess.file_exists("user://baserom.sfc"):
		_fail_import("The private ROM copy was not created.")
		return

	var digest = FileAccess.get_sha256("user://baserom.sfc")
	api_label.text = "SHA-256: %s" % digest
	print("[BUILD53] private ROM sha256=", digest)
	if not _hash_is_supported(digest):
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://baserom.sfc"))
		_fail_import("ROM copied correctly, but its SHA-256 is unsupported: %s" % digest)
		return

	var settings_manager = get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		settings_manager.settings_file["rom_display_name"] = original_path.get_file()
		settings_manager.save_settings()

	status_label.text = "ROM VERIFIED AND SAVED. Starting the game..."
	last_event_label.text = "LAST: valid ROM copied through ContentResolver"
	api_label.text = "GAME: loading title screen"
	success_label.show()
	var timer = get_tree().create_timer(0.7)
	timer.timeout.connect(_launch_game)


func _fail_import(message: String) -> void:
	busy = false
	select_button.disabled = false
	status_label.modulate = Color(1.0, 0.42, 0.42, 1.0)
	status_label.text = message
	last_event_label.text = "LAST: ROM import failed"
	api_label.text = "ROM ERROR: %s" % message
	print("[BUILD53] import failed: ", message)


func _saved_rom_is_valid() -> bool:
	if not FileAccess.file_exists("user://baserom.sfc"):
		return false
	return _hash_is_supported(FileAccess.get_sha256("user://baserom.sfc"))


func _hash_is_supported(digest: String) -> bool:
	return digest in [
		"0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b",
		"5e3d55b019dd012e8db1498dda06b63ad1a304787625402b511e6d525946beaf",
		"d70c9c7716ad12c674fc7dd744736aa48d4d7b4237f58066be620fda26024872",
		"c6808e082ab343be554d07f2b3eb157c3c5134b364a2ffb3806a67f17e0992d0",
		"a6549142be41d0c9efceaaddd7010341cbac8438f612f4eda410590128a03ea5",
		"b5be1dba3012b6811a5660fbf2981cb23cdd1e48f845a42df00f0f55b19f0392",
		"5cc54b1e5c8d3c7701a5e20514145c3b36f15f26fe0a4fe6d2e43677e4b4eda9",
	]


func _launch_game() -> void:
	if launched:
		return
	launched = true
	busy = false
	select_button.disabled = true
	status_label.modulate = Color.WHITE
	status_label.text = "Loading title screen..."
	api_label.text = "GAME: change_scene_to_file"
	var change_error = get_tree().change_scene_to_file("res://Instances/UI/Menus/title_screen.tscn")
	if change_error != OK:
		launched = false
		select_button.disabled = false
		_fail_import("Could not load title screen: %s" % error_string(change_error))
