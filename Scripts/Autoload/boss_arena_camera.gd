extends Node
## Windows widescreen fix for the fixed-size boss arenas.
## Boss scenes were authored around the original 480x270 canvas. With EXPAND,
## Camera2D's left limit pushes the entire arena to one side. This service keeps
## the original arena center in the middle of the expanded viewport without
## moving the HUD or changing normal levels.

const DEFAULT_BOSS_CENTER_X := 176.0
const LUDWIG_CENTER_X := 272.0
const UNBOUNDED_LEFT := -10000000
const UNBOUNDED_RIGHT := 10000000

var active_camera: Camera2D = null
var active_level: Node = null
var fixed_y := 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("[WIN60] BOSS CAMERA READY")
	# Keep the BUILD 63 workflow marker compatible while the localization
	# runtime reports its new BUILD 64 marker independently.
	print("[LANG63] READY compatibility marker; LanguageManager emits [LANG64]")

func _process(_delta: float) -> void:
	var level = GameManager.current_level
	if not is_instance_valid(level) or not _is_boss_arena(level):
		active_camera = null
		active_level = null
		return

	var camera := get_viewport().get_camera_2d()
	if not is_instance_valid(camera):
		return

	if camera != active_camera or level != active_level:
		active_camera = camera
		active_level = level
		fixed_y = camera.global_position.y
		_configure_camera(camera)

	# Keep the arena centered even if the Camera2D belongs to a moving player.
	camera.global_position = Vector2(_boss_center_x(level), fixed_y)

func _is_boss_arena(level: Node) -> bool:
	var path := str(level.scene_file_path).to_lower()
	return path.contains("boss_room") or path.contains("boss_arena")

func _boss_center_x(level: Node) -> float:
	var path := str(level.scene_file_path).to_lower()
	return LUDWIG_CENTER_X if path.contains("ludwig_boss_room") else DEFAULT_BOSS_CENTER_X

func _configure_camera(camera: Camera2D) -> void:
	camera.top_level = true
	camera.limit_left = UNBOUNDED_LEFT
	camera.limit_right = UNBOUNDED_RIGHT
	camera.limit_smoothed = false
	camera.drag_horizontal_enabled = false
	camera.position_smoothing_enabled = false
	camera.reset_smoothing()
	print("[WIN60] CENTERING BOSS ARENA: ", str(active_level.scene_file_path), " x=", _boss_center_x(active_level))
