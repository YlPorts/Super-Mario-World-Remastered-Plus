extends Node
## Shared desktop/mobile helper for the optional "unlock everything" button.
## A request made before choosing a save is persisted and applied as soon as the
## next save file is loaded.

signal unlock_state_changed(message: String)

const PENDING_FILE := "user://unlock_everything.pending"

var pending := false
var _applying := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	pending = _read_pending_state()
	set_process(pending)
	if pending:
		call_deferred("_try_apply_pending")


func _process(_delta: float) -> void:
	if pending:
		_try_apply_pending()


func request_unlock_everything() -> bool:
	pending = true
	_write_pending_state(true)
	set_process(true)
	if _can_unlock_current_save():
		return unlock_current_save()
	unlock_state_changed.emit("Waiting for a save file...")
	return false


func unlock_current_save() -> bool:
	if _applying or not _can_unlock_current_save():
		return false

	_applying = true
	var save: Dictionary = SaveManager.current_save
	var all_levels: Array[String] = []
	var secret_levels: Array[String] = []
	var dragon_levels: Array[String] = []
	var peach_coin_levels: Array[String] = []
	var dragon_coin_entries: Dictionary = save.get("dragon_coins_collected", {}).duplicate(true)

	for area in GameManager.current_campaign.map_areas:
		if area == null:
			continue
		for level in area.levels:
			if level == null:
				continue
			var level_path := str(level.resource_path)
			if level_path.is_empty():
				continue
			_append_unique(all_levels, level_path)
			if bool(level.has_secret_exit):
				_append_unique(secret_levels, level_path)
			if bool(level.has_dragon_coins):
				_append_unique(dragon_levels, level_path)
				if not dragon_coin_entries.has(level_path):
					dragon_coin_entries[level_path] = []
			if bool(level.has_peach_coin):
				_append_unique(peach_coin_levels, level_path)

	var all_achievements: Array[String] = []
	for achievement in GameManager.current_campaign.achievements:
		if achievement == null:
			continue
		var achievement_path := str(achievement.resource_path)
		if not achievement_path.is_empty():
			_append_unique(all_achievements, achievement_path)

	save["unlocked_levels"] = all_levels
	save["beaten_levels"] = all_levels.duplicate()
	save["special_beaten_levels"] = secret_levels
	save["dragon_levels"] = dragon_levels
	save["dragon_coins_collected"] = dragon_coin_entries
	save["peach_coins_collected"] = peach_coin_levels
	save["eggs_rescued"] = [true, true, true, true, true, true, true]
	save["colours_enabled"] = [true, true, true, true]
	save["achievements_unlocked"] = all_achievements
	save["game_beaten"] = true
	save["autumn_unlocked"] = true
	save["peach_coins_unlocked"] = true

	SaveManager.current_save = save
	SaveManager.save_current_file()
	SaveManager.apply_data()

	pending = false
	_write_pending_state(false)
	set_process(false)
	_applying = false
	unlock_state_changed.emit("Everything unlocked")
	return true


func _try_apply_pending() -> void:
	if pending and _can_unlock_current_save():
		if not unlock_current_save():
			unlock_state_changed.emit("Could not unlock this save")


func _can_unlock_current_save() -> bool:
	if _applying:
		return false
	if SaveManager.current_save == null or not SaveManager.current_save is Dictionary:
		return false
	if SaveManager.current_save.is_empty():
		return false
	if GameManager.current_campaign == null:
		return false
	return not GameManager.current_campaign.map_areas.is_empty()


func _append_unique(target: Array[String], value: String) -> void:
	if not target.has(value):
		target.append(value)


func _read_pending_state() -> bool:
	if not FileAccess.file_exists(PENDING_FILE):
		return false
	var file := FileAccess.open(PENDING_FILE, FileAccess.READ)
	if file == null:
		return false
	var value := file.get_as_text().strip_edges()
	file.close()
	return value == "1"


func _write_pending_state(enabled: bool) -> void:
	var file := FileAccess.open(PENDING_FILE, FileAccess.WRITE)
	if file == null:
		push_warning("Could not persist unlock-everything request")
		return
	file.store_string("1" if enabled else "0")
	file.close()
