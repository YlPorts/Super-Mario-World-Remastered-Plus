extends CanvasLayer
## SNES-inspired multitouch controls for Android.

const ZONE_ACTIONS := {
	&"left": [&"move_left_0", &"ui_left"],
	&"right": [&"move_right_0", &"ui_right"],
	&"up": [&"move_up_0", &"ui_up"],
	&"down": [&"move_down_0", &"ui_down"],
	&"jump": [&"jump_0", &"ui_accept"],
	&"run": [&"run_0", &"ui_cancel", &"ui_back"],
	&"spin": [&"spin_jump_0"],
	&"dive": [&"dive_0"],
	&"tab_left": [&"ui_tab_left"],
	&"tab_right": [&"ui_tab_right"],
	&"select": [&"ui_select", &"open_inventory"],
	&"start": [&"pause", &"apply_settings"],
}

const BUTTON_LABELS := {
	&"left": "◀",
	&"right": "▶",
	&"up": "▲",
	&"down": "▼",
	&"jump": "A",
	&"run": "B",
	&"spin": "X",
	&"dive": "Y",
	&"tab_left": "L",
	&"tab_right": "R",
	&"select": "SELECT",
	&"start": "START",
}

const BASE_SIZE := Vector2(480.0, 270.0)
const SIZE_SCALES := [0.75, 0.9, 1.0, 1.15, 1.3]
const OPACITY_VALUES := [0.25, 0.4, 0.55, 0.7, 0.85]

var _device_active := false
var _root: Control
var _zones: Dictionary = {}
var _visuals: Dictionary = {}
var _touch_zone: Dictionary = {}
var _action_counts: Dictionary = {}
var _settings: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_device_active = OS.has_feature("android") or DisplayServer.is_touchscreen_available()
	if not _device_active:
		return

	_root = Control.new()
	_root.name = "AndroidTouchOverlay"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	get_viewport().size_changed.connect(_rebuild_layout)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var port_manager := get_node_or_null("/root/PortManager")
	if port_manager != null:
		port_manager.settings_applied.connect(_apply_preferences)
		port_manager.rom_imported.connect(_on_rom_imported)
	_apply_preferences()


func _apply_preferences() -> void:
	var settings_manager := get_node_or_null("/root/SettingsManager")
	_settings = settings_manager.settings_file if settings_manager != null else {}
	_rebuild_layout()


func _on_rom_imported(_success: bool, _message: String) -> void:
	_update_visibility()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_update_visibility()


func _input(event: InputEvent) -> void:
	if not _device_active or not is_instance_valid(_root) or not _root.visible:
		return

	var consumed := false
	if event is InputEventScreenTouch:
		if event.pressed:
			consumed = _update_touch(event.index, event.position)
		else:
			consumed = _release_touch(event.index)
	elif event is InputEventScreenDrag:
		consumed = _update_touch(event.index, event.position)

	if consumed:
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_release_all()


func _exit_tree() -> void:
	_release_all()


func _update_visibility() -> void:
	if not is_instance_valid(_root):
		return
	var enabled := bool(_settings.get("touch_controls_enabled", true))
	var auto_hide := bool(_settings.get("touch_controls_auto_hide_gamepad", true))
	var gamepad_connected := not Input.get_connected_joypads().is_empty()
	var rom_ready := true
	var port_manager := get_node_or_null("/root/PortManager")
	if port_manager != null:
		rom_ready = port_manager.rom_is_valid()
	_root.visible = enabled and rom_ready and not (auto_hide and gamepad_connected)
	if not _root.visible:
		_release_all()


func _rebuild_layout() -> void:
	if not is_instance_valid(_root):
		return

	_release_all()
	for child in _root.get_children():
		child.queue_free()
	_zones.clear()
	_visuals.clear()

	var viewport_size := get_viewport().get_visible_rect().size
	var layout_rect := _get_safe_layout_rect(viewport_size)
	var size_index := clampi(int(_settings.get("touch_controls_size", 2)), 0, SIZE_SCALES.size() - 1)
	var control_scale: float = SIZE_SCALES[size_index]
	var scale := clampf(minf(viewport_size.x / BASE_SIZE.x, viewport_size.y / BASE_SIZE.y), 0.75, 2.0)
	scale *= control_scale

	_build_dpad(layout_rect, scale)
	_build_face_buttons(layout_rect, scale)
	_build_system_buttons(layout_rect, scale)
	_update_visibility()


func _build_dpad(layout_rect: Rect2, scale: float) -> void:
	var unit := 29.0 * scale
	var center := Vector2(layout_rect.position.x + 68.0 * scale, layout_rect.end.y - 59.0 * scale)
	var dpad_color := _with_control_opacity(Color(0.11, 0.12, 0.15, 1.0), 0.20)

	_add_visual_only(Rect2(center - Vector2.ONE * unit * 0.5, Vector2.ONE * unit), false, dpad_color, Color(0.42, 0.44, 0.5, 0.9))
	_add_control_button(&"left", Rect2(center + Vector2(-unit * 1.5, -unit * 0.5), Vector2.ONE * unit), false, dpad_color)
	_add_control_button(&"right", Rect2(center + Vector2(unit * 0.5, -unit * 0.5), Vector2.ONE * unit), false, dpad_color)
	_add_control_button(&"up", Rect2(center + Vector2(-unit * 0.5, -unit * 1.5), Vector2.ONE * unit), false, dpad_color)
	_add_control_button(&"down", Rect2(center + Vector2(-unit * 0.5, unit * 0.5), Vector2.ONE * unit), false, dpad_color)


func _build_face_buttons(layout_rect: Rect2, scale: float) -> void:
	var size := 41.0 * scale
	var right := layout_rect.end.x
	var bottom := layout_rect.end.y
	_add_centered_button(&"jump", Vector2(right - 42.0 * scale, bottom - 51.0 * scale), size, Color(0.82, 0.18, 0.25, 1.0))
	_add_centered_button(&"run", Vector2(right - 91.0 * scale, bottom - 31.0 * scale), size, Color(0.92, 0.66, 0.14, 1.0))
	_add_centered_button(&"spin", Vector2(right - 47.0 * scale, bottom - 101.0 * scale), size, Color(0.20, 0.48, 0.92, 1.0))
	_add_centered_button(&"dive", Vector2(right - 96.0 * scale, bottom - 81.0 * scale), size, Color(0.22, 0.72, 0.38, 1.0))


func _build_system_buttons(layout_rect: Rect2, scale: float) -> void:
	var shoulder_size := Vector2(48.0, 19.0) * scale
	var shoulder_color := _with_control_opacity(Color(0.15, 0.15, 0.20, 1.0), 0.16)
	_add_control_button(&"tab_left", Rect2(layout_rect.position + Vector2(10.0, 8.0) * scale, shoulder_size), true, shoulder_color)
	_add_control_button(&"tab_right", Rect2(Vector2(layout_rect.end.x - shoulder_size.x - 10.0 * scale, layout_rect.position.y + 8.0 * scale), shoulder_size), true, shoulder_color)

	var pill_size := Vector2(49.0, 17.0) * scale
	var gap := 7.0 * scale
	var group_width := pill_size.x * 2.0 + gap
	var left := layout_rect.get_center().x - group_width * 0.5
	var top := layout_rect.end.y - 25.0 * scale
	var pill_color := _with_control_opacity(Color(0.17, 0.16, 0.22, 1.0), 0.18)
	_add_control_button(&"select", Rect2(Vector2(left, top), pill_size), true, pill_color)
	_add_control_button(&"start", Rect2(Vector2(left + pill_size.x + gap, top), pill_size), true, pill_color)


func _get_safe_layout_rect(viewport_size: Vector2) -> Rect2:
	var full_rect := Rect2(Vector2.ZERO, viewport_size)
	if not bool(_settings.get("touch_controls_safe_area", true)):
		return full_rect
	var physical_size := Vector2(DisplayServer.window_get_size())
	if physical_size.x <= 0.0 or physical_size.y <= 0.0:
		return full_rect
	var safe_area := DisplayServer.get_display_safe_area()
	if safe_area.size.x <= 0 or safe_area.size.y <= 0:
		return full_rect
	var ratio := viewport_size / physical_size
	return Rect2(Vector2(safe_area.position) * ratio, Vector2(safe_area.size) * ratio)


func _add_centered_button(zone: StringName, center: Vector2, diameter: float, fill: Color) -> void:
	_add_control_button(zone, Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), true, _with_control_opacity(fill, 0.08))


func _add_control_button(zone: StringName, rect: Rect2, rounded: bool, fill: Color) -> void:
	_zones[zone] = rect
	var panel := _create_panel(rect, rounded, fill, Color(0.85, 0.87, 0.94, 0.9))
	var label := Label.new()
	label.text = BUTTON_LABELS.get(zone, "?")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var small_label := zone in [&"tab_left", &"tab_right", &"select", &"start"]
	label.add_theme_font_size_override("font_size", maxi(8, int(rect.size.y * (0.42 if small_label else 0.50))))
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.98))
	panel.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.add_child(panel)
	_visuals[zone] = panel


func _add_visual_only(rect: Rect2, rounded: bool, fill: Color, border: Color) -> void:
	_root.add_child(_create_panel(rect, rounded, fill, border))


func _create_panel(rect: Rect2, rounded: bool, fill: Color, border: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(int(rect.size.y * (0.5 if rounded else 0.12)))
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _with_control_opacity(color: Color, extra := 0.0) -> Color:
	var opacity_index := clampi(int(_settings.get("touch_controls_opacity", 1)), 0, OPACITY_VALUES.size() - 1)
	var result := color
	result.a = clampf(OPACITY_VALUES[opacity_index] + extra, 0.15, 0.95)
	return result


func _update_touch(index: int, position: Vector2) -> bool:
	var next_zone: StringName = _zone_at(position)
	var previous_zone: StringName = _touch_zone.get(index, &"")
	if previous_zone == next_zone:
		return next_zone != &""

	if previous_zone != &"":
		_release_zone(previous_zone)

	if next_zone == &"":
		_touch_zone.erase(index)
	else:
		_touch_zone[index] = next_zone
		_press_zone(next_zone)
	return previous_zone != &"" or next_zone != &""


func _release_touch(index: int) -> bool:
	var zone: StringName = _touch_zone.get(index, &"")
	if zone != &"":
		_release_zone(zone)
	_touch_zone.erase(index)
	return zone != &""


func _zone_at(position: Vector2) -> StringName:
	for zone in _zones:
		var rect: Rect2 = _zones[zone]
		if rect.has_point(position):
			return zone
	return &""


func _press_zone(zone: StringName) -> void:
	for action: StringName in ZONE_ACTIONS.get(zone, []):
		if not InputMap.has_action(action):
			continue
		var count := int(_action_counts.get(action, 0)) + 1
		_action_counts[action] = count
		if count == 1:
			Input.action_press(action)
	if bool(_settings.get("touch_vibration", true)):
		Input.vibrate_handheld(18)
	_set_visual_pressed(zone, true)


func _release_zone(zone: StringName) -> void:
	for action: StringName in ZONE_ACTIONS.get(zone, []):
		if not InputMap.has_action(action):
			continue
		var count := maxi(0, int(_action_counts.get(action, 0)) - 1)
		if count == 0:
			_action_counts.erase(action)
			Input.action_release(action)
		else:
			_action_counts[action] = count
	_set_visual_pressed(zone, false)


func _set_visual_pressed(zone: StringName, pressed: bool) -> void:
	var panel: Control = _visuals.get(zone)
	if is_instance_valid(panel):
		panel.scale = Vector2.ONE * (0.92 if pressed else 1.0)
		panel.pivot_offset = panel.size * 0.5
		panel.modulate = Color(1.18, 1.18, 1.18, 1.0) if pressed else Color.WHITE


func _release_all() -> void:
	for action in _action_counts.keys():
		if InputMap.has_action(action):
			Input.action_release(action)
	_action_counts.clear()
	_touch_zone.clear()
	for zone in _visuals:
		_set_visual_pressed(zone, false)
