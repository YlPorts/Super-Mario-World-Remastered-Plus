extends SettingsSection

const PIXEL_FONT: Font = preload("res://Assets/Fonts/PixelifySans.ttf")
const SCALE_VALUES: Array[float] = [0.70, 0.85, 1.00, 1.15, 1.30]
const OPACITY_VALUES: Array[float] = [0.40, 0.60, 0.80, 1.00]

var rows: Array[HBoxContainer] = []
var title_labels: Array[Label] = []
var value_labels: Array[Label] = []
var touch_enabled := true
var scale_index := 2
var opacity_index := 2

@onready var list_container: VBoxContainer = $VBoxContainer

func _ready() -> void:
	title = "Touch Controls"
	_build_interface()
	set_option_node_values()
	_refresh_rows()

func _build_interface() -> void:
	for child in list_container.get_children():
		child.queue_free()
	_create_row("TOUCH BUTTONS")
	_create_row("SIZE")
	_create_row("OPACITY")
	_create_row("EDIT LAYOUT")
	_create_row("RESET LAYOUT")

func _create_row(source_title: String) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 34)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.add_child(row)

	var left := Label.new()
	left.add_theme_font_override("font", PIXEL_FONT)
	left.add_theme_font_size_override("font_size", 15)
	left.add_theme_color_override("font_outline_color", Color.BLACK)
	left.add_theme_constant_override("outline_size", 2)
	left.text = LanguageManager.text(source_title)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(left)

	var right := Label.new()
	right.add_theme_font_override("font", PIXEL_FONT)
	right.add_theme_font_size_override("font_size", 15)
	right.add_theme_color_override("font_outline_color", Color.BLACK)
	right.add_theme_constant_override("outline_size", 2)
	right.custom_minimum_size = Vector2(150, 0)
	right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(right)

	rows.append(row)
	title_labels.append(left)
	value_labels.append(right)

func _physics_process(_delta: float) -> void:
	if not selected or blocks_parent_input():
		return
	if Input.is_action_just_pressed("ui_down"):
		selected_index = min(selected_index + 1, rows.size() - 1)
		SoundManager.play_ui_sound(SoundManager.select)
	elif Input.is_action_just_pressed("ui_up"):
		selected_index = max(selected_index - 1, 0)
		SoundManager.play_ui_sound(SoundManager.select)

	var direction := 0
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left_0"):
		direction = -1
	elif Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right_0"):
		direction = 1
	if direction != 0:
		_change_value(direction)

	if Input.is_action_just_pressed("ui_accept"):
		_activate_row()
	_refresh_rows()

func _change_value(direction: int) -> void:
	match selected_index:
		0:
			touch_enabled = not touch_enabled
		1:
			scale_index = clamp(scale_index + direction, 0, SCALE_VALUES.size() - 1)
		2:
			opacity_index = clamp(opacity_index + direction, 0, OPACITY_VALUES.size() - 1)
		_:
			return
	SoundManager.play_ui_sound(SoundManager.select)
	_apply_preview()

func _activate_row() -> void:
	var controls := get_node_or_null("/root/MobileTouchControls")
	match selected_index:
		0:
			touch_enabled = not touch_enabled
			_apply_preview()
			SoundManager.play_ui_sound(SoundManager.select)
		3:
			if controls != null:
				_apply_preview()
				controls.begin_edit_mode()
				SoundManager.play_ui_sound(SoundManager.coin)
		4:
			if controls != null:
				controls.reset_layout()
				SoundManager.play_ui_sound(SoundManager.coin)

func _apply_preview() -> void:
	var controls := get_node_or_null("/root/MobileTouchControls")
	if controls != null:
		controls.apply_mobile_settings(touch_enabled, SCALE_VALUES[scale_index], OPACITY_VALUES[opacity_index])

func set_option_node_values() -> void:
	var settings: Dictionary = SettingsManager.settings_file
	touch_enabled = bool(settings.get("mobile_touch_enabled", settings.get("touch_controls_enabled", true)))
	var scale_value := float(settings.get("mobile_touch_scale", 1.0))
	var opacity_value := float(settings.get("mobile_touch_opacity", 0.80))
	scale_index = _nearest_index(SCALE_VALUES, scale_value)
	opacity_index = _nearest_index(OPACITY_VALUES, opacity_value)
	_refresh_rows()

func get_chosen_options() -> Dictionary:
	return {
		"mobile_touch_enabled": touch_enabled,
		"mobile_touch_scale": SCALE_VALUES[scale_index],
		"mobile_touch_opacity": OPACITY_VALUES[opacity_index],
	}

func _nearest_index(values: Array[float], target: float) -> int:
	var best_index := 0
	var best_distance := INF
	for index in values.size():
		var distance := abs(values[index] - target)
		if distance < best_distance:
			best_distance = distance
			best_index = index
	return best_index

func _refresh_rows() -> void:
	if rows.is_empty():
		return
	var source_titles := ["TOUCH BUTTONS", "SIZE", "OPACITY", "EDIT LAYOUT", "RESET LAYOUT"]
	for index in rows.size():
		title_labels[index].text = LanguageManager.text(source_titles[index])
		rows[index].modulate = Color(1.0, 0.92, 0.2) if selected and selected_index == index else Color.WHITE
	value_labels[0].text = LanguageManager.text("ENABLED") if touch_enabled else LanguageManager.text("DISABLED")
	value_labels[1].text = "%d%%" % roundi(SCALE_VALUES[scale_index] * 100.0)
	value_labels[2].text = "%d%%" % roundi(OPACITY_VALUES[opacity_index] * 100.0)
	value_labels[3].text = ">"
	value_labels[4].text = ">"

func blocks_parent_input() -> bool:
	var controls := get_node_or_null("/root/MobileTouchControls")
	return controls != null and controls.is_editing()
