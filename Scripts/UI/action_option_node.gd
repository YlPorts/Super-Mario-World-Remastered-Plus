class_name ActionOptionNode
extends OptionNode

@onready var arrow: TextureRect = $MarginContainer/Arrow
@onready var setting_title: Label = $MarginContainer/Container/SettingTitle
@onready var value: Label = $MarginContainer/Container/Value

@export var node_title := ""
@export_enum("Select ROM") var action_type := 0

var _accept_latched := false


func update(_delta: float) -> void:
	arrow.visible = highlighted
	setting_title.text = "  " + node_title + ":"
	value.text = _get_value_text()

	var accept_pressed := Input.is_action_pressed("ui_accept")
	if highlighted and accept_pressed and not _accept_latched:
		_activate()
	_accept_latched = accept_pressed


func _activate() -> void:
	SoundManager.play_ui_sound(SoundManager.select)
	match action_type:
		0:
			var port_manager := get_node_or_null("/root/PortManager")
			if port_manager != null:
				port_manager.request_rom_selection()


func _get_value_text() -> String:
	match action_type:
		0:
			var port_manager := get_node_or_null("/root/PortManager")
			if port_manager != null:
				return port_manager.get_rom_display_name()
	return "Press A"
