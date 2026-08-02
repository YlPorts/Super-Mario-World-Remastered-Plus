extends SettingsSection
## Optional two-step unlock button shared by desktop and Android settings.

const UI_FONT_PATH := "res://Assets/Fonts/PixelifySans.ttf"
const CONFIRMATION_TIME_MS := 3500

var ui_font: Font
var awaiting_confirmation := false
var confirmation_deadline := 0

@onready var heading: Label = $VBoxContainer/Heading
@onready var description: Label = $VBoxContainer/Description
@onready var unlock_button: Button = $VBoxContainer/UnlockButton
@onready var status: Label = $VBoxContainer/Status


func _ready() -> void:
	title = "Unlocks"
	_load_font()
	_apply_font()
	unlock_button.pressed.connect(_on_unlock_pressed)

	var unlock_manager := get_node_or_null("/root/UnlockManager")
	if unlock_manager != null and unlock_manager.has_signal("unlock_state_changed"):
		unlock_manager.unlock_state_changed.connect(_on_unlock_state_changed)

	var language_manager := get_node_or_null("/root/LanguageManager")
	if language_manager != null and language_manager.has_signal("language_changed"):
		language_manager.language_changed.connect(_on_language_changed)

	_refresh_labels()


func _process(_delta: float) -> void:
	if awaiting_confirmation and Time.get_ticks_msec() > confirmation_deadline:
		awaiting_confirmation = false
		status.text = ""


func _physics_process(_delta: float) -> void:
	if not selected:
		return
	if Input.is_action_just_pressed("apply_settings") or Input.is_action_just_pressed("ui_accept"):
		_request_or_confirm()


func set_option_node_values() -> void:
	_refresh_labels()


func get_chosen_options() -> Dictionary:
	return {}


func blocks_parent_input() -> bool:
	return false


func _load_font() -> void:
	var resource := load(UI_FONT_PATH)
	if resource is Font:
		ui_font = resource as Font


func _apply_font() -> void:
	if ui_font == null:
		return
	for control in [heading, description, unlock_button, status]:
		control.add_theme_font_override("font", ui_font)
		control.add_theme_color_override("font_outline_color", Color.BLACK)
		control.add_theme_constant_override("outline_size", 2)
	heading.add_theme_font_size_override("font_size", 18)
	description.add_theme_font_size_override("font_size", 11)
	unlock_button.add_theme_font_size_override("font_size", 15)
	status.add_theme_font_size_override("font_size", 11)


func _refresh_labels() -> void:
	if not is_instance_valid(heading):
		return
	heading.text = LanguageManager.text("Unlocks").to_upper()
	description.text = LanguageManager.text("Unlock every level, route, bonus and achievement in the next save you load.")
	unlock_button.text = LanguageManager.text("Unlock Everything").to_upper()
	unlock_button.tooltip_text = LanguageManager.text("Press Start/Enter or tap the button.")
	if awaiting_confirmation:
		status.text = LanguageManager.text("Press again to confirm")


func _request_or_confirm() -> void:
	if not awaiting_confirmation:
		awaiting_confirmation = true
		confirmation_deadline = Time.get_ticks_msec() + CONFIRMATION_TIME_MS
		status.text = LanguageManager.text("Press again to confirm")
		SoundManager.play_ui_sound(SoundManager.select)
		return

	awaiting_confirmation = false
	var unlock_manager := get_node_or_null("/root/UnlockManager")
	if unlock_manager == null or not unlock_manager.has_method("request_unlock_everything"):
		status.text = LanguageManager.text("Could not unlock this save")
		SoundManager.play_ui_sound(SoundManager.wrong)
		return

	SoundManager.play_ui_sound(SoundManager.coin)
	var applied_now: bool = bool(unlock_manager.request_unlock_everything())
	status.text = LanguageManager.text("Everything unlocked" if applied_now else "Waiting for a save file...")


func _on_unlock_pressed() -> void:
	_request_or_confirm()


func _on_unlock_state_changed(message: String) -> void:
	status.text = LanguageManager.text(message)


func _on_language_changed(_code: String) -> void:
	_refresh_labels()
