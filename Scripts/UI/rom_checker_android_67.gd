extends Node
## Minimal Android ROM selector. The screen intentionally shows one large
## AÑADIR ROM button and only displays text when an error occurs.

const SUPPORTED_HASHES := [
	"0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b",
	"5e3d55b019dd012e8db1498dda06b63ad1a304787625402b511e6d525946beaf",
	"d70c9c7716ad12c674fc7dd744736aa48d4d7b4237f58066be620fda26024872",
	"c6808e082ab343be554d07f2b3eb157c3c5134b364a2ffb3806a67f17e0992d0",
	"a6549142be41d0c9efceaaddd7010341cbac8438f612f4eda410590128a03ea5",
	"b5be1dba3012b6811a5660fbf2981cb23cdd1e48f845a42df00f0f55b19f0392",
	"5cc54b1e5c8d3c7701a5e20514145c3b36f15f26fe0a4fe6d2e43677e4b4eda9",
]

const PIXEL_FONT: Font = preload("res://Assets/Fonts/PixelifySans.ttf")

var importing := false
var launched := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$ColorRect.hide()
	$TextureRect.show()
	_configure_file_dialog()
	_configure_minimal_button()
	$Success.hide()
	$Text.hide()
	if _saved_rom_is_valid():
		call_deferred("_launch_game")
	else:
		$SelectRomButton.show()
		$SelectRomButton.grab_focus()
	print("[ANDROID67] MINIMAL ROM PICKER READY")

func _configure_file_dialog() -> void:
	$FileDialog.access = FileDialog.ACCESS_FILESYSTEM
	$FileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	$FileDialog.use_native_dialog = true
	$FileDialog.filters = PackedStringArray(["*.sfc,*.smc;Super Nintendo ROM"])
	$FileDialog.title = LanguageManager.text("ADD ROM")
	$FileDialog.ok_button_text = LanguageManager.text("ADD ROM")

func _configure_minimal_button() -> void:
	var button: Button = $SelectRomButton
	button.anchor_left = 0.5
	button.anchor_top = 0.5
	button.anchor_right = 0.5
	button.anchor_bottom = 0.5
	button.offset_left = -112.0
	button.offset_top = -30.0
	button.offset_right = 112.0
	button.offset_bottom = 30.0
	button.text = LanguageManager.text("ADD ROM")
	button.add_theme_font_override("font", PIXEL_FONT)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_color_override("font_outline_color", Color.BLACK)
	button.add_theme_constant_override("outline_size", 3)

func _process(_delta: float) -> void:
	if not importing and not launched and Input.is_action_just_pressed("ui_accept"):
		open_rom_picker()

func open_rom_picker() -> void:
	if importing or launched:
		return
	_hide_error()
	$FileDialog.popup_centered_ratio(0.92)

func _on_file_selected(path: String) -> void:
	if importing or launched:
		return
	importing = true
	$SelectRomButton.disabled = true
	call_deferred("_import_rom", path)

func _on_picker_canceled() -> void:
	if launched:
		return
	importing = false
	$SelectRomButton.disabled = false

func _import_rom(path: String) -> void:
	var source := FileAccess.open(path, FileAccess.READ)
	if source == null:
		_fail(LanguageManager.text("ROM ERROR"))
		return
	var data := source.get_buffer(source.get_length())
	source.close()
	if data.is_empty():
		_fail(LanguageManager.text("ROM ERROR"))
		return

	var digest := _sha256(data)
	if not SUPPORTED_HASHES.has(digest):
		# Headered SMC dumps contain an extra 512-byte copier header. Validate the
		# unheadered payload and store it when it matches a supported legal dump.
		if data.size() > 512 and data.size() % 1024 == 512:
			var unheadered := data.slice(512)
			var unheadered_digest := _sha256(unheadered)
			if SUPPORTED_HASHES.has(unheadered_digest):
				data = unheadered
				digest = unheadered_digest
		if not SUPPORTED_HASHES.has(digest):
			_fail(LanguageManager.text("ROM ERROR"))
			return

	var destination := FileAccess.open("user://baserom.sfc", FileAccess.WRITE)
	if destination == null:
		_fail(LanguageManager.text("ROM ERROR"))
		return
	destination.store_buffer(data)
	destination.close()
	if not _saved_rom_is_valid():
		_fail(LanguageManager.text("ROM ERROR"))
		return
	$SelectRomButton.hide()
	_launch_game()

func _sha256(data: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	context.update(data)
	return context.finish().hex_encode()

func _saved_rom_is_valid() -> bool:
	if not FileAccess.file_exists("user://baserom.sfc"):
		return false
	return SUPPORTED_HASHES.has(FileAccess.get_sha256("user://baserom.sfc"))

func _fail(message: String) -> void:
	importing = false
	$SelectRomButton.disabled = false
	$Text.show()
	$Text.text = ""
	$Text/Error.show()
	$Text/Error.text = message

func _hide_error() -> void:
	$Text/Error.hide()
	$Text.hide()

func _launch_game() -> void:
	if launched:
		return
	launched = true
	importing = false
	var result := get_tree().change_scene_to_file("res://Instances/UI/Menus/title_screen.tscn")
	if result != OK:
		launched = false
		_fail(LanguageManager.text("ROM ERROR"))
