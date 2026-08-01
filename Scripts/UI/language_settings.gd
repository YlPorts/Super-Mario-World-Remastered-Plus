extends SettingsSection

const LANGUAGE_CODES := ["en", "es"]
const LANGUAGE_NAMES := ["ENGLISH", "ESPAÑOL"]

@onready var heading: Label = $VBoxContainer/Heading
@onready var english_label: Label = $VBoxContainer/LanguageRow/English
@onready var spanish_label: Label = $VBoxContainer/LanguageRow/Spanish
@onready var left_arrow: Label = $VBoxContainer/LanguageRow/Left
@onready var right_arrow: Label = $VBoxContainer/LanguageRow/Right

func _ready() -> void:
	title = "Language"
	set_option_node_values()
	_refresh_labels()

func _physics_process(_delta: float) -> void:
	if not selected:
		return
	var changed := false
	if Input.is_action_just_pressed("move_left_0") or Input.is_action_just_pressed("ui_left"):
		selected_index = 0
		changed = true
	elif Input.is_action_just_pressed("move_right_0") or Input.is_action_just_pressed("ui_right"):
		selected_index = 1
		changed = true
	if changed:
		SoundManager.play_ui_sound(SoundManager.select)
		_refresh_labels()

func set_option_node_values() -> void:
	var selected_code := str(SettingsManager.settings_file.get("language", "en"))
	selected_index = LANGUAGE_CODES.find(selected_code)
	if selected_index < 0:
		selected_index = 0
	_refresh_labels()

func get_chosen_options() -> Dictionary:
	return {"language": LANGUAGE_CODES[clampi(selected_index, 0, 1)]}

func _refresh_labels() -> void:
	if not is_instance_valid(heading):
		return
	heading.text = LanguageManager.text("Language").to_upper()
	english_label.text = LANGUAGE_NAMES[0]
	spanish_label.text = LANGUAGE_NAMES[1]
	english_label.modulate = Color(1.0, 0.92, 0.25) if selected_index == 0 else Color(0.72, 0.72, 0.78)
	spanish_label.modulate = Color(1.0, 0.92, 0.25) if selected_index == 1 else Color(0.72, 0.72, 0.78)
	left_arrow.modulate.a = 1.0 if selected_index == 1 else 0.35
	right_arrow.modulate.a = 1.0 if selected_index == 0 else 0.35

func blocks_parent_input() -> bool:
	return false
