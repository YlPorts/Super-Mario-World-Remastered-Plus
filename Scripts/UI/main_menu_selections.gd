extends Control

signal option_1_selected
signal option_2_selected
signal option_3_selected
signal option_4_selected
signal option_5_selected
signal option_6_selected


@export var options: Array[String] = []
@export var option_colours: Array[Color] = []
@export var can_exit := false

var active := false

@export var initial_active := false
signal menu_exited

var selected_index := 0

var option_nodes := []

func _ready() -> void:
	# The original 132 px column was too narrow even for several English labels
	# and made Spanish labels spill outside the title layout. Keep it centered but
	# give every language a 264 px safe text column.
	$VBoxContainer.anchor_left = 0.5
	$VBoxContainer.anchor_right = 0.5
	$VBoxContainer.offset_left = -132.0
	$VBoxContainer.offset_right = 132.0
	for i in options.size():
		if options[i] != "":
			add_option_node(options[i], option_colours[i])
	$VBoxContainer/Selection1.queue_free()
	if initial_active:
		open_menu()
	else:
		close_menu()

func add_option_node(option := "", color := Color.WHITE) -> void:
	var option_node = $VBoxContainer/Selection1.duplicate()
	# Keep the English source here. LanguageManager translates it after the node
	# enters the tree and can always restore it when switching languages.
	option_node.get_node("BaseLabel").text = option
	option_node.get_node("BaseLabel").modulate = color
	option_nodes.append(option_node)
	$VBoxContainer.add_child(option_node)

func _process(_delta: float) -> void:
	handle_selections()

func handle_selections() -> void:
	if active:
		if Input.is_action_just_pressed("ui_down"):
			selected_index += 1
		if Input.is_action_just_pressed("ui_up"):
			selected_index -= 1
		if can_exit:
			if Input.is_action_just_pressed("ui_back"):
				exit()
	selected_index = clamp(selected_index, 0, option_nodes.size() - 1)
	for i in option_nodes:
		i.get_node("TextureRect").modulate.a = 1 if option_nodes[selected_index] == i else 0
	if active:
		if Input.is_action_just_pressed("ui_accept"):
			SoundManager.play_ui_sound(SoundManager.coin)
			emit_signal("option_" + str(selected_index + 1) + "_selected")

func open_menu() -> void:
	show()
	await get_tree().physics_frame
	active = true

func exit() -> void:
	SoundManager.play_ui_sound(SoundManager.fireball)
	close_menu()
	menu_exited.emit()

func close_menu() -> void:
	hide()
	active = false
