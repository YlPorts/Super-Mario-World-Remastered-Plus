extends Node

var unlocked_achievements := []
var available_achievements: Array[Achievement] = []
var unlock_queue: Array[Achievement] = []
var showing_animation := false

var _queued_achievement_paths: Dictionary = {}
var _toast_tween: Tween

@onready var _toast: Control = $Ui/AchievementUnlockToast
@onready var _toast_title: Label = $Ui/AchievementUnlockToast/Panel/Title
@onready var _toast_icon: TextureRect = $Ui/AchievementUnlockToast/Panel/Icon
@onready var _toast_sfx: AudioStreamPlayer = $Ui/AchievementUnlockToast/SFX


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_hide_toast_immediately()
	get_viewport().size_changed.connect(_on_viewport_size_changed)


func get_achievement(achievement_name := "") -> Achievement:
	for achievement in available_achievements:
		if achievement.title == achievement_name:
			return achievement
	return null


func is_achievement_unlocked(achievement: Achievement) -> bool:
	if achievement == null:
		return false
	return SaveManager.current_save.achievements_unlocked.has(achievement.resource_path)


func unlock_achievement(achievement: Achievement = null) -> void:
	if achievement == null or GameManager.playing_custom_level:
		return

	var achievement_path := achievement.resource_path
	if is_achievement_unlocked(achievement) or _queued_achievement_paths.has(achievement_path):
		return

	_queued_achievement_paths[achievement_path] = true
	unlock_queue.push_back(achievement)
	SaveManager.current_save.achievements_unlocked.append(achievement_path)
	go_through_queue()


func go_through_queue() -> void:
	if showing_animation:
		return

	showing_animation = true
	while not unlock_queue.is_empty():
		var achievement: Achievement = unlock_queue.pop_front()
		_queued_achievement_paths.erase(achievement.resource_path)
		await show_animation(achievement)
	showing_animation = false


func show_animation(achievement: Achievement) -> void:
	if achievement == null:
		return

	if is_instance_valid(_toast_tween):
		_toast_tween.kill()

	_toast_title.text = achievement.title
	_toast_icon.texture = achievement.icon

	var viewport_size := get_viewport().get_visible_rect().size
	var toast_size := _toast.size
	if toast_size.x <= 0.0 or toast_size.y <= 0.0:
		toast_size = Vector2(216.0, 40.0)

	var y_position := maxf(0.0, viewport_size.y - toast_size.y)
	var hidden_position := Vector2(viewport_size.x + 8.0, y_position)
	var shown_position := Vector2(maxf(8.0, viewport_size.x - toast_size.x - 8.0), y_position)

	_toast.position = hidden_position
	_toast.show()
	_toast_sfx.play()

	_toast_tween = create_tween()
	_toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_toast_tween.tween_property(_toast, "position", shown_position, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_toast_tween.tween_interval(2.0)
	_toast_tween.tween_property(_toast, "position", hidden_position, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await _toast_tween.finished

	_toast.position = hidden_position
	_toast.hide()


func _on_viewport_size_changed() -> void:
	if not showing_animation:
		_hide_toast_immediately()


func _hide_toast_immediately() -> void:
	if not is_node_ready():
		return
	var viewport_size := get_viewport().get_visible_rect().size
	_toast.position = Vector2(viewport_size.x + 8.0, maxf(0.0, viewport_size.y - 40.0))
	_toast.hide()
