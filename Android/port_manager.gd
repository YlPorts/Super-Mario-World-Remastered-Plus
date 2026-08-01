extends Node
## Android/desktop port services shared by the ROM checker and settings menu.

signal rom_imported(success: bool, message: String)
signal settings_applied

const BASE_CONTENT_SIZE := Vector2i(480, 270)
const ROM_PATH := "user://baserom.sfc"
const ROM_FILTERS := PackedStringArray([
	"*.sfc,*.smc;Super Nintendo ROM;application/octet-stream,application/x-snes-rom",
])
const VALID_ROM_HASHES := PackedStringArray([
	"0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b", # USA 1.0
	"5e3d55b019dd012e8db1498dda06b63ad1a304787625402b511e6d525946beaf", # USA headered
	"d70c9c7716ad12c674fc7dd744736aa48d4d7b4237f58066be620fda26024872",
	"c6808e082ab343be554d07f2b3eb157c3c5134b364a2ffb3806a67f17e0992d0", # JPN 1.0
	"a6549142be41d0c9efceaaddd7010341cbac8438f612f4eda410590128a03ea5", # JPN headered
	"b5be1dba3012b6811a5660fbf2981cb23cdd1e48f845a42df00f0f55b19f0392", # EU 1.0
	"5cc54b1e5c8d3c7701a5e20514145c3b36f15f26fe0a4fe6d2e43677e4b4eda9", # EU 1.1
])

var _desktop_dialog: FileDialog
var _selection_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not OS.has_feature("android"):
		_create_desktop_dialog()
	await get_tree().process_frame
	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		apply_settings(settings_manager.settings_file)
	else:
		_apply_content_scaling(0)


func _create_desktop_dialog() -> void:
	_desktop_dialog = FileDialog.new()
	_desktop_dialog.name = "RomFileDialog"
	_desktop_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_desktop_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_desktop_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_desktop_dialog.use_native_dialog = true
	_desktop_dialog.mode_overrides_title = false
	_desktop_dialog.title = "Select your original Super Mario World ROM"
	_desktop_dialog.ok_button_text = "Select ROM"
	_desktop_dialog.filters = ROM_FILTERS
	_desktop_dialog.file_selected.connect(_on_desktop_file_selected)
	_desktop_dialog.canceled.connect(_on_picker_canceled)
	add_child(_desktop_dialog)


func request_rom_selection() -> void:
	if _selection_open:
		return
	_selection_open = true

	if OS.has_feature("android"):
		var error := DisplayServer.file_dialog_show(
			"Select Super Mario World ROM",
			"",
			"",
			false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			ROM_FILTERS,
			_on_android_file_dialog_result,
		)
		if error != OK:
			_selection_open = false
			rom_imported.emit(false, "Android could not open the system file picker. Error: %s" % error_string(error))
		return

	if not is_instance_valid(_desktop_dialog):
		_selection_open = false
		rom_imported.emit(false, "The file picker is unavailable.")
		return
	_desktop_dialog.popup_centered_clamped(Vector2i(760, 460), 0.9)


func _on_android_file_dialog_result(status: bool, selected_paths: PackedStringArray, _selected_filter_index: int) -> void:
	_selection_open = false
	if not status or selected_paths.is_empty():
		rom_imported.emit(false, "No file selected. Tap SELECT ROM to try again.")
		return
	_process_selected_path(selected_paths[0])


func _on_desktop_file_selected(path: String) -> void:
	_selection_open = false
	_process_selected_path(path)


func _on_picker_canceled() -> void:
	_selection_open = false
	rom_imported.emit(false, "No file selected. Tap SELECT ROM to try again.")


func _process_selected_path(path: String) -> void:
	var result := import_rom(path)
	var success := bool(result.get("success", false))
	var message := str(result.get("message", "Unknown ROM error"))
	if success:
		var settings_manager := get_node_or_null("/root/SettingsManager")
		if settings_manager != null:
			apply_settings(settings_manager.settings_file)
	rom_imported.emit(success, message)


func import_rom(source_path: String) -> Dictionary:
	if source_path.is_empty():
		return {"success": false, "message": "No file was selected."}

	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {
			"success": false,
			"message": "Android could not read that file. Choose it again from the system picker.",
		}

	var data := source.get_buffer(source.get_length())
	source.close()
	if data.is_empty():
		return {"success": false, "message": "The selected file is empty."}

	var hash_context := HashingContext.new()
	if hash_context.start(HashingContext.HASH_SHA256) != OK:
		return {"success": false, "message": "Could not start ROM validation."}
	hash_context.update(data)
	var digest := hash_context.finish().hex_encode()
	if not VALID_ROM_HASHES.has(digest):
		return {
			"success": false,
			"message": "Unsupported ROM. Use an original SMW .sfc/.smc dump, not All-Stars or SMA2.",
		}

	var destination := FileAccess.open(ROM_PATH, FileAccess.WRITE)
	if destination == null:
		return {"success": false, "message": "The ROM could not be copied into private app storage."}
	destination.store_buffer(data)
	destination.close()

	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		settings_manager.settings_file["rom_display_name"] = source_path.get_file()
		settings_manager.save_settings()

	return {
		"success": true,
		"message": "ROM verified and saved. It will not be requested again.",
	}


func rom_is_valid() -> bool:
	if not FileAccess.file_exists(ROM_PATH):
		return false
	return VALID_ROM_HASHES.has(FileAccess.get_sha256(ROM_PATH))


func get_rom_display_name() -> String:
	if not rom_is_valid():
		return "Not selected"
	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		var saved_name := str(settings_manager.settings_file.get("rom_display_name", ""))
		if not saved_name.is_empty():
			return saved_name
	return "baserom.sfc"


func apply_settings(settings: Dictionary) -> void:
	if not rom_is_valid():
		_apply_content_scaling(0)
		settings_applied.emit()
		return
	_apply_content_scaling(int(settings.get("android_aspect_mode", 0)))
	settings_applied.emit()


func _apply_content_scaling(aspect_mode: int) -> void:
	var window := get_window()
	if window == null:
		return

	window.content_scale_size = BASE_CONTENT_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	match aspect_mode:
		0:
			window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
		1:
			window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		2:
			window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		_:
			window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
