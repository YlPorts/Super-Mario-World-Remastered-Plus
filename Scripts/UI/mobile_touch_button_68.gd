extends Control
class_name MobileTouchButton68

signal position_changed(button_id: String, normalized_position: Vector2)

const PIXEL_FONT: Font = preload("res://Assets/Fonts/PixelifySans.ttf")

var button_id := ""
var action_name := ""
var caption := "A"
var face_button := true
var button_color := Color(0.85, 0.15, 0.18, 0.92)
var edit_mode := false
var active_touch := -1
var mouse_active := false
var caption_label: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	caption_label = Label.new()
	caption_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	caption_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption_label.add_theme_font_override("font", PIXEL_FONT)
	caption_label.add_theme_font_size_override("font_size", 15)
	caption_label.add_theme_color_override("font_color", Color.WHITE)
	caption_label.add_theme_color_override("font_outline_color", Color(0.06, 0.06, 0.10, 1.0))
	caption_label.add_theme_constant_override("outline_size", 3)
	add_child(caption_label)
	_refresh_visual()

func configure(id_value: String, action_value: String, text_value: String, is_face: bool, color_value: Color) -> void:
	button_id = id_value
	action_name = action_value
	caption = text_value
	face_button = is_face
	button_color = color_value
	if is_instance_valid(caption_label):
		_refresh_visual()

func set_edit_mode(enabled: bool) -> void:
	if not enabled:
		_release_action()
	edit_mode = enabled
	_refresh_visual()

func release_action() -> void:
	active_touch = -1
	mouse_active = false
	_release_action()

func _refresh_visual() -> void:
	if is_instance_valid(caption_label):
		caption_label.text = caption
		caption_label.modulate = Color(1.0, 0.92, 0.2) if edit_mode else Color.WHITE
	queue_redraw()

func _draw() -> void:
	var center := size * 0.5
	var shadow := Color(0.02, 0.02, 0.04, 0.58)
	var edge := Color(0.07, 0.07, 0.11, 0.98)
	if face_button:
		var radius := min(size.x, size.y) * 0.42
		draw_circle(center + Vector2(2, 3), radius, shadow)
		draw_circle(center, radius + 2.0, edge)
		draw_circle(center, radius, button_color)
		draw_arc(center, radius - 3.0, PI * 1.05, PI * 1.8, 18, Color(1, 1, 1, 0.34), 2.0)
	else:
		var rect := Rect2(Vector2(3, 3), size - Vector2(6, 6))
		var shadow_rect := Rect2(rect.position + Vector2(2, 3), rect.size)
		draw_rect(shadow_rect, shadow, true)
		draw_rect(rect, edge, true)
		draw_rect(rect.grow(-3.0), button_color, true)
	if edit_mode:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.85, 0.2, 0.9), false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed and active_touch < 0:
			active_touch = touch.index
			if not edit_mode:
				Input.action_press(action_name)
			accept_event()
		elif not touch.pressed and touch.index == active_touch:
			if edit_mode:
				_emit_position()
			else:
				_release_action()
			active_touch = -1
			accept_event()
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		if edit_mode and drag.index == active_touch:
			_move_by(drag.relative)
			accept_event()
	elif event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			mouse_active = mouse_button.pressed
			if edit_mode:
				if not mouse_button.pressed:
					_emit_position()
			elif mouse_button.pressed:
				Input.action_press(action_name)
			else:
				_release_action()
			accept_event()
	elif event is InputEventMouseMotion and mouse_active and edit_mode:
		_move_by((event as InputEventMouseMotion).relative)
		accept_event()

func _move_by(relative_motion: Vector2) -> void:
	var viewport_size := get_viewport_rect().size
	var next_position := global_position + relative_motion
	next_position.x = clamp(next_position.x, 0.0, max(0.0, viewport_size.x - size.x))
	next_position.y = clamp(next_position.y, 0.0, max(0.0, viewport_size.y - size.y))
	global_position = next_position

func _emit_position() -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x > 0.0 and viewport_size.y > 0.0:
		position_changed.emit(button_id, (global_position + size * 0.5) / viewport_size)

func _release_action() -> void:
	if not action_name.is_empty() and Input.is_action_pressed(action_name):
		Input.action_release(action_name)

func _exit_tree() -> void:
	release_action()
