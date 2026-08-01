extends Level

var selected_index := 0
@export var sections: Array[SettingsSection] = []
var current_section: SettingsSection = null

func _ready() -> void:
	MusicPlayer.update_song_label("Mario Kart DS - Options Menu", "Fyre150")
	get_viewport().size_changed.connect(_adapt_widescreen_layout)
	_adapt_widescreen_layout()
	await get_tree().process_frame
	_sync_current_section()
	set_starting_values()

func _physics_process(_delta: float) -> void:
	_sync_current_section()
	if _current_section_blocks_parent_input():
		$TitleHeader/SettingsHeader.text = current_section.title
		return

	if Input.is_action_just_pressed("ui_tab_left"):
		selected_index -= 1
		SoundManager.play_ui_sound(SoundManager.select)
	elif Input.is_action_just_pressed("ui_tab_right"):
		selected_index += 1
		SoundManager.play_ui_sound(SoundManager.select)

	if Input.is_action_just_pressed("debug_clear"):
		SettingsManager.settings_file = SettingsManager.settings_template.duplicate(true)
		SoundManager.play_ui_sound(SoundManager.cape_fly)
		SettingsManager.save_settings()
		SettingsManager.apply_settings(SettingsManager.get_file())
		set_starting_values()

	_sync_current_section()
	$TitleHeader/SettingsHeader.text = current_section.title

	if Input.is_action_just_pressed("apply_settings"):
		apply_settings()
	if Input.is_action_just_pressed("ui_back"):
		TransitionManager.transition_to_menu("res://Instances/UI/Menus/title_screen.tscn", self)

func _sync_current_section() -> void:
	if sections.is_empty():
		return
	selected_index = wrap(selected_index, 0, sections.size())
	for section in sections:
		section.visible = sections[selected_index] == section
		section.selected = section.visible
		if section.visible:
			current_section = section

func _current_section_blocks_parent_input() -> bool:
	if current_section == null:
		return false
	if current_section.has_method("blocks_parent_input"):
		return current_section.blocks_parent_input()
	return false

func set_starting_values() -> void:
	for i in sections:
		i.set_option_node_values()

func apply_settings() -> void:
	# AndroidSettings intentionally does not exist in the Windows branch.
	for i in [$DisplaySettings, $AudioSettings, $GameplaySettings, $AbilitySettings]:
		var options = i.get_chosen_options()
		for x in options.keys():
			SettingsManager.settings_file[x] = options[x]
	SettingsManager.settings_file["sprite_settings"] = $SpriteSettings.get_chosen_options()
	SoundManager.play_ui_sound(SoundManager.coin)
	SettingsManager.apply_settings(SettingsManager.settings_file)
	SettingsManager.save_settings()

func _adapt_widescreen_layout() -> void:
	# Keep the header aligned to the viewport edges when EXPAND reveals more
	# horizontal game space on ultrawide displays.
	$TitleHeader.anchor_left = 0.0
	$TitleHeader.anchor_right = 1.0
	$TitleHeader.offset_left = 16.0
	$TitleHeader.offset_right = -16.0
	$HSeparator.anchor_left = 0.5
	$HSeparator.anchor_right = 0.5
	$HSeparator.offset_left = -56.0
	$HSeparator.offset_right = 56.0
