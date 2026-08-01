extends Node
## Editable TXT localization system for the Windows port.
##
## Built-in English and Spanish packs live in res://languages. The portable
## Windows build also places them beside the EXE in a languages folder. Files in
## that external folder override built-ins and additional .txt packs are loaded
## automatically on the next launch.

signal language_changed(code: String)

const BUILTIN_LANGUAGE_DIR := "res://languages"
const DEFAULT_LANGUAGE := "en"
const RESCAN_SECONDS := 0.20
const PIXEL_FALLBACK_FONT: Font = preload("res://Resources/Fonts/SMW Text NC.ttf")
const META_SOURCE_PREFIX := "_smwr_language_source_"
const META_RENDERED_PREFIX := "_smwr_language_rendered_"

var packs: Dictionary = {}
var current_language := DEFAULT_LANGUAGE
var external_language_dir := ""

var _tracked: Array[WeakRef] = []
var _tracked_ids: Dictionary = {}
var _scan_elapsed := 0.0
var _patched_fonts: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	external_language_dir = _get_external_language_dir()
	reload_language_packs()

	var desired := DEFAULT_LANGUAGE
	var settings_manager := get_node_or_null("/root/SettingsManager")
	if settings_manager != null:
		desired = str(settings_manager.settings_file.get("language", DEFAULT_LANGUAGE))
	set_language(desired, false)

	get_tree().node_added.connect(_on_node_added)
	get_tree().node_removed.connect(_on_node_removed)
	call_deferred("_register_tree", get_tree().root)
	print("[LANG63] READY languages=", get_available_language_codes(), " selected=", current_language)


func _process(delta: float) -> void:
	_scan_elapsed += delta
	if _scan_elapsed < RESCAN_SECONDS:
		return
	_scan_elapsed = 0.0
	_refresh_tracked_nodes()


func reload_language_packs() -> void:
	packs.clear()
	_load_language_directory(BUILTIN_LANGUAGE_DIR, false)
	if not external_language_dir.is_empty():
		_load_language_directory(external_language_dir, true)

	if not packs.has(DEFAULT_LANGUAGE):
		packs[DEFAULT_LANGUAGE] = {
			"code": DEFAULT_LANGUAGE,
			"name": "English",
			"fallback": "",
			"entries": {},
			"path": "",
		}


func set_language(code: String, save_setting := true) -> void:
	var normalized := code.strip_edges().to_lower()
	if not packs.has(normalized):
		normalized = DEFAULT_LANGUAGE
	current_language = normalized

	if save_setting:
		var settings_manager := get_node_or_null("/root/SettingsManager")
		if settings_manager != null:
			settings_manager.settings_file["language"] = current_language
			settings_manager.save_settings()

	_refresh_tracked_nodes(true)
	language_changed.emit(current_language)
	print("[LANG63] LANGUAGE CHANGED: ", current_language)


func text(source_english: String) -> String:
	var lookup := _normalize_source(source_english)
	if lookup.is_empty():
		return source_english

	var pack: Dictionary = packs.get(current_language, {})
	var entries: Dictionary = pack.get("entries", {})
	if entries.has(lookup):
		return str(entries[lookup])

	var fallback_code := str(pack.get("fallback", DEFAULT_LANGUAGE)).to_lower()
	if not fallback_code.is_empty() and packs.has(fallback_code):
		var fallback_entries: Dictionary = packs[fallback_code].get("entries", {})
		if fallback_entries.has(lookup):
			return str(fallback_entries[lookup])

	var english_entries: Dictionary = packs[DEFAULT_LANGUAGE].get("entries", {})
	if english_entries.has(lookup):
		return str(english_entries[lookup])
	return source_english


func get_available_languages() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for code in packs.keys():
		var pack: Dictionary = packs[code]
		result.append({
			"code": str(code),
			"name": str(pack.get("name", code)),
			"path": str(pack.get("path", "")),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_code := str(a["code"])
		var b_code := str(b["code"])
		if a_code == DEFAULT_LANGUAGE:
			return true
		if b_code == DEFAULT_LANGUAGE:
			return false
		if a_code == "es":
			return true
		if b_code == "es":
			return false
		return str(a["name"]).naturalnocasecmp_to(str(b["name"])) < 0
	)
	return result


func get_available_language_codes() -> Array[String]:
	var result: Array[String] = []
	for record in get_available_languages():
		result.append(str(record["code"]))
	return result


func get_language_name(code: String) -> String:
	if packs.has(code):
		return str(packs[code].get("name", code))
	return code


func _get_external_language_dir() -> String:
	if OS.has_feature("android"):
		return "user://languages"
	if OS.has_feature("editor"):
		return ""
	var executable := OS.get_executable_path()
	if executable.is_empty():
		return ""
	return executable.get_base_dir().path_join("languages")


func _load_language_directory(path: String, overwrite_existing: bool) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return

	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.to_lower().ends_with(".txt") and not filename.begins_with("_"):
			var pack := _parse_language_file(path.path_join(filename))
			var code := str(pack.get("code", "")).to_lower()
			if not code.is_empty() and (overwrite_existing or not packs.has(code)):
				packs[code] = pack
		filename = directory.get_next()
	directory.list_dir_end()


func _parse_language_file(path: String) -> Dictionary:
	var result := {
		"code": "",
		"name": "",
		"fallback": DEFAULT_LANGUAGE,
		"entries": {},
		"path": path,
	}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("Could not read language file: " + path)
		return result

	var content := file.get_as_text().replace("\r\n", "\n").replace("\r", "\n")
	file.close()
	for raw_line in content.split("\n"):
		var line := str(raw_line)
		if line.strip_edges().is_empty() or line.strip_edges().begins_with("#") or line.strip_edges().begins_with(";"):
			continue

		if line.begins_with("@code="):
			result["code"] = _unescape(line.substr(6)).strip_edges().to_lower()
			continue
		if line.begins_with("@name="):
			result["name"] = _unescape(line.substr(6)).strip_edges()
			continue
		if line.begins_with("@fallback="):
			result["fallback"] = _unescape(line.substr(10)).strip_edges().to_lower()
			continue

		var separator := _find_unescaped_equals(line)
		if separator < 0:
			continue
		var source := _normalize_source(_unescape(line.substr(0, separator)))
		var translated := _unescape(line.substr(separator + 1))
		if not source.is_empty():
			var entries: Dictionary = result["entries"]
			entries[source] = translated
			result["entries"] = entries

	if str(result["code"]).is_empty():
		result["code"] = path.get_file().get_basename().to_lower()
	if str(result["name"]).is_empty():
		result["name"] = str(result["code"])
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
	return source.strip_edges()


func _source_exists(source: String) -> bool:
	if not packs.has(DEFAULT_LANGUAGE):
		return false
	var entries: Dictionary = packs[DEFAULT_LANGUAGE].get("entries", {})
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
	_ensure_pixel_font_fallback(node)
	_translate_node(node, true)


func _refresh_tracked_nodes(force := false) -> void:
	var remaining: Array[WeakRef] = []
	for reference in _tracked:
		var node = reference.get_ref()
		if node == null or not is_instance_valid(node):
			continue
		remaining.append(reference)
		_ensure_pixel_font_fallback(node)
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
	var rendered := _translate_preserving_outer_whitespace(source)
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


func _ensure_pixel_font_fallback(node: Node) -> void:
	if not node is Control:
		return
	var control := node as Control
	for theme_font_name in [&"font", &"normal_font", &"bold_font", &"italics_font", &"bold_italics_font"]:
		if control.has_theme_font(theme_font_name):
			_add_font_fallback(control.get_theme_font(theme_font_name))


func _add_font_fallback(font: Font) -> void:
	if font == null or font == PIXEL_FALLBACK_FONT:
		return
	var id := font.get_instance_id()
	if _patched_fonts.has(id):
		return
	var fallbacks: Array[Font] = font.fallbacks.duplicate()
	if not fallbacks.has(PIXEL_FALLBACK_FONT):
		fallbacks.append(PIXEL_FALLBACK_FONT)
		font.fallbacks = fallbacks
	_patched_fonts[id] = true
