extends Node

## P6 每日任务/隐式签到测试

const CollectorScript = preload("res://context_collector.gd")
const QuestServiceScript = preload("res://components/engagement/daily_quest_service.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_event_recorded_signal()
	_test_checkin()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_checkin() -> void:
	# 隐式签到：load_from_save 触发结算——首日 streak=1；连续 +1；断签归 1；同日不重复计
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	_assert_equal(svc.streak_days, 1, "first_day_streak_1")
	_assert_equal(svc.today_checked_in, true, "checked_in_today")
	# 同日重复 load 不重复计
	var saved: Dictionary = svc.get_save_data()
	svc.load_from_save(saved)
	_assert_equal(svc.streak_days, 1, "same_day_no_double")
	# 连续：昨日 last_checkin → +1
	var yesterday_key: String = svc._shift_date_key(-1)
	svc.load_from_save({"streak_days": 3, "last_checkin_key": yesterday_key, "today_key": yesterday_key})
	_assert_equal(svc.streak_days, 4, "consecutive_plus_one")
	# 断签（5 天前）→ 归 1
	svc.load_from_save({"streak_days": 7, "last_checkin_key": svc._shift_date_key(-5), "today_key": svc._shift_date_key(-5)})
	_assert_equal(svc.streak_days, 1, "broken_streak_resets")
	# 奖励公式 min(10 + streak*2, 30)：streak=1 → 12；streak=15 → 30 封顶
	_assert_equal(svc._checkin_reward(1), 12, "reward_day1")
	_assert_equal(svc._checkin_reward(15), 30, "reward_capped")
	svc.queue_free()

func _test_event_recorded_signal() -> void:
	# record_event 尾部应发 event_recorded(type, payload) 信号（P6 任务系统数据源）
	var collector = CollectorScript.new()
	add_child(collector)
	var received: Array = []
	collector.event_recorded.connect(func(event_type, payload): received.append([event_type, payload]))
	collector.record_event("item_used", {"item_type": "food"})
	_assert_true(received.size() == 1, "signal_fired_once")
	_assert_equal(String(received[0][0]), "item_used", "signal_carries_type")
	_assert_equal(String(received[0][1].get("item_type", "")), "food", "signal_carries_payload")
	# payload 带 type/t 元数据键（collector 记录格式），不破坏既有消费方
	_assert_true(received[0][1].has("t"), "payload_has_timestamp")
	collector.queue_free()

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
	print("========== daily_quests tests ==========")
	print("passed: %d" % _passed)
	print("failed: %d" % _failed)
	for f in _failures:
		print("  FAIL: " + f)
