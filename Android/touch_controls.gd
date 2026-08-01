extends CanvasLayer
## SNES-inspired multitouch controls with an in-game layout editor.

const PORT_MANAGER_SCRIPT := "res://Android/port_manager.gd"
const BASE_SIZE := Vector2(480.0, 270.0)
const SIZE_SCALES := [0.75, 0.9, 1.0, 1.15, 1.3]
const OPACITY_VALUES := [0.20, 0.30, 0.40, 0.55, 0.70, 0.85, 1.0]

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

var _device_active := false
var _root: Control
var _zones: Dictionary = {}
var _visuals: Dictionary = {}
var _zone_groups: Dictionary = {}
var _group_nodes: Dictionary = {}
var _touch_zone: Dictionary = {}
var _action_counts: Dictionary = {}
var _settings: Dictionary = {}
var _layout_offsets: Dictionary = {}
var _layout_rect := Rect2()

var _editing := false
var _edit_was_paused := false
var _edit_touch_id := -1
var _edit_group := ""
var _edit_last_position := Vector2.ZERO
var _editor_ui_controls: Array[Control] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_device_active = OS.has_feature("android") or DisplayServer.is_touchscreen_available()
	if not _device_active:
		return

	_ensure_port_manager()
	_root = Control.new()
	_root.name = "AndroidTouchOverlay"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	get_viewport().size_changed.connect(_rebuild_layout)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	refresh_services()


func _ensure_port_manager() -> Node:
	var manager := get_node_or_null("/root/PortManager")
	if manager != null:
		return manager
	var manager_script := load(PORT_MANAGER_SCRIPT)
	if manager_script == null:
		return null
	manager = manager_script.new()
	manager.name = "PortManager"
	get_tree().root.add_child(manager)
	return manager


func refresh_services() -> void:
	var port_manager := _ensure_port_manager()
	if port_manager != null:
		if not port_manager.settings_applied.is_connected(_apply_preferences):
			port_manager.settings_applied.connect(_apply_preferences)
		if not port_manager.rom_imported.is_connected(_on_rom_imported):
			port_manager.rom_imported.connect(_on_rom_imported)
	_apply_preferences()


func _apply_preferences() -> void:
	var settings_manager := get_node_or_null("/root/SettingsManager")
	_settings = settings_manager.settings_file if settings_manager != null else {}
	_load_layout_offsets()
	_rebuild_layout()


func _load_layout_offsets() -> void:
	_layout_offsets.clear()
	var saved = _settings.get("touch_control_offsets", {})
	if not saved is Dictionary:
		return
	for key in saved:
		var value = saved[key]
		if value is Array and value.size() >= 2:
			_layout_offsets[str(key)] = Vector2(float(value[0]), float(value[1]))


func _save_layout_offsets() -> void:
	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager == null:
		return
	var serialized := {}
	for group in _layout_offsets:
		var offset: Vector2 = _layout_offsets[group]
		serialized[str(group)] = [snappedf(offset.x, 0.1), snappedf(offset.y, 0.1)]
	settings_manager.settings_file["touch_control_offsets"] = serialized
	settings_manager.save_settings()
	_settings = settings_manager.settings_file


func _on_rom_imported(_success: bool, _message: String) -> void:
	_update_visibility()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	_update_visibility()


func _input(event: InputEvent) -> void:
	if not _device_active or not is_instance_valid(_root) or not _root.visible:
		return

	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if _point_is_over_editor_ui(event.position):
			return

	var consumed := false
	if _editing:
		consumed = _handle_editor_input(event)
	elif event is InputEventScreenTouch:
		if event.pressed:
			consumed = _update_touch(event.index, event.position)
		else:
			consumed = _release_touch(event.index)
	elif event is InputEventScreenDrag:
		consumed = _update_touch(event.index, event.position)

	if consumed:
		get_viewport().set_input_as_handled()


func _handle_editor_input(event: InputEvent) -> bool:
	if event is InputEventScreenTouch:
		if event.pressed:
			if _edit_touch_id != -1:
				return true
			var zone := _zone_at(event.position)
			if zone == &"":
				return true
			_edit_touch_id = event.index
			_edit_group = str(_zone_groups.get(zone, str(zone)))
			_edit_last_position = event.position
			_set_group_highlight(_edit_group, true)
			Input.vibrate_handheld(20)
			return true
		if event.index == _edit_touch_id:
			_finish_edit_drag()
			return true
		return true

	if event is InputEventScreenDrag:
		if event.index == _edit_touch_id and not _edit_group.is_empty():
			var delta := event.position - _edit_last_position
			_edit_last_position = event.position
			_move_group(_edit_group, delta)
		return true
	return false


func _point_is_over_editor_ui(point: Vector2) -> bool:
	for control in _editor_ui_controls:
		if is_instance_valid(control) and control.visible and control.get_global_rect().has_point(point):
			return true
	return false


func _finish_edit_drag() -> void:
	if not _edit_group.is_empty():
		_set_group_highlight(_edit_group, false)
		_save_layout_offsets()
	_edit_touch_id = -1
	_edit_group = ""


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_release_all()
		_finish_edit_drag()


func _exit_tree() -> void:
	_release_all()
	if _editing:
		get_tree().paused = _edit_was_paused


func _update_visibility() -> void:
	if not is_instance_valid(_root):
		return
	var enabled := bool(_settings.get("touch_controls_enabled", true))
	var auto_hide := bool(_settings.get("touch_controls_auto_hide_gamepad", true))
	var gamepad_connected := not Input.get_connected_joypads().is_empty()
	var port_manager := get_node_or_null("/root/PortManager")
	var rom_ready := port_manager != null and port_manager.rom_is_valid()
	_root.visible = rom_ready and (enabled or _editing) and (_editing or not (auto_hide and gamepad_connected))
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
	_zone_groups.clear()
	_group_nodes.clear()
	_editor_ui_controls.clear()

	var viewport_size := get_viewport().get_visible_rect().size
	_layout_rect = _get_safe_layout_rect(viewport_size)
	var size_index := clampi(int(_settings.get("touch_controls_size", 2)), 0, SIZE_SCALES.size() - 1)
	var control_scale: float = SIZE_SCALES[size_index]
	var scale := clampf(minf(viewport_size.x / BASE_SIZE.x, viewport_size.y / BASE_SIZE.y), 0.75, 2.0)
	scale *= control_scale

	_build_dpad(_layout_rect, scale)
	_build_face_buttons(_layout_rect, scale)
	_build_system_buttons(_layout_rect, scale)
	_build_editor_ui(_layout_rect, scale)
	_update_visibility()


func _build_dpad(layout_rect: Rect2, scale: float) -> void:
	var group := "dpad"
	var unit := 29.0 * scale
	var center := Vector2(layout_rect.position.x + 68.0 * scale, layout_rect.end.y - 59.0 * scale) + _offset_for(group)
	var dpad_color := _with_control_opacity(Color(0.11, 0.12, 0.15, 1.0), 0.20)

	_add_visual_only(Rect2(center - Vector2.ONE * unit * 0.5, Vector2.ONE * unit), false, dpad_color, Color(0.72, 0.74, 0.82, 0.9), group)
	_add_control_button(&"left", Rect2(center + Vector2(-unit * 1.5, -unit * 0.5), Vector2.ONE * unit), false, dpad_color, group)
	_add_control_button(&"right", Rect2(center + Vector2(unit * 0.5, -unit * 0.5), Vector2.ONE * unit), false, dpad_color, group)
	_add_control_button(&"up", Rect2(center + Vector2(-unit * 0.5, -unit * 1.5), Vector2.ONE * unit), false, dpad_color, group)
	_add_control_button(&"down", Rect2(center + Vector2(-unit * 0.5, unit * 0.5), Vector2.ONE * unit), false, dpad_color, group)


func _build_face_buttons(layout_rect: Rect2, scale: float) -> void:
	var size := 41.0 * scale
	var right := layout_rect.end.x
	var bottom := layout_rect.end.y
	_add_centered_button(&"jump", Vector2(right - 42.0 * scale, bottom - 51.0 * scale) + _offset_for("jump"), size, Color(0.82, 0.18, 0.25, 1.0), "jump")
	_add_centered_button(&"run", Vector2(right - 91.0 * scale, bottom - 31.0 * scale) + _offset_for("run"), size, Color(0.92, 0.66, 0.14, 1.0), "run")
	_add_centered_button(&"spin", Vector2(right - 47.0 * scale, bottom - 101.0 * scale) + _offset_for("spin"), size, Color(0.20, 0.48, 0.92, 1.0), "spin")
	_add_centered_button(&"dive", Vector2(right - 96.0 * scale, bottom - 81.0 * scale) + _offset_for("dive"), size, Color(0.22, 0.72, 0.38, 1.0), "dive")


func _build_system_buttons(layout_rect: Rect2, scale: float) -> void:
	var shoulder_size := Vector2(48.0, 19.0) * scale
	var shoulder_color := _with_control_opacity(Color(0.15, 0.15, 0.20, 1.0), 0.16)
	var left_rect := Rect2(layout_rect.position + Vector2(10.0, 8.0) * scale + _offset_for("tab_left"), shoulder_size)
	var right_rect := Rect2(Vector2(layout_rect.end.x - shoulder_size.x - 10.0 * scale, layout_rect.position.y + 8.0 * scale) + _offset_for("tab_right"), shoulder_size)
	_add_control_button(&"tab_left", left_rect, true, shoulder_color, "tab_left")
	_add_control_button(&"tab_right", right_rect, true, shoulder_color, "tab_right")

	var pill_size := Vector2(49.0, 17.0) * scale
	var gap := 7.0 * scale
	var group_width := pill_size.x * 2.0 + gap
	var left := layout_rect.get_center().x - group_width * 0.5
	var top := layout_rect.end.y - 25.0 * scale
	var pill_color := _with_control_opacity(Color(0.17, 0.16, 0.22, 1.0), 0.18)
	_add_control_button(&"select", Rect2(Vector2(left, top) + _offset_for("select"), pill_size), true, pill_color, "select")
	_add_control_button(&"start", Rect2(Vector2(left + pill_size.x + gap, top) + _offset_for("start"), pill_size), true, pill_color, "start")


func _build_editor_ui(layout_rect: Rect2, scale: float) -> void:
	if not _editing:
		var edit_button := Button.new()
		edit_button.text = "EDIT"
		edit_button.focus_mode = Control.FOCUS_NONE
		edit_button.process_mode = Node.PROCESS_MODE_ALWAYS
		edit_button.position = Vector2(layout_rect.get_center().x - 23.0 * scale, layout_rect.position.y + 7.0 * scale)
		edit_button.size = Vector2(46.0, 18.0) * scale
		edit_button.add_theme_font_size_override("font_size", maxi(8, int(9.0 * scale)))
		_style_editor_button(edit_button, Color(0.18, 0.20, 0.28, 0.92))
		edit_button.pressed.connect(begin_edit_mode)
		_root.add_child(edit_button)
		_editor_ui_controls.append(edit_button)
		return

	var panel := Panel.new()
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.position = Vector2(layout_rect.get_center().x - 150.0 * scale, layout_rect.position.y + 5.0 * scale)
	panel.size = Vector2(300.0, 47.0) * scale
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.04, 0.05, 0.09, 0.96)
	panel_style.border_color = Color(0.72, 0.78, 0.96, 1.0)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(int(7.0 * scale))
	panel.add_theme_stylebox_override("panel", panel_style)
	_root.add_child(panel)
	_editor_ui_controls.append(panel)

	var title := Label.new()
	title.text = "DRAG BUTTONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(4.0, 2.0) * scale
	title.size = Vector2(292.0, 13.0) * scale
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_font_size_override("font_size", maxi(7, int(8.0 * scale)))
	panel.add_child(title)

	var minus := _make_editor_button("-", Rect2(Vector2(6.0, 18.0) * scale, Vector2(30.0, 23.0) * scale))
	minus.pressed.connect(_change_opacity.bind(-1))
	panel.add_child(minus)

	var opacity := Label.new()
	opacity.text = "%d%%" % int(round(_current_opacity() * 100.0))
	opacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	opacity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	opacity.position = Vector2(39.0, 18.0) * scale
	opacity.size = Vector2(48.0, 23.0) * scale
	opacity.mouse_filter = Control.MOUSE_FILTER_IGNORE
	opacity.add_theme_font_size_override("font_size", maxi(7, int(8.0 * scale)))
	panel.add_child(opacity)

	var plus := _make_editor_button("+", Rect2(Vector2(90.0, 18.0) * scale, Vector2(30.0, 23.0) * scale))
	plus.pressed.connect(_change_opacity.bind(1))
	panel.add_child(plus)

	var reset := _make_editor_button("RESET", Rect2(Vector2(128.0, 18.0) * scale, Vector2(72.0, 23.0) * scale))
	reset.pressed.connect(reset_layout)
	panel.add_child(reset)

	var done := _make_editor_button("DONE", Rect2(Vector2(207.0, 18.0) * scale, Vector2(87.0, 23.0) * scale))
	done.pressed.connect(end_edit_mode)
	panel.add_child(done)


func _make_editor_button(text_value: String, rect: Rect2) -> Button:
	var button := Button.new()
	button.text = text_value
	button.focus_mode = Control.FOCUS_NONE
	button.process_mode = Node.PROCESS_MODE_ALWAYS
	button.position = rect.position
	button.size = rect.size
	button.add_theme_font_size_override("font_size", maxi(7, int(rect.size.y * 0.34)))
	_style_editor_button(button, Color(0.18, 0.20, 0.28, 1.0))
	return button


func _style_editor_button(button: Button, fill: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = fill
	normal.border_color = Color(0.78, 0.82, 0.94, 1.0)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.34, 0.38, 0.52, 1.0)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover", pressed)


func begin_edit_mode() -> void:
	if _editing:
		return
	_release_all()
	_edit_was_paused = get_tree().paused
	get_tree().paused = true
	_editing = true
	_rebuild_layout()


func end_edit_mode() -> void:
	if not _editing:
		return
	_finish_edit_drag()
	_save_layout_offsets()
	_editing = false
	get_tree().paused = _edit_was_paused
	_rebuild_layout()


func reset_layout() -> void:
	_layout_offsets.clear()
	_save_layout_offsets()
	_rebuild_layout()


func _change_opacity(delta: int) -> void:
	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager == null:
		return
	var current := clampi(int(settings_manager.settings_file.get("touch_controls_opacity", 2)), 0, OPACITY_VALUES.size() - 1)
	current = clampi(current + delta, 0, OPACITY_VALUES.size() - 1)
	settings_manager.settings_file["touch_controls_opacity"] = current
	settings_manager.save_settings()
	_settings = settings_manager.settings_file
	_rebuild_layout()


func _current_opacity() -> float:
	var opacity_index := clampi(int(_settings.get("touch_controls_opacity", 2)), 0, OPACITY_VALUES.size() - 1)
	return OPACITY_VALUES[opacity_index]


func _offset_for(group: String) -> Vector2:
	return _layout_offsets.get(group, Vector2.ZERO)


func _move_group(group: String, requested_delta: Vector2) -> void:
	var nodes: Array = _group_nodes.get(group, [])
	if nodes.is_empty():
		return
	var group_rect := Rect2()
	var has_rect := false
	for item in nodes:
		var control := item as Control
		if not is_instance_valid(control):
			continue
		var rect := Rect2(control.position, control.size)
		group_rect = rect if not has_rect else group_rect.merge(rect)
		has_rect = true
	if not has_rect:
		return

	var margin := 2.0
	var delta := requested_delta
	delta.x = clampf(delta.x, _layout_rect.position.x + margin - group_rect.position.x, _layout_rect.end.x - margin - group_rect.end.x)
	delta.y = clampf(delta.y, _layout_rect.position.y + margin - group_rect.position.y, _layout_rect.end.y - margin - group_rect.end.y)
	if delta.is_zero_approx():
		return

	for item in nodes:
		var control := item as Control
		if is_instance_valid(control):
			control.position += delta
	for zone in _zone_groups:
		if str(_zone_groups[zone]) == group:
			var rect: Rect2 = _zones[zone]
			rect.position += delta
			_zones[zone] = rect
	_layout_offsets[group] = _offset_for(group) + delta


func _set_group_highlight(group: String, highlighted: bool) -> void:
	for item in _group_nodes.get(group, []):
		var control := item as Control
		if is_instance_valid(control):
			control.modulate = Color(1.25, 1.25, 1.25, 1.0) if highlighted else Color.WHITE


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


func _add_centered_button(zone: StringName, center: Vector2, diameter: float, fill: Color, group: String) -> void:
	_add_control_button(zone, Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), true, _with_control_opacity(fill, 0.08), group)


func _add_control_button(zone: StringName, rect: Rect2, rounded: bool, fill: Color, group: String) -> void:
	_zones[zone] = rect
	_zone_groups[zone] = group
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
	_register_group_node(group, panel)


func _add_visual_only(rect: Rect2, rounded: bool, fill: Color, border: Color, group: String) -> void:
	var panel := _create_panel(rect, rounded, fill, border)
	_root.add_child(panel)
	_register_group_node(group, panel)


func _register_group_node(group: String, control: Control) -> void:
	if not _group_nodes.has(group):
		_group_nodes[group] = []
	_group_nodes[group].append(control)


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
	var result := color
	result.a = clampf(_current_opacity() + extra, 0.12, 1.0)
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
