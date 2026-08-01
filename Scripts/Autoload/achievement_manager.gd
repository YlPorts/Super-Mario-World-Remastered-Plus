extends Node

const TOAST_WIDTH := 216.0
const TOAST_HEIGHT := 40.0
const SLIDE_TIME := 0.22
const HOLD_TIME := 2.0

var unlocked_achievements := []
var available_achievements: Array[Achievement] = []
var unlock_queue := []
var showing_animation := false
var toast_tween: Tween = null

@onready var toast: Control = $Ui/AchievementUnlockToast
@onready var legacy_animation: AnimationPlayer = $Ui/AchievementUnlockToast/AnimationPlayer
@onready var toast_sfx: AudioStreamPlayer = $Ui/AchievementUnlockToast/SFX

func _ready() -> void:
	# The original animation used x=480 and x=264, which only worked on the
	# old fixed canvas. Keep the toast anchored to the actual bottom-right edge.
	legacy_animation.stop()
	_configure_toast_geometry(true)
	toast.hide()
	get_viewport().size_changed.connect(_on_viewport_size_changed)

func _on_viewport_size_changed() -> void:
	if not showing_animation:
		_configure_toast_geometry(true)

func _configure_toast_geometry(hidden: bool) -> void:
	toast.anchor_left = 1.0
	toast.anchor_top = 1.0
	toast.anchor_right = 1.0
	toast.anchor_bottom = 1.0
	toast.offset_top = -TOAST_HEIGHT
	toast.offset_bottom = 0.0
	if hidden:
		toast.offset_left = 0.0
		toast.offset_right = TOAST_WIDTH
	else:
		toast.offset_left = -TOAST_WIDTH
		toast.offset_right = 0.0

func get_achievement(achievement_name := "") -> Achievement:
	for i in available_achievements:
		if i.title == achievement_name:
			return i
	return null

func is_achievement_unlocked(achievement: Achievement) -> bool:
	return SaveManager.current_save.achievements_unlocked.has(achievement.resource_path)

func unlock_achievement(achievement: Achievement = null):
	if achievement == null:
		return
	if is_achievement_unlocked(achievement) or GameManager.playing_custom_level:
		return
	unlock_queue.push_front(achievement)
	SaveManager.current_save.achievements_unlocked.append(achievement.resource_path)
	go_through_queue()

func go_through_queue(force := false) -> void:
	if showing_animation and not force:
		return
	if unlock_queue.is_empty():
		return
	showing_animation = true
	await show_animation(unlock_queue.pop_back())
	if not unlock_queue.is_empty():
		go_through_queue(true)
	else:
		showing_animation = false

func show_animation(achievement: Achievement) -> void:
	$Ui/AchievementUnlockToast/Panel/Title.text = achievement.title
	$Ui/AchievementUnlockToast/Panel/Icon.texture = achievement.icon
	legacy_animation.stop()
	if toast_tween != null and toast_tween.is_valid():
		toast_tween.kill()

	_configure_toast_geometry(true)
	toast.show()
	toast_sfx.play()
	toast_tween = create_tween()
	toast_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	toast_tween.set_trans(Tween.TRANS_QUAD)
	toast_tween.set_ease(Tween.EASE_OUT)
	toast_tween.parallel().tween_property(toast, "offset_left", -TOAST_WIDTH, SLIDE_TIME)
	toast_tween.parallel().tween_property(toast, "offset_right", 0.0, SLIDE_TIME)
	toast_tween.tween_interval(HOLD_TIME)
	toast_tween.set_ease(Tween.EASE_IN)
	toast_tween.parallel().tween_property(toast, "offset_left", 0.0, SLIDE_TIME)
	toast_tween.parallel().tween_property(toast, "offset_right", TOAST_WIDTH, SLIDE_TIME)
	await toast_tween.finished
	toast.hide()
	_configure_toast_geometry(true)
