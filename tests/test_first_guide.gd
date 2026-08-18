extends Node

const GuideScript = preload("res://components/engagement/first_guide_controller.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_guide_flow()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_guide_flow() -> void:
	# 状态机：未引导→step1(摸摸)→step2(道具)→done；done 不再触发
	var guide = GuideScript.new()
	add_child(guide)
	_assert_equal(guide.stage, 0, "starts_at_zero")
	guide.start()
	_assert_equal(guide.stage, 1, "start_enters_step1")
	guide.notify_interaction("pet")
	_assert_equal(guide.stage, 2, "pet_completes_step1")
	guide.notify_interaction("food")
	_assert_equal(guide.stage, 3, "item_completes_step2")
	# 完成后不再回退
	guide.notify_interaction("pet")
	_assert_equal(guide.stage, 3, "done_is_terminal")
	# 已完成的实例 start() 是 no-op
	guide.start()
	_assert_equal(guide.stage, 3, "restart_noop_after_done")
	# step1 延迟 30 秒触发提示（快进验证）
	var guide3 = GuideScript.new()
	add_child(guide3)
	var msgs: Array[String] = []
	guide3.guide_stage_changed.connect(func(_s, m): if not m.is_empty(): msgs.append(m))
	guide3.start()
	for i in range(31):
		guide3.tick(1.0)
	_assert_true(msgs.has("摸摸我吧"), "step1_fires_after_30s")
	# step2 超时跳过（10 分钟无互动自动完成）
	var guide2 = GuideScript.new()
	add_child(guide2)
	guide2.start()
	guide2.notify_interaction("pet")
	guide2._step2_deadline_unix = int(Time.get_unix_time_from_system()) - 1
	guide2.tick()
	_assert_equal(guide2.stage, 3, "step2_timeout_completes")
	guide.queue_free()
	guide2.queue_free()
	guide3.queue_free()

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
