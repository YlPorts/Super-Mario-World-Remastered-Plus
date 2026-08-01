extends SettingsSection

const HUD_FONT = preload("res://Assets/Sprites/UI/HUD/HUDFont.png")
const CAPTURE_BLOCK_MS := 250

var action_rows: Array[HBoxContainer] = []
var action_labels: Array[Label] = []
var key_labels: Array[Label] = []
var listening_for_key := false
var suppress_parent_until := 0
var help_label: Label
var reset_row: HBoxContainer

@onready var list_container: VBoxContainer = $VBoxContainer

func _ready() -> void:
	title = "Controls"
	_build_interface()
	set_process_input(true)
	_refresh_rows()

func _build_interface() -> void:
	for child in list_container.get_children():
		child.queue_free()

	help_label = Label.new()
	help_label.add_theme_font_override("font", HUD_FONT)
	help_label.text = "UP/DOWN: SELECT    ENTER/SPACE: CHANGE KEY"
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.custom_minimum_size = Vector2(0, 20)
	list_container.add_child(help_label)

	for entry in SettingsManager.REBINDABLE_KEYBOARD_ACTIONS:
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 18)
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		list_container.add_child(row)

		var action_label := Label.new()
		action_label.add_theme_font_override("font", HUD_FONT)
		action_label.text = str(entry["label"]).to_upper()
		action_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(action_label)

		var key_label := Label.new()
		key_label.add_theme_font_override("font", HUD_FONT)
		key_label.custom_minimum_size = Vector2(120, 0)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(key_label)

		action_rows.append(row)
		action_labels.append(action_label)
		key_labels.append(key_label)

	reset_row = HBoxContainer.new()
	reset_row.custom_minimum_size = Vector2(0, 22)
	reset_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_container.add_child(reset_row)
	var reset_label := Label.new()
	reset_label.add_theme_font_override("font", HUD_FONT)
	reset_label.text = "RESTORE DEFAULT KEYS"
	reset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reset_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_row.add_child(reset_label)

func _physics_process(_delta: float) -> void:
	if not selected:
		_refresh_rows()
		return
	if listening_for_key:
		_refresh_rows()
		return

	var row_count := action_rows.size() + 1
	if Input.is_action_just_pressed("ui_down"):
		selected_index = min(selected_index + 1, row_count - 1)
		SoundManager.play_ui_sound(SoundManager.select)
	elif Input.is_action_just_pressed("ui_up"):
		selected_index = max(selected_index - 1, 0)
		SoundManager.play_ui_sound(SoundManager.select)

	if Input.is_action_just_pressed("ui_accept"):
		if selected_index == action_rows.size():
			SettingsManager.reset_keyboard_bindings()
			SoundManager.play_ui_sound(SoundManager.coin)
			suppress_parent_until = Time.get_ticks_msec() + CAPTURE_BLOCK_MS
		else:
			listening_for_key = true
			help_label.text = "PRESS A NEW KEY    ESC: CANCEL"
			SoundManager.play_ui_sound(SoundManager.select)

	selected_index = clamp(selected_index, 0, row_count - 1)
	_refresh_rows()
	_ensure_selected_visible()

func _input(event: InputEvent) -> void:
	if not listening_for_key:
		return
	if not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	get_viewport().set_input_as_handled()
	if key_event.keycode == KEY_ESCAPE or key_event.physical_keycode == KEY_ESCAPE:
		listening_for_key = false
		suppress_parent_until = Time.get_ticks_msec() + CAPTURE_BLOCK_MS
		help_label.text = "KEY CHANGE CANCELLED"
		SoundManager.play_ui_sound(SoundManager.wrong)
		_refresh_rows()
		return

	var keycode := int(key_event.physical_keycode)
	if keycode == 0:
		keycode = int(key_event.keycode)
	if keycode <= 0:
		return

	var entry = SettingsManager.REBINDABLE_KEYBOARD_ACTIONS[selected_index]
	SettingsManager.set_keyboard_binding(str(entry["action"]), keycode)
	listening_for_key = false
	suppress_parent_until = Time.get_ticks_msec() + CAPTURE_BLOCK_MS
	help_label.text = "KEY SAVED    ENTER/SPACE: CHANGE ANOTHER"
	SoundManager.play_ui_sound(SoundManager.correct)
	_refresh_rows()

func _refresh_rows() -> void:
	for index in action_rows.size():
		var entry = SettingsManager.REBINDABLE_KEYBOARD_ACTIONS[index]
		key_labels[index].text = SettingsManager.get_keyboard_key_name(str(entry["action"])).to_upper()
		var highlighted := selected and selected_index == index
		action_rows[index].modulate = Color.YELLOW if highlighted else Color.WHITE
		if listening_for_key and highlighted:
			key_labels[index].text = "PRESS KEY..."
			key_labels[index].modulate = Color(1.0, 0.65, 0.2)
		else:
			key_labels[index].modulate = Color.WHITE

	if is_instance_valid(reset_row):
		reset_row.modulate = Color.YELLOW if selected and selected_index == action_rows.size() else Color.WHITE

func _ensure_selected_visible() -> void:
	var target: Control = reset_row if selected_index == action_rows.size() else action_rows[selected_index]
	if is_instance_valid(target):
		scroll_vertical = max(0, int(target.position.y) - 70)

func is_waiting_for_key() -> bool:
	return listening_for_key

func blocks_parent_input() -> bool:
	return listening_for_key or Time.get_ticks_msec() < suppress_parent_until

func set_option_node_values() -> void:
	_refresh_rows()

func get_chosen_options() -> Dictionary:
	return {}
