extends Node
## Minimal first-launch gate used by BUILD 47 diagnostics.
##
## Android input and native picker calls are intentionally handled only by the
## independent RomPickerProbe node so the diagnostic report cannot be confused
## by duplicate requests from this script.

const ROM_PATH := "user://baserom.sfc"
const VALID_ROM_HASHES := PackedStringArray([
	"0838e531fe22c077528febe14cb3ff7c492f1f5fa8de354192bdff7137c27f5b",
	"5e3d55b019dd012e8db1498dda06b63ad1a304787625402b511e6d525946beaf",
	"d70c9c7716ad12c674fc7dd744736aa48d4d7b4237f58066be620fda26024872",
	"c6808e082ab343be554d07f2b3eb157c3c5134b364a2ffb3806a67f17e0992d0",
	"a6549142be41d0c9efceaaddd7010341cbac8438f612f4eda410590128a03ea5",
	"b5be1dba3012b6811a5660fbf2981cb23cdd1e48f845a42df00f0f55b19f0392",
	"5cc54b1e5c8d3c7701a5e20514145c3b36f15f26fe0a4fe6d2e43677e4b4eda9",
])


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_keep_touch_controls_alive()
	if verify_rom():
		proceed()
	else:
		$RomPanel/Content/Status.text = "Diagnostic probe is starting..."
		$RomPanel/Content/Status.modulate = Color(1.0, 0.86, 0.35, 1.0)


func _keep_touch_controls_alive() -> void:
	var controls := get_node_or_null("TouchControls")
	if controls == null:
		return
	var existing := get_node_or_null("/root/TouchControls")
	if existing != null and existing != controls:
		controls.queue_free()
		return
	controls.reparent(get_tree().root)
	controls.name = "TouchControls"


func verify_rom() -> bool:
	return FileAccess.file_exists(ROM_PATH) and VALID_ROM_HASHES.has(FileAccess.get_sha256(ROM_PATH))


func proceed() -> void:
	TransitionManager.transition_to_menu("res://Instances/UI/Menus/disclaimer.tscn", self)
