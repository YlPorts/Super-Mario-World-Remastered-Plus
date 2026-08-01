extends CanvasLayer
## Runtime multitouch overlay for Android.
## Uses Input actions directly, preserving the game's existing keyboard/gamepad code.

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
	&"pause": [&"pause", &"apply_settings"],
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
	&"pause": "START",
}

const BASE_SIZE := Vector2(480.0, 270.0)
const SIZE_SCALES := [0.75, 0.9, 1.0, 1.15, 1.3]
const OPACITY_VALUES := [0.2, 0.35, 0.5, 0.65, 0.8]

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

	_normalize_primary_joypad_devices()
	get_viewport().size_changed.connect(_rebuild_layout)
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	var port_manager := get_node_or_null("/root/PortManager")
	if port_manager != null:
		port_manager.settings_applied.connect(_apply_preferences)
	_apply_preferences()


func _apply_preferences() -> void:
	var settings_manager := get_node_or_null("/root/SettingsManager")
	_settings = settings_manager.settings_file if settings_manager != null else {}
	_rebuild_layout()


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	# Android can assign a new device ID after a Bluetooth/USB reconnect.
	# Rebind player-one/UI actions to any joypad without releasing touch input.
	call_deferred("_normalize_primary_joypad_devices")
	_update_visibility()


func _normalize_primary_joypad_devices() -> void:
	var actions_to_fix: Dictionary = {}
	for zone_actions: Array in ZONE_ACTIONS.values():
		for action: StringName in zone_actions:
			actions_to_fix[action] = true

	for action: StringName in actions_to_fix.keys():
		if not InputMap.has_action(action):
			continue
		for event: InputEvent in InputMap.action_get_events(action):
			if not (event is InputEventJoypadButton or event is InputEventJoypadMotion):
				continue
			if event.device == -1:
				continue
			var replacement := event.duplicate() as InputEvent
			replacement.device = -1
			InputMap.action_erase_event(action, event)
			InputMap.action_add_event(action, replacement)


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
	# A connected/ghost Android joypad must never make the fallback controls
	# disappear. Gamepad and touchscreen input are intentionally simultaneous.
	_root.visible = bool(_settings.get("touch_controls_enabled", true))
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

	var dpad_size := 42.0 * scale
	var dpad_center := Vector2(layout_rect.position.x + 70.0 * scale, layout_rect.end.y - 62.0 * scale)
	_add_button(&"left", Rect2(dpad_center + Vector2(-dpad_size * 1.05, -dpad_size * 0.5), Vector2.ONE * dpad_size), false)
	_add_button(&"right", Rect2(dpad_center + Vector2(dpad_size * 0.05, -dpad_size * 0.5), Vector2.ONE * dpad_size), false)
	_add_button(&"up", Rect2(dpad_center + Vector2(-dpad_size * 0.5, -dpad_size * 1.05), Vector2.ONE * dpad_size), false)
	_add_button(&"down", Rect2(dpad_center + Vector2(-dpad_size * 0.5, dpad_size * 0.05), Vector2.ONE * dpad_size), false)

	var face_size := 49.0 * scale
	_add_centered_button(&"jump", Vector2(layout_rect.end.x - 39.0 * scale, layout_rect.end.y - 48.0 * scale), face_size, true)
	_add_centered_button(&"run", Vector2(layout_rect.end.x - 96.0 * scale, layout_rect.end.y - 33.0 * scale), face_size, true)
	_add_centered_button(&"spin", Vector2(layout_rect.end.x - 48.0 * scale, layout_rect.end.y - 106.0 * scale), face_size, true)
	_add_centered_button(&"dive", Vector2(layout_rect.end.x - 105.0 * scale, layout_rect.end.y - 91.0 * scale), face_size, true)

	var shoulder_size := Vector2(40.0, 20.0) * scale
	_add_button(&"tab_left", Rect2(Vector2(layout_rect.position.x + 10.0 * scale, layout_rect.position.y + 8.0 * scale), shoulder_size), false)
	_add_button(&"tab_right", Rect2(Vector2(layout_rect.end.x - shoulder_size.x - 10.0 * scale, layout_rect.position.y + 8.0 * scale), shoulder_size), false)

	var pause_size := Vector2(52.0, 20.0) * scale
	_add_button(&"pause", Rect2(Vector2(layout_rect.get_center().x - pause_size.x * 0.5, layout_rect.position.y + 8.0 * scale), pause_size), false)
	_update_visibility()


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


func _add_centered_button(zone: StringName, center: Vector2, diameter: float, circular: bool) -> void:
	_add_button(zone, Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), circular)


func _add_button(zone: StringName, rect: Rect2, circular: bool) -> void:
	_zones[zone] = rect

	var panel := Panel.new()
	panel.name = String(zone).capitalize()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var opacity_index := clampi(int(_settings.get("touch_controls_opacity", 1)), 0, OPACITY_VALUES.size() - 1)
	var opacity: float = OPACITY_VALUES[opacity_index]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, opacity)
	style.border_color = Color(1.0, 1.0, 1.0, minf(opacity + 0.2, 0.9))
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(rect.size.y * (0.5 if circular else 0.18)))
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = BUTTON_LABELS.get(zone, "?")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(8, int(rect.size.y * (0.3 if zone == &"pause" else 0.38))))
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	panel.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_root.add_child(panel)
	_visuals[zone] = panel


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
	var panel: Panel = _visuals.get(zone)
	if is_instance_valid(panel):
		panel.modulate = Color(1.35, 1.35, 1.35, 1.0) if pressed else Color.WHITE


func _release_all() -> void:
	for action in _action_counts.keys():
		if InputMap.has_action(action):
			Input.action_release(action)
	_action_counts.clear()
	_touch_zone.clear()
	for zone in _visuals:
		_set_visual_pressed(zone, false)
