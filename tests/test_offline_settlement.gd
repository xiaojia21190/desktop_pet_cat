extends Node

## P9 离线正向结算测试

const SettlementScript = preload("res://components/engagement/offline_settlement.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_short_offline_noop()
	_test_hourly_gain_and_cap()
	_test_welcome_tiers()
	_test_personality_lines()
	_test_negative_elapsed()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_short_offline_noop() -> void:
	# <5 分钟：无增益无台词
	var r: Dictionary = SettlementScript.settle(120, 50.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", -1.0)), 0.0), "short_zero_gain")
	_assert_equal(int(r.get("welcome_tier", -1)), 0, "short_tier0")
	_assert_equal(String(r.get("line", "x")), "", "short_no_line")

func _test_hourly_gain_and_cap() -> void:
	# 1 小时 energy=50 → +8, tier=1
	var r: Dictionary = SettlementScript.settle(3600, 50.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", 0.0)), 8.0), "1h_gain_8")
	_assert_equal(int(r.get("welcome_tier", 0)), 1, "1h_tier1")
	# 12 小时 energy=80 → 理论 +96，封顶只补 20
	r = SettlementScript.settle(12 * 3600, 80.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", 0.0)), 20.0), "cap_to_100")
	# 不满整小时零头不计：3599 秒仍 0 增益（且 <1h 无仪式）
	r = SettlementScript.settle(3599, 50.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", -1.0)), 0.0), "partial_hour_no_gain")

func _test_welcome_tiers() -> void:
	_assert_equal(int(SettlementScript.settle(3600, 50.0, "tsundere").get("welcome_tier", 0)), 1, "tier_1h")
	_assert_equal(int(SettlementScript.settle(25 * 3600, 50.0, "tsundere").get("welcome_tier", 0)), 2, "tier_1d")
	_assert_equal(int(SettlementScript.settle(73 * 3600, 50.0, "tsundere").get("welcome_tier", 0)), 3, "tier_3d")

func _test_personality_lines() -> void:
	var tsun: String = String(SettlementScript.settle(3600, 50.0, "tsundere").get("line", ""))
	var gent: String = String(SettlementScript.settle(3600, 50.0, "gentle").get("line", ""))
	var play: String = String(SettlementScript.settle(3600, 50.0, "playful").get("line", ""))
	_assert_true(not tsun.is_empty() and not gent.is_empty() and not play.is_empty(), "lines_nonempty")
	_assert_true(tsun != gent and gent != play and tsun != play, "lines_differ")
	# 未知性格走傲娇
	var unk: String = String(SettlementScript.settle(3600, 50.0, "unknown").get("line", ""))
	_assert_equal(unk, tsun, "unknown_falls_to_tsundere")
	# 三天档台词不同于一小时档
	var long_line: String = String(SettlementScript.settle(73 * 3600, 50.0, "tsundere").get("line", ""))
	_assert_true(long_line != tsun and not long_line.is_empty(), "tier3_differs")

func _test_negative_elapsed() -> void:
	var r: Dictionary = SettlementScript.settle(-100, 50.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", -1.0)), 0.0), "negative_zero_gain")
	_assert_equal(int(r.get("welcome_tier", -1)), 0, "negative_tier0")

func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)

func _assert_equal(actual, expected, name: String) -> void:
	if actual == expected:
		_passed += 1
	else:
		_failed += 1
		_failures.append("%s (expected=%s actual=%s)" % [name, str(expected), str(actual)])

func _print_summary() -> void:
	print("========== offline_settlement tests ==========")
	print("passed: %d" % _passed)
	print("failed: %d" % _failed)
	for f in _failures:
		print("  FAIL: " + f)
