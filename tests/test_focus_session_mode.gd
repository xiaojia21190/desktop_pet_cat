extends Node

const FOCUS_SESSION_MODE_SCRIPT := preload("res://focus_session_mode.gd")

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
	mode._ensure_recording_dirs()

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

	mode.start_recording_script(10, false)
	mode.on_typing_attack()
	mode.on_item_used("food")
	mode.stop_recording_script("test_stop")
	_assert_true(mode._recording_events.size() >= 3, "recording_events_captured")

	var stamp := Time.get_unix_time_from_system()
	var recording_path := "user://recordings/test_focus_session_mode_%d.json" % stamp
	var exported_path: String = String(mode.export_recording_log(recording_path))
	_assert_equal(exported_path, recording_path, "export_returns_custom_path")
	_assert_true(FileAccess.file_exists(recording_path), "recording_file_exists")

	var replay_ok: bool = bool(mode.replay_recording_log(recording_path))
	_assert_true(replay_ok, "replay_exported_recording_success")

	mode._refresh_recording_list(false)
	mode._select_recording_path(recording_path)
	mode._on_demo_delete_pressed()
	mode._on_demo_delete_pressed()
	_assert_true(not FileAccess.file_exists(recording_path), "recording_moved_to_trash")
	_assert_true(not mode._last_deleted_trash_path.is_empty(), "last_deleted_trash_path_set")
	_assert_true(FileAccess.file_exists(mode._last_deleted_trash_path), "trash_file_exists")

	mode._on_demo_restore_pressed()
	mode._refresh_recording_list(false)
	var restored_path: String = String(mode._selected_recording_path)
	_assert_true(not restored_path.is_empty(), "restored_path_selected")
	_assert_true(FileAccess.file_exists(restored_path), "restored_file_exists")

	mode._on_ops_tail_pressed()
	_assert_true(mode._hint_label.text.find("Ops tail") != -1, "ops_tail_hint_updated")

	var ops_export_path := "user://recordings/test_ops_export_%d.jsonl" % stamp
	var exported_ops: String = String(mode.export_recording_ops_log(ops_export_path))
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
