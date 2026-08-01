extends Control
@onready var pointer: CenterContainer = $Pointer
@onready var animations: AnimationPlayer = $Animations
@onready var heading: Label = $Label

@onready var panels = [$"HBoxContainer/1Player", $"HBoxContainer/2Player", $"HBoxContainer/3Player", $"HBoxContainer/4Player"]

var selected_index := 0
var active := false

signal selected
signal cancelled

func _ready() -> void:
	# The old 136 px title area clipped English and pushed accented Spanish
	# glyphs above the frame. Use a centered 300 px area with a safe top margin.
	heading.anchor_left = 0.5
	heading.anchor_right = 0.5
	heading.offset_left = -150.0
	heading.offset_right = 150.0
	heading.offset_top = 8.0
	heading.offset_bottom = 34.0
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

func open() -> void:
	show()
	await get_tree().create_timer(0.25).timeout
	active = true

func _process(_delta: float) -> void:
	if not active:
		return
	if Input.is_action_just_pressed("ui_left"):
		selected_index -= 1
		SoundManager.play_ui_sound(SoundManager.select)
	if Input.is_action_just_pressed("ui_right"):
		selected_index += 1
		SoundManager.play_ui_sound(SoundManager.select)
	selected_index = clamp(selected_index, 0, 3)
	if Input.is_action_just_pressed("ui_accept"):
		selected_amount()
	if Input.is_action_just_pressed("ui_back"):
		cancel()
	pointer.global_position.x = panels[selected_index].global_position.x + 40.5
	var panel_index := 0
	for i in panels:
		i.global_position.y = 103
		if panel_index == selected_index:
			i.global_position.y = 85
		panel_index += 1

func selected_amount() -> void:
	SoundManager.play_ui_sound(SoundManager.coin)
	CoopManager.players_connected = selected_index + 1
	selected.emit()
	exit()

func cancel() -> void:
	exit()
	SoundManager.play_ui_sound(SoundManager.fireball)
	cancelled.emit()

func exit() -> void:
	hide()
	active = false


func _on_save_select_closed() -> void:
	pass # Replace with function body.
