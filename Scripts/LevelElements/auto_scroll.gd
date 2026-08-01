extends Node

@export var path: Path2D = null
@export var scroll_speed := 5.0

# Auto-scroll levels were authored around a 480x270 gameplay window. Windows
# widescreen keeps drawing the full expanded world, but this guard treats the
# central 480x270 rectangle as the interactive activation area. The original
# moving walls remain at -240/+240, while enemies, moving hazards and screen
# triggers in the ultrawide side previews stay dormant until they enter the
# authored gameplay rectangle.
const SAFE_HALF_EXTENTS := Vector2(240.0, 135.0)
const ENTRY_PADDING := Vector2(8.0, 8.0)
const EXIT_PADDING := Vector2(40.0, 24.0)
const RESCAN_INTERVAL := 0.20

var can_die := false
var _rescan_elapsed := 0.0
var _guarded_targets: Dictionary = {}
var _guard_active := false

@onready var walls: StaticBody2D = $Path/FollowJoint/Follow/Camera/Walls
@onready var path_node: Path2D = $Path
@onready var follow_joint: PathFollow2D = $Path/FollowJoint
@onready var camera: Camera2D = $Path/FollowJoint/Follow/Camera


func _exit_tree() -> void:
	GameManager.autoscrolling = false
	_restore_guarded_targets()
	_guard_active = false
	print("[AUTOSCROLL62] WIDESCREEN SAFE ZONE RESTORED")


func _ready() -> void:
	process_priority = -1000
	process_physics_priority = -1000
	GameManager.autoscrolling = true
	_guard_active = true

	# Do not change content_scale_aspect: EXPAND stays active, so ultrawide
	# continues to show the level scenery on both sides without black bars.
	path_node.curve = path.curve.duplicate()
	follow_joint.progress_ratio = 0
	_scan_activation_markers()
	_update_safe_zone_targets()
	print("[AUTOSCROLL62] WIDESCREEN VISUALS + 480PX GAMEPLAY SAFE ZONE ENABLED")

	await get_tree().physics_frame
	walls.set_collision_layer_value(1, true)
	camera.enabled = true
	camera.make_current()
	_update_safe_zone_targets()

	await get_tree().create_timer(1).timeout
	can_die = true


func _process(delta: float) -> void:
	if not _guard_active:
		return
	_rescan_elapsed += delta
	if _rescan_elapsed >= RESCAN_INTERVAL:
		_rescan_elapsed = 0.0
		_scan_activation_markers()
	_update_safe_zone_targets()


func _physics_process(delta: float) -> void:
	CoopManager.coop_camera.enabled = false
	follow_joint.progress += scroll_speed * delta
	camera.make_current()
	_update_safe_zone_targets()


func _scan_activation_markers() -> void:
	var root: Node = null
	if is_instance_valid(GameManager.current_level):
		root = GameManager.current_level
	else:
		root = get_tree().current_scene
	if root == null:
		return
	_collect_activation_markers(root)


func _collect_activation_markers(node: Node) -> void:
	for child in node.get_children():
		if child is VisibleOnScreenNotifier2D:
			_register_activation_marker(child)
		_collect_activation_markers(child)


func _register_activation_marker(marker: VisibleOnScreenNotifier2D) -> void:
	var target := _resolve_marker_target(marker)
	if not _can_guard_target(target):
		return

	var target_id := target.get_instance_id()
	var marker_id := marker.get_instance_id()
	var record: Dictionary
	if _guarded_targets.has(target_id):
		record = _guarded_targets[target_id]
	else:
		var active_mode := target.process_mode
		if active_mode == Node.PROCESS_MODE_DISABLED:
			active_mode = Node.PROCESS_MODE_INHERIT
		record = {
			"node": target,
			"markers": [],
			"marker_ids": {},
			"original_process_mode": target.process_mode,
			"active_process_mode": active_mode,
			"original_visible": target.visible if target is CanvasItem else true,
			"active": false,
			"initialized": false,
		}

	var marker_ids: Dictionary = record["marker_ids"]
	if marker_ids.has(marker_id):
		return
	marker_ids[marker_id] = true
	record["marker_ids"] = marker_ids

	var marker_record := {
		"node": marker,
		"screen_entered": _take_signal_connections(marker, &"screen_entered"),
		"screen_exited": _take_signal_connections(marker, &"screen_exited"),
	}
	var markers: Array = record["markers"]
	markers.append(marker_record)
	record["markers"] = markers
	_guarded_targets[target_id] = record


func _resolve_marker_target(marker: VisibleOnScreenNotifier2D) -> Node:
	if marker is VisibleOnScreenEnabler2D:
		var enabler := marker as VisibleOnScreenEnabler2D
		if not enabler.enable_node_path.is_empty():
			var explicit_target := enabler.get_node_or_null(enabler.enable_node_path)
			if explicit_target != null:
				return explicit_target
	return marker.get_parent()


func _can_guard_target(target: Node) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if target == self or self.is_ancestor_of(target):
		return false
	if target == GameManager.current_level or target == get_tree().current_scene:
		return false
	if target is Camera2D or target is CanvasLayer or target is TileMap or target is TileMapLayer:
		return false
	if not target is Node2D:
		return false

	var ancestor: Node = target
	while ancestor != null:
		if ancestor is Player:
			return false
		ancestor = ancestor.get_parent()
	return true


func _take_signal_connections(marker: Node, signal_name: StringName) -> Array:
	var stored: Array = []
	for connection in marker.get_signal_connection_list(signal_name):
		var callback: Callable = connection.get("callable", Callable())
		if not callback.is_valid():
			continue
		if marker.is_connected(signal_name, callback):
			marker.disconnect(signal_name, callback)
		stored.append({
			"callable": callback,
			"flags": int(connection.get("flags", 0)),
		})
	return stored


func _update_safe_zone_targets() -> void:
	if not _guard_active or not is_instance_valid(camera):
		return
	var center := camera.get_screen_center_position()
	var entry_rect := Rect2(
		center - SAFE_HALF_EXTENTS - ENTRY_PADDING,
		(SAFE_HALF_EXTENTS + ENTRY_PADDING) * 2.0
	)
	var exit_rect := Rect2(
		center - SAFE_HALF_EXTENTS - EXIT_PADDING,
		(SAFE_HALF_EXTENTS + EXIT_PADDING) * 2.0
	)

	for target_id in _guarded_targets.keys():
		var record: Dictionary = _guarded_targets[target_id]
		var target: Node = record["node"]
		if not is_instance_valid(target):
			_guarded_targets.erase(target_id)
			continue

		var test_rect := exit_rect if bool(record["active"]) else entry_rect
		var should_be_active := _record_intersects_rect(record, test_rect)
		_set_record_active(target_id, record, should_be_active)


func _record_intersects_rect(record: Dictionary, safe_rect: Rect2) -> bool:
	var markers: Array = record["markers"]
	for marker_record in markers:
		var marker: Node = marker_record["node"]
		if is_instance_valid(marker) and marker is Node2D:
			if safe_rect.has_point((marker as Node2D).global_position):
				return true

	var target: Node = record["node"]
	return target is Node2D and safe_rect.has_point((target as Node2D).global_position)


func _set_record_active(target_id, record: Dictionary, active: bool) -> void:
	var target: Node = record["node"]
	if not is_instance_valid(target):
		_guarded_targets.erase(target_id)
		return

	var was_initialized := bool(record["initialized"])
	var was_active := bool(record["active"])
	if was_initialized and was_active == active:
		# VisibleOnScreenEnabler2D may try to re-enable a side-preview target.
		# Reassert the safe-zone state every frame.
		if not active:
			target.process_mode = Node.PROCESS_MODE_DISABLED
			if target is CanvasItem:
				(target as CanvasItem).visible = false
		return

	record["initialized"] = true
	record["active"] = active
	if active:
		target.process_mode = int(record["active_process_mode"])
		if target is CanvasItem:
			(target as CanvasItem).visible = bool(record["original_visible"])
		_fire_stored_connections(record, "screen_entered")
	else:
		if was_initialized and was_active:
			_fire_stored_connections(record, "screen_exited")
		target.process_mode = Node.PROCESS_MODE_DISABLED
		if target is CanvasItem:
			(target as CanvasItem).visible = false
	_guarded_targets[target_id] = record


func _fire_stored_connections(record: Dictionary, connection_key: String) -> void:
	var markers: Array = record["markers"]
	for marker_index in range(markers.size()):
		var marker_record: Dictionary = markers[marker_index]
		var connections: Array = marker_record[connection_key]
		var remaining: Array = []
		for connection in connections:
			var callback: Callable = connection.get("callable", Callable())
			var flags := int(connection.get("flags", 0))
			if callback.is_valid():
				callback.call_deferred()
			if (flags & Object.CONNECT_ONE_SHOT) == 0:
				remaining.append(connection)
		marker_record[connection_key] = remaining
		markers[marker_index] = marker_record
	record["markers"] = markers


func _restore_guarded_targets() -> void:
	for target_id in _guarded_targets.keys():
		var record: Dictionary = _guarded_targets[target_id]
		var target: Node = record["node"]
		if is_instance_valid(target):
			target.process_mode = int(record["original_process_mode"])
			if target is CanvasItem:
				(target as CanvasItem).visible = bool(record["original_visible"])
		_restore_marker_connections(record)
	_guarded_targets.clear()


func _restore_marker_connections(record: Dictionary) -> void:
	var markers: Array = record["markers"]
	for marker_record in markers:
		var marker: Node = marker_record["node"]
		if not is_instance_valid(marker):
			continue
		_restore_connection_list(marker, &"screen_entered", marker_record["screen_entered"])
		_restore_connection_list(marker, &"screen_exited", marker_record["screen_exited"])


func _restore_connection_list(marker: Node, signal_name: StringName, connections: Array) -> void:
	for connection in connections:
		var callback: Callable = connection.get("callable", Callable())
		var flags := int(connection.get("flags", 0))
		if callback.is_valid() and not marker.is_connected(signal_name, callback):
			marker.connect(signal_name, callback, flags)


func _on_area_2d_area_entered(area: Area2D) -> void:
	if area.get_parent() is Player and can_die:
		area.get_parent().die()
