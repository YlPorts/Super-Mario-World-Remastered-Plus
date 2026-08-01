extends Node
## First-launch ROM importer.
##
## This scene owns its FileDialog and ROM validation directly. It deliberately
## does not depend on PortManager, autoload registration, Script.new(), or
## DisplayServer.file_dialog_show(), because those service paths failed on some
## Android exports.

const ROM_PATH := "user://baserom.sfc"
const ROM_FILTERS := PackedStringArray([
	"*.sfc,*.smc;Super Nintendo ROM;application/octet-stream",
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

@onready var _file_dialog: FileDialog = $RomFileDialog


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_keep_touch_controls_alive()
	_configure_file_dialog()

	if verify_rom():
		proceed()
	else:
		show_rom_prompt("Choose your original Super Mario World .sfc or .smc ROM.")


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
	_set_status("Opening Android file picker...", false)
	# Deferring the popup prevents Android from rejecting it while processing the
	# same touch event that pressed SELECT ROM.
	call_deferred("_show_file_dialog")


func _show_file_dialog() -> void:
	if not is_instance_valid(_file_dialog):
		_dialog_open = false
		show_rom_prompt("BUILD 44 error: the FileDialog node is missing.", true)
		return
	_file_dialog.popup_centered_clamped(Vector2i(760, 460), 0.9)


func _on_file_dialog_canceled() -> void:
	_dialog_open = false
	show_rom_prompt("No file selected. Tap SELECT ROM to try again.")


func _on_file_selected(path: String) -> void:
	_dialog_open = false
	var result := import_rom(path)
	if bool(result.get("success", false)):
		success()
	else:
		show_rom_prompt(str(result.get("message", "Unknown ROM error.")), true)


func import_rom(source_path: String) -> Dictionary:
	if source_path.is_empty():
		return {"success": false, "message": "No file was selected."}

	# Android's native picker can return a content:// URI. Godot FileAccess can
	# read that URI directly, so it must not be converted to a filesystem path.
	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {
			"success": false,
			"message": "Android returned the file, but Godot could not read it. Try selecting it from Downloads or internal storage.",
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
	$RomPanel/Content/SelectRomButton.grab_focus()


func proceed() -> void:
	TransitionManager.transition_to_menu("res://Instances/UI/Menus/disclaimer.tscn", self)


func success() -> void:
	can_check = false
	$RomPanel.hide()
	$Success.show()
	SoundManager.play_ui_sound(SoundManager.correct)
	await get_tree().create_timer(0.8, false).timeout
	proceed()
