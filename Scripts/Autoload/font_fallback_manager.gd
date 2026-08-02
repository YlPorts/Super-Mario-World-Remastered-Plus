extends Node
## Adds a bundled pixel-style Latin font only when an original bitmap font is
## missing a glyph. The font is loaded at runtime instead of preloaded so a
## clean Godot checkout can import the TTF before this autoload uses it.

const LATIN_FONT_PATH := "res://Assets/Fonts/PixelifySans.ttf"
const META_APPLIED := &"_smwr_latin_fallback_applied"

var latin_font: Font

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not _load_latin_font():
		push_warning("[FONT70] Latin fallback font is not available yet: %s" % LATIN_FONT_PATH)
		return
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_scan_tree", get_tree().root)
	print("[FONT70] LATIN PIXEL FALLBACK READY")

func _load_latin_font() -> bool:
	var resource := load(LATIN_FONT_PATH)
	if resource is Font:
		latin_font = resource as Font
		return true
	latin_font = null
	return false

func _on_node_added(node: Node) -> void:
	call_deferred("_scan_tree", node)

func _scan_tree(node: Node) -> void:
	if latin_font == null or node == null or not is_instance_valid(node):
		return
	if node is Control:
		_apply_to_control(node as Control)
	for child in node.get_children():
		_scan_tree(child)

func _apply_to_control(control: Control) -> void:
	if latin_font == null or control.has_meta(META_APPLIED):
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
		if base_font == null or base_font == latin_font:
			continue
		var combined: Font = base_font.duplicate(true)
		var fallbacks: Array[Font] = combined.fallbacks.duplicate()
		if not fallbacks.has(latin_font):
			fallbacks.append(latin_font)
		combined.fallbacks = fallbacks
		control.add_theme_font_override(font_name, combined)
		applied = true

	if applied:
		control.set_meta(META_APPLIED, true)
