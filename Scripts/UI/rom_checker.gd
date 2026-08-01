extends Node
## First-launch ROM importer for Android.
##
## Build 46 bypasses Godot Button activation and FileDialog.popup() on touch.
## It opens Android's Storage Access Framework automatically after startup and
## also detects touchscreen presses directly as a fallback.

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

@onready var _file_dialog: FileDialog = $RomFileDialog
@onready var _select_button: Button = $RomPanel/Content/SelectRomButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	_keep_touch_controls_alive()
	_configure_input_layers()
	_configure_file_dialog()

	if not _select_button.pressed.is_connected(open_rom_picker):
		_select_button.pressed.connect(open_rom_picker)
	if not _select_button.gui_input.is_connected(_on_select_button_gui_input):
		_select_button.gui_input.connect(_on_select_button_gui_input)

	if verify_rom():
		proceed()
	else:
		show_rom_prompt("Choose your original Super Mario World .sfc or .smc ROM.")
		call_deferred("_auto_open_after_startup")


func _auto_open_after_startup() -> void:
	# Give the Android Activity time to reach its resumed state. This route does
	# not require the SELECT ROM button to receive any touch event.
	await get_tree().create_timer(1.35, true, false, true).timeout
	if can_check and not _dialog_open and not verify_rom():
		_set_status("Opening Android Files automatically...", false)
		open_rom_picker()


func _configure_input_layers() -> void:
	$TextureRect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$ColorRect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$RomPanel.mouse_filter = Control.MOUSE_FILTER_PASS
	_select_button.mouse_filter = Control.MOUSE_FILTER_STOP
	_select_button.focus_mode = Control.FOCUS_NONE


func _keep_touch_controls_alive() -> void:
	var controls := get_node_or_null("TouchControls")
	if controls == null:
		return
	var existing := get_node_or_null("/root/TouchControls")
	if existing != null and existing != controls:
		controls.queue_free()
		return
	controls.reparent(get_tree().root)
	controls.name = "TouchControls"


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


func _input(event: InputEvent) -> void:
	if not can_check:
		return

	if event is InputEventScreenTouch and event.pressed:
		if _select_button.get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			_set_status("Touch detected. Opening Android Files...", false)
			open_rom_picker()
			return

	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _select_button.get_global_rect().has_point(event.position):
			get_viewport().set_input_as_handled()
			_set_status("Press detected. Opening Android Files...", false)
			open_rom_picker()


func _on_select_button_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_set_status("Button touch detected. Opening Android Files...", false)
		open_rom_picker()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_status("Button press detected. Opening Android Files...", false)
		open_rom_picker()


func _process(_delta: float) -> void:
	if can_check and Input.is_action_just_pressed("ui_accept"):
		open_rom_picker()


func verify_rom() -> bool:
	if not FileAccess.file_exists(ROM_PATH):
		return false
	return VALID_ROM_HASHES.has(FileAccess.get_sha256(ROM_PATH))


func open_rom_picker() -> void:
	if not can_check or _dialog_open:
		return
	_dialog_open = true
	_request_generation += 1
	var generation := _request_generation
	_set_status("Requesting Android Storage Access Framework...", false)
	call_deferred("_show_native_dialog", generation)


func _show_native_dialog(generation: int) -> void:
	if generation != _request_generation or not _dialog_open:
		return

	if OS.has_feature("android"):
		if not DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
			_dialog_open = false
			show_rom_prompt("BUILD 46: Android reports no native file-dialog support.", true)
			return

		var callback := Callable(self, "_on_native_file_dialog_result")
		var error := DisplayServer.file_dialog_show(
			"Select Super Mario World ROM",
			"",
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			ROM_FILTERS,
			callback
		)
		if error == OK:
			_set_status("Android accepted the picker request. Choose the ROM in Files.", false)
			return

		_dialog_open = false
		show_rom_prompt("Android rejected the picker request: %s (%d)." % [error_string(error), error], true)
		return

	_file_dialog.use_native_dialog = false
	_file_dialog.popup_centered_clamped(Vector2i(760, 460), 0.9)


func _on_native_file_dialog_result(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
	_dialog_open = false
	if not status or selected_paths.is_empty():
		show_rom_prompt("No file selected. Tap SELECT ROM to try again.")
		return
	_on_file_selected(selected_paths[0])


func _on_file_dialog_canceled() -> void:
	_dialog_open = false
	show_rom_prompt("No file selected. Tap SELECT ROM to try again.")


func _on_file_selected(path: String) -> void:
	_dialog_open = false
	_set_status("Reading and validating the selected ROM...", false)
	var result := import_rom(path)
	if bool(result.get("success", false)):
		success()
	else:
		show_rom_prompt(str(result.get("message", "Unknown ROM error.")), true)


func import_rom(source_path: String) -> Dictionary:
	if source_path.is_empty():
		return {"success": false, "message": "No file was selected."}

	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {
			"success": false,
			"message": "Android returned the file, but Godot could not read it. Try Downloads or internal storage.",
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
	if not VALID_ROM_HASHES.has(digest):
		return {
			"success": false,
			"message": "Unsupported ROM. Use an original Super Mario World .sfc/.smc dump, not All-Stars or SMA2.",
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

	var touch_controls := get_node_or_null("/root/TouchControls")
	if touch_controls != null and touch_controls.has_method("refresh_services"):
		touch_controls.refresh_services()

	return {"success": true, "message": "ROM verified and saved."}


func _set_status(message: String, is_error: bool) -> void:
	$RomPanel/Content/Status.text = message
	$RomPanel/Content/Status.modulate = Color(1.0, 0.45, 0.45, 1.0) if is_error else Color(1.0, 0.86, 0.35, 1.0)


func show_rom_prompt(message: String, is_error := false) -> void:
	$ColorRect.show()
	$RomPanel.show()
	$Success.hide()
	_set_status(message, is_error)


func proceed() -> void:
	TransitionManager.transition_to_menu("res://Instances/UI/Menus/disclaimer.tscn", self)


func success() -> void:
	can_check = false
	$RomPanel.hide()
	$Success.show()
	SoundManager.play_ui_sound(SoundManager.correct)
	await get_tree().create_timer(0.8, false).timeout
	proceed()
