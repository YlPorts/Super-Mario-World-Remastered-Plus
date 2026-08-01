extends Node
## Adds a bundled pixel-style Latin font only when an original bitmap font is
## missing a glyph. This keeps the existing SMW fonts while allowing Ñ/ñ,
## accented vowels, ¿ and ¡ to render correctly.

const LATIN_FONT: Font = preload("res://Assets/Fonts/PixelifySans.ttf")
const META_APPLIED := &"_smwr_latin_fallback_applied"
const RESCAN_SECONDS := 0.25

var _elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_scan_tree", get_tree().root)
	print("[FONT67] LATIN PIXEL FALLBACK READY")

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < RESCAN_SECONDS:
		return
	_elapsed = 0.0
	_scan_tree(get_tree().root)

func _on_node_added(node: Node) -> void:
	call_deferred("_scan_tree", node)

func _scan_tree(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if node is Control:
		_apply_to_control(node as Control)
	for child in node.get_children():
		_scan_tree(child)

func _apply_to_control(control: Control) -> void:
	if control.has_meta(META_APPLIED):
		return

	var font_names: Array[StringName] = []
	if control is RichTextLabel:
		font_names = [&"normal_font", &"bold_font", &"italics_font", &"bold_italics_font", &"mono_font"]
	elif control is Label or control is Button or control is LineEdit or control is TextEdit:
		font_names = [&"font"]
	else:
		return

	var applied := false
	for font_name in font_names:
		var base_font := control.get_theme_font(font_name)
		if base_font == null or base_font == LATIN_FONT:
			continue
		var combined: Font = base_font.duplicate(true)
		var fallbacks: Array[Font] = combined.fallbacks.duplicate()
		if not fallbacks.has(LATIN_FONT):
			fallbacks.append(LATIN_FONT)
		combined.fallbacks = fallbacks
		control.add_theme_font_override(font_name, combined)
		applied = true

	if applied:
		control.set_meta(META_APPLIED, true)
