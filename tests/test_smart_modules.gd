extends Node

const HabitProfileServiceScript := preload("res://habit_profile_service.gd")
const ReactionPolicyEngineScript := preload("res://reaction_policy_engine.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_policy_quiet_hours()
	_test_policy_focus_milestone()
	_test_profile_tags()

	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

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
