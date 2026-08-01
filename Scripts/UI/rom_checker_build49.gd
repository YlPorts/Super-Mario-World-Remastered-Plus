extends Node

# BUILD 49: minimal ROM picker test.
# This script deliberately avoids the previous native DisplayServer probe and
# opens Godot's FileDialog as soon as the button receives button_down.

var status_label
var heartbeat_label
var last_event_label
var api_label
var select_button
var file_dialog
var elapsed := 0.0
var heartbeat := 0
var dialog_open := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	status_label = get_node("RomPanel/Content/Status")
	heartbeat_label = get_node("DebugPanel/DebugContent/Heartbeat")
	last_event_label = get_node("DebugPanel/DebugContent/LastEvent")
	api_label = get_node("DebugPanel/DebugContent/ApiStatus")
	select_button = get_node("RomPanel/Content/SelectRomButton")
	file_dialog = get_node("RomFileDialog")

	file_dialog.process_mode = Node.PROCESS_MODE_ALWAYS
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.use_native_dialog = true
	file_dialog.filters = PackedStringArray(["*.sfc,*.smc;Super Nintendo ROM"])

	set_process(true)
	set_process_input(true)
	status_label.text = "SCRIPT ACTIVE. Press SELECT ROM; it opens before finger release."
	heartbeat_label.text = "BUILD 49 SCRIPT ACTIVE - HEARTBEAT 0"
	last_event_label.text = "LAST: ready"
	api_label.text = "PICKER: native Godot FileDialog ready"
	print("[BUILD49] rom_checker_build49.gd READY")


func _process(delta: float) -> void:
	elapsed += delta
	if elapsed >= 0.5:
		elapsed = 0.0
		heartbeat += 1
		heartbeat_label.text = "BUILD 49 SCRIPT ACTIVE - HEARTBEAT %d" % heartbeat


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		last_event_label.text = "LAST: raw touch down at %s" % str(event.position)
		if select_button.get_global_rect().has_point(event.position):
			_open_picker("raw touch down")
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		last_event_label.text = "LAST: raw mouse down at %s" % str(event.position)
		if select_button.get_global_rect().has_point(event.position):
			_open_picker("raw mouse down")


func _on_select_button_down() -> void:
	last_event_label.text = "LAST: SELECT ROM button_down received"
	_open_picker("button_down signal")


func _on_select_pressed() -> void:
	last_event_label.text = "LAST: SELECT ROM pressed received"
	_open_picker("pressed signal")


func _open_picker(source: String) -> void:
	if dialog_open:
		return
	dialog_open = true
	status_label.text = "TOUCH RECEIVED. Opening Android file picker..."
	api_label.text = "PICKER: popup requested from %s" % source
	print("[BUILD49] opening picker from ", source)
	file_dialog.popup_centered_ratio(0.95)


func _on_file_selected(path: String) -> void:
	dialog_open = false
	status_label.text = "FILE SELECTED: %s" % path.get_file()
	last_event_label.text = "LAST: file_selected callback received"
	api_label.text = "PICKER: callback OK"
	print("[BUILD49] selected: ", path)


func _on_file_dialog_canceled() -> void:
	dialog_open = false
	status_label.text = "Picker closed. Press SELECT ROM to try again."
	last_event_label.text = "LAST: canceled callback received"
	api_label.text = "PICKER: canceled normally"
	print("[BUILD49] picker canceled")
