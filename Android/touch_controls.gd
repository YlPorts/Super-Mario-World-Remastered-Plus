extends CanvasLayer
## Runtime multitouch overlay for Android.
##
## This autoload intentionally uses Input.action_press()/release() instead of
## keyboard emulation, so gameplay and menus continue to use the project's
## existing InputMap actions.

const ZONE_ACTIONS := {
	&"left": [&"move_left_0", &"ui_left"],
	&"right": [&"move_right_0", &"ui_right"],
	&"up": [&"move_up_0", &"ui_up"],
	&"down": [&"move_down_0", &"ui_down"],
	&"jump": [&"jump_0", &"ui_accept"],
	&"run": [&"run_0", &"ui_cancel"],
	&"spin": [&"spin_jump_0"],
	&"dive": [&"dive_0"],
	&"pause": [&"pause"],
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
	&"pause": "Ⅱ",
}

const BASE_SIZE := Vector2(480.0, 270.0)

@export_range(0.1, 0.9, 0.05) var opacity := 0.38
@export_range(0.75, 1.35, 0.05) var control_scale := 1.0

var _active := false
var _root: Control
var _zones: Dictionary = {}
var _visuals: Dictionary = {}
var _touch_zone: Dictionary = {}
var _action_counts: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_active = OS.has_feature("android") or DisplayServer.is_touchscreen_available()
	if not _active:
		return

	_root = Control.new()
	_root.name = "AndroidTouchOverlay"
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	get_viewport().size_changed.connect(_rebuild_layout)
	_rebuild_layout()


func _input(event: InputEvent) -> void:
	if not _active:
		return

	if event is InputEventScreenTouch:
		if event.pressed:
			_update_touch(event.index, event.position)
		else:
			_release_touch(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		_update_touch(event.index, event.position)
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_release_all()


func _exit_tree() -> void:
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
	var scale := clampf(minf(viewport_size.x / BASE_SIZE.x, viewport_size.y / BASE_SIZE.y), 0.75, 2.0)
	scale *= control_scale

	var dpad_size := 42.0 * scale
	var dpad_center := Vector2(70.0 * scale, viewport_size.y - 62.0 * scale)
	_add_button(&"left", Rect2(dpad_center + Vector2(-dpad_size * 1.05, -dpad_size * 0.5), Vector2.ONE * dpad_size), false)
	_add_button(&"right", Rect2(dpad_center + Vector2(dpad_size * 0.05, -dpad_size * 0.5), Vector2.ONE * dpad_size), false)
	_add_button(&"up", Rect2(dpad_center + Vector2(-dpad_size * 0.5, -dpad_size * 1.05), Vector2.ONE * dpad_size), false)
	_add_button(&"down", Rect2(dpad_center + Vector2(-dpad_size * 0.5, dpad_size * 0.05), Vector2.ONE * dpad_size), false)

	var face_size := 49.0 * scale
	_add_centered_button(&"jump", Vector2(viewport_size.x - 39.0 * scale, viewport_size.y - 48.0 * scale), face_size, true)
	_add_centered_button(&"run", Vector2(viewport_size.x - 96.0 * scale, viewport_size.y - 33.0 * scale), face_size, true)
	_add_centered_button(&"spin", Vector2(viewport_size.x - 48.0 * scale, viewport_size.y - 106.0 * scale), face_size, true)
	_add_centered_button(&"dive", Vector2(viewport_size.x - 105.0 * scale, viewport_size.y - 91.0 * scale), face_size, true)

	var pause_size := Vector2(40.0, 20.0) * scale
	_add_button(&"pause", Rect2(Vector2(viewport_size.x * 0.5 - pause_size.x * 0.5, 8.0 * scale), pause_size), false)


func _add_centered_button(zone: StringName, center: Vector2, diameter: float, circular: bool) -> void:
	_add_button(zone, Rect2(center - Vector2.ONE * diameter * 0.5, Vector2.ONE * diameter), circular)


func _add_button(zone: StringName, rect: Rect2, circular: bool) -> void:
	_zones[zone] = rect

	var panel := Panel.new()
	panel.name = String(zone).capitalize()
	panel.position = rect.position
	panel.size = rect.size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.1, opacity)
	style.border_color = Color(1.0, 1.0, 1.0, minf(opacity + 0.2, 0.85))
	style.set_border_width_all(1)
	style.set_corner_radius_all(int(rect.size.y * (0.5 if circular else 0.18)))
	panel.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = BUTTON_LABELS.get(zone, "?")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", maxi(12, int(rect.size.y * 0.38)))
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.92))
	panel.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_root.add_child(panel)
	_visuals[zone] = panel


func _update_touch(index: int, position: Vector2) -> void:
	var next_zone: StringName = _zone_at(position)
	var previous_zone: StringName = _touch_zone.get(index, &"")
	if previous_zone == next_zone:
		return

	if previous_zone != &"":
		_release_zone(previous_zone)

	if next_zone == &"":
		_touch_zone.erase(index)
	else:
		_touch_zone[index] = next_zone
		_press_zone(next_zone)


func _release_touch(index: int) -> void:
	var zone: StringName = _touch_zone.get(index, &"")
	if zone != &"":
		_release_zone(zone)
	_touch_zone.erase(index)


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
