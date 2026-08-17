class_name FocusSessionMode
extends CanvasLayer

signal session_finished(result: String, summary: Dictionary)
signal recording_script_finished(output_path: String, summary: Dictionary)

const MAX_VALUE := 100.0
const MIN_VALUE := 0.0
const RESULT_VICTORY := "victory"
const RESULT_FAILURE := "failure"


@export var session_duration_seconds: int = 30 * 60
@export var focus_start: float = 85.0
@export var affection_start: float = 45.0
@export var chaos_start: float = 20.0
@export var objective_interval_seconds: int = 45
@export var show_tutorial_on_start: bool = true
@export var auto_start_session: bool = false
@export var demo_script_mode: bool = false
@export var recording_default_duration_seconds: int = 120
@export var recording_auto_export: bool = true
@export var trash_purge_old_default_days: int = 30
@export var recording_ops_tail_preview_size: int = 5
@export var recording_ops_panel_preview_size: int = 20

var focus_value: float = 0.0
var affection_value: float = 0.0
var chaos_value: float = 0.0

var _remaining_seconds: int = 0
var _elapsed_seconds: int = 0
var _running: bool = false
var _finished: bool = false
var _time_accumulator: float = 0.0
var _objective_timer: float = 0.0
var _last_state_impact_ms: Dictionary = {}

var _objective_system: FocusObjectiveSystem
var _hud: FocusHud
var _root: Control
var _demo_events: Array[Dictionary] = []
var _demo_cursor: int = 0
var _demo_paused: bool = false
var _current_objective_tier: int = 1

var _recording_mode: bool = false
var _recording_target_seconds: int = 0
var _recording_output_path: String = ""
var _recording_events: Array[Dictionary] = []
var _replay_mode: bool = false
var _replay_source_path: String = ""
var _recording_files: Array[String] = []
var _selected_recording_path: String = ""
var _trash_files: Array[String] = []
var _selected_trash_path: String = ""
var _demo_playback_speed: float = 1.0
var _demo_speed_options: Array[float] = [0.5, 1.0, 2.0]
var _delete_confirm_path: String = ""
var _delete_confirm_until: int = 0
var _purge_confirm_path: String = ""
var _purge_confirm_until: int = 0
var _purge_old_confirm_days: int = 0
var _purge_old_confirm_until: int = 0
var _trash_purge_old_days: int = 30
var _last_deleted_original_path: String = ""
var _last_deleted_trash_path: String = ""
var _ops_panel_visible: bool = false

var _tutorial: FocusTutorialController

var _demo_control_panel: PanelContainer
var _demo_status_label: Label
var _recording_select: OptionButton
var _trash_select: OptionButton
var _trash_purge_days_spin: SpinBox
var _speed_option: OptionButton
var _ops_panel: PanelContainer
var _ops_log_view: TextEdit

func _ready() -> void:
	_hud = FocusHud.new()
	_hud.name = "FocusHud"
	add_child(_hud)
	_objective_system = FocusObjectiveSystem.new()
	_objective_system.name = "ObjectiveSystem"
	add_child(_objective_system)
	_objective_system.set_cards(FocusObjectiveSystem.default_cards())
	_objective_system.objective_completed.connect(_on_objective_completed)
	_objective_system.objective_failed.connect(_on_objective_failed)
	_demo_events = _build_default_demo_events()
	_tutorial = FocusTutorialController.new()
	_tutorial.name = "TutorialController"
	add_child(_tutorial)
	_tutorial.setup(FocusTutorialController.default_steps(), func(text: String): _hud.set_hint(text))
	_trash_purge_old_days = maxi(trash_purge_old_default_days, 1)
	_load_last_deleted_recording()
	# 默认不自动开启专注会话，避免桌宠启动约 1 分钟后必然弹出失败面板
	if auto_start_session:
		start_session()

func _process(delta: float) -> void:
	if not _running:
		return

	_tutorial.update(delta)

	_time_accumulator += delta
	_objective_timer -= delta

	while _time_accumulator >= 1.0:
		_time_accumulator -= 1.0
		_elapsed_seconds += 1
		_remaining_seconds = max(_remaining_seconds - 1, 0)
		_current_objective_tier = _current_difficulty_tier()

		# 核心循环：被动衰减 -> Demo脚本注入 -> 目标/胜负判定
		_apply_passive_changes()
		_consume_demo_events()
		if _objective_system.check_timeout(_objective_timer, focus_value, affection_value, chaos_value):
			_apply_delta(-4.0, -3.0, 6.0, "Objective failed. Penalty applied.")
			_record_event("objective_failed", {
				"id": _objective_system.get_objective_key(),
				"target": _objective_system.get_objective_target()
			})
			_roll_objective()
		_check_end_condition()
		_check_recording_target()
		if not _running:
			break

	_update_ui()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_F5:
		start_session()
		return

	if key_event.keycode == KEY_F1 and _tutorial.active:
		_tutorial.skip()
		return

	if key_event.keycode == KEY_F2:
		_on_ops_panel_pressed()
		return

	if key_event.keycode == KEY_F9:
		set_demo_script_enabled(not demo_script_mode, true)
		if _demo_control_panel:
			_demo_control_panel.visible = demo_script_mode
		_hud.set_hint("Demo script mode: " + ("ON" if demo_script_mode else "OFF"))
		return

	if key_event.keycode == KEY_F10:
		if _recording_mode:
			stop_recording_script("hotkey_stop")
		else:
			start_recording_script(recording_default_duration_seconds, true)
		return

	if key_event.keycode == KEY_F11:
		if not _replay_selected_or_latest():
			_hud.set_hint("Replay failed: no valid recording log found.")
		return

	if key_event.keycode == KEY_F8:
		_on_demo_delete_pressed()
		return

	if key_event.keycode == KEY_F4:
		_on_trash_purge_old_pressed()
		return

	if key_event.keycode == KEY_F6:
		_on_trash_purge_pressed()
		return

	if key_event.keycode == KEY_F7:
		_on_demo_restore_pressed()
		return

	if key_event.keycode == KEY_F3:
		_on_ops_tail_pressed()
		return

	if key_event.keycode == KEY_F12:
		_cycle_demo_speed()

func start_session() -> void:
	focus_value = focus_start
	affection_value = affection_start
	chaos_value = chaos_start

	_remaining_seconds = session_duration_seconds
	_elapsed_seconds = 0
	_running = true
	_finished = false
	_time_accumulator = 0.0
	_last_state_impact_ms.clear()
	_hud.hide_result()
	_hud.show_hud()
	_demo_cursor = 0
	_objective_system.reset_demo_cursor()
	_demo_paused = false
	_current_objective_tier = 1
	_hud.set_hint("Session started. Keep focus until time runs out.")
	_hud.set_help(_build_help_text())
	_refresh_demo_control_ui()
	_record_event("session_start", {
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value
	})

	_tutorial.start(show_tutorial_on_start)
	_roll_objective()
	_update_ui()

func set_objective_cards(cards: Array[Dictionary]) -> void:
	_objective_system.set_cards(cards)
	_roll_objective()
	_update_ui()

func set_demo_events(events: Array[Dictionary]) -> void:
	var normalized: Array[Dictionary] = []
	for event in events:
		if not event.has("type"):
			continue
		normalized.append({
			"at": int(event.get("at", 0)),
			"type": String(event.get("type", "")),
			"value": event.get("value", "")
		})
	normalized.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("at", 0)) < int(b.get("at", 0))
	)
	_demo_events = normalized
	_demo_cursor = 0

func start_recording_script(duration_seconds: int = -1, force_demo_mode: bool = true) -> void:
	var duration := duration_seconds
	if duration <= 0:
		duration = recording_default_duration_seconds
	_recording_mode = true
	_recording_target_seconds = max(duration, 10)
	_recording_events.clear()
	_recording_output_path = ""
	_replay_mode = false
	_replay_source_path = ""

	if force_demo_mode and not demo_script_mode:
		set_demo_script_enabled(true, false)

	start_session()
	_record_event("recording_start", {
		"target_seconds": _recording_target_seconds,
		"demo_mode": demo_script_mode
	})
	_hud.set_hint("Recording script started.")
	_refresh_demo_control_ui()

func stop_recording_script(reason: String = "manual_stop") -> void:
	if not _recording_mode:
		return
	_finalize_recording(reason)

func export_recording_log(custom_path: String = "") -> String:
	var path := custom_path
	if path.is_empty():
		var dir := DirAccess.open("user://")
		if dir:
			dir.make_dir_recursive("recordings")
		path = "user://recordings/focus_recording_%d.json" % Time.get_unix_time_from_system()

	var payload := {
		"generated_at": Time.get_unix_time_from_system(),
		"target_seconds": _recording_target_seconds,
		"demo_mode": demo_script_mode,
		"events": _recording_events
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return path

func replay_recording_log(path: String = "") -> bool:
	var resolved_path := path
	if resolved_path.is_empty():
		resolved_path = _find_latest_recording_path()
	if resolved_path.is_empty():
		return false
	if _recording_files.find(resolved_path) == -1:
		_refresh_recording_list(false)
	_select_recording_path(resolved_path)

	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		return false
	var content := file.get_as_text()
	file.close()

	var payload = JSON.parse_string(content)
	if typeof(payload) != TYPE_DICTIONARY:
		return false

	return replay_recording_payload(payload as Dictionary, resolved_path)

func _replay_selected_or_latest() -> bool:
	var preferred_path := _selected_recording_path
	if preferred_path.is_empty():
		return replay_recording_log()
	if replay_recording_log(preferred_path):
		return true
	var latest_path := _find_latest_recording_path()
	if latest_path.is_empty() or latest_path == preferred_path:
		return false
	if replay_recording_log(latest_path):
		_hud.set_hint("Selected replay failed, fallback to latest: " + _short_recording_path(latest_path))
		return true
	return false

func replay_recording_payload(payload: Dictionary, source_tag: String = "") -> bool:
	var events = payload.get("events", [])
	if not (events is Array):
		return false

	var replay_events: Array[Dictionary] = []
	for raw_event in events:
		if not (raw_event is Dictionary):
			continue
		var event_dict := raw_event as Dictionary
		var at := int(event_dict.get("t", 0))
		var event_name := String(event_dict.get("event", ""))
		match event_name:
			"typing_attack":
				replay_events.append({"at": at, "type": "typing"})
			"item_used":
				var item_type := String(event_dict.get("item_type", ""))
				if item_type == "food":
					replay_events.append({"at": at, "type": "item_food"})
				elif item_type == "wand":
					replay_events.append({"at": at, "type": "item_wand"})
			"state_impact":
				replay_events.append({
					"at": at,
					"type": "state",
					"value": String(event_dict.get("state", "Watching"))
				})
			_:
				pass

	if replay_events.is_empty():
		return false

	replay_events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("at", 0)) < int(b.get("at", 0))
	)
	set_demo_events(replay_events)
	set_demo_script_enabled(true, false)
	_replay_mode = true
	_replay_source_path = source_tag
	start_session()
	_hud.set_hint("Replay loaded: " + _short_recording_path(_replay_source_path))
	_refresh_demo_control_ui()
	return true

func set_demo_playback_speed(speed: float) -> void:
	if speed <= 0.0:
		return
	_demo_playback_speed = speed
	var speed_index := _demo_speed_options.find(_demo_playback_speed)
	if _speed_option and speed_index != -1 and _speed_option.get_item_count() > speed_index:
		_speed_option.select(speed_index)
	_refresh_demo_control_ui()

func _cycle_demo_speed() -> void:
	var current_index := _demo_speed_options.find(_demo_playback_speed)
	if current_index == -1:
		current_index = 0
	var next_index := (current_index + 1) % _demo_speed_options.size()
	_demo_playback_speed = _demo_speed_options[next_index]
	if _speed_option and _speed_option.get_item_count() == _demo_speed_options.size():
		_speed_option.select(next_index)
	_hud.set_hint("Replay speed: " + str(_demo_playback_speed) + "x")
	_refresh_demo_control_ui()

func _refresh_recording_list(select_latest: bool = true) -> void:
	var previous_selection := _selected_recording_path
	_recording_files.clear()

	var dir := DirAccess.open("user://recordings")
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".json"):
				_recording_files.append("user://recordings/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	_recording_files.sort()
	if _recording_select:
		_recording_select.clear()
		for full_path in _recording_files:
			_recording_select.add_item(_short_recording_path(full_path))

	if _recording_files.is_empty():
		_selected_recording_path = ""
		_refresh_demo_control_ui()
		return

	var selected_index := 0
	if select_latest:
		selected_index = _recording_files.size() - 1
	elif not previous_selection.is_empty():
		var prev_index := _recording_files.find(previous_selection)
		if prev_index != -1:
			selected_index = prev_index
	_selected_recording_path = _recording_files[selected_index]

	if _recording_select and _recording_select.get_item_count() > selected_index:
		_recording_select.select(selected_index)
	_refresh_demo_control_ui()

func _refresh_trash_list(select_latest: bool = true) -> void:
	var previous_selection := _selected_trash_path
	_trash_files.clear()

	var dir := DirAccess.open("user://recordings/.trash")
	if dir != null:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and file_name.ends_with(".json") and file_name != "last_deleted.json":
				_trash_files.append("user://recordings/.trash/" + file_name)
			file_name = dir.get_next()
		dir.list_dir_end()

	_trash_files.sort()
	if _trash_select:
		_trash_select.clear()
		for full_path in _trash_files:
			_trash_select.add_item(_short_recording_path(full_path))

	if _trash_files.is_empty():
		_selected_trash_path = ""
		_refresh_demo_control_ui()
		return

	var selected_index := 0
	if select_latest:
		selected_index = _trash_files.size() - 1
	elif not previous_selection.is_empty():
		var prev_index := _trash_files.find(previous_selection)
		if prev_index != -1:
			selected_index = prev_index
	_selected_trash_path = _trash_files[selected_index]

	if _trash_select and _trash_select.get_item_count() > selected_index:
		_trash_select.select(selected_index)
	_refresh_demo_control_ui()

func _select_recording_path(path: String) -> void:
	if path.is_empty():
		return
	var idx := _recording_files.find(path)
	if idx == -1:
		return
	_selected_recording_path = path
	if _recording_select and _recording_select.get_item_count() > idx:
		_recording_select.select(idx)
	_refresh_demo_control_ui()

func _select_trash_path(path: String) -> void:
	if path.is_empty():
		_selected_trash_path = ""
		_refresh_demo_control_ui()
		return
	var idx := _trash_files.find(path)
	if idx == -1:
		_selected_trash_path = ""
		_refresh_demo_control_ui()
		return
	_selected_trash_path = path
	if _trash_select and _trash_select.get_item_count() > idx:
		_trash_select.select(idx)
	_refresh_demo_control_ui()

func _clear_delete_confirmation() -> void:
	_delete_confirm_path = ""
	_delete_confirm_until = 0

func _clear_purge_confirmation() -> void:
	_purge_confirm_path = ""
	_purge_confirm_until = 0

func _clear_purge_old_confirmation() -> void:
	_purge_old_confirm_days = 0
	_purge_old_confirm_until = 0

func _ensure_recording_dirs() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.make_dir_recursive("recordings")
	dir.make_dir_recursive("recordings/.trash")

func _append_recording_op_log(action: String, source_path: String, target_path: String, result: String) -> void:
	_ensure_recording_dirs()
	var log_path := "user://recordings/recording_ops.jsonl"
	var file: FileAccess = null
	if FileAccess.file_exists(log_path):
		file = FileAccess.open(log_path, FileAccess.READ_WRITE)
		if file:
			file.seek_end()
	else:
		file = FileAccess.open(log_path, FileAccess.WRITE)
	if file == null:
		return
	var payload := {
		"t": Time.get_unix_time_from_system(),
		"action": action,
		"source_path": source_path,
		"target_path": target_path,
		"result": result
	}
	file.store_line(JSON.stringify(payload))
	file.close()
	_refresh_ops_panel()

func _tail_recording_ops(max_lines: int = 5) -> Array[Dictionary]:
	var safe_max := maxi(max_lines, 1)
	var log_path := "user://recordings/recording_ops.jsonl"
	if not FileAccess.file_exists(log_path):
		return []
	var file := FileAccess.open(log_path, FileAccess.READ)
	if file == null:
		return []
	var content := file.get_as_text()
	file.close()
	if content.is_empty():
		return []
	var lines := content.split("\n", false)
	if lines.is_empty():
		return []
	var start_idx := maxi(lines.size() - safe_max, 0)
	var tail: Array[Dictionary] = []
	for i in range(start_idx, lines.size()):
		var line := String(lines[i]).strip_edges()
		if line.is_empty():
			continue
		var parsed = JSON.parse_string(line)
		if typeof(parsed) == TYPE_DICTIONARY:
			tail.append(parsed as Dictionary)
	return tail

func export_recording_ops_log(custom_path: String = "") -> String:
	var source_path := "user://recordings/recording_ops.jsonl"
	if not FileAccess.file_exists(source_path):
		return ""
	var target_path := custom_path
	if target_path.is_empty():
		_ensure_recording_dirs()
		target_path = "user://recordings/recording_ops_export_%d.jsonl" % Time.get_unix_time_from_system()
	var source_file := FileAccess.open(source_path, FileAccess.READ)
	if source_file == null:
		return ""
	var content := source_file.get_as_text()
	source_file.close()
	var target_file := FileAccess.open(target_path, FileAccess.WRITE)
	if target_file == null:
		return ""
	target_file.store_string(content)
	target_file.close()
	return target_path

func _format_ops_entry(entry: Dictionary) -> String:
	var ts := int(entry.get("t", 0))
	var action := String(entry.get("action", "-"))
	var result := String(entry.get("result", "-"))
	var source_path := String(entry.get("source_path", ""))
	var target_path := String(entry.get("target_path", ""))
	var source_short := _short_recording_path(source_path)
	var target_short := _short_recording_path(target_path)
	return str(ts) + " | " + action + " | " + result + " | " + source_short + " -> " + target_short

func _refresh_ops_panel() -> void:
	if not _ops_panel or not _ops_log_view:
		return
	_ops_panel.visible = _ops_panel_visible
	if not _ops_panel_visible:
		return
	var max_lines := maxi(recording_ops_panel_preview_size, 1)
	var tail := _tail_recording_ops(max_lines)
	if tail.is_empty():
		_ops_log_view.text = "No ops logs."
		return
	var lines: Array[String] = []
	for entry in tail:
		lines.append(_format_ops_entry(entry))
	_ops_log_view.text = "\n".join(lines)

func _persist_last_deleted_recording() -> void:
	_ensure_recording_dirs()
	var meta_path := "user://recordings/.trash/last_deleted.json"
	if _last_deleted_trash_path.is_empty():
		var absolute_meta_path := ProjectSettings.globalize_path(meta_path)
		if FileAccess.file_exists(meta_path):
			DirAccess.remove_absolute(absolute_meta_path)
		return
	var file := FileAccess.open(meta_path, FileAccess.WRITE)
	if file == null:
		return
	var payload := {
		"updated_at": Time.get_unix_time_from_system(),
		"original_path": _last_deleted_original_path,
		"trash_path": _last_deleted_trash_path
	}
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()

func _clear_last_deleted_recording(persist: bool = true) -> void:
	_last_deleted_original_path = ""
	_last_deleted_trash_path = ""
	if persist:
		_persist_last_deleted_recording()

func _load_last_deleted_recording() -> void:
	_last_deleted_original_path = ""
	_last_deleted_trash_path = ""
	var meta_path := "user://recordings/.trash/last_deleted.json"
	if not FileAccess.file_exists(meta_path):
		return
	var file := FileAccess.open(meta_path, FileAccess.READ)
	if file == null:
		return
	var content := file.get_as_text()
	file.close()
	var payload = JSON.parse_string(content)
	if typeof(payload) != TYPE_DICTIONARY:
		return
	var original_path := String(payload.get("original_path", ""))
	var trash_path := String(payload.get("trash_path", ""))
	if trash_path.is_empty() or not FileAccess.file_exists(trash_path):
		_clear_last_deleted_recording(true)
		return
	_last_deleted_original_path = original_path
	_last_deleted_trash_path = trash_path

func _delete_recording_path(path: String) -> bool:
	if path.is_empty():
		return false
	var normalized := path.replace("\\", "/")
	if not normalized.begins_with("user://recordings/"):
		return false
	if not FileAccess.file_exists(normalized):
		_append_recording_op_log("delete", normalized, "", "missing_source")
		return false
	_ensure_recording_dirs()
	var trash_name := "%d_%d_%s" % [
		Time.get_unix_time_from_system(),
		int(Time.get_ticks_msec() % 1000),
		_short_recording_path(normalized)
	]
	var trash_path := "user://recordings/.trash/" + trash_name
	var source_absolute_path := ProjectSettings.globalize_path(normalized)
	var trash_absolute_path := ProjectSettings.globalize_path(trash_path)
	var err := DirAccess.rename_absolute(source_absolute_path, trash_absolute_path)
	if err != OK:
		_append_recording_op_log("delete", normalized, trash_path, "rename_failed")
		return false
	_last_deleted_original_path = normalized
	_last_deleted_trash_path = trash_path
	_persist_last_deleted_recording()
	_append_recording_op_log("delete", normalized, trash_path, "ok")
	return true

func _build_restored_recording_path(original_path: String) -> String:
	var target_path := original_path
	if target_path.is_empty() or not target_path.begins_with("user://recordings/"):
		target_path = "user://recordings/restored_%d.json" % Time.get_unix_time_from_system()
	if not FileAccess.file_exists(target_path):
		return target_path
	var short_name := _short_recording_path(target_path)
	var dot_idx := short_name.rfind(".")
	var stem := short_name
	if dot_idx > 0:
		stem = short_name.substr(0, dot_idx)
	return "user://recordings/%s_restored_%d.json" % [stem, Time.get_unix_time_from_system()]

func _derive_original_path_from_trash(trash_path: String) -> String:
	if trash_path == _last_deleted_trash_path and not _last_deleted_original_path.is_empty():
		return _last_deleted_original_path
	var short_name := _short_recording_path(trash_path)
	var first_sep := short_name.find("_")
	if first_sep == -1:
		return ""
	var second_sep := short_name.find("_", first_sep + 1)
	if second_sep == -1 or second_sep + 1 >= short_name.length():
		return ""
	var recovered_name := short_name.substr(second_sep + 1)
	if recovered_name.is_empty():
		return ""
	return "user://recordings/" + recovered_name

func _restore_trash_path(trash_path: String, preferred_original_path: String = "") -> String:
	if trash_path.is_empty():
		return ""
	if not FileAccess.file_exists(trash_path):
		_append_recording_op_log("restore", trash_path, "", "missing_trash")
		if trash_path == _last_deleted_trash_path:
			_clear_last_deleted_recording(true)
		return ""
	_ensure_recording_dirs()
	var original_path := preferred_original_path
	if original_path.is_empty():
		original_path = _derive_original_path_from_trash(trash_path)
	var restore_target_path := _build_restored_recording_path(original_path)
	var trash_absolute_path := ProjectSettings.globalize_path(trash_path)
	var target_absolute_path := ProjectSettings.globalize_path(restore_target_path)
	var err := DirAccess.rename_absolute(trash_absolute_path, target_absolute_path)
	if err != OK:
		_append_recording_op_log("restore", trash_path, restore_target_path, "rename_failed")
		return ""
	if trash_path == _last_deleted_trash_path:
		_clear_last_deleted_recording(true)
	_append_recording_op_log("restore", trash_path, restore_target_path, "ok")
	return restore_target_path

func _restore_last_deleted_recording() -> String:
	return _restore_trash_path(_last_deleted_trash_path, _last_deleted_original_path)

func _purge_trash_path(trash_path: String) -> bool:
	if trash_path.is_empty():
		return false
	var normalized := trash_path.replace("\\", "/")
	if not normalized.begins_with("user://recordings/.trash/"):
		return false
	if not FileAccess.file_exists(normalized):
		_append_recording_op_log("purge", normalized, "", "missing_trash")
		return false
	var absolute_path := ProjectSettings.globalize_path(normalized)
	var err := DirAccess.remove_absolute(absolute_path)
	if err != OK:
		_append_recording_op_log("purge", normalized, "", "remove_failed")
		return false
	if normalized == _last_deleted_trash_path:
		_clear_last_deleted_recording(true)
	_append_recording_op_log("purge", normalized, "", "ok")
	return true

func _purge_trash_older_than(days: int) -> int:
	if days <= 0:
		return 0
	_refresh_trash_list(false)
	var now := int(Time.get_unix_time_from_system())
	var threshold := now - days * 24 * 60 * 60
	var candidates: Array[String] = []
	for trash_path in _trash_files:
		var modified_time := int(FileAccess.get_modified_time(trash_path))
		if modified_time <= 0:
			continue
		if modified_time <= threshold:
			candidates.append(trash_path)
	var purged_count := 0
	for trash_path in candidates:
		if _purge_trash_path(trash_path):
			purged_count += 1
	return purged_count

func set_demo_script_enabled(enabled: bool, restart_session: bool = false) -> void:
	demo_script_mode = enabled
	_objective_system.set_demo_mode(enabled)
	_demo_paused = false
	if not enabled:
		_replay_mode = false
		_replay_source_path = ""
	if restart_session:
		start_session()
	_refresh_demo_control_ui()

func start_demo() -> void:
	if not demo_script_mode:
		set_demo_script_enabled(true, false)
	_demo_paused = false
	if not _running:
		start_session()
	_refresh_demo_control_ui()

func pause_demo(paused: bool = true) -> void:
	_demo_paused = paused
	_refresh_demo_control_ui()

func trigger_next_demo_event() -> bool:
	if _demo_events.is_empty():
		return false
	if _demo_cursor >= _demo_events.size():
		return false
	var event := _demo_events[_demo_cursor]
	_demo_cursor += 1
	_apply_demo_event(event)
	_refresh_demo_control_ui()
	return true

func on_typing_attack() -> void:
	if not _running:
		return
	_apply_delta(-8.0, -2.0, 16.0, "Typing attack! Focus dropped.")
	_record_event("typing_attack")
	_check_end_condition()

func on_item_used(item_type: String) -> void:
	if not _running:
		return

	match item_type:
		"food":
			_apply_delta(4.0, 8.0, -14.0, "Food used. Cat calmed down.")
		"wand":
			_apply_delta(3.0, 5.0, -9.0, "Wand used. Cat attention redirected.")
		_:
			return

	_record_event("item_used", {"item_type": item_type})
	if _objective_system.check_progress(focus_value, affection_value, chaos_value):
		_apply_delta(3.0, 4.0, -4.0, "Objective completed. Bonus applied.")
		_record_event("objective_completed", {
			"id": _objective_system.get_objective_key(),
			"target": _objective_system.get_objective_target()
		})
		_roll_objective()
	_check_end_condition()

func on_cat_state_changed(to_state: StringName) -> void:
	if not _running:
		return

	var key := String(to_state)
	var now := Time.get_ticks_msec()
	var last_ms := int(_last_state_impact_ms.get(key, 0))
	if now - last_ms < 1200:
		return
	_last_state_impact_ms[key] = now

	match to_state:
		&"Blocking":
			_apply_delta(-5.0, -1.0, 10.0, "Blocking state triggered.")
		&"Chasing":
			_apply_delta(-4.0, 0.0, 8.0, "Chasing state triggered.")
		&"Pouncing":
			_apply_delta(-3.0, 0.0, 7.0, "Pouncing state triggered.")
		&"TailWagging":
			_apply_delta(1.0, 4.0, -3.0, "Tail wagging improved mood.")
		&"Watching":
			_apply_delta(-1.0, 1.0, 2.0, "Cat is watching your cursor.")
		_:
			return

	_record_event("state_impact", {"state": String(to_state)})
	if _objective_system.check_progress(focus_value, affection_value, chaos_value):
		_apply_delta(3.0, 4.0, -4.0, "Objective completed. Bonus applied.")
		_record_event("objective_completed", {
			"id": _objective_system.get_objective_key(),
			"target": _objective_system.get_objective_target()
		})
		_roll_objective()
	_check_end_condition()

func get_snapshot() -> Dictionary:
	return {
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value,
		"remaining_seconds": _remaining_seconds,
		"running": _running,
		"objective": _objective_system.get_objective_key()
	}

func _apply_passive_changes() -> void:
	var passive_focus_drain := 1.0 + chaos_value * 0.03
	focus_value = clampf(focus_value - passive_focus_drain, MIN_VALUE, MAX_VALUE)
	chaos_value = clampf(chaos_value - 0.8, MIN_VALUE, MAX_VALUE)

	var affection_shift := 0.15
	if focus_value < 35.0:
		affection_shift = -0.45
	affection_value = clampf(affection_value + affection_shift, MIN_VALUE, MAX_VALUE)

	if _objective_system.check_progress(focus_value, affection_value, chaos_value):
		_apply_delta(3.0, 4.0, -4.0, "Objective completed. Bonus applied.")
		_record_event("objective_completed", {
			"id": _objective_system.get_objective_key(),
			"target": _objective_system.get_objective_target()
		})
		_roll_objective()

func _apply_delta(focus_delta: float, affection_delta: float, chaos_delta: float, hint: String = "") -> void:
	focus_value = clampf(focus_value + focus_delta, MIN_VALUE, MAX_VALUE)
	affection_value = clampf(affection_value + affection_delta, MIN_VALUE, MAX_VALUE)
	chaos_value = clampf(chaos_value + chaos_delta, MIN_VALUE, MAX_VALUE)
	if not hint.is_empty():
		_hud.set_hint(hint)

func _roll_objective() -> void:
	_objective_timer = float(objective_interval_seconds)
	_objective_system.roll_new_objective(_current_difficulty_tier(), focus_value, affection_value, chaos_value)
	_record_event("objective_roll", {
		"id": _objective_system.get_objective_key(),
		"target": _objective_system.get_objective_target(),
		"tier": _current_difficulty_tier()
	})

func _current_difficulty_tier() -> int:
	var ratio := 0.0
	if session_duration_seconds > 0:
		ratio = clampf(float(_elapsed_seconds) / float(session_duration_seconds), 0.0, 1.0)
	if ratio < 0.34:
		return 1
	if ratio < 0.67:
		return 2
	return 3

func _on_objective_completed(objective_id: String, _target: float) -> void:
	pass  # 奖励在调用点就地应用，信号仅作外部观测

func _on_objective_failed(objective_id: String, _target: float) -> void:
	pass  # 惩罚在调用点就地应用，信号仅作外部观测

func _check_end_condition() -> void:
	if focus_value <= 0.0 or chaos_value >= 100.0:
		_finish_session(RESULT_FAILURE)
		return
	if _remaining_seconds <= 0:
		_finish_session(RESULT_VICTORY)

func _finish_session(result: String) -> void:
	if _finished:
		return

	_running = false
	_finished = true

	if result == RESULT_VICTORY:
		_hud.show_result("Session Complete", "You stayed productive for 30 minutes.\nF5 restart | F9 toggle demo mode.")
	else:
		_hud.show_result("Session Failed", "Focus collapsed.\nF5 restart | F9 toggle demo mode.")

	session_finished.emit(result, {
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value,
		"remaining_seconds": _remaining_seconds
	})
	_record_event("session_finished", {"result": result})
	if _recording_mode:
		_finalize_recording("session_finished")

func _consume_demo_events() -> void:
	if not demo_script_mode:
		return
	if _demo_paused:
		return
	var timeline_seconds := _elapsed_seconds
	if _replay_mode:
		timeline_seconds = int(floor(float(_elapsed_seconds) * _demo_playback_speed))
	while _demo_cursor < _demo_events.size():
		var event := _demo_events[_demo_cursor]
		var at_second := int(event.get("at", -1))
		if at_second > timeline_seconds:
			return
		_demo_cursor += 1
		_apply_demo_event(event)

func _apply_demo_event(event: Dictionary) -> void:
	var event_type := String(event.get("type", ""))
	_record_event("demo_event", {
		"type": event_type,
		"value": event.get("value", ""),
		"at": int(event.get("at", -1))
	})
	match event_type:
		"typing":
			on_typing_attack()
		"item_food":
			on_item_used("food")
		"item_wand":
			on_item_used("wand")
		"state":
			var state_name := StringName(event.get("value", "Watching"))
			on_cat_state_changed(state_name)
		"hint":
			_hud.set_hint(String(event.get("value", "")))
		_:
			pass

func _check_recording_target() -> void:
	if not _recording_mode:
		return
	if _elapsed_seconds < _recording_target_seconds:
		return
	_record_event("recording_target_reached")
	if _running and not _finished:
		_finish_session(RESULT_VICTORY)

func _find_latest_recording_path() -> String:
	var dir := DirAccess.open("user://recordings")
	if dir == null:
		return ""

	var latest_file := ""
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			if latest_file.is_empty() or file_name > latest_file:
				latest_file = file_name
		file_name = dir.get_next()
	dir.list_dir_end()

	if latest_file.is_empty():
		return ""
	return "user://recordings/" + latest_file

func _short_recording_path(path: String) -> String:
	if path.is_empty():
		return "(memory)"
	var normalized := path.replace("\\", "/")
	var idx := normalized.rfind("/")
	if idx == -1:
		return normalized
	return normalized.substr(idx + 1)

func _record_event(event_name: String, extra: Dictionary = {}) -> void:
	if not _recording_mode:
		return
	var payload := {
		"t": _elapsed_seconds,
		"event": event_name,
		"focus": round(focus_value * 10.0) / 10.0,
		"affection": round(affection_value * 10.0) / 10.0,
		"chaos": round(chaos_value * 10.0) / 10.0,
		"objective": _objective_system.get_objective_key()
	}
	for key in extra.keys():
		payload[key] = extra[key]
	_recording_events.append(payload)

func _finalize_recording(reason: String) -> void:
	if not _recording_mode:
		return

	_record_event("recording_finalize", {"reason": reason})

	if recording_auto_export:
		_recording_output_path = export_recording_log()
		if not _recording_output_path.is_empty():
			_refresh_recording_list(true)
			_select_recording_path(_recording_output_path)
	else:
		_recording_output_path = ""

	var summary := _build_recording_summary(reason)
	recording_script_finished.emit(_recording_output_path, summary)

	if _recording_output_path.is_empty():
		_hud.set_hint("Recording finished: " + reason)
	else:
		_hud.set_hint("Recording exported: " + _recording_output_path)

	_recording_mode = false
	_refresh_demo_control_ui()

func _build_recording_summary(reason: String) -> Dictionary:
	return {
		"reason": reason,
		"duration_seconds": _elapsed_seconds,
		"target_seconds": _recording_target_seconds,
		"events_count": _recording_events.size(),
		"output_path": _recording_output_path
	}

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_demo_control_panel = PanelContainer.new()
	_demo_control_panel.position = Vector2(462, 16)
	_demo_control_panel.custom_minimum_size = Vector2(420, 320)
	_demo_control_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_demo_control_panel.visible = false
	_root.add_child(_demo_control_panel)

	var demo_box := VBoxContainer.new()
	demo_box.add_theme_constant_override("separation", 4)
	_demo_control_panel.add_child(demo_box)

	var demo_title := Label.new()
	demo_title.text = "Demo Control"
	demo_box.add_child(demo_title)

	_demo_status_label = Label.new()
	_demo_status_label.text = "-"
	demo_box.add_child(_demo_status_label)

	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 4)
	demo_box.add_child(speed_row)

	var speed_label := Label.new()
	speed_label.text = "Speed"
	speed_row.add_child(speed_label)

	_speed_option = OptionButton.new()
	_speed_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for speed in _demo_speed_options:
		_speed_option.add_item(str(speed) + "x")
	var speed_index := _demo_speed_options.find(_demo_playback_speed)
	if speed_index == -1:
		speed_index = 1
	_speed_option.select(speed_index)
	_speed_option.item_selected.connect(_on_speed_selected)
	speed_row.add_child(_speed_option)

	var file_row := HBoxContainer.new()
	file_row.add_theme_constant_override("separation", 4)
	demo_box.add_child(file_row)

	_recording_select = OptionButton.new()
	_recording_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_recording_select.item_selected.connect(_on_recording_selected)
	file_row.add_child(_recording_select)

	var demo_refresh_btn := Button.new()
	demo_refresh_btn.text = "Refresh"
	demo_refresh_btn.pressed.connect(_on_demo_refresh_pressed)
	file_row.add_child(demo_refresh_btn)

	var demo_delete_btn := Button.new()
	demo_delete_btn.text = "Delete"
	demo_delete_btn.pressed.connect(_on_demo_delete_pressed)
	file_row.add_child(demo_delete_btn)

	var demo_restore_btn := Button.new()
	demo_restore_btn.text = "Restore"
	demo_restore_btn.pressed.connect(_on_demo_restore_pressed)
	file_row.add_child(demo_restore_btn)

	var trash_row := HBoxContainer.new()
	trash_row.add_theme_constant_override("separation", 4)
	demo_box.add_child(trash_row)

	_trash_select = OptionButton.new()
	_trash_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_trash_select.item_selected.connect(_on_trash_selected)
	trash_row.add_child(_trash_select)

	var trash_refresh_btn := Button.new()
	trash_refresh_btn.text = "Trash"
	trash_refresh_btn.pressed.connect(_on_trash_refresh_pressed)
	trash_row.add_child(trash_refresh_btn)

	var trash_restore_btn := Button.new()
	trash_restore_btn.text = "RestoreSel"
	trash_restore_btn.pressed.connect(_on_trash_restore_pressed)
	trash_row.add_child(trash_restore_btn)

	var trash_purge_btn := Button.new()
	trash_purge_btn.text = "Purge"
	trash_purge_btn.pressed.connect(_on_trash_purge_pressed)
	trash_row.add_child(trash_purge_btn)

	var trash_maintain_row := HBoxContainer.new()
	trash_maintain_row.add_theme_constant_override("separation", 4)
	demo_box.add_child(trash_maintain_row)

	var trash_days_label := Label.new()
	trash_days_label.text = "Old(d)"
	trash_maintain_row.add_child(trash_days_label)

	_trash_purge_days_spin = SpinBox.new()
	_trash_purge_days_spin.min_value = 1
	_trash_purge_days_spin.max_value = 3650
	_trash_purge_days_spin.step = 1
	_trash_purge_days_spin.value = float(_trash_purge_old_days)
	_trash_purge_days_spin.custom_minimum_size = Vector2(74, 0)
	_trash_purge_days_spin.value_changed.connect(_on_trash_purge_days_changed)
	trash_maintain_row.add_child(_trash_purge_days_spin)

	var trash_purge_old_btn := Button.new()
	trash_purge_old_btn.text = "PurgeOld"
	trash_purge_old_btn.pressed.connect(_on_trash_purge_old_pressed)
	trash_maintain_row.add_child(trash_purge_old_btn)

	var log_tail_btn := Button.new()
	log_tail_btn.text = "LogTail"
	log_tail_btn.pressed.connect(_on_ops_tail_pressed)
	trash_maintain_row.add_child(log_tail_btn)

	var ops_row := HBoxContainer.new()
	ops_row.add_theme_constant_override("separation", 4)
	demo_box.add_child(ops_row)

	var ops_panel_btn := Button.new()
	ops_panel_btn.text = "OpsPanel"
	ops_panel_btn.pressed.connect(_on_ops_panel_pressed)
	ops_row.add_child(ops_panel_btn)

	var ops_export_btn := Button.new()
	ops_export_btn.text = "OpsExport"
	ops_export_btn.pressed.connect(_on_ops_export_pressed)
	ops_row.add_child(ops_export_btn)

	_ops_panel = PanelContainer.new()
	_ops_panel.visible = false
	_ops_panel.custom_minimum_size = Vector2(0, 108)
	demo_box.add_child(_ops_panel)

	_ops_log_view = TextEdit.new()
	_ops_log_view.editable = false
	_ops_log_view.context_menu_enabled = false
	_ops_log_view.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_ops_log_view.custom_minimum_size = Vector2(0, 96)
	_ops_panel.add_child(_ops_log_view)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 4)
	demo_box.add_child(btn_row)

	var demo_start_btn := Button.new()
	demo_start_btn.text = "Start"
	demo_start_btn.pressed.connect(_on_demo_start_pressed)
	btn_row.add_child(demo_start_btn)

	var demo_pause_btn := Button.new()
	demo_pause_btn.text = "Pause"
	demo_pause_btn.pressed.connect(_on_demo_pause_pressed)
	btn_row.add_child(demo_pause_btn)

	var demo_next_btn := Button.new()
	demo_next_btn.text = "Next"
	demo_next_btn.pressed.connect(_on_demo_next_pressed)
	btn_row.add_child(demo_next_btn)

	var record_row := HBoxContainer.new()
	record_row.add_theme_constant_override("separation", 4)
	demo_box.add_child(record_row)

	var demo_record_btn := Button.new()
	demo_record_btn.text = "Record"
	demo_record_btn.pressed.connect(_on_demo_record_pressed)
	record_row.add_child(demo_record_btn)

	var demo_replay_btn := Button.new()
	demo_replay_btn.text = "Replay"
	demo_replay_btn.pressed.connect(_on_demo_replay_pressed)
	record_row.add_child(demo_replay_btn)

	var demo_export_btn := Button.new()
	demo_export_btn.text = "Export"
	demo_export_btn.pressed.connect(_on_demo_export_pressed)
	record_row.add_child(demo_export_btn)

	var demo_folder_btn := Button.new()
	demo_folder_btn.text = "Folder"
	demo_folder_btn.pressed.connect(_on_demo_open_folder_pressed)
	record_row.add_child(demo_folder_btn)

	_refresh_recording_list(true)
	_refresh_trash_list(false)
	_select_trash_path(_last_deleted_trash_path)


	_refresh_ops_panel()
	_refresh_demo_control_ui()

func _update_ui() -> void:
	_hud.update_metrics({
		"remaining_text": _format_seconds(_remaining_seconds),
		"objective_title": _objective_title_text(),
		"objective_detail": "Tier " + str(_current_objective_tier) + " | Target " + _objective_target_text() + " | Left " + str(int(ceil(_objective_timer))) + "s",
		"objective_progress": _objective_system.progress(focus_value, affection_value, chaos_value),
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value,
		"help_text": _build_help_text()
	})
	_refresh_demo_control_ui()

func _objective_title_text() -> String:
	match _objective_system.get_objective_key():
		FocusObjectiveSystem.OBJECTIVE_KEEP_FOCUS:
			return "Keep Focus"
		FocusObjectiveSystem.OBJECTIVE_REDUCE_CHAOS:
			return "Reduce Chaos"
		FocusObjectiveSystem.OBJECTIVE_BUILD_AFFECTION:
			return "Build Affection"
		_:
			return "-"

func _objective_target_text() -> String:
	match _objective_system.get_objective_key():
		FocusObjectiveSystem.OBJECTIVE_KEEP_FOCUS:
			return "Focus >= " + str(int(round(_objective_system.get_objective_target())))
		FocusObjectiveSystem.OBJECTIVE_REDUCE_CHAOS:
			return "Chaos <= " + str(int(round(_objective_system.get_objective_target())))
		FocusObjectiveSystem.OBJECTIVE_BUILD_AFFECTION:
			return "Affection >= " + str(int(round(_objective_system.get_objective_target())))
		_:
			return "-"

func _format_seconds(total_seconds: int) -> String:
	var safe_seconds: int = maxi(total_seconds, 0)
	var minutes: int = safe_seconds / 60
	var seconds: int = safe_seconds % 60
	return "%02d:%02d" % [minutes, seconds]

func _build_help_text() -> String:
	return "F5 restart | F1 skip tutorial | F2 ops-panel | F3 log | F4 purge-old | F6 purge | F7 restore | F8 delete | F9 demo | F10 record | F11 replay | F12 speed"

func _build_default_demo_events() -> Array[Dictionary]:
	return [
		{"at": 3, "type": "hint", "value": "Demo event: cat starts disturbing."},
		{"at": 5, "type": "typing"},
		{"at": 8, "type": "state", "value": "Blocking"},
		{"at": 12, "type": "item_wand"},
		{"at": 18, "type": "typing"},
		{"at": 22, "type": "item_food"},
		{"at": 28, "type": "state", "value": "TailWagging"},
		{"at": 35, "type": "hint", "value": "Demo event: objective should be near completion."}
	]

func _refresh_demo_control_ui() -> void:
	if not _demo_status_label:
		return
	var mode_text := "ON" if demo_script_mode else "OFF"
	var pause_text := "PAUSED" if _demo_paused else "RUN"
	var recording_text := "REC OFF"
	if _recording_mode:
		recording_text = "REC " + str(_elapsed_seconds) + "/" + str(_recording_target_seconds)
	var replay_text := "REPLAY OFF"
	if _replay_mode:
		replay_text = "REPLAY " + _short_recording_path(_replay_source_path)
	var speed_text := "SPD " + str(_demo_playback_speed) + "x"
	var selected_text := "SEL -"
	if not _selected_recording_path.is_empty():
		selected_text = "SEL " + _short_recording_path(_selected_recording_path)
	if not _delete_confirm_path.is_empty() and int(Time.get_unix_time_from_system()) > _delete_confirm_until:
		_clear_delete_confirmation()
	var delete_text := "DEL READY"
	if not _delete_confirm_path.is_empty():
		delete_text = "DEL CONFIRM " + _short_recording_path(_delete_confirm_path)
	if not _purge_confirm_path.is_empty() and int(Time.get_unix_time_from_system()) > _purge_confirm_until:
		_clear_purge_confirmation()
	var purge_text := "PURGE READY"
	if not _purge_confirm_path.is_empty():
		purge_text = "PURGE CONFIRM " + _short_recording_path(_purge_confirm_path)
	if _purge_old_confirm_days > 0 and int(Time.get_unix_time_from_system()) > _purge_old_confirm_until:
		_clear_purge_old_confirmation()
	var purge_old_text := "POLD " + str(_trash_purge_old_days) + "d"
	if _purge_old_confirm_days > 0:
		purge_old_text = "POLD CONFIRM " + str(_purge_old_confirm_days) + "d"
	var trash_text := "TRASH -"
	if not _selected_trash_path.is_empty():
		trash_text = "TRASH " + _short_recording_path(_selected_trash_path)
	var restore_text := "RESTORE -"
	if not _last_deleted_trash_path.is_empty():
		restore_text = "RESTORE " + _short_recording_path(_last_deleted_trash_path)
	var ops_text := "OPS OFF"
	if _ops_panel_visible:
		ops_text = "OPS ON"
	_demo_status_label.text = "Mode " + mode_text + " | " + pause_text + " | " + recording_text + " | " + replay_text + " | " + speed_text + " | " + selected_text + " | " + trash_text + " | " + delete_text + " | " + purge_text + " | " + purge_old_text + " | " + restore_text + " | " + ops_text + " | event " + str(_demo_cursor) + "/" + str(_demo_events.size())

func _on_demo_start_pressed() -> void:
	start_demo()

func _on_demo_pause_pressed() -> void:
	pause_demo(not _demo_paused)

func _on_demo_next_pressed() -> void:
	if not trigger_next_demo_event():
		_hud.set_hint("No pending demo event.")

func _on_demo_record_pressed() -> void:
	if _recording_mode:
		stop_recording_script("manual_stop")
		return
	start_recording_script(recording_default_duration_seconds, true)

func _on_demo_replay_pressed() -> void:
	if not _replay_selected_or_latest():
		_hud.set_hint("Replay failed: no valid recording log found.")

func _on_demo_export_pressed() -> void:
	if _recording_events.is_empty():
		_hud.set_hint("Export skipped: no recording events.")
		return
	var path := export_recording_log()
	if path.is_empty():
		_hud.set_hint("Export failed.")
		return
	_recording_output_path = path
	_refresh_recording_list(true)
	_select_recording_path(path)
	_hud.set_hint("Exported: " + _short_recording_path(path))
	_refresh_demo_control_ui()

func _on_demo_refresh_pressed() -> void:
	_clear_delete_confirmation()
	_clear_purge_confirmation()
	_clear_purge_old_confirmation()
	_refresh_recording_list(false)
	_refresh_trash_list(false)
	if _recording_files.is_empty():
		_hud.set_hint("No recording files found.")
	else:
		_hud.set_hint("Recording list refreshed: " + str(_recording_files.size()) + " files.")

func _on_recording_selected(index: int) -> void:
	if index < 0 or index >= _recording_files.size():
		return
	_clear_delete_confirmation()
	_selected_recording_path = _recording_files[index]
	_hud.set_hint("Selected: " + _short_recording_path(_selected_recording_path))
	_refresh_demo_control_ui()

func _on_speed_selected(index: int) -> void:
	if index < 0 or index >= _demo_speed_options.size():
		return
	set_demo_playback_speed(_demo_speed_options[index])
	_hud.set_hint("Replay speed: " + str(_demo_playback_speed) + "x")

func _on_demo_delete_pressed() -> void:
	if _selected_recording_path.is_empty():
		_hud.set_hint("Delete skipped: no selected recording.")
		return
	var now := int(Time.get_unix_time_from_system())
	if _delete_confirm_path != _selected_recording_path or now > _delete_confirm_until:
		_delete_confirm_path = _selected_recording_path
		_delete_confirm_until = now + 4
		_hud.set_hint("Press Delete again in 4s: " + _short_recording_path(_selected_recording_path))
		_refresh_demo_control_ui()
		return
	var deleting_path := _selected_recording_path
	if not _delete_recording_path(deleting_path):
		_hud.set_hint("Delete failed: " + _short_recording_path(deleting_path))
		_clear_delete_confirmation()
		_refresh_demo_control_ui()
		return
	if _replay_source_path == deleting_path:
		_replay_source_path = ""
	_clear_delete_confirmation()
	_clear_purge_confirmation()
	_clear_purge_old_confirmation()
	_refresh_recording_list(false)
	_refresh_trash_list(true)
	_select_trash_path(_last_deleted_trash_path)
	_hud.set_hint("Moved to trash: " + _short_recording_path(deleting_path))
	_refresh_demo_control_ui()

func _on_demo_restore_pressed() -> void:
	var restored_path := _restore_last_deleted_recording()
	if restored_path.is_empty():
		_hud.set_hint("Restore failed: no available trashed recording.")
		_refresh_demo_control_ui()
		return
	_clear_delete_confirmation()
	_clear_purge_confirmation()
	_clear_purge_old_confirmation()
	_refresh_recording_list(false)
	_refresh_trash_list(false)
	_select_recording_path(restored_path)
	_hud.set_hint("Restored: " + _short_recording_path(restored_path))
	_refresh_demo_control_ui()

func _on_trash_refresh_pressed() -> void:
	_clear_purge_confirmation()
	_clear_purge_old_confirmation()
	_refresh_trash_list(false)
	if _trash_files.is_empty():
		_hud.set_hint("Trash is empty.")
	else:
		_hud.set_hint("Trash refreshed: " + str(_trash_files.size()) + " files.")

func _on_trash_selected(index: int) -> void:
	if index < 0 or index >= _trash_files.size():
		return
	_clear_purge_confirmation()
	_clear_purge_old_confirmation()
	_selected_trash_path = _trash_files[index]
	_hud.set_hint("Trash selected: " + _short_recording_path(_selected_trash_path))
	_refresh_demo_control_ui()

func _on_trash_restore_pressed() -> void:
	if _selected_trash_path.is_empty():
		_hud.set_hint("Restore skipped: no selected trash file.")
		return
	var restored_path := _restore_trash_path(_selected_trash_path)
	if restored_path.is_empty():
		_hud.set_hint("Restore failed: " + _short_recording_path(_selected_trash_path))
		_refresh_demo_control_ui()
		return
	_clear_purge_confirmation()
	_clear_purge_old_confirmation()
	_refresh_recording_list(false)
	_refresh_trash_list(false)
	_select_recording_path(restored_path)
	_hud.set_hint("Restored from trash: " + _short_recording_path(restored_path))
	_refresh_demo_control_ui()

func _on_trash_purge_pressed() -> void:
	if _selected_trash_path.is_empty():
		_hud.set_hint("Purge skipped: no selected trash file.")
		return
	var now := int(Time.get_unix_time_from_system())
	if _purge_confirm_path != _selected_trash_path or now > _purge_confirm_until:
		_purge_confirm_path = _selected_trash_path
		_purge_confirm_until = now + 4
		_hud.set_hint("Press Purge again in 4s: " + _short_recording_path(_selected_trash_path))
		_refresh_demo_control_ui()
		return
	var purging_path := _selected_trash_path
	if not _purge_trash_path(purging_path):
		_hud.set_hint("Purge failed: " + _short_recording_path(purging_path))
		_clear_purge_confirmation()
		_refresh_demo_control_ui()
		return
	_clear_purge_confirmation()
	_clear_purge_old_confirmation()
	_refresh_trash_list(false)
	_hud.set_hint("Purged: " + _short_recording_path(purging_path))
	_refresh_demo_control_ui()

func _on_trash_purge_days_changed(value: float) -> void:
	_trash_purge_old_days = maxi(int(round(value)), 1)
	_clear_purge_old_confirmation()
	if _trash_purge_days_spin and int(round(_trash_purge_days_spin.value)) != _trash_purge_old_days:
		_trash_purge_days_spin.value = float(_trash_purge_old_days)
	_refresh_demo_control_ui()

func _on_trash_purge_old_pressed() -> void:
	var target_days := maxi(_trash_purge_old_days, 1)
	var now := int(Time.get_unix_time_from_system())
	if _purge_old_confirm_days != target_days or now > _purge_old_confirm_until:
		_purge_old_confirm_days = target_days
		_purge_old_confirm_until = now + 4
		_hud.set_hint("Press PurgeOld again in 4s: older than %dd" % target_days)
		_refresh_demo_control_ui()
		return
	_clear_purge_old_confirmation()
	_clear_purge_confirmation()
	var purged_count := _purge_trash_older_than(target_days)
	_refresh_trash_list(false)
	if purged_count <= 0:
		_hud.set_hint("PurgeOld finished: no files older than %dd." % target_days)
	else:
		_hud.set_hint("PurgeOld removed %d files older than %dd." % [purged_count, target_days])
	_refresh_demo_control_ui()

func _on_ops_tail_pressed() -> void:
	var tail_size := maxi(recording_ops_tail_preview_size, 1)
	var ops_tail := _tail_recording_ops(tail_size)
	if ops_tail.is_empty():
		_hud.set_hint("Ops tail empty.")
		return
	var last := ops_tail[ops_tail.size() - 1]
	var action := String(last.get("action", "-"))
	var result := String(last.get("result", "-"))
	var source_path := String(last.get("source_path", ""))
	var target_path := String(last.get("target_path", ""))
	var focus_path := source_path if not source_path.is_empty() else target_path
	var short_path := _short_recording_path(focus_path)
	_hud.set_hint("Ops tail " + str(ops_tail.size()) + ": " + action + " " + result + " " + short_path)
	_refresh_ops_panel()

func _on_ops_panel_pressed() -> void:
	_ops_panel_visible = not _ops_panel_visible
	_refresh_ops_panel()
	_hud.set_hint("Ops panel: " + ("ON" if _ops_panel_visible else "OFF"))
	_refresh_demo_control_ui()

func _on_ops_export_pressed() -> void:
	var path := export_recording_ops_log()
	if path.is_empty():
		_hud.set_hint("Ops export failed: no ops log.")
		return
	_hud.set_hint("Ops exported: " + _short_recording_path(path))
	_refresh_ops_panel()

func _on_demo_open_folder_pressed() -> void:
	var dir := DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("recordings")
	var global_path := ProjectSettings.globalize_path("user://recordings")
	OS.shell_open(global_path)
	_hud.set_hint("Opened recordings folder.")
