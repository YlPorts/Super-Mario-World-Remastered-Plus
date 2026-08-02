extends CanvasLayer

signal edit_mode_changed(enabled: bool)

const TOUCH_BUTTON = preload("res://Scripts/UI/mobile_touch_button_68.gd")
const PIXEL_FONT: Font = preload("res://Assets/Fonts/PixelifySans.ttf")
const DEFAULT_LAYOUT := {
	"left": [0.085, 0.77], "right": [0.215, 0.77],
	"up": [0.15, 0.64], "down": [0.15, 0.90],
	"a": [0.91, 0.70], "b": [0.82, 0.82],
	"x": [0.82, 0.58], "y": [0.73, 0.70],
	"start": [0.53, 0.91],
}

var root: Control
var dimmer: ColorRect
var edit_help: Label
var save_button: Button
var buttons: Dictionary = {}
var edit_mode := false
var enabled := true
var control_scale := 1.0
var control_opacity := 0.86
var layout: Dictionary = DEFAULT_LAYOUT.duplicate(true)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	_build_overlay()
	get_viewport().size_changed.connect(_apply_layout)
	# MobileTouchControls is inserted before some of the existing autoloads.
	# Defer reading SettingsManager until every autoload has completed _ready().
	call_deferred("_finish_startup")
	print("[MOBILE68] SNES TOUCH CONTROLS READY")

func _finish_startup() -> void:
	_load_settings()
	_apply_layout()

func _process(_delta: float) -> void:
	if root != null:
		root.visible = edit_mode or (OS.has_feature("android") and enabled and _is_gameplay_scene())

func _build_overlay() -> void:
	root = Control.new()
	root.name = "MobileTouchOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	dimmer = ColorRect.new()
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.02, 0.02, 0.06, 0.28)
	dimmer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dimmer.visible = false
	root.add_child(dimmer)

	_create_button("left", "move_left_0", "<", false, Color(0.22, 0.23, 0.29, 0.96))
	_create_button("right", "move_right_0", ">", false, Color(0.22, 0.23, 0.29, 0.96))
	_create_button("up", "move_up_0", "^", false, Color(0.22, 0.23, 0.29, 0.96))
	_create_button("down", "move_down_0", "v", false, Color(0.22, 0.23, 0.29, 0.96))
	_create_button("a", "jump_0", "A", true, Color(0.86, 0.18, 0.22, 0.96))
	_create_button("b", "run_0", "B", true, Color(0.94, 0.76, 0.14, 0.96))
	_create_button("x", "spin_jump_0", "X", true, Color(0.18, 0.46, 0.91, 0.96))
	_create_button("y", "dive_0", "Y", true, Color(0.20, 0.72, 0.36, 0.96))
	_create_button("start", "pause", "START", false, Color(0.38, 0.38, 0.46, 0.96))

	edit_help = Label.new()
	edit_help.anchor_left = 0.5
	edit_help.anchor_right = 0.5
	edit_help.offset_left = -180
	edit_help.offset_right = 180
	edit_help.offset_top = 8
	edit_help.offset_bottom = 36
	edit_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	edit_help.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	edit_help.add_theme_font_override("font", PIXEL_FONT)
	edit_help.add_theme_font_size_override("font_size", 15)
	edit_help.add_theme_color_override("font_outline_color", Color.BLACK)
	edit_help.add_theme_constant_override("outline_size", 3)
	edit_help.mouse_filter = Control.MOUSE_FILTER_IGNORE
	edit_help.visible = false
	root.add_child(edit_help)

	save_button = Button.new()
	save_button.anchor_left = 0.5
	save_button.anchor_right = 0.5
	save_button.anchor_top = 1.0
	save_button.anchor_bottom = 1.0
	save_button.offset_left = -72
	save_button.offset_right = 72
	save_button.offset_top = -52
	save_button.offset_bottom = -14
	save_button.add_theme_font_override("font", PIXEL_FONT)
	save_button.add_theme_font_size_override("font_size", 13)
	save_button.visible = false
	save_button.pressed.connect(finish_edit_mode)
	root.add_child(save_button)

func _create_button(id_value: String, action: String, caption: String, face: bool, color: Color) -> void:
	var button := MobileTouchButton68.new()
	button.name = id_value.capitalize()
	button.configure(id_value, action, caption, face, color)
	button.position_changed.connect(_on_button_position_changed)
	root.add_child(button)
	buttons[id_value] = button

func _load_settings() -> void:
	var manager := get_node_or_null("/root/SettingsManager")
	if manager == null:
		return
	var loaded_settings = manager.get("settings_file")
	if not loaded_settings is Dictionary:
		return
	var settings: Dictionary = loaded_settings
	enabled = bool(settings.get("mobile_touch_enabled", settings.get("touch_controls_enabled", true)))
	control_scale = float(settings.get("mobile_touch_scale", 1.0))
	control_opacity = float(settings.get("mobile_touch_opacity", 0.86))
	var stored_layout = settings.get("mobile_touch_layout", {})
	if stored_layout is Dictionary:
		for key in DEFAULT_LAYOUT.keys():
			if stored_layout.has(key) and stored_layout[key] is Array and stored_layout[key].size() >= 2:
				layout[key] = [float(stored_layout[key][0]), float(stored_layout[key][1])]
	_apply_layout()

func apply_mobile_settings(new_enabled: bool, new_scale: float, new_opacity: float) -> void:
	enabled = new_enabled
	control_scale = clamp(new_scale, 0.65, 1.45)
	control_opacity = clamp(new_opacity, 0.35, 1.0)
	_save_settings()
	_apply_layout()

func begin_edit_mode() -> void:
	edit_mode = true
	dimmer.visible = true
	edit_help.text = LanguageManager.text("DRAG THE BUTTONS")
	edit_help.visible = true
	save_button.text = LanguageManager.text("START: SAVE")
	save_button.visible = true
	for button in buttons.values():
		button.set_edit_mode(true)
	root.visible = true
	edit_mode_changed.emit(true)

func finish_edit_mode() -> void:
	if not edit_mode:
		return
	edit_mode = false
	dimmer.visible = false
	edit_help.visible = false
	save_button.visible = false
	for button in buttons.values():
		button.set_edit_mode(false)
	_save_settings()
	edit_mode_changed.emit(false)

func reset_layout() -> void:
	layout = DEFAULT_LAYOUT.duplicate(true)
	_save_settings()
	_apply_layout()

func is_editing() -> bool:
	return edit_mode

func _on_button_position_changed(button_id: String, normalized_position: Vector2) -> void:
	layout[button_id] = [clamp(normalized_position.x, 0.02, 0.98), clamp(normalized_position.y, 0.04, 0.98)]

func _apply_layout() -> void:
	if root == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0:
		return
	for id_value in buttons.keys():
		var button: MobileTouchButton68 = buttons[id_value]
		var is_start := id_value == "start"
		var base_size := Vector2(70, 34) if is_start else Vector2(48, 48)
		if not button.face_button and not is_start:
			base_size = Vector2(42, 42)
		button.size = base_size * control_scale
		button.modulate.a = control_opacity if not edit_mode else 1.0
		var values: Array = layout.get(id_value, DEFAULT_LAYOUT[id_value])
		var center := Vector2(float(values[0]) * viewport_size.x, float(values[1]) * viewport_size.y)
		button.position = center - button.size * 0.5

func _save_settings() -> void:
	var manager := get_node_or_null("/root/SettingsManager")
	if manager == null:
		return
	var loaded_settings = manager.get("settings_file")
	if not loaded_settings is Dictionary:
		return
	manager.settings_file["mobile_touch_enabled"] = enabled
	manager.settings_file["mobile_touch_scale"] = control_scale
	manager.settings_file["mobile_touch_opacity"] = control_opacity
	manager.settings_file["mobile_touch_layout"] = layout.duplicate(true)
	manager.save_settings()

func _is_gameplay_scene() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var path := str(scene.scene_file_path).to_lower()
	for blocked in ["rom_checker", "title_screen", "settings_menu", "keyboard_settings", "language_settings", "save_select", "player_select", "campaign"]:
		if path.contains(blocked):
			return false
	return true

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_GO_BACK_REQUEST:
		for button in buttons.values():
			button.release_action()
