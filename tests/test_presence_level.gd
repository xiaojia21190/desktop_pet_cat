extends Node

const CustomizationServiceScript = preload("res://customization_service.gd")
const PolicyEngineScript = preload("res://reaction_policy_engine.gd")
const ContextCollectorScript = preload("res://context_collector.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_presence_setting_roundtrip()
	_test_legacy_migration()
	_test_soft_hard_quiet()
	_test_sliding_window()
	_test_cooldown_multiplier()
	_test_intent_whitelist()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_presence_setting_roundtrip() -> void:
	# presence_level 读写往返 + 越界钳制
	var cs = CustomizationServiceScript.new()
	add_child(cs)
	cs.apply_settings({"presence_level": 3})
	_assert_equal(int(cs.to_settings_dict().get("presence_level", -1)), 3, "presence_roundtrip")
	cs.apply_settings({"presence_level": 9})
	_assert_equal(cs.presence_level, 4, "presence_clamped_high")
	cs.apply_settings({"presence_level": -1})
	_assert_equal(cs.presence_level, 0, "presence_clamped_low")
	# persona 不再携带 reminder_intensity
	cs.apply_settings({"presence_level": 2})
	_assert_true(not cs.get_persona().has("reminder_intensity"), "persona_drops_reminder")
	cs.queue_free()

func _test_legacy_migration() -> void:
	# 旧 reminder_intensity 映射：low→1 medium→2 high→3
	var cs = CustomizationServiceScript.new()
	add_child(cs)
	for legacy in [["low", 1], ["medium", 2], ["high", 3]]:
		cs.apply_settings({"reminder_intensity": legacy[0]})
		_assert_equal(cs.presence_level, int(legacy[1]), "migrate_%s" % legacy[0])
	# 无任何键时默认 2（中频）
	var cs2 = CustomizationServiceScript.new()
	add_child(cs2)
	_assert_equal(cs2.presence_level, 2, "default_medium")
	cs.queue_free()
	cs2.queue_free()

func _test_soft_hard_quiet() -> void:
	# 分层静音：软=静音开始后 60 分钟，硬=其余。默认 23-8 → 23:00 软 23:59 硬
	var engine = PolicyEngineScript.new()
	add_child(engine)
	# 23:30 软静音 → 深夜关怀可达（活跃 30 分钟滑窗）
	var d: Dictionary = engine.evaluate(
		{"hour": 23, "minute": 30, "quiet_hours_start": 23, "quiet_hours_end": 8,
		 "fullscreen": false, "continuous_active_seconds": 1800.0,
		 "presence_level": 2, "psyche": {"energy": 100.0}},
		[], [], {"personality": "tsundere"})
	_assert_equal(String(d.get("policy_intent", "")), "night_owl_care", "soft_quiet_allows_care")
	# 02:00 硬静音 → quiet_mode
	d = engine.evaluate(
		{"hour": 2, "quiet_hours_start": 23, "quiet_hours_end": 8,
		 "fullscreen": false, "continuous_active_seconds": 1800.0,
		 "presence_level": 2, "psyche": {"energy": 100.0}},
		[], [], {"personality": "tsundere"})
	_assert_equal(String(d.get("policy_intent", "")), "quiet_mode", "hard_quiet_silences")
	# 非跨午夜场景：2-8 → 2:00-2:59 软，3:00 起硬
	d = engine.evaluate(
		{"hour": 2, "minute": 30, "quiet_hours_start": 2, "quiet_hours_end": 8,
		 "fullscreen": false, "continuous_active_seconds": 1800.0,
		 "presence_level": 2, "psyche": {"energy": 100.0}},
		[], [], {"personality": "tsundere"})
	_assert_equal(String(d.get("policy_intent", "")), "night_owl_care", "nonwrap_soft_quiet")
	engine.queue_free()

func _test_sliding_window() -> void:
	# 滑窗累计：45s-5min 停顿按 50% 计入；>5min 清零
	var collector = ContextCollectorScript.new()
	add_child(collector)
	# 活跃 60s → 停 120s（思考）→ 应累计 60 + 120*0.5 = 120
	collector.record_input("typing")
	collector.update_context(60.0)
	collector._last_input_unix = int(Time.get_unix_time_from_system()) - 120  # 模拟停了 2 分钟
	collector.update_context(1.0)  # 触发一次判定
	_assert_true(float(collector.get_snapshot().get("continuous_active_seconds", 0.0)) >= 100.0,
		"pause_counts_half")
	# 停 6 分钟 → 清零
	collector._last_input_unix = int(Time.get_unix_time_from_system()) - 360
	collector.update_context(1.0)
	_assert_true(float(collector.get_snapshot().get("continuous_active_seconds", -1.0)) < 60.0,
		"long_pause_resets")
	collector.queue_free()

func _test_cooldown_multiplier() -> void:
	# 档位冷却倍率：安静 ×4 → 基础 900 的 break_hint 安静档 3600s 内不重复
	var engine = PolicyEngineScript.new()
	add_child(engine)
	var snap := {"hour": 14, "quiet_hours_start": 23, "quiet_hours_end": 8,
		"fullscreen": false, "continuous_active_seconds": 4000.0,
		"presence_level": 0, "psyche": {"energy": 100.0}}
	var d1: Dictionary = engine.evaluate(snap, [], [], {"personality": "tsundere"})
	_assert_equal(String(d1.get("policy_intent", "")), "long_focus", "first_break_hint_fires")
	# 安静档 ×4：900×4=3600s → 3000s 前触发过则拦截
	engine._last_trigger_time["break_hint"] = int(Time.get_unix_time_from_system()) - 3000
	var d2: Dictionary = engine.evaluate(snap, [], [], {"personality": "tsundere"})
	_assert_true(not bool(d2.get("react", true)), "quiet_multiplier_blocks")
	engine.queue_free()

func _test_intent_whitelist() -> void:
	# 安静档不触发饭点；中频档触发
	var engine = PolicyEngineScript.new()
	add_child(engine)
	var snap := {"hour": 12, "minute": 10, "quiet_hours_start": 23, "quiet_hours_end": 8,
		"fullscreen": false, "continuous_active_seconds": 600.0,
		"psyche": {"energy": 100.0}}
	snap["presence_level"] = 0
	var quiet_d: Dictionary = engine.evaluate(snap.duplicate(), [], [], {"personality": "tsundere"})
	_assert_true(String(quiet_d.get("policy_intent", "")) != "meal_hint", "quiet_no_meal_hint")
	snap["presence_level"] = 2
	var mid_d: Dictionary = engine.evaluate(snap.duplicate(), [], [], {"personality": "tsundere"})
	_assert_equal(String(mid_d.get("policy_intent", "")), "meal_hint", "medium_meal_hint")
	engine.queue_free()

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
	print("passed: %d  failed: %d" % [_passed, _failed])
	for f in _failures:
		print("  FAIL: " + f)
