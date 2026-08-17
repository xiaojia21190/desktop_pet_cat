extends Node

const MonitorScript = preload("res://components/perception/foreground_app_monitor.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var monitor = MonitorScript.new()
	monitor.use_system_source = false  # headless 测试不挂 PowerShell 源
	add_child(monitor)

	# 默认关闭：不采集、快照为空
	_assert_true(not monitor.enabled, "disabled_by_default")
	_assert_equal(monitor.get_snapshot().get("app", ""), "", "no_app_when_disabled")

	# 注入假采集源：轮询产生快照
	var fake_source := FakeSource.new()
	fake_source.next_name = "Code.exe"
	monitor.set_source(fake_source)
	monitor.enabled = true
	monitor.poll_interval = 0.05
	await get_tree().create_timer(0.3).timeout
	var snap: Dictionary = monitor.get_snapshot()
	_assert_equal(String(snap.get("app", "")), "Code.exe", "fake_app_reported")
	_assert_equal(String(snap.get("activity", "")), "coding", "activity_classified")
	_assert_true(float(snap.get("activity_seconds", 0.0)) >= 0.0, "seconds_valid")

	# 切换应用后重计、历史保留
	fake_source.next_name = "chrome.exe"
	await get_tree().create_timer(0.2).timeout
	snap = monitor.get_snapshot()
	_assert_equal(String(snap.get("app", "")), "chrome.exe", "app_switch_detected")
	_assert_equal(String(snap.get("activity", "")), "browsing", "activity_switched")
	_assert_true(snap.has("history"), "history_present")

	# 采集源失败 → unknown 降级
	fake_source.fail_mode = true
	await get_tree().create_timer(0.2).timeout
	snap = monitor.get_snapshot()
	_assert_equal(String(snap.get("app", "")), "unknown", "failure_degrades_to_unknown")

	# 关闭后清空快照且不再更新
	monitor.enabled = false
	fake_source.fail_mode = false
	fake_source.next_name = "potplayer.exe"
	await get_tree().create_timer(0.2).timeout
	_assert_equal(String(monitor.get_snapshot().get("app", "")), "", "cleared_and_no_update_when_disabled")

	monitor.queue_free()
	_print_summary()
	get_tree().quit(1 if _failed > 0 else 0)

func _assert_true(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
	else:
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
	print("========== foreground_app_monitor tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		for name in _failures:
			print(" - ", name)

class FakeSource:
	extends RefCounted
	const is_slow := false
	var next_name := ""
	var fail_mode := false
	func query() -> String:
		return "unknown" if fail_mode else next_name
