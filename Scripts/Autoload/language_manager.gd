extends Node
## Built-in bilingual localization for desktop and Android.
## Only English and Spanish are exposed; external language packs are ignored.

signal language_changed(code: String)

const DEFAULT_LANGUAGE := "en"
const LANGUAGE_ORDER := ["en", "es"]
const LANGUAGE_PATHS := {
	"en": "res://languages/en.txt",
	"es": "res://languages/es.txt",
}
const LANGUAGE_NAMES := {
	"en": "ENGLISH",
	"es": "ESPAÑOL",
}
const RESCAN_SECONDS := 0.20
const META_SOURCE_PREFIX := "_smwr_language_source_"
const META_RENDERED_PREFIX := "_smwr_language_rendered_"

var packs: Dictionary = {}
var current_language := DEFAULT_LANGUAGE
var _tracked: Array[WeakRef] = []
var _tracked_ids: Dictionary = {}
var _scan_elapsed := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reload_language_packs()
	var desired := DEFAULT_LANGUAGE
	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		desired = str(settings_manager.settings_file.get("language", DEFAULT_LANGUAGE))
	set_language(desired, false)
	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	call_deferred("_register_tree", get_tree().root)
	print("[LANG66] READY languages=", LANGUAGE_ORDER, " selected=", current_language)

func _process(delta: float) -> void:
	_scan_elapsed += delta
	if _scan_elapsed < RESCAN_SECONDS:
		return
	_scan_elapsed = 0.0
	_refresh_tracked_nodes()

func reload_language_packs() -> void:
	packs.clear()
	for code in LANGUAGE_ORDER:
		var path := str(LANGUAGE_PATHS.get(code, ""))
		var pack := _parse_language_file(path)
		pack["code"] = code
		pack["name"] = LANGUAGE_NAMES[code]
		packs[code] = pack
	if not packs.has(DEFAULT_LANGUAGE):
		packs[DEFAULT_LANGUAGE] = {"entries": {}, "fallback": ""}

func set_language(code: String, save_setting := true) -> void:
	var normalized := code.strip_edges().to_lower()
	if not LANGUAGE_ORDER.has(normalized):
		normalized = DEFAULT_LANGUAGE
	current_language = normalized
	if save_setting:
		var settings_manager := get_node_or_null("/root/SettingsManager")
		if settings_manager != null:
			settings_manager.settings_file["language"] = current_language
			settings_manager.save_settings()
	_refresh_tracked_nodes(true)
	language_changed.emit(current_language)
	print("[LANG66] LANGUAGE CHANGED: ", current_language)

func text(source_english: String) -> String:
	var lookup := _normalize_source(source_english)
	if lookup.is_empty():
		return source_english
	var entries: Dictionary = packs.get(current_language, {}).get("entries", {})
	if entries.has(lookup):
		return str(entries[lookup])
	var english_entries: Dictionary = packs.get(DEFAULT_LANGUAGE, {}).get("entries", {})
	if english_entries.has(lookup):
		return str(english_entries[lookup])
	return source_english

func get_available_languages() -> Array[Dictionary]:
	return [
		{"code": "en", "name": LANGUAGE_NAMES["en"]},
		{"code": "es", "name": LANGUAGE_NAMES["es"]},
	]

func get_available_language_codes() -> Array[String]:
	return ["en", "es"]

func get_language_name(code: String) -> String:
	return str(LANGUAGE_NAMES.get(code, LANGUAGE_NAMES[DEFAULT_LANGUAGE]))

func _parse_language_file(path: String) -> Dictionary:
	var result := {"entries": {}, "fallback": DEFAULT_LANGUAGE}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not read language file: " + path)
		return result
	var content := file.get_as_text().replace("\r\n", "\n").replace("\r", "\n")
	file.close()
	for raw_line in content.split("\n"):
		var line := str(raw_line)
		var stripped := line.strip_edges()
		if stripped.is_empty() or stripped == "#" or stripped.begins_with("# ") or stripped.begins_with(";"):
			continue
		if line.begins_with("@fallback="):
			result["fallback"] = _unescape(line.substr(10)).strip_edges().to_lower()
			continue
		if line.begins_with("@"):
			continue
		var separator := _find_unescaped_equals(line)
		if separator < 0:
			continue
		var source := _normalize_source(_unescape(line.substr(0, separator)))
		if source.is_empty():
			continue
		var entries: Dictionary = result["entries"]
		entries[source] = _unescape(line.substr(separator + 1))
		result["entries"] = entries
	return result

func _find_unescaped_equals(line: String) -> int:
	var escaped := false
	for index in range(line.length()):
		var character := line.substr(index, 1)
		if escaped:
			escaped = false
		elif character == "\\":
			escaped = true
		elif character == "=":
			return index
	return -1

func _unescape(value: String) -> String:
	var output := ""
	var escaped := false
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if not escaped:
			if character == "\\":
				escaped = true
			else:
				output += character
			continue
		match character:
			"n": output += "\n"
			"r": output += "\r"
			"t": output += "\t"
			"=": output += "="
			"\\": output += "\\"
			_: output += character
		escaped = false
	if escaped:
		output += "\\"
	return output

func _normalize_source(source: String) -> String:
	var stripped := source.strip_edges().to_lower()
	var output := ""
	var pending_space := false
	for index in range(stripped.length()):
		var character := stripped.substr(index, 1)
		if character in [" ", "\t", "\n", "\r"]:
			pending_space = true
			continue
		if pending_space and not output.is_empty():
			output += " "
		output += character
		pending_space = false
	return output

func _source_exists(source: String) -> bool:
	var entries: Dictionary = packs.get(DEFAULT_LANGUAGE, {}).get("entries", {})
	return entries.has(_normalize_source(source))

func _on_node_added(node: Node) -> void:
	call_deferred("_register_tree", node)

func _on_node_removed(node: Node) -> void:
	_tracked_ids.erase(node.get_instance_id())

func _register_tree(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	if _is_text_node(node):
		_register_text_node(node)
	for child in node.get_children():
		_register_tree(child)

func _is_text_node(node: Node) -> bool:
	return node is Label or node is Button or node is RichTextLabel or node is LineEdit or node is Window

func _register_text_node(node: Node) -> void:
	var id := node.get_instance_id()
	if _tracked_ids.has(id):
		return
	_tracked_ids[id] = true
	_tracked.append(weakref(node))
	_translate_node(node, true)

func _refresh_tracked_nodes(force := false) -> void:
	var remaining: Array[WeakRef] = []
	for reference in _tracked:
		var node = reference.get_ref()
		if node == null or not is_instance_valid(node):
			continue
		remaining.append(reference)
		_translate_node(node, force)
	_tracked = remaining

func _translate_node(node: Node, force := false) -> void:
	if node is Label or node is Button or node is RichTextLabel:
		_translate_property(node, "text", force)
	elif node is LineEdit:
		_translate_property(node, "placeholder_text", force)
	elif node is Window:
		_translate_property(node, "title", force)
	if node is Control:
		_translate_property(node, "tooltip_text", force)

func _translate_property(object: Object, property_name: String, force: bool) -> void:
	var current := str(object.get(property_name))
	if current.is_empty():
		return
	var source_meta := META_SOURCE_PREFIX + property_name
	var rendered_meta := META_RENDERED_PREFIX + property_name
	var source := str(object.get_meta(source_meta, ""))
	var last_rendered := str(object.get_meta(rendered_meta, ""))
	if source.is_empty() or (current != last_rendered and not force):
		if _source_exists(current):
			source = current
			object.set_meta(source_meta, source)
		else:
			if not source.is_empty() and current != last_rendered:
				object.remove_meta(source_meta)
				object.remove_meta(rendered_meta)
			return
	if source.is_empty():
		return
	var rendered := _make_font_safe(object, _translate_preserving_outer_whitespace(source))
	if current != rendered or force:
		object.set(property_name, rendered)
	object.set_meta(rendered_meta, rendered)

func _translate_preserving_outer_whitespace(source: String) -> String:
	var left := 0
	while left < source.length() and source.substr(left, 1) in [" ", "\t", "\n", "\r"]:
		left += 1
	var right := source.length()
	while right > left and source.substr(right - 1, 1) in [" ", "\t", "\n", "\r"]:
		right -= 1
	var core := source.substr(left, right - left)
	return source.substr(0, left) + text(core) + source.substr(right)

func _make_font_safe(object: Object, value: String) -> String:
	if not object is Control:
		return value
	var control := object as Control
	var font_name: StringName = &"font"
	if object is RichTextLabel:
		font_name = &"normal_font"
	var font := control.get_theme_font(font_name)
	if font == null:
		return value
	var output := ""
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if font.has_char(character.unicode_at(0)):
			output += character
		else:
			output += _ascii_fallback(character)
	return output

func _ascii_fallback(character: String) -> String:
	match character:
		"á", "à", "â", "ä", "ã": return "a"
		"Á", "À", "Â", "Ä", "Ã": return "A"
		"é", "è", "ê", "ë": return "e"
		"É", "È", "Ê", "Ë": return "E"
		"í", "ì", "î", "ï": return "i"
		"Í", "Ì", "Î", "Ï": return "I"
		"ó", "ò", "ô", "ö", "õ": return "o"
		"Ó", "Ò", "Ô", "Ö", "Õ": return "O"
		"ú", "ù", "û", "ü": return "u"
		"Ú", "Ù", "Û", "Ü": return "U"
		"ñ": return "n"
		"Ñ": return "N"
		"ç": return "c"
		"Ç": return "C"
		"¿", "¡": return ""
		"º": return "o"
		"ª": return "a"
		"–", "—": return "-"
		"…": return "..."
		_: return character
