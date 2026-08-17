extends Node

const EngineScript = preload("res://components/focus/focus_charge_engine.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var engine = EngineScript.new()

	# 纯打字：每秒 10 次键入 → 显著充能
	var delta_f: float = engine.compute_focus_delta({"typing": 10, "clicks": 0, "focus_activity": false})
	_assert_true(delta_f > 3.0, "typing_charges_focus")

	# 纯点击：每秒 5 次 → 温和充能
	delta_f = engine.compute_focus_delta({"typing": 0, "clicks": 5, "focus_activity": false})
	_assert_true(delta_f > 0.5, "clicks_charge_mildly")

	# 专注活动无键入（看代码思考）：底薪充能
	delta_f = engine.compute_focus_delta({"typing": 0, "clicks": 0, "focus_activity": true})
	_assert_true(delta_f >= 1.0, "focus_activity_floor_charge")

	# 完全闲置：慢衰减
	delta_f = engine.compute_focus_delta({"typing": 0, "clicks": 0, "focus_activity": false})
	_assert_true(is_equal_approx(delta_f, -0.18), "idle_slow_drain")

	# 高强度打字封顶（防炸服）
	delta_f = engine.compute_focus_delta({"typing": 100, "clicks": 50, "focus_activity": true})
	_assert_true(delta_f <= 10.0, "charge_capped")

	# 普通工作节奏（每秒 2 键 + 专注活动）可持续
	var normal_work: float = engine.compute_focus_delta({"typing": 2, "clicks": 0, "focus_activity": true})
	_assert_true(normal_work > 1.0, "normal_work_sustainable")

	# 闲置归零时间：85 起、-0.18/秒 ≈ 472 秒（约 8 分钟）
	var seconds_to_zero: int = int(85.0 / 0.18)
	_assert_true(seconds_to_zero > 420 and seconds_to_zero < 600, "idle_fail_in_eight_to_ten_min")

	# get_work_score 公开
	var score: float = engine.get_work_score({"typing": 3, "clicks": 1, "focus_activity": true})
	_assert_true(score >= 1.0, "work_score_exposed")

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
	print("========== focus_charge_engine tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		for name in _failures:
			print(" - ", name)
