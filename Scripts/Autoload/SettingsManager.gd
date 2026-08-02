extends Node

var sprite_settings := {
	"bobomb": 0,
	"bonybeetle": 0,
	"bowser": 0,
	"buzzybeetleshell": 0,
	"drybones": 0,
	"fishbone": 0,
	"galoomba": 0,
	"koopalings": 0,
	"luigi": 0,
	"muncher": 0,
	"peach": 0,
	"pidget": 0,
	"podoboo": 0,
	"spiketop": 0,
	"spiny": 0,
	"yoshi": 0,
	"magikoopa": 0,
	"yoshiswim": 0,
	"yoshiturn": 0,
	"bowserflame": 0,
	"fireball": 0,
	"bubble": 0,
	"snakeblock": 0,
	"coloured_switch_empty": 0,
	"iceblock": 0,
	"coin": 0,
	"motor": 0,
	"onoffswitch": 0,
	"pswitch": 0,
	"door": 0,
	"tileset_colour_style": 0,
	"parachute": 0,
	"lakitucloud": 0,
	"1up": 0,
	"yoshi_berry": 0,
	"signpost": 0,
	"chain_chomp": 0,
	"spike": 0,
	"blooper": 0,
	"angry_sun": 0
}

# Keyboard actions exposed in Options > Controls. Controller events remain
# untouched; only InputEventKey entries are replaced.
const REBINDABLE_KEYBOARD_ACTIONS := [
	{"action": "move_left_0", "label": "Move Left"},
	{"action": "move_right_0", "label": "Move Right"},
	{"action": "move_up_0", "label": "Move Up"},
	{"action": "move_down_0", "label": "Move Down"},
	{"action": "jump_0", "label": "Jump"},
	{"action": "run_0", "label": "Run / Grab"},
	{"action": "spin_jump_0", "label": "Spin Jump"},
	{"action": "dive_0", "label": "Dive"},
	{"action": "pause", "label": "Pause"}
]

const DEFAULT_KEYBOARD_BINDINGS := {
	"move_left_0": KEY_A,
	"move_right_0": KEY_D,
	"move_up_0": KEY_W,
	"move_down_0": KEY_S,
	"jump_0": KEY_SPACE,
	"run_0": KEY_X,
	"spin_jump_0": KEY_SHIFT,
	"dive_0": KEY_C,
	"pause": KEY_ESCAPE
}

@onready var settings_file: Dictionary = settings_template

var settings_template := {
	"resolution": Vector2(1440, 810),
	"window_type": 0,
	"vsync_enabled": false,
	"drop_shadows": false,
	"hud_dragon_coin_style": 0,
	"master_volume": 0.5,
	"music_volume": 0.5,
	"sfx_volume": 0.5,
	"ui_volume": 0.5,
	"ground_pound": false,
	"air_twirl": false,
	"wall_jump": false,
	"dive": false,
	"air_flutter": false,
	"timer_enabled": false,
	"yoshi_spawn_pause": false,
	"autumn_type": 0,
	"timer_type": 0,
	"level_layout_type": 0,
	"boss_remix": false,
	"sp_collection_style": 0,
	"character_specific_physics": false,
	"soundtrack_type": 0,
	"player_damage_style": 0,
	"coyote_time": false,
	"fast_swim_accel": false,
	"disable_auto_scroll": false,
	"fast_climb": false,
	"fast_map_unlock_speed": false,
	"show_level_start_text": true,
	"jump_buffer": true,
	"sprite_settings": sprite_settings,
	"edible_dolphins": false,
	"holding_spin_jump": false,
	"auto_item_drop": true,
	"camera_shake": true,
	"android_aspect_mode": 1,
	"touch_controls_enabled": true,
	"touch_controls_size": 2,
	"touch_controls_opacity": 1,
	"touch_controls_auto_hide_gamepad": false,
	"touch_controls_safe_area": true,
	"touch_vibration": true,
	"mobile_touch_enabled": true,
	"mobile_touch_scale": 1.0,
	"mobile_touch_opacity": 0.86,
	"mobile_touch_layout": {},
	"rom_display_name": "",
	"language": "en",
	"keyboard_bindings": DEFAULT_KEYBOARD_BINDINGS.duplicate()
}

var raw_file: FileAccess = null

func _ready() -> void:
	if not FileAccess.file_exists("user://settings.cfg"):
		settings_file = settings_template.duplicate(true)
		save_settings()
	settings_file = get_file()
	if settings_file == null:
		settings_file = settings_template.duplicate(true)
	apply_settings(settings_file)

func save_settings() -> void:
	raw_file = FileAccess.open("user://settings.cfg", FileAccess.WRITE)
	if raw_file == null:
		push_error("Could not write user://settings.cfg")
		return
	raw_file.store_string(JSON.stringify(settings_file, "\t"))
	raw_file.close()

func get_file():
	raw_file = FileAccess.open("user://settings.cfg", FileAccess.READ)
	if raw_file == null:
		return settings_template.duplicate(true)
	var file = JSON.parse_string(raw_file.get_as_text())
	raw_file.close()
	if file is Dictionary:
		return file
	return settings_template.duplicate(true)

func apply_settings(settings) -> void:
	settings_file = settings
	verify_settings()
	apply_video_settings(settings_file)
	apply_audio_settings(settings_file)
	apply_sprite_settings(settings_file.sprite_settings)
	apply_keyboard_settings(settings_file.keyboard_bindings)
	var language_manager := get_node_or_null("/root/LanguageManager")
	if language_manager != null:
		language_manager.set_language(str(settings_file.get("language", "en")), false)
	var port_manager := get_node_or_null("/root/PortManager")
	if port_manager != null:
		port_manager.apply_settings(settings_file)

func verify_settings() -> void:
	for i in settings_template.keys():
		if not settings_file.has(i):
			var default_value = settings_template[i]
			settings_file[i] = default_value.duplicate(true) if default_value is Dictionary else default_value

	var bindings = settings_file.get("keyboard_bindings", {})
	if not bindings is Dictionary:
		bindings = {}
	for action in DEFAULT_KEYBOARD_BINDINGS.keys():
		if not bindings.has(action):
			bindings[action] = DEFAULT_KEYBOARD_BINDINGS[action]
	settings_file["keyboard_bindings"] = bindings
	save_settings()

func apply_keyboard_settings(bindings: Dictionary) -> void:
	for action in DEFAULT_KEYBOARD_BINDINGS.keys():
		var keycode := int(bindings.get(action, DEFAULT_KEYBOARD_BINDINGS[action]))
		_apply_keyboard_action(action, keycode)

func set_keyboard_binding(action: String, keycode: int) -> void:
	if not DEFAULT_KEYBOARD_BINDINGS.has(action) or keycode <= 0:
		return
	var bindings: Dictionary = settings_file.get("keyboard_bindings", DEFAULT_KEYBOARD_BINDINGS.duplicate())
	bindings[action] = keycode
	settings_file["keyboard_bindings"] = bindings
	_apply_keyboard_action(action, keycode)
	save_settings()

func reset_keyboard_bindings() -> void:
	settings_file["keyboard_bindings"] = DEFAULT_KEYBOARD_BINDINGS.duplicate()
	apply_keyboard_settings(settings_file["keyboard_bindings"])
	save_settings()

func get_keyboard_keycode(action: String) -> int:
	var bindings = settings_file.get("keyboard_bindings", DEFAULT_KEYBOARD_BINDINGS)
	return int(bindings.get(action, DEFAULT_KEYBOARD_BINDINGS.get(action, 0)))

func get_keyboard_key_name(action: String) -> String:
	var keycode := get_keyboard_keycode(action)
	var display_name := OS.get_keycode_string(keycode)
	return display_name if not display_name.is_empty() else str(keycode)

func _apply_keyboard_action(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		push_warning("Missing input action: " + action)
		return
	for event in InputMap.action_get_events(action).duplicate():
		if event is InputEventKey:
			InputMap.action_erase_event(action, event)
	var keyboard_event := InputEventKey.new()
	keyboard_event.device = -1
	keyboard_event.physical_keycode = keycode
	InputMap.action_add_event(action, keyboard_event)

func apply_video_settings(settings) -> void:
	# Android owns the physical window. Only desktop builds should resize or
	# reposition it; PortManager handles Android content scaling separately.
	if OS.has_feature("android"):
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync_enabled else DisplayServer.VSYNC_DISABLED)
		return

	var res = settings.resolution
	if res is String:
		res = res.replace(")", "")
		res = res.replace("(", "")
		res = res.replace(" ", "")
		res = res.split(",")
		res = Vector2(int(res[0]), int(res[1]))
	DisplayServer.window_set_size(res)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if settings.vsync_enabled else DisplayServer.VSYNC_DISABLED)
	var window_type = int(settings.window_type)
	match window_type:
		0:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MAX, false)
		1:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MAX, false)
		2:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_MAX, true)
	await get_tree().process_frame
	center_window()

func apply_sprite_settings(settings) -> void:
	for i in settings.keys():
		sprite_settings[i] = settings[i]

func center_window() -> void:
	DisplayServer.window_set_position(Vector2(DisplayServer.screen_get_position()) + DisplayServer.screen_get_size() * 0.5 - DisplayServer.window_get_size() * 0.5)

func apply_audio_settings(settings) -> void:
	var bus_index := 0
	for i in [settings.master_volume, settings.music_volume, settings.sfx_volume, settings.ui_volume]:
		AudioServer.set_bus_volume_db(bus_index, linear_to_db(i))
		bus_index += 1
