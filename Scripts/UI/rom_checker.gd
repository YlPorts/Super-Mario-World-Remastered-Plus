extends Node

# Compile-time references force these Android services into the exported APK.
# The previous runtime load() calls could return null after export because the
# scripts were not statically referenced by the startup scene.
const PORT_MANAGER_SCRIPT: Script = preload("res://Android/port_manager.gd")
const TOUCH_CONTROLS_SCRIPT: Script = preload("res://Android/touch_controls.gd")

var can_check := true
var _port_manager: Node


func _ready() -> void:
	_port_manager = _ensure_root_service("PortManager", PORT_MANAGER_SCRIPT)
	var touch_controls := _ensure_root_service("TouchControls", TOUCH_CONTROLS_SCRIPT)
	if touch_controls != null and touch_controls.has_method("refresh_services"):
		touch_controls.refresh_services()
	_connect_port_manager()

	if verify_rom():
		proceed()
		return

	show_rom_prompt("Choose your original Super Mario World .sfc or .smc ROM.")


func _process(_delta: float) -> void:
	if can_check and Input.is_action_just_pressed("ui_accept"):
		open_rom_picker()


func _ensure_root_service(service_name: String, service_script: Script) -> Node:
	var existing := get_node_or_null("/root/" + service_name)
	if existing != null:
		return existing

	if service_script == null:
		push_error("Android service was not compiled into the APK: " + service_name)
		return null

	var service := service_script.new() as Node
	if service == null:
		push_error("Could not create Android service: " + service_name)
		return null
	service.name = service_name
	get_tree().root.add_child(service)
	return service


func _connect_port_manager() -> void:
	if _port_manager == null:
		return
	if not _port_manager.rom_imported.is_connected(_on_rom_imported):
		_port_manager.rom_imported.connect(_on_rom_imported)


func _refresh_port_manager() -> bool:
	if is_instance_valid(_port_manager):
		return true
	_port_manager = _ensure_root_service("PortManager", PORT_MANAGER_SCRIPT)
	_connect_port_manager()
	return is_instance_valid(_port_manager)


func verify_rom() -> bool:
	return _refresh_port_manager() and _port_manager.rom_is_valid()


func open_rom_picker() -> void:
	if not can_check:
		return
	if not _refresh_port_manager():
		show_rom_prompt("The ROM service did not load. Install the newest APK build.", true)
		return
	$RomPanel/Content/Status.text = "Opening Android file picker..."
	$RomPanel/Content/Status.modulate = Color(1.0, 0.86, 0.35, 1.0)
	_port_manager.request_rom_selection()


func _on_rom_imported(import_success: bool, message: String) -> void:
	if import_success:
		success()
	else:
		show_rom_prompt(message, true)


func show_rom_prompt(message: String, is_error := false) -> void:
	$ColorRect.show()
	$RomPanel.show()
	$Success.hide()
	$RomPanel/Content/Status.text = message
	$RomPanel/Content/Status.modulate = Color(1.0, 0.45, 0.45, 1.0) if is_error else Color(1.0, 0.86, 0.35, 1.0)
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
