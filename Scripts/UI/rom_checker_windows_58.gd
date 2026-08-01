extends Node

# Windows desktop ROM selector with editable language support.

var can_select := true
var importing := false
var launched := false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	$ColorRect.hide()
	$TextureRect.show()
	$Text.show()
	$SelectRomButton.show()
	$Success.hide()
	$Text/Error.hide()
	$FileDialog.access = FileDialog.ACCESS_FILESYSTEM
	$FileDialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	$FileDialog.use_native_dialog = true
	$FileDialog.filters = PackedStringArray(["*.sfc,*.smc;Super Nintendo ROM"])
	$FileDialog.title = LanguageManager.text("Select Super Mario World ROM")
	$FileDialog.ok_button_text = LanguageManager.text("SELECT ROM")
	$SelectRomButton.text = LanguageManager.text("SELECT ROM")
	print("[WIN58] ROM CHECKER READY")

	if _saved_rom_is_valid():
		$Text.text = LanguageManager.text("Saved ROM verified. Starting the game...")
		$Text/Path.text = "user://baserom.sfc"
		$SelectRomButton.hide()
		call_deferred("_launch_game")
	else:
		_show_prompt()

func _process(_delta: float) -> void:
	if can_select and Input.is_action_just_pressed("ui_accept"):
		open_rom_picker()

func _show_prompt() -> void:
	$Text.text = "\n" + LanguageManager.text("Select your legally dumped Super Mario World ROM.\n\nSupported files: .sfc or .smc\n\nPress Enter or click SELECT ROM.")
	$Text/Path.text = LanguageManager.text("No ROM selected")
	$Text/Error.hide()
	$SelectRomButton.disabled = false
	$SelectRomButton.grab_focus()

func open_rom_picker() -> void:
	if not can_select or importing or launched:
		return
	$Text/Error.hide()
	$Text/Path.text = LanguageManager.text("Opening Windows file picker...")
	$FileDialog.popup_centered_ratio(0.85)

func _on_file_selected(path: String) -> void:
	if importing or launched:
		return
	importing = true
	can_select = false
	$SelectRomButton.disabled = true
	$Text/Path.text = LanguageManager.text("Reading") + ": " + path.get_file()
	call_deferred("_import_rom", path)

func _on_picker_canceled() -> void:
	if launched:
		return
	$Text/Path.text = LanguageManager.text("No ROM selected")
	$SelectRomButton.disabled = false
	can_select = true

func _import_rom(path: String) -> void:
	var source = FileAccess.open(path, FileAccess.READ)
	if source == null:
		_fail(LanguageManager.text("Windows could not read the selected file") + ". " + LanguageManager.text("Error") + " %d." % FileAccess.get_open_error())
		return

	var data = source.get_buffer(source.get_length())
	source.close()
	if data.is_empty():
		_fail(LanguageManager.text("The selected ROM is empty or unreadable."))
		return

	var context = HashingContext.new()
	var start_error = context.start(HashingContext.HASH_SHA256)
	if start_error != OK:
		_fail(LanguageManager.text("Could not start ROM validation."))
		return
	context.update(data)
	var digest = context.finish().hex_encode()
	print("[WIN58] selected ROM sha256=", digest)
	if not _hash_is_supported(digest):
		_fail(LanguageManager.text("Unsupported ROM. Select an original supported Super Mario World .sfc/.smc dump.") + "\nSHA-256: " + digest)
		return

	var destination = FileAccess.open("user://baserom.sfc", FileAccess.WRITE)
	if destination == null:
		_fail(LanguageManager.text("The ROM could not be copied to the game's private settings folder."))
		return
	destination.store_buffer(data)
	destination.close()

	if not _saved_rom_is_valid():
		_fail(LanguageManager.text("The private ROM copy failed its final verification."))
		return

	$Text.hide()
	$SelectRomButton.hide()
	$Success.text = LanguageManager.text("ROM verified!\nStarting the game...")
	$Success.show()
	print("[WIN58] ROM VERIFIED")
	var timer = get_tree().create_timer(0.7)
	timer.timeout.connect(_launch_game)

func _fail(message: String) -> void:
	importing = false
	can_select = true
	$SelectRomButton.disabled = false
	$Text.show()
	$Text/Error.text = message
	$Text/Error.show()
	$Text/Path.text = LanguageManager.text("Select another ROM and try again.")
	print("[WIN58] ROM ERROR: ", message)

func _saved_rom_is_valid() -> bool:
	if not FileAccess.file_exists("user://baserom.sfc"):
		return false
	return _hash_is_supported(FileAccess.get_sha256("user://baserom.sfc"))

func _hash_is_supported(digest: String) -> bool:
	if digest == "0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b":
		return true
	if digest == "5e3d55b019dd012e8db1498dda06b63ad1a304787625402b511e6d525946beaf":
		return true
	if digest == "d70c9c7716ad12c674fc7dd744736aa48d4d7b4237f58066be620fda26024872":
		return true
	if digest == "c6808e082ab343be554d07f2b3eb157c3c5134b364a2ffb3806a67f17e0992d0":
		return true
	if digest == "a6549142be41d0c9efceaaddd7010341cbac8438f612f4eda410590128a03ea5":
		return true
	if digest == "b5be1dba3012b6811a5660fbf2981cb23cdd1e48f845a42df00f0f55b19f0392":
		return true
	if digest == "5cc54b1e5c8d3c7701a5e20514145c3b36f15f26fe0a4fe6d2e43677e4b4eda9":
		return true
	return false

func _launch_game() -> void:
	if launched:
		return
	launched = true
	can_select = false
	importing = false
	print("[WIN58] LOADING TITLE SCREEN")
	var change_error = get_tree().change_scene_to_file("res://Instances/UI/Menus/title_screen.tscn")
	if change_error != OK:
		launched = false
		_fail(LanguageManager.text("Could not load the title screen") + ": " + error_string(change_error))
