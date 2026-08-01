extends Node
## BUILD 56 bridge: the ROM importer writes baserom.sfc directly, after the
## TouchControls autoload has already hidden itself. This watcher refreshes the
## persistent overlay exactly when the ROM changes from unavailable to valid.

var _elapsed := 0.0
var _refreshed_for_current_rom := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	print("[TOUCH56] READY")
	call_deferred("_refresh_if_ready")


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < 0.25:
		return
	_elapsed = 0.0
	_refresh_if_ready()


func _refresh_if_ready() -> void:
	if not OS.has_feature("android") and not DisplayServer.is_touchscreen_available():
		return

	var port_manager := get_node_or_null("/root/PortManager")
	if port_manager == null or not port_manager.has_method("rom_is_valid"):
		return

	var rom_ready := bool(port_manager.rom_is_valid())
	if not rom_ready:
		_refreshed_for_current_rom = false
		return
	if _refreshed_for_current_rom:
		return

	var touch_controls := get_node_or_null("/root/TouchControls")
	if touch_controls == null:
		return

	if touch_controls.has_method("refresh_services"):
		touch_controls.refresh_services()
	elif touch_controls.has_method("_update_visibility"):
		touch_controls.call("_update_visibility")
	else:
		return

	_refreshed_for_current_rom = true
	print("[TOUCH56] OVERLAY REFRESHED rom_valid=true")

	# Keep existing listeners synchronized with the direct ContentResolver import.
	if port_manager.has_signal("rom_imported"):
		port_manager.emit_signal("rom_imported", true, "ROM ready; touch overlay refreshed.")
