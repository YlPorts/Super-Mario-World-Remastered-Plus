extends Node

# PortManager and TouchControls are instantiated directly by rom_checker.tscn.
# This avoids Script.new()/load() on Android, which produced a null service on
# some exported APKs even though the scripts were present in the PCK.
var can_check := true
var _port_manager: Node


func _ready() -> void:
	_port_manager = _adopt_scene_service("PortManager", "PortManager")
	var touch_controls := _adopt_scene_service("TouchControls", "TouchControls")

	if touch_controls != null and touch_controls.has_method("refresh_services"):
		touch_controls.refresh_services()
	_connect_port_manager()

	if not _port_manager_is_ready():
		show_rom_prompt("Build 43 error: PortManager scene node did not initialize.", true)
		return

	if verify_rom():
		proceed()
		return

	show_rom_prompt("Choose your original Super Mario World .sfc or .smc ROM.")


func _process(_delta: float) -> void:
	if can_check and Input.is_action_just_pressed("ui_accept"):
		open_rom_picker()


func _adopt_scene_service(child_name: String, root_name: String) -> Node:
	var existing := get_node_or_null("/root/" + root_name)
	var scene_service := get_node_or_null(child_name)

	# A service created by an older path may already exist. Keep it and remove
	# the duplicate scene node safely.
	if existing != null:
		if scene_service != null and scene_service != existing:
			scene_service.queue_free()
		return existing

	if scene_service == null:
		push_error("Missing scene service node: " + child_name)
		return null

	# Move the already-instantiated node outside this temporary checker scene so
	# it survives the transition to the disclaimer/menu/game scenes.
	scene_service.reparent(get_tree().root)
	scene_service.name = root_name
	return scene_service


func _port_manager_is_ready() -> bool:
	return (
		is_instance_valid(_port_manager)
		and _port_manager.has_method("rom_is_valid")
		and _port_manager.has_method("request_rom_selection")
		and _port_manager.has_signal("rom_imported")
	)


func _connect_port_manager() -> void:
	if not _port_manager_is_ready():
		return
	var callback := Callable(self, "_on_rom_imported")
	if not _port_manager.is_connected("rom_imported", callback):
		_port_manager.connect("rom_imported", callback)


func _refresh_port_manager() -> bool:
	if _port_manager_is_ready():
		return true
	_port_manager = get_node_or_null("/root/PortManager")
	_connect_port_manager()
	return _port_manager_is_ready()


func verify_rom() -> bool:
	return _refresh_port_manager() and bool(_port_manager.call("rom_is_valid"))


func open_rom_picker() -> void:
	if not can_check:
		return
	if not _refresh_port_manager():
		show_rom_prompt("Build 43 error: ROM service is unavailable.", true)
		return
	$RomPanel/Content/Status.text = "Opening Android file picker..."
	$RomPanel/Content/Status.modulate = Color(1.0, 0.86, 0.35, 1.0)
	_port_manager.call("request_rom_selection")


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
