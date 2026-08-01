extends Node

var can_check := true
var _port_manager: Node


func _ready() -> void:
	_port_manager = get_node_or_null("/root/PortManager")
	if _port_manager != null:
		_port_manager.rom_imported.connect(_on_rom_imported)

	if verify_rom():
		proceed()
		return

	show_rom_prompt("Choose your original Super Mario World .sfc or .smc ROM.")


func _process(_delta: float) -> void:
	if can_check and Input.is_action_just_pressed("ui_accept"):
		open_rom_picker()


func verify_rom() -> bool:
	return _port_manager != null and _port_manager.rom_is_valid()


func open_rom_picker() -> void:
	if not can_check:
		return
	if _port_manager == null:
		show_rom_prompt("File picker unavailable. Restart the app and try again.", true)
		return
	$RomPanel/Content/Status.text = "Opening Android file picker..."
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
