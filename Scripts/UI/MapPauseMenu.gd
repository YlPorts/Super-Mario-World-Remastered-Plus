extends Control

@onready var options = [$Box/MarginContainer/Vbox/Label, $Box/MarginContainer/Vbox/PlayerSetup, $Box/MarginContainer/Vbox/Save, $Box/MarginContainer/Vbox/Label3]
@onready var arrow: TextureRect = $Arrow

var selected_index := 0
var can_select := true
signal player_setup_selected

func _ready() -> void:
	get_tree().paused = false
	GameManager.game_paused = false
	hide()
	_update_arrow_position()

func _process(_delta: float) -> void:
	selected_index = clamp(selected_index, 0, options.size() - 1)
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
	if Input.is_action_just_pressed("pause"):
		pause_toggle()

func _update_arrow_position() -> void:
	if options.is_empty():
		return
	selected_index = clamp(selected_index, 0, options.size() - 1)
	var option: Control = options[selected_index]
	if not is_instance_valid(option) or not is_instance_valid(arrow):
		return
	arrow.global_position = Vector2(
		option.global_position.x - arrow.size.x - 4.0,
		option.global_position.y + (option.size.y - arrow.size.y) * 0.5
	)

func pause_toggle() -> void:
	if get_tree().paused:
		if GameManager.game_paused:
			resume_game()
	elif not GameManager.game_paused and GameManager.can_pause and GameManager.current_map.can_move:
		pause_game()

func option_selected() -> void:
	if can_select:
		can_select = false
	else:
		return
	SoundManager.play_ui_sound(SoundManager.correct)
	await select_animation(options[selected_index])
	do_option()

func resume_game() -> void:
	selected_index = 0
	GameManager.game_paused = false
	get_tree().paused = false
	hide()

func pause_game() -> void:
	GameManager.game_paused = true
	get_tree().paused = true
	can_select = true
	show()
	call_deferred("_update_arrow_position")

func do_option() -> void:
	match selected_index:
		0:
			resume_game()
		1:
			player_setup_selected.emit()
			get_tree().paused = false
			await $CharacterSelect.finished
			resume_game()
			TransitionManager.transition_to_map(GameManager.current_map_path, GameManager.current_map, false, GameManager.map_point_save)
		2:
			SaveManager.save_current_file()
			resume_game()
		3:
			if OnlineManager.in_multiplayer_game:
				multiplayer.multiplayer_peer.close()
				get_tree().set_multiplayer(null)
			MusicPlayer.map.stop()
			GameManager.current_map_area = null
			TransitionManager.transition_to_menu(TransitionManager.TITLE_SCREEN, GameManager.current_map)
			GameManager.game_paused = false

func select_animation(option) -> void:
	for i in 5:
		option.modulate.a = 0
		await get_tree().create_timer(0.05).timeout
		option.modulate.a = 1
		await get_tree().create_timer(0.05).timeout
