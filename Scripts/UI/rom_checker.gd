extends Node
## BUILD 48: self-contained Android touch and ROM-picker diagnostic.
##
## The previous diagnostic lived in a secondary CanvasLayer. On the test phone
## that script never reached _ready(), so this version keeps every probe inside
## the already-visible main scene script and removes all gameplay touch overlays.

const ROM_PATH := "user://baserom.sfc"
const ROM_FILTERS := PackedStringArray([
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

var can_check := true
var _dialog_open := false
var _request_generation := 0
var _heartbeat := 0
var _heartbeat_elapsed := 0.0
var _touch_count := 0
var _mouse_count := 0
var _button_down_count := 0
var _pressed_count := 0
var _last_event := "No touch or mouse event received yet."
var _api_status := "Picker API has not been called."
var _log_lines := PackedStringArray()

@onready var _file_dialog: FileDialog = $RomFileDialog
@onready var _select_button: Button = $RomPanel/Content/SelectRomButton
@onready var _status_label: Label = $RomPanel/Content/Status
@onready var _heartbeat_label: Label = $DebugPanel/DebugContent/Heartbeat
@onready var _last_event_label: Label = $DebugPanel/DebugContent/LastEvent
@onready var _api_label: Label = $DebugPanel/DebugContent/ApiStatus
@onready var _test_button: Button = $DebugPanel/DebugContent/Buttons/TestPickerButton
@onready var _copy_button: Button = $DebugPanel/DebugContent/Buttons/CopyReportButton
@onready var _clear_button: Button = $DebugPanel/DebugContent/Buttons/ClearButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	set_process_input(true)
	set_process_unhandled_input(true)
	_configure_file_dialog()
	_connect_diagnostic_signals()

	_record("READY: main rom_checker.gd started")
	_record("OS=%s android=%s" % [OS.get_name(), str(OS.has_feature("android"))])
	_record("Viewport=%s button_rect=%s" % [str(get_viewport().get_visible_rect().size), _button_rect_text()])
	_record("Native file dialog feature=%s" % str(DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)))
	_refresh_debug_labels()

	if verify_rom():
		proceed()
	else:
		show_rom_prompt("MAIN SCRIPT ACTIVE. Tap SELECT ROM; every press will appear below.")


func _connect_diagnostic_signals() -> void:
	if not _select_button.button_down.is_connected(_on_select_button_down):
		_select_button.button_down.connect(_on_select_button_down)
	if not _select_button.pressed.is_connected(_on_select_button_pressed):
		_select_button.pressed.connect(_on_select_button_pressed)
	if not _select_button.gui_input.is_connected(_on_select_button_gui_input):
		_select_button.gui_input.connect(_on_select_button_gui_input)
	if not _test_button.pressed.is_connected(_on_test_picker_pressed):
		_test_button.pressed.connect(_on_test_picker_pressed)
	if not _copy_button.pressed.is_connected(_copy_report):
		_copy_button.pressed.connect(_copy_report)
	if not _clear_button.pressed.is_connected(_clear_report):
		_clear_button.pressed.connect(_clear_report)


func _configure_file_dialog() -> void:
	_file_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.use_native_dialog = OS.has_feature("android")
	_file_dialog.mode_overrides_title = false
	_file_dialog.title = "Select Super Mario World ROM"
	_file_dialog.ok_button_text = "Select ROM"
	_file_dialog.filters = ROM_FILTERS
	if not _file_dialog.file_selected.is_connected(_on_file_selected):
		_file_dialog.file_selected.connect(_on_file_selected)
	if not _file_dialog.canceled.is_connected(_on_file_dialog_canceled):
		_file_dialog.canceled.connect(_on_file_dialog_canceled)


func _process(delta: float) -> void:
	_heartbeat_elapsed += delta
	if _heartbeat_elapsed >= 0.5:
		_heartbeat_elapsed = 0.0
		_heartbeat += 1
		_refresh_debug_labels()

	if can_check and Input.is_action_just_pressed("ui_accept"):
		_record("INPUT MAP: ui_accept")
		open_rom_picker("ui_accept")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_touch_count += 1
		_last_event = "_input SCREEN TOUCH #%d at %s" % [_touch_count, str(event.position)]
		_record(_last_event)
		_refresh_debug_labels()
		if _select_button.get_global_rect().has_point(event.position):
			_record("Touch is INSIDE SELECT ROM rect")
			open_rom_picker("_input screen touch")
		else:
			_record("Touch is outside SELECT ROM rect")
		return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_mouse_count += 1
		_last_event = "_input MOUSE LEFT #%d at %s" % [_mouse_count, str(event.position)]
		_record(_last_event)
		_refresh_debug_labels()
		if _select_button.get_global_rect().has_point(event.position):
			_record("Mouse event is INSIDE SELECT ROM rect")
			open_rom_picker("_input mouse left")


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_record("_unhandled_input also received SCREEN TOUCH at %s" % str(event.position))
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_record("_unhandled_input also received MOUSE LEFT at %s" % str(event.position))


func _on_select_button_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_last_event = "BUTTON gui_input received SCREEN TOUCH at %s" % str(event.position)
		_record(_last_event)
		_refresh_debug_labels()
		open_rom_picker("button gui_input touch")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_last_event = "BUTTON gui_input received MOUSE LEFT at %s" % str(event.position)
		_record(_last_event)
		_refresh_debug_labels()
		open_rom_picker("button gui_input mouse")


func _on_select_button_down() -> void:
	_button_down_count += 1
	_last_event = "BUTTON button_down #%d" % _button_down_count
	_record(_last_event)
	_refresh_debug_labels()
	open_rom_picker("button_down")


func _on_select_button_pressed() -> void:
	_pressed_count += 1
	_last_event = "BUTTON pressed #%d" % _pressed_count
	_record(_last_event)
	_refresh_debug_labels()
	open_rom_picker("pressed")


func _on_test_picker_pressed() -> void:
	_record("TEST PICKER button pressed")
	open_rom_picker("test picker button")


func verify_rom() -> bool:
	if not FileAccess.file_exists(ROM_PATH):
		return false
	return VALID_ROM_HASHES.has(FileAccess.get_sha256(ROM_PATH))


func open_rom_picker(source: String = "unknown") -> void:
	_record("open_rom_picker source=%s can_check=%s dialog_open=%s" % [source, str(can_check), str(_dialog_open)])
	if not can_check:
		_api_status = "Ignored: ROM checking is disabled."
		_refresh_debug_labels()
		return
	if _dialog_open:
		_api_status = "Ignored duplicate request while picker is already open."
		_refresh_debug_labels()
		return

	_dialog_open = true
	_request_generation += 1
	var generation := _request_generation
	_api_status = "Calling Android native file dialog..."
	_set_status("Touch received. Calling Android Files...", false)
	_refresh_debug_labels()
	call_deferred("_show_native_dialog", generation)


func _show_native_dialog(generation: int) -> void:
	if generation != _request_generation or not _dialog_open:
		return

	var native_supported := DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)
	_record("Native file dialog feature=%s" % str(native_supported))

	if OS.has_feature("android"):
		if not native_supported:
			_dialog_open = false
			_api_status = "ERROR: Android reports no native file-dialog feature."
			show_rom_prompt(_api_status, true)
			_refresh_debug_labels()
			return

		var callback := Callable(self, "_on_native_file_dialog_result")
		var result := DisplayServer.file_dialog_show(
			"Select Super Mario World ROM",
			"",
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			ROM_FILTERS,
			callback
		)
		_api_status = "file_dialog_show returned %s (%d)" % [error_string(result), result]
		_record(_api_status)
		_refresh_debug_labels()

		if result == OK:
			_set_status("Android accepted the request. Waiting for Files/callback...", false)
			_watch_callback_timeout(generation)
		else:
			_dialog_open = false
			show_rom_prompt("Android rejected picker: %s (%d)." % [error_string(result), result], true)
		return

	_file_dialog.use_native_dialog = false
	_api_status = "Non-Android fallback FileDialog opened."
	_record(_api_status)
	_refresh_debug_labels()
	_file_dialog.popup_centered_clamped(Vector2i(460, 250), 0.95)


func _watch_callback_timeout(generation: int) -> void:
	await get_tree().create_timer(6.0, true, false, true).timeout
	if generation == _request_generation and _dialog_open:
		_dialog_open = false
		_api_status = "TIMEOUT: API returned OK, but no callback arrived in 6 seconds."
		_record(_api_status)
		show_rom_prompt(_api_status, true)
		_refresh_debug_labels()


func _on_native_file_dialog_result(status: bool, selected_paths: PackedStringArray, selected_filter_index: int) -> void:
	_dialog_open = false
	_api_status = "CALLBACK: status=%s paths=%d filter=%d" % [str(status), selected_paths.size(), selected_filter_index]
	_record(_api_status)
	if not selected_paths.is_empty():
		_record("Callback first path=%s" % selected_paths[0])
	_refresh_debug_labels()

	if not status or selected_paths.is_empty():
		show_rom_prompt("Callback arrived, but no file was selected.")
		return
	_on_file_selected(selected_paths[0])


func _on_file_dialog_canceled() -> void:
	_dialog_open = false
	_api_status = "File dialog canceled signal received."
	_record(_api_status)
	show_rom_prompt("No file selected. Tap SELECT ROM to try again.")
	_refresh_debug_labels()


func _on_file_selected(path: String) -> void:
	_dialog_open = false
	_record("Selected path received: %s" % path)
	_set_status("Reading and validating selected ROM...", false)
	var result := import_rom(path)
	_api_status = str(result.get("message", "Unknown import result."))
	_record("Import result: %s" % _api_status)
	_refresh_debug_labels()
	if bool(result.get("success", false)):
		success()
	else:
		show_rom_prompt(_api_status, true)


func import_rom(source_path: String) -> Dictionary:
	if source_path.is_empty():
		return {"success": false, "message": "No file was selected."}

	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {
			"success": false,
			"message": "Android returned a path, but Godot could not read it. Try Downloads/internal storage.",
		}

	var data := source.get_buffer(source.get_length())
	source.close()
	if data.is_empty():
		return {"success": false, "message": "The selected file is empty."}

	var hash_context := HashingContext.new()
	var hash_error := hash_context.start(HashingContext.HASH_SHA256)
	if hash_error != OK:
		return {"success": false, "message": "Could not start ROM validation."}
	hash_context.update(data)
	var digest := hash_context.finish().hex_encode()
	_record("Selected file bytes=%d sha256=%s" % [data.size(), digest])
	if not VALID_ROM_HASHES.has(digest):
		return {
			"success": false,
			"message": "Unsupported ROM. Use an original Super Mario World .sfc/.smc dump.",
		}

	var destination := FileAccess.open(ROM_PATH, FileAccess.WRITE)
	if destination == null:
		return {"success": false, "message": "The ROM could not be copied to private app storage."}
	destination.store_buffer(data)
	destination.close()

	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		settings_manager.settings_file["rom_display_name"] = source_path.get_file()
		settings_manager.save_settings()

	return {"success": true, "message": "ROM verified and saved."}


func _record(message: String) -> void:
	var line := "%05dms | %s" % [Time.get_ticks_msec(), message]
	_log_lines.append(line)
	while _log_lines.size() > 40:
		_log_lines.remove_at(0)
	print("[ROM DIAG] ", line)


func _button_rect_text() -> String:
	var rect := _select_button.get_global_rect()
	return "pos=%s size=%s" % [str(rect.position), str(rect.size)]


func _refresh_debug_labels() -> void:
	if not is_node_ready():
		return
	_heartbeat_label.text = "MAIN ACTIVE • HEARTBEAT %d • touch=%d mouse=%d" % [_heartbeat, _touch_count, _mouse_count]
	_last_event_label.text = "LAST: %s" % _last_event
	_api_label.text = "API: %s" % _api_status


func _build_report() -> String:
	var header := PackedStringArray([
		"SMW BUILD 48 MAIN TOUCH DIAGNOSTIC",
		"OS=%s" % OS.get_name(),
		"android=%s" % str(OS.has_feature("android")),
		"viewport=%s" % str(get_viewport().get_visible_rect().size),
		"button_rect=%s" % _button_rect_text(),
		"native_dialog=%s" % str(DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE)),
		"touch_count=%d mouse_count=%d button_down=%d pressed=%d" % [_touch_count, _mouse_count, _button_down_count, _pressed_count],
		"last_event=%s" % _last_event,
		"api_status=%s" % _api_status,
		"--- LOG ---",
	])
	return "\n".join(header) + "\n" + "\n".join(_log_lines)


func _copy_report() -> void:
	DisplayServer.clipboard_set(_build_report())
	_api_status = "REPORT COPIED TO CLIPBOARD. Paste it in ChatGPT."
	_record(_api_status)
	_refresh_debug_labels()
	_set_status("Report copied. Paste it in the chat.", false)


func _clear_report() -> void:
	_log_lines.clear()
	_touch_count = 0
	_mouse_count = 0
	_button_down_count = 0
	_pressed_count = 0
	_last_event = "Counters cleared; waiting for input."
	_api_status = "Picker API has not been called since clear."
	_record("Diagnostic counters cleared")
	_refresh_debug_labels()


func _set_status(message: String, is_error: bool) -> void:
	_status_label.text = message
	_status_label.modulate = Color(1.0, 0.45, 0.45, 1.0) if is_error else Color(1.0, 0.86, 0.35, 1.0)


func show_rom_prompt(message: String, is_error: bool = false) -> void:
	$ColorRect.show()
	$RomPanel.show()
	$DebugPanel.show()
	$Success.hide()
	_set_status(message, is_error)


func proceed() -> void:
	TransitionManager.transition_to_menu("res://Instances/UI/Menus/disclaimer.tscn", self)


func success() -> void:
	can_check = false
	$RomPanel.hide()
	$DebugPanel.hide()
	$Success.show()
	SoundManager.play_ui_sound(SoundManager.correct)
	await get_tree().create_timer(0.8, false).timeout
	proceed()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready():
		_record("NOTIFICATION_APPLICATION_RESUMED")
		_last_event = "Application resumed after Android activity."
		_refresh_debug_labels()
