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
	_test_event_quests()
	_test_window_quests()
	_test_save_and_roll()
	_test_summary()
	_test_save_manager_section()
	_test_quest_bond_gain()
	_test_achievement_defs()
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

func _test_event_quests() -> void:
	# focus_session：focus_milestone 事件完成；focus_failed 不完成
	var svc = QuestServiceScript.new()
	add_child(svc)
	var fired: Array = []
	svc.quest_completed.connect(func(qid, reward): fired.append([qid, reward]))
	svc.notify_event("focus_milestone", {})
	_assert_true(svc.is_completed("focus_session"), "focus_milestone_completes")
	_assert_equal(fired.size(), 1, "focus_fires_once")
	_assert_true(is_equal_approx(float(fired[0][1]), 15.0), "focus_reward_15")
	# 重复事件不重复发
	svc.notify_event("focus_milestone", {})
	_assert_equal(fired.size(), 1, "no_double_fire")
	svc.queue_free()

	var svc2 = QuestServiceScript.new()
	add_child(svc2)
	svc2.notify_event("focus_failed", {})
	_assert_true(not svc2.is_completed("focus_session"), "failure_no_complete")
	svc2.queue_free()

	# interact_once：item_used / petting_started / cat_clicked 任一完成
	var svc3 = QuestServiceScript.new()
	add_child(svc3)
	var fired3: Array = []
	svc3.quest_completed.connect(func(qid, reward): fired3.append([qid, reward]))
	svc3.notify_event("item_used", {"item_type": "food"})
	_assert_true(svc3.is_completed("interact_once"), "item_used_completes")
	_assert_true(is_equal_approx(float(fired3[0][1]), 8.0), "interact_reward_8")
	svc3.queue_free()

	var svc4 = QuestServiceScript.new()
	add_child(svc4)
	svc4.notify_event("petting_started", {})
	_assert_true(svc4.is_completed("interact_once"), "petting_completes")
	svc4.queue_free()

	var svc5 = QuestServiceScript.new()
	add_child(svc5)
	svc5.notify_event("cat_clicked", {})
	_assert_true(svc5.is_completed("interact_once"), "click_completes")
	svc5.queue_free()

func _test_window_quests() -> void:
	# stand_up：long_focus 提醒开 5 分钟窗，窗口内 idle>=120s 完成
	var svc = QuestServiceScript.new()
	add_child(svc)
	var fired: Array = []
	svc.quest_completed.connect(func(qid, reward): fired.append([qid, reward]))
	# 提醒事件（smart_decision 带 intent）
	svc.notify_event("smart_decision", {"intent": "long_focus"})
	# 窗口内轮询：闲置 2 分钟达标
	svc.poll_snapshot({"idle_seconds": 130.0})
	_assert_true(svc.is_completed("stand_up"), "standup_after_reminder")
	_assert_true(is_equal_approx(float(fired[0][1]), 10.0), "standup_reward_10")
	svc.queue_free()

	# 窗口过期：提醒后超过 5 分钟才闲置 → 不完成
	var svc2 = QuestServiceScript.new()
	add_child(svc2)
	svc2.notify_event("smart_decision", {"intent": "long_focus"})
	svc2._window_deadline["stand_up"] = int(Time.get_unix_time_from_system()) - 1
	svc2.poll_snapshot({"idle_seconds": 300.0})
	_assert_true(not svc2.is_completed("stand_up"), "expired_window_no_complete")
	svc2.queue_free()

	# 无提醒直接闲置 → 不完成（防白拿）
	var svc3 = QuestServiceScript.new()
	add_child(svc3)
	svc3.poll_snapshot({"idle_seconds": 600.0})
	_assert_true(not svc3.is_completed("stand_up"), "no_reminder_no_complete")
	svc3.queue_free()

	# meal_on_time：meal_hint 提醒开 30 分钟窗，窗口内 idle>=300s 完成
	var svc4 = QuestServiceScript.new()
	add_child(svc4)
	svc4.notify_event("smart_decision", {"intent": "meal_hint"})
	svc4.poll_snapshot({"idle_seconds": 320.0})
	_assert_true(svc4.is_completed("meal_on_time"), "meal_after_reminder")
	svc4.queue_free()

	# 窗口内但闲置不够 → 不完成
	var svc5 = QuestServiceScript.new()
	add_child(svc5)
	svc5.notify_event("smart_decision", {"intent": "meal_hint"})
	svc5.poll_snapshot({"idle_seconds": 60.0})
	_assert_true(not svc5.is_completed("meal_on_time"), "insufficient_idle_no_complete")
	svc5.queue_free()

	# 其他 intent 不开窗
	var svc6 = QuestServiceScript.new()
	add_child(svc6)
	svc6.notify_event("smart_decision", {"intent": "weather_smalltalk"})
	svc6.poll_snapshot({"idle_seconds": 600.0})
	_assert_true(not svc6.is_completed("stand_up"), "other_intent_no_window")
	svc6.queue_free()

func _test_save_and_roll() -> void:
	# roundtrip：completed 状态与 streak 恢复
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	svc.notify_event("item_used", {})
	var saved: Dictionary = svc.get_save_data()
	var svc2 = QuestServiceScript.new()
	add_child(svc2)
	svc2.load_from_save(saved)
	_assert_true(svc2.is_completed("interact_once"), "roundtrip_completed")
	_assert_equal(svc2.streak_days, svc.streak_days, "roundtrip_streak")

	# 跨天：伪造昨日档 → load 后任务清空重新计数
	var stale: Dictionary = saved.duplicate(true)
	stale["today_key"] = svc._shift_date_key(-1)
	stale["last_checkin_key"] = svc._shift_date_key(-1)
	var svc3 = QuestServiceScript.new()
	add_child(svc3)
	svc3.load_from_save(stale)
	_assert_true(not svc3.is_completed("interact_once"), "cross_day_resets_quests")
	_assert_equal(svc3.streak_days, svc.streak_days + 1, "cross_day_streak_plus")

	# 异常兜底：空档/缺字段/类型错乱不崩
	var svc4 = QuestServiceScript.new()
	add_child(svc4)
	svc4.load_from_save({"streak_days": "abc", "completed": "not_array"})
	_assert_equal(svc4.streak_days, 1, "garbage_fallback_streak1")
	svc.queue_free()
	svc2.queue_free()
	svc3.queue_free()
	svc4.queue_free()

func _test_summary() -> void:
	# 面板数据：get_today_summary 返回任务列表与签到天数
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	svc.notify_event("item_used", {})
	var summary: Dictionary = svc.get_today_summary()
	var quests: Array = summary.get("quests", [])
	_assert_equal(quests.size(), 4, "summary_has_4_quests")
	var interact: Dictionary = {}
	for q in quests:
		if String(q.get("id", "")) == "interact_once":
			interact = q
	_assert_equal(bool(interact.get("completed", false)), true, "summary_marks_completed")
	_assert_equal(String(interact.get("title", "")), "摸摸我吧", "summary_carries_title")
	_assert_true(int(summary.get("streak_days", 0)) >= 1, "summary_has_streak")
	svc.queue_free()

func _test_save_manager_section() -> void:
	# daily_quests 区块默认值 + 写档（写真实 user:// 路径——测试环境 SAVE_PATH 可写）
	var sm = preload("res://save_manager.gd").new()
	add_child(sm)
	var defaults: Dictionary = sm._get_default_data()
	var dq: Dictionary = defaults.get("daily_quests", {})
	_assert_equal(int(dq.get("streak_days", -1)), 0, "default_streak_0")
	_assert_equal(String(dq.get("today_key", "x")), "", "default_today_empty")
	# _write_config 真实落盘（验证 ConfigFile 序列化 Array 不崩）
	var data := defaults.duplicate(true)
	data["daily_quests"] = {"today_key": "20260819", "completed": ["interact_once"], "streak_days": 3, "last_checkin_key": "20260819"}
	var err: int = sm._write_config(data)
	_assert_equal(err, 0, "write_config_ok")
	sm.queue_free()

func _test_quest_bond_gain() -> void:
	# quest_reward 增益类型：显式 amount 直加，不受同类递减影响
	var bond = preload("res://components/bond_system.gd").new()
	add_child(bond)
	bond.bond = 0.0
	var g1: float = bond.add_bond("quest_reward", 15.0)
	var g2: float = bond.add_bond("quest_reward", 10.0)
	_assert_true(is_equal_approx(g1, 15.0), "quest_gain_15")
	_assert_true(is_equal_approx(g2, 10.0), "no_decay_on_quest")
	_assert_true(is_equal_approx(bond.bond, 25.0), "bond_total_25")
	bond.queue_free()

const AchDefsScript = preload("res://components/engagement/achievement_defs.gd")

func _test_achievement_defs() -> void:
	# 定义表完整性：8 成就含必需字段；3 周任务含 target
	var defs: Dictionary = AchDefsScript.ACHIEVEMENTS
	_assert_equal(defs.size(), 8, "eight_achievements")
	for id in defs:
		var d: Dictionary = defs[id]
		_assert_true(d.has("name") and d.has("need") and d.has("stat") and d.has("reward"), "def_complete_" + String(id))
	_assert_equal(String(defs["focus_10"]["title"]), "专注搭档", "focus10_title")
	_assert_true(is_equal_approx(float(defs["checkin_30"]["reward"]), 150.0), "checkin30_reward")
	var weekly: Dictionary = AchDefsScript.WEEKLY_QUESTS
	_assert_equal(weekly.size(), 3, "three_weekly")
	_assert_equal(int(weekly["week_focus"]["target"]), 3, "weekfocus_target")

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
