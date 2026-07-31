extends Node

const VALID_HASHES := PackedStringArray([
	"0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b",
	"5e3d55b019dd012e8db1498dda06b63ad1a304787625402b511e6d525946beaf",
	"d70c9c7716ad12c674fc7dd744736aa48d4d7b4237f58066be620fda26024872",
	"c6808e082ab343be554d07f2b3eb157c3c5134b364a2ffb3806a67f17e0992d0",
	"a6549142be41d0c9efceaaddd7010341cbac8438f612f4eda410590128a03ea5",
	"b5be1dba3012b6811a5660fbf2981cb23cdd1e48f845a42df00f0f55b19f0392",
	"5cc54b1e5c8d3c7701a5e20514145c3b36f15f26fe0a4fe6d2e43677e4b4eda9",
])

var can_check := true
var _port_manager: Node


func _ready() -> void:
	_port_manager = get_node_or_null("/root/PortManager")
	if _port_manager != null:
		_port_manager.rom_imported.connect(_on_rom_imported)
	if verify_rom():
		proceed()
	else:
		$ColorRect.hide()
		_show_selection_prompt()
		if OS.has_feature("android"):
			await get_tree().process_frame
			open_rom_picker()


func _show_selection_prompt() -> void:
	$Text.text = "\nSelect your legally dumped Super Mario World ROM.\n\nSupported files: .sfc or .smc\n\nPress A / Enter or tap SELECT ROM.\n\nThe app validates it and copies it to private storage."
	$Text/Path.text = "No ROM selected"
	$Text/Error.hide()
	if has_node("SelectRomButton"):
		$SelectRomButton.show()


func run_check() -> void:
	if not can_check:
		return
	if verify_rom():
		success()
	else:
		open_rom_picker()


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		run_check()


func verify_rom() -> bool:
	if _port_manager != null:
		return _port_manager.rom_is_valid()
	return FileAccess.file_exists("user://baserom.sfc") and VALID_HASHES.has(FileAccess.get_sha256("user://baserom.sfc"))


func open_rom_picker() -> void:
	if _port_manager == null:
		fail("File picker is unavailable. Place baserom.sfc in " + ProjectSettings.globalize_path("user://"))
		return
	_port_manager.request_rom_selection()


func _on_rom_imported(import_success: bool, message: String) -> void:
	if import_success:
		success()
	else:
		fail(message)


func proceed() -> void:
	TransitionManager.transition_to_menu("res://Instances/UI/Menus/disclaimer.tscn", self)


func success() -> void:
	can_check = false
	$Success.show()
	$Text.hide()
	if has_node("SelectRomButton"):
		$SelectRomButton.hide()
	SoundManager.play_ui_sound(SoundManager.correct)
	await get_tree().create_timer(1, false).timeout
	proceed()


func fail(message := "Error verifying ROM.") -> void:
	$Success.hide()
	$Text.show()
	$Text/Error.show()
	$Text/Error.text = message
	SoundManager.play_ui_sound(SoundManager.wrong)
