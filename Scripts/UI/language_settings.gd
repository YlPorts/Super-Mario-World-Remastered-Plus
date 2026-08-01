extends SettingsSection

var language_codes: Array[String] = []
var language_names: Array[String] = []

@onready var heading: Label = $VBoxContainer/Heading
@onready var value: Label = $VBoxContainer/LanguageRow/Value
@onready var left_arrow: Label = $VBoxContainer/LanguageRow/Left
@onready var right_arrow: Label = $VBoxContainer/LanguageRow/Right
@onready var help: Label = $VBoxContainer/Help


func _ready() -> void:
	title = "Language"
	set_option_node_values()
	_refresh_labels()


func _physics_process(_delta: float) -> void:
	if not selected or language_codes.is_empty():
		return
	var changed := false
	if Input.is_action_just_pressed("move_left_0"):
		selected_index = wrap(selected_index - 1, 0, language_codes.size())
		changed = true
	elif Input.is_action_just_pressed("move_right_0"):
		selected_index = wrap(selected_index + 1, 0, language_codes.size())
		changed = true
	if changed:
		SoundManager.play_ui_sound(SoundManager.select)
	_refresh_labels()


func set_option_node_values() -> void:
	language_codes.clear()
	language_names.clear()
	for record in LanguageManager.get_available_languages():
		language_codes.append(str(record["code"]))
		language_names.append(str(record["name"]))
	var selected_code := str(SettingsManager.settings_file.get("language", "en"))
	selected_index = language_codes.find(selected_code)
	if selected_index < 0:
		selected_index = 0
	_refresh_labels()


func get_chosen_options() -> Dictionary:
	if language_codes.is_empty():
		return {"language": "en"}
	return {"language": language_codes[selected_index]}


func _refresh_labels() -> void:
	if not is_instance_valid(heading):
		return
	heading.text = LanguageManager.text("Available Languages")
	help.text = LanguageManager.text("LEFT/RIGHT: CHANGE LANGUAGE") + "    " + LanguageManager.text("START/ENTER: APPLY")
	if language_names.is_empty():
		value.text = "English"
	else:
		selected_index = clamp(selected_index, 0, language_names.size() - 1)
		value.text = language_names[selected_index]
	left_arrow.modulate.a = 1.0 if language_names.size() > 1 else 0.0
	right_arrow.modulate.a = left_arrow.modulate.a


func blocks_parent_input() -> bool:
	return false
