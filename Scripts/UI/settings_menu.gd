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
		$TitleHeader/SettingsHeader.text = LanguageManager.text(current_section.title)
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
	$TitleHeader/SettingsHeader.text = LanguageManager.text(current_section.title)

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
	for i in [$DisplaySettings, $AudioSettings, $GameplaySettings, $LanguageSettings, $AbilitySettings]:
		var options = i.get_chosen_options()
		for x in options.keys():
			SettingsManager.settings_file[x] = options[x]
	SettingsManager.settings_file["sprite_settings"] = $SpriteSettings.get_chosen_options()
	SoundManager.play_ui_sound(SoundManager.coin)
	SettingsManager.apply_settings(SettingsManager.settings_file)
	SettingsManager.save_settings()

func _adapt_widescreen_layout() -> void:
	# Keep every options page centered and give the title/value rows a little
	# more horizontal room. The previous asymmetric 10%-88.3% area made long
	# English and Spanish labels collide with their values.
	for section in sections:
		if is_instance_valid(section):
			section.anchor_left = 0.08
			section.anchor_right = 0.92
			section.offset_left = 0.0
			section.offset_right = 0.0

	$TitleHeader.anchor_left = 0.0
	$TitleHeader.anchor_right = 1.0
	$TitleHeader.offset_left = 16.0
	$TitleHeader.offset_right = -16.0
	$HSeparator.anchor_left = 0.5
	$HSeparator.anchor_right = 0.5
	$HSeparator.offset_left = -56.0
	$HSeparator.offset_right = 56.0

	# These credits were positioned at y=1 and one extended beyond the right
	# edge, so fullscreen clipped the upper half of both lines. Keep them fully
	# inside the frame and correct the original Bowser typo.
	$Label3.anchor_left = 0.0
	$Label3.anchor_top = 0.0
	$Label3.anchor_right = 0.0
	$Label3.anchor_bottom = 0.0
	$Label3.offset_left = 10.0
	$Label3.offset_top = 5.0
	$Label3.offset_right = 220.0
	$Label3.offset_bottom = 19.0
	$Label3.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT

	$Label4.anchor_left = 1.0
	$Label4.anchor_top = 0.0
	$Label4.anchor_right = 1.0
	$Label4.anchor_bottom = 0.0
	$Label4.offset_left = -220.0
	$Label4.offset_top = 5.0
	$Label4.offset_right = -10.0
	$Label4.offset_bottom = 19.0
	$Label4.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	$Label4.text = "Mod created by Bowser"

	$Label2.offset_left = -240.0
	$Label2.offset_right = -10.0
	$Label2.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
