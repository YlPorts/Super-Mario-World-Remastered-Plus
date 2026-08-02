extends SettingsSection
## Fixed two-language selector for desktop and Android builds.
## Community language discovery is intentionally not exposed in the UI.

const SELECTOR_FONT_PATH := "res://Assets/Fonts/PixelifySans.ttf"
const LANGUAGE_CODES: Array[String] = ["en", "es"]
const LANGUAGE_NAMES: Array[String] = ["ENGLISH", "ESPAÑOL"]

var selector_font: Font

@onready var heading: Label = $VBoxContainer/Heading
@onready var value: Label = $VBoxContainer/LanguageRow/Value
@onready var left_arrow: Label = $VBoxContainer/LanguageRow/Left
@onready var right_arrow: Label = $VBoxContainer/LanguageRow/Right
@onready var help: Label = $VBoxContainer/Help

func _ready() -> void:
	title = "Language"
	_load_selector_font()
	_apply_selector_font()
	set_option_node_values()
	_refresh_labels()

func _load_selector_font() -> void:
	var resource := load(SELECTOR_FONT_PATH)
	if resource is Font:
		selector_font = resource as Font
	else:
		selector_font = null
		push_warning("[LANG70] Selector font is unavailable: %s" % SELECTOR_FONT_PATH)

func _physics_process(_delta: float) -> void:
	if not selected:
		return
	var changed := false
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("move_left_0"):
		selected_index = wrap(selected_index - 1, 0, LANGUAGE_CODES.size())
		changed = true
	elif Input.is_action_just_pressed("ui_right") or Input.is_action_just_pressed("move_right_0"):
		selected_index = wrap(selected_index + 1, 0, LANGUAGE_CODES.size())
		changed = true
	if changed:
		SoundManager.play_ui_sound(SoundManager.select)
	_refresh_labels()

func set_option_node_values() -> void:
	var selected_code := str(SettingsManager.settings_file.get("language", "en")).to_lower()
	selected_index = LANGUAGE_CODES.find(selected_code)
	if selected_index < 0:
		selected_index = 0
	_refresh_labels()

func get_chosen_options() -> Dictionary:
	selected_index = clamp(selected_index, 0, LANGUAGE_CODES.size() - 1)
	return {"language": LANGUAGE_CODES[selected_index]}

func _apply_selector_font() -> void:
	if selector_font == null:
		return
	for label in [heading, value, left_arrow, right_arrow, help]:
		label.add_theme_font_override("font", selector_font)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 2)
	heading.add_theme_font_size_override("font_size", 18)
	value.add_theme_font_size_override("font_size", 20)
	left_arrow.add_theme_font_size_override("font_size", 20)
	right_arrow.add_theme_font_size_override("font_size", 20)
	help.add_theme_font_size_override("font_size", 12)

func _refresh_labels() -> void:
	if not is_instance_valid(heading):
		return
	selected_index = clamp(selected_index, 0, LANGUAGE_CODES.size() - 1)
	heading.text = LanguageManager.text("Language").to_upper()
	value.text = LANGUAGE_NAMES[selected_index]
	help.text = LanguageManager.text("LEFT/RIGHT: CHANGE LANGUAGE") + "    " + LanguageManager.text("START/ENTER: APPLY")
	left_arrow.text = "<"
	right_arrow.text = ">"
	left_arrow.modulate = Color.WHITE
	right_arrow.modulate = Color.WHITE

func blocks_parent_input() -> bool:
	return false
