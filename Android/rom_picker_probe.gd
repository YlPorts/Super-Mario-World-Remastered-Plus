extends CanvasLayer
## Runtime probe for Android ROM-picker failures.
##
## This script is intentionally independent from rom_checker.gd. It records
## touchscreen delivery, Button signals, DisplayServer feature flags, the return
## value from file_dialog_show(), and any callback from Android. The report is
## shown on screen, saved to user://rom_picker_debug.txt, and can be copied.

const LOG_PATH := "user://rom_picker_debug.txt"
const ROM_PATH := "user://baserom.sfc"
const FILTERS := PackedStringArray([
	"*.sfc,*.smc;Super Nintendo ROM;application/octet-stream,application/x-snes-rom",
])
const VALID_ROM_HASHES := PackedStringArray([
	"0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b",
	"5e3d55b019dd012e8db1498dda06b63ad1a304787625402b511e6d525946beaf",
	"d70c9c7716ad12c674fc7dd744736aa48d4d7b4237f58066be620fda26024872",
	"c6808e082ab343be554d07f2b3eb157c3c5134b364a2ffb3806a67f17e0992d0",
	"a6549142be41d0c9efceaaddd7010341cbac8438f612f4eda410590128a03ea5",
	"b5be1dba3012b6811a5660fbf2981cb23cdd1e48f845a42df00f0f55b19f0392",
	"5cc54b1e5c8d3c7701a5e20514145c3b36f15f26fe0a4fe6d2e43677e4b4eda9",
])

var _lines: Array[String] = []
var _select_button: Button
var _main_status: Label
var _main_hint: Label
var _debug_text: Label
var _request_in_flight := false
var _request_number := 0
var _callback_received := false
var _ready_time_ms := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 2000
	set_process_input(true)
	set_process_unhandled_input(true)
	_ready_time_ms = Time.get_ticks_msec()
	_build_debug_panel()
	call_deferred("_initialize_probe")


func _initialize_probe() -> void:
	_select_button = get_node_or_null("../RomPanel/Content/SelectRomButton") as Button
	_main_status = get_node_or_null("../RomPanel/Content/Status") as Label
	_main_hint = get_node_or_null("../RomPanel/Content/Hint") as Label

	_clear_log_file()
	_log("PROBE_READY build=47")
	_log("datetime=" + Time.get_datetime_string_from_system())
	_log("godot=" + str(Engine.get_version_info()))
	_log("os=" + OS.get_name() + " version=" + OS.get_version())
	_log("model=" + OS.get_model_name())
	_log("display_server=" + DisplayServer.get_name())
	_log("android_feature=" + str(OS.has_feature("android")))
	_log("touchscreen_available=" + str(DisplayServer.is_touchscreen_available()))
	_log("feature_touch=" + str(DisplayServer.has_feature(DisplayServer.FEATURE_TOUCHSCREEN)))
	_log("feature_native_file=" + str(DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)))
	_log("feature_native_mime=" + str(DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE_MIME)))
	_log("granted_permissions=" + str(OS.get_granted_permissions()))
	_log("log_path=" + ProjectSettings.globalize_path(LOG_PATH))

	if is_instance_valid(_select_button):
		_log("select_button=FOUND rect=" + str(_select_button.get_global_rect()))
		_connect_button_signals()
	else:
		_log("select_button=MISSING")

	if is_instance_valid(_main_hint):
		_main_hint.text = "BUILD 47 DIAGNOSTIC • Touch + API return + callback log"
	_set_main_status("DIAG READY. Tap SELECT ROM, then copy the report.", false)


func _connect_button_signals() -> void:
	if not _select_button.button_down.is_connected(_on_button_down):
		_select_button.button_down.connect(_on_button_down)
	if not _select_button.pressed.is_connected(_on_button_pressed):
		_select_button.pressed.connect(_on_button_pressed)
	if not _select_button.gui_input.is_connected(_on_button_gui_input):
		_select_button.gui_input.connect(_on_button_gui_input)


func _build_debug_panel() -> void:
	var root := Control.new()
	root.name = "ProbeOverlay"
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var panel := PanelContainer.new()
	panel.name = "DebugPanel"
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.anchor_left = 0.015
	panel.anchor_top = 0.705
	panel.anchor_right = 0.985
	panel.anchor_bottom = 0.985
	panel.offset_left = 0.0
	panel.offset_top = 0.0
	panel.offset_right = 0.0
	panel.offset_bottom = 0.0
	root.add_child(panel)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.015, 0.02, 0.035, 0.97)
	style.border_color = Color(1.0, 0.55, 0.2, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(7)
	panel.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	panel.add_child(box)

	_debug_text = Label.new()
	_debug_text.name = "DebugText"
	_debug_text.text = "Starting diagnostic probe..."
	_debug_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_debug_text.clip_text = true
	_debug_text.custom_minimum_size = Vector2(0, 43)
	_debug_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_debug_text.add_theme_font_size_override("font_size", 7)
	_debug_text.add_theme_color_override("font_color", Color(1.0, 0.82, 0.48, 1.0))
	_debug_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_debug_text)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	box.add_child(buttons)

	var test_button := Button.new()
	test_button.text = "TEST PICKER"
	test_button.focus_mode = Control.FOCUS_NONE
	test_button.process_mode = Node.PROCESS_MODE_ALWAYS
	test_button.custom_minimum_size = Vector2(100, 24)
	test_button.add_theme_font_size_override("font_size", 8)
	test_button.pressed.connect(_request_picker.bind("diagnostic_button"))
	buttons.add_child(test_button)

	var copy_button := Button.new()
	copy_button.text = "COPY REPORT"
	copy_button.focus_mode = Control.FOCUS_NONE
	copy_button.process_mode = Node.PROCESS_MODE_ALWAYS
	copy_button.custom_minimum_size = Vector2(100, 24)
	copy_button.add_theme_font_size_override("font_size", 8)
	copy_button.pressed.connect(_copy_report)
	buttons.add_child(copy_button)

	var clear_button := Button.new()
	clear_button.text = "CLEAR"
	clear_button.focus_mode = Control.FOCUS_NONE
	clear_button.process_mode = Node.PROCESS_MODE_ALWAYS
	clear_button.custom_minimum_size = Vector2(70, 24)
	clear_button.add_theme_font_size_override("font_size", 8)
	clear_button.pressed.connect(_clear_visible_log)
	buttons.add_child(clear_button)


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_log("INPUT touch pressed=" + str(event.pressed) + " index=" + str(event.index) + " pos=" + str(event.position))
		if event.pressed and _button_contains(event.position):
			_log("INPUT touch HIT select button")
			get_viewport().set_input_as_handled()
			_request_picker("global_screen_touch")
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_log("INPUT mouse pressed=" + str(event.pressed) + " pos=" + str(event.position))
		if event.pressed and _button_contains(event.position):
			_log("INPUT mouse HIT select button")
			get_viewport().set_input_as_handled()
			_request_picker("global_mouse")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_log("UNHANDLED touch pos=" + str(event.position))
	elif event is InputEventMouseButton and event.pressed:
		_log("UNHANDLED mouse pos=" + str(event.position))


func _button_contains(position: Vector2) -> bool:
	return is_instance_valid(_select_button) and _select_button.get_global_rect().has_point(position)


func _on_button_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_log("BUTTON gui_input touch pressed=" + str(event.pressed) + " pos=" + str(event.position))
	elif event is InputEventMouseButton:
		_log("BUTTON gui_input mouse pressed=" + str(event.pressed) + " pos=" + str(event.position))


func _on_button_down() -> void:
	_log("BUTTON signal=button_down")
	_request_picker("button_down_signal")


func _on_button_pressed() -> void:
	_log("BUTTON signal=pressed")
	_request_picker("pressed_signal")


func _request_picker(source: String) -> void:
	_log("REQUEST source=" + source + " in_flight=" + str(_request_in_flight))
	if _request_in_flight:
		return

	_request_in_flight = true
	_callback_received = false
	_request_number += 1
	var request_id := _request_number
	_set_main_status("Touch received. Calling Android file-dialog API...", false)

	var feature_file := DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	var feature_mime := DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE_MIME)
	_log("REQUEST#" + str(request_id) + " feature_native_file=" + str(feature_file) + " mime=" + str(feature_mime))

	var result: Error = DisplayServer.file_dialog_show(
		"Select Super Mario World ROM",
		"",
		"",
		false,
		DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
		FILTERS,
		_on_native_dialog_result
	)
	_log("REQUEST#" + str(request_id) + " file_dialog_show_return=" + str(int(result)) + " (" + _error_name(result) + ")")

	if result != OK:
		_request_in_flight = false
		_set_main_status("API ERROR " + str(int(result)) + ": " + _error_name(result) + ". Copy report.", true)
		return

	_set_main_status("API returned OK. Waiting for Android callback...", false)
	_watch_callback_timeout(request_id)


func _watch_callback_timeout(request_id: int) -> void:
	await get_tree().create_timer(6.0, true, false, true).timeout
	if request_id != _request_number or _callback_received:
		return
	_log("REQUEST#" + str(request_id) + " CALLBACK_TIMEOUT after 6 seconds")
	_request_in_flight = false
	_set_main_status("API returned OK, but Android sent no callback. Copy report.", true)


func _on_native_dialog_result(status: bool, selected_paths: PackedStringArray, selected_filter_index: int) -> void:
	_callback_received = true
	_request_in_flight = false
	_log("CALLBACK status=" + str(status) + " paths=" + str(selected_paths) + " filter=" + str(selected_filter_index))

	if not status or selected_paths.is_empty():
		_set_main_status("Android callback arrived, but no file was selected.", true)
		return

	_set_main_status("Android callback OK. Reading selected ROM...", false)
	var import_result := _import_rom(selected_paths[0])
	_log("IMPORT result=" + str(import_result))
	if bool(import_result.get("success", false)):
		_set_main_status("ROM verified and saved. Restart the app.", false)
	else:
		_set_main_status(str(import_result.get("message", "ROM import failed.")), true)


func _import_rom(source_path: String) -> Dictionary:
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {"success": false, "message": "FileAccess.open failed for the Android URI/path."}
	var data := source.get_buffer(source.get_length())
	source.close()
	if data.is_empty():
		return {"success": false, "message": "The selected file is empty."}

	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return {"success": false, "message": "SHA-256 validation could not start."}
	context.update(data)
	var digest := context.finish().hex_encode()
	_log("IMPORT bytes=" + str(data.size()) + " sha256=" + digest)
	if not VALID_ROM_HASHES.has(digest):
		return {"success": false, "message": "The file opened, but its ROM hash is unsupported."}

	var destination := FileAccess.open(ROM_PATH, FileAccess.WRITE)
	if destination == null:
		return {"success": false, "message": "Could not write user://baserom.sfc."}
	destination.store_buffer(data)
	destination.close()
	return {"success": true, "message": "ROM imported."}


func _error_name(code: int) -> String:
	match code:
		OK:
			return "OK"
		FAILED:
			return "FAILED"
		ERR_UNAVAILABLE:
			return "ERR_UNAVAILABLE"
		ERR_UNCONFIGURED:
			return "ERR_UNCONFIGURED"
		ERR_UNAUTHORIZED:
			return "ERR_UNAUTHORIZED"
		ERR_PARAMETER_RANGE_ERROR:
			return "ERR_PARAMETER_RANGE_ERROR"
		_:
			return "ERROR_CODE_" + str(code)


func _set_main_status(message: String, is_error: bool) -> void:
	if is_instance_valid(_main_status):
		_main_status.text = message
		_main_status.modulate = Color(1.0, 0.42, 0.35, 1.0) if is_error else Color(1.0, 0.86, 0.35, 1.0)


func _log(message: String) -> void:
	var elapsed := Time.get_ticks_msec() - _ready_time_ms
	var line := "%06dms  %s" % [elapsed, message]
	_lines.append(line)
	while _lines.size() > 80:
		_lines.pop_front()
	print("ROM_PICKER_PROBE: " + line)
	_append_log_file(line)
	_refresh_debug_text()


func _refresh_debug_text() -> void:
	if not is_instance_valid(_debug_text):
		return
	var first := maxi(0, _lines.size() - 6)
	var recent := PackedStringArray()
	for index in range(first, _lines.size()):
		recent.append(_lines[index])
	_debug_text.text = "\n".join(recent)


func _clear_log_file() -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string("")
		file.close()


func _append_log_file(line: String) -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(line)
	file.close()


func _copy_report() -> void:
	var report := "\n".join(PackedStringArray(_lines))
	DisplayServer.clipboard_set(report)
	_log("REPORT copied_to_clipboard chars=" + str(report.length()))
	_set_main_status("Diagnostic report copied. Paste it in ChatGPT.", false)


func _clear_visible_log() -> void:
	_lines.clear()
	_clear_log_file()
	_log("LOG_CLEARED")
