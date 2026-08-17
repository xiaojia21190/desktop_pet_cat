extends Node

const HabitProfileServiceScript := preload("res://habit_profile_service.gd")
const ReactionPolicyEngineScript := preload("res://reaction_policy_engine.gd")
const CustomizationServiceScript := preload("res://customization_service.gd")
const ContextCollectorScript := preload("res://context_collector.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_policy_quiet_hours()
	_test_policy_focus_milestone()
	_test_policy_build_fail_streak()
	_test_profile_tags()
	_test_customization_llm_settings()
	await _test_collector_perception_fields()
	_test_activity_tags()
	_test_psyche_injection()
	_test_psyche_modulated_policy()
	_test_memory_lines()
	_test_night_owl_care()

	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_activity_tags() -> void:
	# —— 活动标签 ——
	var profile = HabitProfileServiceScript.new()
	add_child(profile)
	var snap := {
		"hour": 14, "typing_per_min": 5.0, "continuous_active_seconds": 60.0,
		"idle_seconds": 5.0, "activity": "video", "activity_seconds": 900.0
	}
	var tags: Array[String] = profile.build_tags(snap, [])
	_assert_true(tags.has("watching_video"), "tag_watching_video")

	snap["activity"] = "coding"
	snap["activity_seconds"] = 1200.0
	tags = profile.build_tags(snap, [])
	_assert_true(tags.has("coding_now"), "tag_coding_now")

	snap["activity"] = "browsing"
	snap["activity_seconds"] = 700.0
	tags = profile.build_tags(snap, [])
	_assert_true(tags.has("browsing_now"), "tag_browsing_now")

	# 未达 10 分钟不贴标签
	snap["activity"] = "video"
	snap["activity_seconds"] = 300.0
	tags = profile.build_tags(snap, [])
	_assert_true(not tags.has("watching_video"), "tag_needs_ten_minutes")

	# SMART 决策喂入含 activity 的快照不报错（管线兼容）
	var policy = ReactionPolicyEngineScript.new()
	add_child(policy)
	var decision: Dictionary = policy.evaluate(
		{"hour": 14, "fullscreen": false, "continuous_active_seconds": 100.0, "activity": "video"},
		[], [], {"personality": "tsundere", "reminder_intensity": "medium"})
	_assert_true(decision.has("react"), "policy_tolerates_activity_field")
	profile.queue_free()
	policy.queue_free()

func _test_collector_perception_fields() -> void:
	# —— ContextCollector 感知字段扩展 ——
	var collector = ContextCollectorScript.new()
	add_child(collector)

	# 未喂入时快照字段为空默认值
	var snap: Dictionary = collector.get_snapshot()
	_assert_equal(String(snap.get("foreground_app", "x")), "", "collector_default_app_empty")
	_assert_equal(String(snap.get("activity", "x")), "", "collector_default_activity_empty")

	# 喂入监测数据
	collector.update_foreground("Code.exe", "coding")
	await get_tree().create_timer(0.12).timeout
	snap = collector.get_snapshot()
	_assert_equal(String(snap.get("foreground_app")), "Code.exe", "collector_app_reported")
	_assert_equal(String(snap.get("activity")), "coding", "collector_activity_reported")
	_assert_true(float(snap.get("activity_seconds", -1.0)) >= 0.0, "collector_seconds_accumulate")

	# 切换活动累计到 activity_totals
	collector.update_foreground("chrome.exe", "browsing")
	await get_tree().create_timer(0.1).timeout
	snap = collector.get_snapshot()
	var totals: Dictionary = snap.get("activity_totals", {})
	_assert_true(float(totals.get("coding", 0.0)) >= 0.0, "coding_total_accumulated")
	_assert_equal(String(snap.get("activity")), "browsing", "activity_switched")

	collector.queue_free()

func _test_policy_quiet_hours() -> void:
	var policy = ReactionPolicyEngineScript.new()
	add_child(policy)
	var decision: Dictionary = policy.evaluate(
		{"hour": 23, "quiet_hours_start": 22, "quiet_hours_end": 8, "fullscreen": false, "continuous_active_seconds": 0.0},
		[],
		[],
		{"personality": "tsundere", "reminder_intensity": "medium"}
	)
	_assert_true(bool(decision.get("react", false)), "policy_quiet_hours_react")
	_assert_equal(String(decision.get("action_id", "")), "sleep_curl", "policy_quiet_hours_action")
	policy.queue_free()

func _test_policy_focus_milestone() -> void:
	var policy = ReactionPolicyEngineScript.new()
	add_child(policy)
	var now := Time.get_unix_time_from_system()
	var decision: Dictionary = policy.evaluate(
		{"hour": 14, "quiet_hours_start": 23, "quiet_hours_end": 8, "fullscreen": false, "continuous_active_seconds": 300.0},
		[],
		[{"type": "focus_milestone", "t": now}],
		{"personality": "gentle", "reminder_intensity": "medium"}
	)
	_assert_true(bool(decision.get("react", false)), "policy_focus_milestone_react")
	_assert_equal(String(decision.get("action_id", "")), "celebrate", "policy_focus_milestone_action")
	policy.queue_free()

func _test_profile_tags() -> void:
	var service = HabitProfileServiceScript.new()
	add_child(service)

	service.ingest_snapshot({"hour": 23, "active_seconds": 600.0})
	service.ingest_snapshot({"hour": 0, "active_seconds": 900.0})
	service.ingest_snapshot({"hour": 10, "active_seconds": 100.0})

	var now := Time.get_unix_time_from_system()
	var tags: Array[String] = service.build_tags(
		{
			"typing_per_min": 20.0,
			"continuous_active_seconds": 2400.0,
			"idle_seconds": 5.0
		},
		[
			{"type": "typing_burst", "t": now - 10},
			{"type": "typing_burst", "t": now - 20},
			{"type": "typing_burst", "t": now - 30}
		]
	)

	_assert_true(tags.has("night_owl"), "profile_has_night_owl")
	_assert_true(tags.has("coding_heavy"), "profile_has_coding_heavy")
	_assert_true(tags.has("deep_focus"), "profile_has_deep_focus")
	_assert_true(tags.has("easily_distracted"), "profile_has_distracted")
	service.queue_free()

func _test_policy_build_fail_streak() -> void:
	var policy = ReactionPolicyEngineScript.new()
	add_child(policy)
	var now := Time.get_unix_time_from_system()
	var decision: Dictionary = policy.evaluate(
		{"hour": 14, "quiet_hours_start": 23, "quiet_hours_end": 8, "fullscreen": false, "continuous_active_seconds": 120.0},
		[],
		[{"type": "build_fail_streak", "t": now, "streak": 3}],
		{"personality": "tsundere", "reminder_intensity": "medium"}
	)
	_assert_true(bool(decision.get("react", false)), "policy_build_fail_streak_react")
	_assert_equal(String(decision.get("action_id", "")), "comfort", "policy_build_fail_streak_action")
	policy.queue_free()

func _test_customization_llm_settings() -> void:
	var customization = CustomizationServiceScript.new()
	add_child(customization)
	customization.apply_settings({
		"llm_enabled": true,
		"llm_endpoint": "https://example.test/v1/chat/completions",
		"llm_model": "test-mini",
		"llm_api_key": "abc123",
		"llm_api_key_env": "PET_LLM_KEY",
		"llm_timeout_seconds": 22.0
	})
	var snapshot: Dictionary = customization.to_settings_dict()
	_assert_equal(bool(snapshot.get("llm_enabled", false)), true, "customization_llm_enabled")
	_assert_equal(String(snapshot.get("llm_endpoint", "")), "https://example.test/v1/chat/completions", "customization_llm_endpoint")
	_assert_equal(String(snapshot.get("llm_model", "")), "test-mini", "customization_llm_model")
	_assert_equal(String(snapshot.get("llm_api_key_env", "")), "PET_LLM_KEY", "customization_llm_api_env")
	_assert_equal(float(snapshot.get("llm_timeout_seconds", 0.0)), 22.0, "customization_llm_timeout")

	# —— 感知设置链路 ——
	customization.apply_settings({"perception_enabled": true, "perception_default_rules": false})
	_assert_equal(bool(customization.perception_enabled), true, "custom_perception_enabled")
	_assert_equal(bool(customization.perception_default_rules), false, "custom_perception_defaults_off")
	var dict2: Dictionary = customization.to_settings_dict()
	_assert_equal(bool(dict2.get("perception_enabled")), true, "dict_perception_enabled")
	customization.queue_free()

func _test_psyche_injection() -> void:
	# —— 心理注入：决策快照携带 psyche 字段 ——
	var controller = preload("res://smart_pet_controller.gd").new()
	add_child(controller)
	var behavior = preload("res://cat_behavior_system.gd").new()
	add_child(behavior)
	behavior.mood = 75.0
	behavior.energy = 25.0
	controller.bind_behavior(behavior)
	var snapshot := {"hour": 14}
	controller._inject_psyche(snapshot)
	var psyche: Dictionary = snapshot.get("psyche", {})
	_assert_equal(float(psyche.get("mood", 0.0)), 75.0, "psyche_mood_injected")
	_assert_equal(float(psyche.get("energy", 0.0)), 25.0, "psyche_energy_injected")
	_assert_true(psyche.has("affection"), "psyche_affection_present")
	_assert_true(psyche.has("chaos"), "psyche_chaos_present")
	controller.queue_free()
	behavior.queue_free()

func _test_psyche_modulated_policy() -> void:
	# —— 新意图：看视频陪伴 ——
	var policy = ReactionPolicyEngineScript.new()
	add_child(policy)
	var decision: Dictionary = policy.evaluate(
		{"hour": 20, "fullscreen": false, "continuous_active_seconds": 100.0,
		 "activity": "video", "activity_seconds": 900.0},
		["watching_video"], [],
		{"personality": "tsundere", "reminder_intensity": "medium"})
	_assert_true(bool(decision.get("react", false)), "video_companion_reacts")
	_assert_equal(String(decision.get("action_id", "")), "idle", "video_companion_action_idle")

	# —— 新意图：写代码鼓励 ——
	decision = policy.evaluate(
		{"hour": 14, "fullscreen": false, "continuous_active_seconds": 1900.0,
		 "activity": "coding", "activity_seconds": 1900.0},
		["coding_now"], [],
		{"personality": "tsundere", "reminder_intensity": "medium"})
	_assert_equal(String(decision.get("action_id", "")), "tail_wag", "coding_cheer_action_tailwag")

	# —— 心理调制：精力低时 celebrate 换 sleep_curl ——
	var policy2 = ReactionPolicyEngineScript.new()
	add_child(policy2)
	decision = policy2.evaluate(
		{"hour": 14, "fullscreen": false, "continuous_active_seconds": 100.0,
		 "psyche": {"mood": 50.0, "energy": 20.0, "affection": 50.0, "chaos": 10.0}},
		[], [{"type": "focus_milestone", "t": Time.get_unix_time_from_system()}],
		{"personality": "gentle", "reminder_intensity": "medium"})
	_assert_equal(String(decision.get("action_id", "")), "sleep_curl", "tired_cat_celebrates_quietly")
	policy.queue_free()
	policy2.queue_free()

func _test_memory_lines() -> void:
	var profile = HabitProfileServiceScript.new()
	add_child(profile)
	# 空数据无记忆
	var lines: Array[String] = profile.build_memory_lines()
	_assert_equal(lines.size(), 0, "no_memory_on_empty")

	# 喂入深夜重度使用（70 次 × 60 秒 = 4200 秒，过 3600 阈值）
	for i in range(70):
		profile.ingest_snapshot({"hour": 23, "active_seconds": 60.0,
			"activity_totals": {"coding": 7300.0}})
	lines = profile.build_memory_lines()
	_assert_true(lines.size() >= 1, "night_memory_generated")
	var joined := "\n".join(lines)
	_assert_true(joined.contains("深夜") or joined.contains("晚上"), "night_memory_text")
	_assert_true(joined.contains("代码"), "coding_memory_text")
	profile.queue_free()

func _test_night_owl_care() -> void:
	var policy = ReactionPolicyEngineScript.new()
	add_child(policy)
	# 深夜 + 长活跃 → 关怀提醒（记忆线优先）
	var decision: Dictionary = policy.evaluate(
		{"hour": 23, "fullscreen": false, "continuous_active_seconds": 2800.0,
		 "quiet_hours_start": 3, "quiet_hours_end": 4,
		 "memory_lines": ["你最近总在深夜活跃，要注意休息呀。"]},
		["night_owl"], [],
		{"personality": "gentle", "reminder_intensity": "medium"})
	_assert_true(bool(decision.get("react", false)), "night_owl_care_reacts")
	_assert_equal(String(decision.get("action_id", "")), "comfort", "night_owl_care_action_comfort")
	_assert_true(String(decision.get("template_line", "")).contains("深夜"), "night_owl_care_uses_memory")
	policy.queue_free()

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
	print("========== smart modules tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		print("failure list:")
		for name in _failures:
			print(" - ", name)
