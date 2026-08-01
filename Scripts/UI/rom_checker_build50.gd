extends Node

# BUILD 50: Android picker + ROM validation + real game launch.
# Opens the native picker after the current input event finishes, accepts both
# FileDialog signal forms, copies the legal ROM into user://, and continues to
# the disclaimer/menu scene after successful validation.

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

var status_label: Label
var heartbeat_label: Label
var last_event_label: Label
var api_label: Label
var select_button: Button
var file_dialog: FileDialog
var success_label: Label
var elapsed := 0.0
var heartbeat := 0
var dialog_open := false
var picker_pending := false
var importing := false
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
	file_dialog.use_native_dialog = OS.has_feature("android")
	file_dialog.mode_overrides_title = false
	file_dialog.title = "Select Super Mario World ROM"
	file_dialog.ok_button_text = "Select ROM"
	file_dialog.filters = ROM_FILTERS

	set_process(true)
	set_process_input(true)
	_set_status("SCRIPT ACTIVE. Select your legal Super Mario World ROM.", false)
	heartbeat_label.text = "BUILD 50 ACTIVE - HEARTBEAT 0"
	last_event_label.text = "LAST: ready"
	api_label.text = "ROM: waiting for selection"
	print("[BUILD50] ready")

	if verify_saved_rom():
		_set_status("Saved ROM verified. Starting game...", false)
		api_label.text = "ROM: existing baserom.sfc is valid"
		call_deferred("_launch_game")


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.5:
		elapsed = 0.0
		heartbeat += 1
		heartbeat_label.text = "BUILD 50 ACTIVE - HEARTBEAT %d" % heartbeat


func _input(event: InputEvent) -> void:
	if importing or launched:
		return
	if event is InputEventScreenTouch and event.pressed:
		last_event_label.text = "LAST: touch down at %s" % str(event.position)
		if select_button.get_global_rect().has_point(event.position):
			_request_picker("touch fallback")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		last_event_label.text = "LAST: mouse down at %s" % str(event.position)
		if select_button.get_global_rect().has_point(event.position):
			_request_picker("mouse fallback")


func _on_select_button_down() -> void:
	last_event_label.text = "LAST: SELECT ROM button_down"
	_request_picker("button_down")


func _on_select_pressed() -> void:
	last_event_label.text = "LAST: SELECT ROM pressed"
	_request_picker("pressed")


func _request_picker(source: String) -> void:
	if dialog_open or picker_pending or importing or launched:
		return
	picker_pending = true
	_set_status("Touch received. Preparing Android file picker...", false)
	api_label.text = "PICKER: queued from %s" % source
	call_deferred("_open_picker_after_input", source)


func _open_picker_after_input(source: String) -> void:
	# Let the touch/mouse event finish before Android starts its file activity.
	await get_tree().process_frame
	if dialog_open or importing or launched:
		picker_pending = false
		return
	picker_pending = false
	dialog_open = true
	_set_status("Android picker opened. Choose the ROM and press Select.", false)
	api_label.text = "PICKER: popup requested from %s" % source
	print("[BUILD50] opening picker from ", source)
	file_dialog.popup_centered_ratio(0.95)


func _on_file_selected(path: String) -> void:
	_receive_selected_paths(PackedStringArray([path]), "file_selected")


func _on_files_selected(paths: PackedStringArray) -> void:
	_receive_selected_paths(paths, "files_selected")


func _receive_selected_paths(paths: PackedStringArray, callback_name: String) -> void:
	dialog_open = false
	picker_pending = false
	last_event_label.text = "LAST: %s callback, paths=%d" % [callback_name, paths.size()]
	print("[BUILD50] callback ", callback_name, " paths=", paths.size())
	if paths.is_empty():
		_set_status("Android returned without a selected file. Try again.", true)
		api_label.text = "PICKER: empty callback"
		return
	_process_selected_rom(paths[0])


func _on_file_dialog_canceled() -> void:
	dialog_open = false
	picker_pending = false
	_set_status("Picker closed. Press SELECT ROM to try again.", false)
	last_event_label.text = "LAST: canceled callback"
	api_label.text = "PICKER: canceled normally"
	print("[BUILD50] picker canceled")


func _process_selected_rom(source_path: String) -> void:
	if importing or launched:
		return
	importing = true
	select_button.disabled = true
	_set_status("Reading and validating the selected ROM...", false)
	api_label.text = "ROM: opening selected file"
	last_event_label.text = "LAST: selected %s" % source_path.get_file()
	await get_tree().process_frame

	var result := import_rom(source_path)
	var message := str(result.get("message", "Unknown import result."))
	api_label.text = "ROM: %s" % message
	print("[BUILD50] import result: ", message)
	if not bool(result.get("success", false)):
		importing = false
		select_button.disabled = false
		_set_status(message, true)
		return

	_set_status("ROM VERIFIED AND SAVED. Starting the game...", false)
	last_event_label.text = "LAST: valid ROM imported"
	success_label.show()
	await get_tree().create_timer(0.7, true, false, true).timeout
	_launch_game()


func import_rom(source_path: String) -> Dictionary:
	if source_path.is_empty():
		return {"success": false, "message": "No file was selected."}

	var source := FileAccess.open(source_path, FileAccess.READ)
	if source == null:
		return {
			"success": false,
			"message": "Android selected the file, but Godot could not read it. Move it to Downloads and try again.",
		}

	var length := source.get_length()
	if length <= 0:
		source.close()
		return {"success": false, "message": "The selected file is empty."}
	var data := source.get_buffer(length)
	source.close()
	if data.is_empty():
		return {"success": false, "message": "The selected file could not be read."}

	var hash_context := HashingContext.new()
	var hash_error := hash_context.start(HashingContext.HASH_SHA256)
	if hash_error != OK:
		return {"success": false, "message": "Could not start ROM validation."}
	hash_context.update(data)
	var digest := hash_context.finish().hex_encode()
	print("[BUILD50] bytes=", data.size(), " sha256=", digest)
	if not VALID_ROM_HASHES.has(digest):
		return {
			"success": false,
			"message": "Unsupported ROM. Use an original supported Super Mario World .sfc/.smc dump.",
		}

	var destination := FileAccess.open(ROM_PATH, FileAccess.WRITE)
	if destination == null:
		return {"success": false, "message": "The ROM could not be copied to private app storage."}
	destination.store_buffer(data)
	destination.close()

	if not verify_saved_rom():
		return {"success": false, "message": "The copied ROM failed its final verification."}

	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		settings_manager.settings_file["rom_display_name"] = source_path.get_file()
		settings_manager.save_settings()

	return {"success": true, "message": "ROM verified and saved."}


func verify_saved_rom() -> bool:
	if not FileAccess.file_exists(ROM_PATH):
		return false
	return VALID_ROM_HASHES.has(FileAccess.get_sha256(ROM_PATH))


func _launch_game() -> void:
	if launched:
		return
	launched = true
	importing = false
	select_button.disabled = true
	_set_status("Loading disclaimer and main menu...", false)
	api_label.text = "GAME: transition requested"
	print("[BUILD50] launching disclaimer/menu")
	TransitionManager.transition_to_menu("res://Instances/UI/Menus/disclaimer.tscn", self)


func _set_status(message: String, is_error: bool) -> void:
	status_label.text = message
	status_label.modulate = Color(1.0, 0.42, 0.42, 1.0) if is_error else Color(1.0, 0.86, 0.35, 1.0)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_RESUMED and is_node_ready() and dialog_open:
		last_event_label.text = "LAST: returned from Android picker; waiting for callback"
		api_label.text = "PICKER: app resumed"
		print("[BUILD50] application resumed while picker open")
