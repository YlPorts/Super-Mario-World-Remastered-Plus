extends Node

@export var path: Path2D = null
@export var scroll_speed := 5.0

# Auto-scroll courses were authored around the original 480x270 camera. Under
# EXPAND, an ultrawide window increases the logical camera width while the
# moving walls remain at -240/+240. It also makes screen-based enemy triggers
# activate earlier. Temporarily using KEEP preserves the original gameplay
# rectangle and adds centered pillar-boxing only while auto-scroll is active.
const ORIGINAL_GAME_SIZE := Vector2i(480, 270)

var can_die := false
var _safe_framing_active := false
var _previous_scale_aspect := Window.CONTENT_SCALE_ASPECT_EXPAND
var _previous_scale_size := ORIGINAL_GAME_SIZE

@onready var walls: StaticBody2D = $Path/FollowJoint/Follow/Camera/Walls
@onready var path_node: Path2D = $Path
@onready var follow_joint: PathFollow2D = $Path/FollowJoint
@onready var camera: Camera2D = $Path/FollowJoint/Follow/Camera


func _exit_tree() -> void:
	GameManager.autoscrolling = false
	_restore_widescreen_framing()


func _ready() -> void:
	GameManager.autoscrolling = true
	_enable_original_autoscroll_framing()
	path_node.curve = path.curve.duplicate()
	follow_joint.progress_ratio = 0
	await get_tree().physics_frame
	walls.set_collision_layer_value(1, true)

	camera.enabled = true
	await get_tree().create_timer(1).timeout
	can_die = true


func _physics_process(delta: float) -> void:
	CoopManager.coop_camera.enabled = false
	follow_joint.progress += scroll_speed * delta
	camera.make_current()


func _enable_original_autoscroll_framing() -> void:
	if _safe_framing_active:
		return
	var window := get_window()
	if window == null:
		return
	_previous_scale_aspect = window.content_scale_aspect
	_previous_scale_size = window.content_scale_size
	window.content_scale_size = ORIGINAL_GAME_SIZE
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	_safe_framing_active = true
	print("[AUTOSCROLL61] SAFE 16:9 FRAME ENABLED")


func _restore_widescreen_framing() -> void:
	if not _safe_framing_active:
		return
	var window := get_window()
	if window != null:
		window.content_scale_size = _previous_scale_size
		window.content_scale_aspect = _previous_scale_aspect
	_safe_framing_active = false
	print("[AUTOSCROLL61] WIDESCREEN FRAME RESTORED")


func _on_area_2d_area_entered(area: Area2D) -> void:
	if area.get_parent() is Player and can_die:
		area.get_parent().die()
