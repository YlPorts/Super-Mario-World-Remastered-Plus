extends Node
## Android/desktop port services shared by the ROM checker and settings menu.

signal rom_imported(success: bool, message: String)
signal settings_applied

const BASE_CONTENT_SIZE := Vector2i(480, 270)
const ROM_PATH := "user://baserom.sfc"
const VALID_ROM_HASHES := PackedStringArray([
	"0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b", # USA 1.0
	"5e3d55b019dd012e8db1498dda06b63ad1a304787625402b511e6d525946beaf", # USA headered
	"d70c9c7716ad12c674fc7dd744736aa48d4d7b4237f58066be620fda26024872",
	"c6808e082ab343be554d07f2b3eb157c3c5134b364a2ffb3806a67f17e0992d0", # JPN 1.0
	"a6549142be41d0c9efceaaddd7010341cbac8438f612f4eda410590128a03ea5", # JPN headered
	"b5be1dba3012b6811a5660fbf2981cb23cdd1e48f845a42df00f0f55b19f0392", # EU 1.0
	"5cc54b1e5c8d3c7701a5e20514145c3b36f15f26fe0a4fe6d2e43677e4b4eda9", # EU 1.1
])

var _file_dialog: FileDialog
var _selection_open := false
var _startup_layer: CanvasLayer
var _startup_root: Control
var _startup_status: Label
var _startup_button: Button


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_file_dialog()
	_create_startup_overlay()
	await get_tree().process_frame

	var settings_manager := get_node_or_null("/root/SettingsManager")
	if rom_is_valid():
		_hide_startup_overlay()
		if settings_manager != null:
			apply_settings(settings_manager.settings_file)
	else:
		# Keep first launch in a safe 16:9 viewport. Expanding the whole root
		# viewport exposes several legacy transition sprites that live just
		# outside the original 480x270 canvas.
		_apply_content_scaling(0)
		_show_startup_overlay("Choose your legally dumped .sfc or .smc ROM.")
		call_deferred("_open_picker_after_startup")


func _create_file_dialog() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.name = "RomFileDialog"
	_file_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.use_native_dialog = OS.has_feature("android")
	_file_dialog.mode_overrides_title = false
	_file_dialog.title = "Select your original Super Mario World ROM"
	_file_dialog.ok_button_text = "Select ROM"
	# Android's Storage Access Framework works most reliably with a broad
	# binary MIME type while extensions still limit the visible files.
	_file_dialog.filters = PackedStringArray([
		"*.sfc,*.smc;Super Nintendo ROM;application/octet-stream",
	])
	_file_dialog.file_selected.connect(_on_rom_file_selected)
	_file_dialog.canceled.connect(_on_file_dialog_canceled)
	add_child(_file_dialog)

	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if not downloads.is_empty():
		_file_dialog.current_dir = downloads


func _create_startup_overlay() -> void:
	_startup_layer = CanvasLayer.new()
	_startup_layer.name = "RomSelectionOverlay"
	_startup_layer.layer = 1000
	_startup_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_startup_layer)

	_startup_root = Control.new()
	_startup_root.name = "Root"
	_startup_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_startup_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_startup_layer.add_child(_startup_root)

	var background := ColorRect.new()
	background.color = Color(0.025, 0.055, 0.105, 1.0)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_startup_root.add_child(background)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_startup_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(370, 205)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.06, 0.10, 0.18, 0.98)
	panel_style.border_color = Color(0.72, 0.82, 1.0, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 9)
	margin.add_child(box)

	var title := Label.new()
	title.text = "SELECT SUPER MARIO WORLD ROM"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	box.add_child(title)

	var instructions := Label.new()
	instructions.text = "Use your own original .sfc or .smc dump.\nThe ROM is validated and copied to private app storage."
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	instructions.add_theme_font_size_override("font_size", 10)
	box.add_child(instructions)

	_startup_status = Label.new()
	_startup_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_startup_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_startup_status.add_theme_color_override("font_color", Color(1.0, 0.86, 0.35, 1.0))
	_startup_status.add_theme_font_size_override("font_size", 10)
	box.add_child(_startup_status)

	_startup_button = Button.new()
	_startup_button.text = "SELECT ROM"
	_startup_button.custom_minimum_size = Vector2(0, 40)
	_startup_button.add_theme_font_size_override("font_size", 15)
	_startup_button.pressed.connect(request_rom_selection)
	box.add_child(_startup_button)

	var hint := Label.new()
	hint.text = "If the picker closes, tap SELECT ROM again."
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 8)
	hint.modulate = Color(1, 1, 1, 0.72)
	box.add_child(hint)

	_startup_root.hide()


func _open_picker_after_startup() -> void:
	# Opening during the first rendered frame is rejected by some Android
	# devices. A small delay lets the Activity reach its resumed state.
	await get_tree().create_timer(0.85, true, false, true).timeout
	if not rom_is_valid() and is_instance_valid(_startup_root) and _startup_root.visible:
		request_rom_selection()


func request_rom_selection() -> void:
	if not is_instance_valid(_file_dialog):
		_show_startup_overlay("The file picker could not be created. Restart the app and try again.")
		return
	if _selection_open:
		return

	_selection_open = true
	if is_instance_valid(_startup_status):
		_startup_status.text = "Opening Android file picker..."
	call_deferred("_popup_rom_dialog")


func _popup_rom_dialog() -> void:
	if not is_instance_valid(_file_dialog):
		_selection_open = false
		return
	_file_dialog.popup_centered_clamped(Vector2i(760, 460), 0.9)
	# If Android silently refuses an automatic popup, unlock the button so a
	# user gesture can try again instead of leaving the picker permanently busy.
	await get_tree().create_timer(1.5, true, false, true).timeout
	_selection_open = false
	if is_instance_valid(_startup_status) and _startup_root.visible:
		_startup_status.text = "Choose the ROM in the system picker, or tap SELECT ROM again."


func _on_file_dialog_canceled() -> void:
	_selection_open = false
	if is_instance_valid(_startup_status) and _startup_root.visible:
		_startup_status.text = "No file selected. Tap SELECT ROM to try again."


func _on_rom_file_selected(path: String) -> void:
	_selection_open = false
	var result := import_rom(path)
	var success := bool(result.get("success", false))
	var message := str(result.get("message", "Unknown ROM error"))

	if success:
		if is_instance_valid(_startup_status):
			_startup_status.text = "ROM verified. Starting the game..."
		_hide_startup_overlay()
		var settings_manager := get_node_or_null("/root/SettingsManager")
		if settings_manager != null:
			apply_settings(settings_manager.settings_file)
	else:
		_show_startup_overlay(message)

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
			"message": "Unsupported ROM. Use an original SMW SFC/SMC dump, not All-Stars or SMA2.",
		}

	var destination := FileAcess.open(ROM_PATH, FileAccess.WRITE)
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
		"message": "ROM verified and saved as baserom.sfc. It will not be requested again.",
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
	# Never enable root-viewport expansion while the first-launch checker is
	# active. This keeps legacy transition graphics outside the visible area.
	if not rom_is_valid():
	_apply_content_scaling(0)
		return
	_apply_content_scaling(int(settings.get("android_aspect_mode", 0)))
	settings_applied.emit()


func _show_startup_overlay(message: String) -> void:
	if not is_instance_valid(_startup_root):
		return
	_apply_content_scaling(0)
	_startup_status.text = message
	_startup_root.show()
	_startup_button.grab_focus()


func _hide_startup_overlay() -> void:
	if is_instance_valid(_startup_root):
		_startup_root.hide()


func _apply_content_scaling(aspect_mode: int) -> void:
	var window := get_window()
	if window == null:
		return

	window.content_scale_size = BASE_CONTENT_SIZE
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	match aspect_mode:
		0: # Original 16:9 with letter/pillarboxing.
			window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP		1: # Real ultrawide: reveal additional horizontal game world.
			window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		2: # Fill the complete screen by stretching the image.
			window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
		_:
			window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
