extends Node

const BondSystemScript = preload("res://components/bond_system.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_level_thresholds()
	_test_repeat_decay()
	_test_daily_cap()
	_test_unlocks()
	_test_save_roundtrip()
	_test_petting_intent()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_level_thresholds() -> void:
	# 等级边界：0→Lv1，50→Lv2，150→Lv3，320→Lv4，600→Lv5
	var cases := [[0.0, 1], [49.9, 1], [50.0, 2], [150.0, 3], [320.0, 4], [600.0, 5], [9999.0, 5]]
	for case in cases:
		var bond = BondSystemScript.new()
		add_child(bond)
		bond.bond = float(case[0])
		_assert_equal(bond.get_level(), int(case[1]), "level_at_%s" % case[0])
		bond.queue_free()

func _test_repeat_decay() -> void:
	# 同类连续互动收益递减（×0.6），异类重置
	var bond = BondSystemScript.new()
	add_child(bond)
	var g1: float = bond.add_bond("food_given")   # 4.0
	var g2: float = bond.add_bond("food_given")   # 4.0×0.6=2.4
	var g3: float = bond.add_bond("wand_given")   # 换类型 → 5.0
	_assert_true(is_equal_approx(g1, 4.0), "first_gain_full")
	_assert_true(is_equal_approx(g2, 2.4), "repeat_gain_decayed")
	_assert_true(is_equal_approx(g3, 5.0), "switch_type_resets_decay")
	bond.queue_free()

func _test_daily_cap() -> void:
	# 日上限 200：喂到上限后返回 0
	var bond = BondSystemScript.new()
	add_child(bond)
	bond.bond = 0.0
	var total: float = 0.0
	for i in range(60):
		# wand/food 交替，递减后累计必然触顶
		total += bond.add_bond("wand_given" if i % 2 == 0 else "food_given")
	_assert_true(total <= 200.0 + 0.01, "daily_total_capped")
	var extra: float = bond.add_bond("play_success")
	_assert_true(is_equal_approx(extra, 0.0), "capped_gain_returns_zero")
	bond.queue_free()

func _test_unlocks() -> void:
	# greet Lv2 解锁；Lv1 未解锁；不在解锁表的动作默认可用；品种 calico Lv3
	var bond = BondSystemScript.new()
	add_child(bond)
	bond.bond = 0.0
	_assert_true(not bond.is_anim_unlocked("greet"), "greet_locked_at_lv1")
	_assert_true(bond.is_anim_unlocked("idle_stand"), "base_anim_always_unlocked")
	_assert_true(not bond.is_breed_unlocked("calico"), "calico_locked_at_lv1")
	bond.bond = 150.0
	_assert_true(bond.is_anim_unlocked("celebrate"), "celebrate_unlocked_at_lv3")
	_assert_true(bond.is_breed_unlocked("calico"), "calico_unlocked_at_lv3")
	_assert_true(not bond.is_breed_unlocked("tuxedo"), "tuxedo_locked_at_lv3")
	bond.queue_free()

func _test_save_roundtrip() -> void:
	# 存读档往返；跨天 today_bond 清零（用昨天日期 key 模拟）
	var bond = BondSystemScript.new()
	add_child(bond)
	bond.add_bond("food_given")
	bond.add_bond("food_given")
	var saved: Dictionary = bond.get_save_data()
	_assert_true(float(saved.get("bond", 0.0)) > 0.0, "save_contains_bond")

	var bond2 = BondSystemScript.new()
	add_child(bond2)
	bond2.load_save_data(saved)
	_assert_true(is_equal_approx(bond2.bond, float(saved["bond"])), "load_restores_bond")

	# 伪造昨日 key → load 后 today 清零
	var stale := saved.duplicate(true)
	stale["today"] = "20200101"
	bond2.load_save_data(stale)
	_assert_true(is_equal_approx(bond2._today_bond, 0.0), "stale_day_resets_today")
	bond.queue_free()
	bond2.queue_free()

const InputComponentScript = preload("res://components/cat_input_component.gd")

func _test_petting_intent() -> void:
	# 撸猫意图状态机：按住 0.6s 进入 PET(3)；漂移>20px 升级 DRAG(2)；松手发 petting_ended
	var owner := Node2D.new()
	owner.global_position = Vector2(500, 500)
	add_child(owner)
	var comp = InputComponentScript.new()
	owner.add_child(comp)  # _ready 中 owner_node = get_parent()

	var started: Array[String] = []
	var ended: Array[float] = []
	comp.petting_started.connect(func(part): started.append(part))
	comp.petting_ended.connect(func(sec): ended.append(sec))

	# 按下命中猫（100px 半径内）→ PENDING(1)
	var press := InputEventMouseButton.new()
	press.pressed = true
	press.button_index = MOUSE_BUTTON_LEFT
	press.global_position = Vector2(500, 500)
	press.position = Vector2(500, 500)
	comp._input(press)
	_assert_equal(comp._intent, 1, "press_enters_pending")

	# 快进 0.7s（超过 pet_start_delay=0.6）→ PET(3)
	for i in range(7):
		comp._process(0.1)
	_assert_equal(comp._intent, 3, "hold_enters_pet")
	_assert_equal(started.size(), 1, "petting_started_once")

	# 漂移超 20px（sq>400）→ 升级 DRAG(2)
	var drift := InputEventMouseMotion.new()
	drift.position = Vector2(530, 500)
	comp._handle_mouse_motion(drift)
	_assert_equal(comp._intent, 2, "drift_upgrades_drag")
	_assert_equal(ended.size(), 1, "petting_ended_before_drag")

	# 松手 → 归零并触发 drag_ended
	var release := InputEventMouseButton.new()
	release.pressed = false
	release.button_index = MOUSE_BUTTON_LEFT
	release.global_position = Vector2(530, 500)
	release.position = Vector2(530, 500)
	comp._input(release)
	_assert_equal(comp._intent, 0, "release_resets_none")
	owner.queue_free()

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
