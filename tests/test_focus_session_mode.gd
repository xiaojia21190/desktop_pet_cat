extends Node

const FOCUS_SESSION_MODE_SCRIPT := preload("res://focus_session_mode.gd")
const SESSION_RECORDER_SCRIPT := preload("res://tests/debug_tools/session_recorder.gd")
const BEHAVIOR_SYSTEM_SCRIPT := preload("res://cat_behavior_system.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var mode = FOCUS_SESSION_MODE_SCRIPT.new()
	mode.show_tutorial_on_start = false
	mode.recording_auto_export = false
	add_child(mode)
	await get_tree().process_frame
	await get_tree().process_frame

	# 默认不自启会话：桌宠启动时不应自动进入专注模式
	_assert_true(not mode._running, "session_not_autostarted_by_default")
	_assert_true(not mode._hud.hud_panel.visible, "hud_hidden_by_default")

	# 调试设施隔离：正常实例化不自动挂载 recorder
	var recorder = SESSION_RECORDER_SCRIPT.new()
	mode.bind_debug_recorder(recorder)
	add_child(recorder)
	await get_tree().process_frame
	recorder._ensure_recording_dirs()

	mode.start_session()
	_assert_true(mode._running, "start_session_runs")

	# 心理统一：affection/chaos 代理到行为系统，focus 保留会话内
	var behavior = BEHAVIOR_SYSTEM_SCRIPT.new()
	add_child(behavior)
	mode.bind_behavior(behavior)
	behavior.affection = 60.0
	behavior.chaos = 25.0
	mode.start_session()
	_assert_true(is_equal_approx(float(mode.affection_value), 60.0), "affection_synced_from_behavior")
	_assert_true(is_equal_approx(float(mode.chaos_value), 25.0), "chaos_synced_from_behavior")
	mode.on_item_used("food")  # affection +8
	_assert_true(float(mode.affection_value) > 60.0, "affection_delta_writes_through")
	_assert_true(is_equal_approx(float(behavior.affection), float(mode.affection_value)), "behavior_sees_session_affection")

	_assert_true(mode.get_snapshot().has("focus"), "snapshot_has_focus")
	_assert_true(mode.get_snapshot().has("remaining_seconds"), "snapshot_has_remaining_seconds")

	mode.set_demo_events([
		{"at": 0, "type": "typing"},
		{"at": 1, "type": "item_food"}
	])
	var focus_before: float = float(mode.focus_value)
	var triggered: bool = bool(mode.trigger_next_demo_event())
	_assert_true(triggered, "trigger_next_demo_event_success")
	_assert_true(mode.focus_value < focus_before, "typing_event_reduces_focus")

	recorder.start_recording_script(10, false)
	mode.on_typing_attack()
	mode.on_item_used("food")
	recorder.stop_recording_script("test_stop")
	_assert_true(mode._recording_events.size() >= 3, "recording_events_captured")

	var stamp := Time.get_unix_time_from_system()
	var recording_path := "user://recordings/test_focus_session_mode_%d.json" % stamp
	var exported_path: String = String(recorder.export_recording_log(recording_path))
	_assert_equal(exported_path, recording_path, "export_returns_custom_path")
	_assert_true(FileAccess.file_exists(recording_path), "recording_file_exists")

	var replay_ok: bool = bool(recorder.replay_recording_log(recording_path))
	_assert_true(replay_ok, "replay_exported_recording_success")

	recorder._refresh_recording_list(false)
	recorder._select_recording_path(recording_path)
	recorder._on_demo_delete_pressed()
	recorder._on_demo_delete_pressed()
	_assert_true(not FileAccess.file_exists(recording_path), "recording_moved_to_trash")
	_assert_true(not recorder._last_deleted_trash_path.is_empty(), "last_deleted_trash_path_set")
	_assert_true(FileAccess.file_exists(recorder._last_deleted_trash_path), "trash_file_exists")

	recorder._on_demo_restore_pressed()
	recorder._refresh_recording_list(false)
	var restored_path: String = String(recorder._selected_recording_path)
	_assert_true(not restored_path.is_empty(), "restored_path_selected")
	_assert_true(FileAccess.file_exists(restored_path), "restored_file_exists")

	recorder._on_ops_tail_pressed()
	_assert_true(mode._hud.hint_label.text.find("Ops tail") != -1, "ops_tail_hint_updated")

	var ops_export_path := "user://recordings/test_ops_export_%d.jsonl" % stamp
	var exported_ops: String = String(recorder.export_recording_ops_log(ops_export_path))
	_assert_equal(exported_ops, ops_export_path, "ops_export_returns_custom_path")
	_assert_true(FileAccess.file_exists(ops_export_path), "ops_export_file_exists")

	mode.queue_free()
	await get_tree().process_frame
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _assert_true(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
		return
	_failed += 1
	_failures.append(test_name)

func _assert_equal(actual, expected, test_name: String) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	_failures.append("%s (actual=%s expected=%s)" % [test_name, str(actual), str(expected)])

func _print_summary() -> void:
	print("")
	print("========== focus_session_mode tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		print("failure list:")
		for name in _failures:
			print(" - ", name)
