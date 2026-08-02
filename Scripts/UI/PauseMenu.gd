extends Control

@onready var options = [$Box/MarginContainer/Vbox/Label, $Box/MarginContainer/Vbox/Label2, $Box/MarginContainer/Vbox/Label3]
@onready var arrow: TextureRect = $Arrow
@onready var box: NinePatchRect = $Box
@onready var option_container: VBoxContainer = $Box/MarginContainer/Vbox

var selected_index := 0
var can_select := true
var valid_choices := [true, true, true]
var can_quit := false
var can_restart := false


func _ready() -> void:
	var language_manager := get_node_or_null("/root/LanguageManager")
	if language_manager != null and not language_manager.language_changed.is_connected(_on_language_changed):
		language_manager.language_changed.connect(_on_language_changed)
	call_deferred("_fit_menu_box")
	_update_arrow_position()


func _process(_delta: float) -> void:
	visible = GameManager.game_paused
	if not is_instance_valid(GameManager.current_level) or not is_instance_valid(CoopManager.get_first_any_player()) or not GameManager.can_pause:
		return

	selected_index = clamp(selected_index, 0, options.size() - 1)
	can_quit = players_grounded_check()
	can_restart = players_grounded_check() and more_than_one_life_check()
	valid_choices[2] = can_quit
	valid_choices[1] = can_restart

	if GameManager.game_paused and can_select:
		if Input.is_action_just_pressed("ui_down"):
			selected_index = min(selected_index + 1, options.size() - 1)
			SoundManager.play_ui_sound(SoundManager.select)
		elif Input.is_action_just_pressed("ui_up"):
			selected_index = max(selected_index - 1, 0)
			SoundManager.play_ui_sound(SoundManager.select)
		if Input.is_action_just_pressed("ui_accept"):
			option_selected()

	_update_arrow_position()
	for index in options.size():
		options[index].modulate = Color.WEB_GRAY if not valid_choices[index] else Color.WHITE

	if Input.is_action_just_pressed("pause"):
		pause_toggle()


func _fit_menu_box() -> void:
	if not is_instance_valid(box) or not is_instance_valid(option_container):
		return
	await get_tree().process_frame
	# Use the float-specific helpers here. Generic max()/min() return Variant in
	# Godot 4.7, and this project treats inferred Variant warnings as errors.
	var content_size: Vector2 = option_container.get_combined_minimum_size()
	var viewport_width: float = get_viewport_rect().size.x
	var wanted_width: float = maxf(156.0, content_size.x + 32.0)
	wanted_width = minf(wanted_width, maxf(156.0, viewport_width - 24.0))
	var wanted_height: float = maxf(84.0, content_size.y + 20.0)
	box.offset_left = -floorf(wanted_width * 0.5)
	box.offset_right = ceilf(wanted_width * 0.5)
	box.offset_top = -floorf(wanted_height * 0.5)
	box.offset_bottom = ceilf(wanted_height * 0.5)
	call_deferred("_update_arrow_position")


func _on_language_changed(_code: String) -> void:
	call_deferred("_fit_menu_box")


func _update_arrow_position() -> void:
	if options.is_empty():
		return
	selected_index = clamp(selected_index, 0, options.size() - 1)
	var option: Control = options[selected_index]
	if not is_instance_valid(option) or not is_instance_valid(arrow):
		return
	# Derive both axes from the selected label so the pointer remains beside the
	# centered menu on 16:9, widescreen and ultrawide displays.
	arrow.global_position = Vector2(
		option.global_position.x - arrow.size.x - 4.0,
		option.global_position.y + (option.size.y - arrow.size.y) * 0.5
	)


func pause_toggle() -> void:
	if get_tree().paused:
		if GameManager.game_paused:
			resume_game()
	elif not GameManager.game_paused:
		pause_game()


func players_grounded_check() -> bool:
	for i in CoopManager.alive_players.values():
		if is_instance_valid(i):
			if not i.is_on_floor() and not i.is_on_wall():
				return false
	return true


func more_than_one_life_check() -> bool:
	return GameManager.lives > 0


func option_selected() -> void:
	if can_select:
		can_select = false
	else:
		return
	if not valid_choices[selected_index]:
		can_select = true
		SoundManager.play_ui_sound(SoundManager.wrong)
		return
	SoundManager.play_ui_sound(SoundManager.correct)
	await select_animation(options[selected_index])
	do_option()
	selected_index = 0


func resume_game() -> void:
	GameManager.game_paused = false
	get_tree().paused = false


func pause_game() -> void:
	SoundManager.play_ui_sound("res://Assets/Audio/SFX/pause.wav")
	GameManager.game_paused = true
	get_tree().paused = true
	can_select = true
	call_deferred("_fit_menu_box")
	call_deferred("_update_arrow_position")


func do_option() -> void:
	match selected_index:
		0:
			resume_game()
		1:
			MusicPlayer.stop_level_music()
			for i in 4:
				CoopManager.player_power_states[i] = CoopManager.SMALL
				CoopManager.player_yoshis[i] = false
			GameManager.reset_values()
			TransitionManager.transition_to_level(GameManager.starting_level_path, GameManager.current_level, false)
			GameManager.game_paused = false
		2:
			MusicPlayer.stop_level_music()
			GameManager.reset_values()
			if GameManager.playing_custom_level:
				TransitionManager.transition_to_menu(GameManager.CUSTOM_LEVEL_SELECT, GameManager.current_level)
			elif check_drag_coins() and not SaveManager.current_save.peach_coins_unlocked:
				TransitionManager.transition_to_level("res://Instances/Levels/Cutscenes/all_dragon_coins_cutscene.tscn", GameManager.current_level)
			else:
				TransitionManager.transition_to_map(GameManager.current_map_path, GameManager.current_level, false)
			GameManager.game_paused = false


const drag_coins := ["res://Resources/Achievements/Completionist/DragCoins/BVDragCoin.tres", "res://Resources/Achievements/Completionist/DragCoins/CIDragCoin.tres", "res://Resources/Achievements/Completionist/DragCoins/DPDragCoin.tres", "res://Resources/Achievements/Completionist/DragCoins/IFDragCoin.tres", "res://Resources/Achievements/Completionist/DragCoins/SPDragCoin.tres", "res://Resources/Achievements/Completionist/DragCoins/SRDragCoin.tres", "res://Resources/Achievements/Completionist/DragCoins/TBDragCoin.tres", "res://Resources/Achievements/Completionist/DragCoins/VDDragCoin.tres", "res://Resources/Achievements/Completionist/DragCoins/YIDragCoin.tres"]


func check_drag_coins() -> bool:
	for i in drag_coins:
		if not SaveManager.current_save.achievements_unlocked.has(i):
			return false
	return true


func select_animation(option) -> void:
	for i in 5:
		option.modulate.a = 0
		await get_tree().create_timer(0.05).timeout
		option.modulate.a = 1
		await get_tree().create_timer(0.05).timeout
