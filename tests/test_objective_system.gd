extends Node

const ObjectiveSystemScript = preload("res://components/focus/objective_system.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var sys = ObjectiveSystemScript.new()
	add_child(sys)

	sys.set_cards([
		{"id": "keep_focus", "target_min": 40.0, "target_max": 60.0,
		 "weight": 1.0, "tier_min": 1, "tier_max": 3},
		{"id": "reduce_chaos", "target_min": 2.0, "target_max": 10.0,
		 "weight": 1.0, "tier_min": 1, "tier_max": 3}
	])

	# 初始无目标
	_assert_true(sys.get_objective_key().is_empty(), "no_objective_initially")

	# roll 出目标后 key 合法、target 在区间
	sys.roll_new_objective(1, 50.0, 45.0, 20.0)
	_assert_true(not sys.get_objective_key().is_empty(), "objective_rolled")
	var target: float = sys.get_objective_target()
	_assert_true(target >= 2.0 and target <= 60.0, "target_in_range")

	# keep_focus 完成：focus 抬到 95
	if sys.get_objective_key() == "keep_focus":
		_assert_true(sys.is_completed(95.0, 45.0, 20.0), "keep_focus_completed")
	# reduce_chaos 完成：chaos 压到 0
	if sys.get_objective_key() == "reduce_chaos":
		_assert_true(sys.is_completed(50.0, 45.0, 0.0), "reduce_chaos_completed")

	# 进度值合法
	var progress: float = sys.progress(50.0, 45.0, 10.0)
	_assert_true(progress >= 0.0 and progress <= 1.0, "progress_valid")

	# 重新 roll 可换新目标
	sys.roll_new_objective(2, 50.0, 45.0, 10.0)
	_assert_true(not sys.get_objective_key().is_empty(), "reroll_works")

	# check_progress：构造已完成目标验证返回 true
	sys.roll_new_objective(1, 95.0, 95.0, 0.0)  # 全满状态，大概率立即完成
	var completed: bool = sys.check_progress(100.0, 100.0, 0.0)
	_assert_true(completed, "check_progress_detects_completion")

	# check_timeout：timer > 0 时不触发
	var timeout: bool = sys.check_timeout(10.0, 0.0, 0.0, 100.0)
	_assert_true(not timeout, "check_timeout_blocked_by_timer")

	_print_summary()
	get_tree().quit(1 if _failed > 0 else 0)

func _assert_true(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)

func _print_summary() -> void:
	print("")
	print("========== objective_system tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		for name in _failures:
			print(" - ", name)
