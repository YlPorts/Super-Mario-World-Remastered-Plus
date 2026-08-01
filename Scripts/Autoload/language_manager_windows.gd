extends "res://Scripts/Autoload/language_manager.gd"
## Windows bitmap-font compatibility layer.
##
## Several imported image fonts report accented characters as available even
## though Godot renders their missing-glyph boxes. Transliterate those characters
## before asking the base localization manager to validate the active font. This
## keeps the original pixel typography, spacing and alignment without mixing in a
## proportional TTF.

func _make_font_safe(object: Object, value: String) -> String:
	var bitmap_safe := ""
	for index in range(value.length()):
		bitmap_safe += _ascii_fallback(value.substr(index, 1))
	return super._make_font_safe(object, bitmap_safe)
