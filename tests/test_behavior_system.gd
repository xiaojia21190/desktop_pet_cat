extends Node
class_name BehaviorSystemTest

# 行为系统单元测试
# 运行方式：在 Godot 编辑器中创建场景，添加此脚本，运行场景

var behavior_system: CatBehaviorSystem
var test_results: Array = []
var tests_passed: int = 0
var tests_failed: int = 0

func _ready():
	print("========== 行为系统单元测试 ==========")
	behavior_system = CatBehaviorSystem.new()
	add_child(behavior_system)

	# 运行所有测试
	_run_all_tests()

	# 输出结果
	_print_results()

func _run_all_tests():
	# 情绪系统测试
	test_mood_modification()
	test_mood_state_thresholds()
	test_energy_modification()
	test_affection_modification()
	test_emotion_clamping()

	# 记忆系统测试
	test_interaction_recording()
	test_interaction_history_limit()
	test_interaction_stats()

	# 学习系统测试
	test_behavior_reinforcement()
	test_weight_clamping()
	test_weighted_selection()
	test_adjusted_weights()

	# 状态链系统测试
	test_chain_start()
	test_chain_interruption()
	test_chain_completion()

	# 时间感知测试
	test_time_of_day()

	# 数据持久化测试
	test_save_load_data()

# ============================================
# 情绪系统测试
# ============================================

func test_mood_modification():
	behavior_system.mood = 50.0
	behavior_system.modify_mood(10)
	_assert_equal(behavior_system.mood, 60.0, "mood_modification_positive")

	behavior_system.modify_mood(-20)
	_assert_equal(behavior_system.mood, 40.0, "mood_modification_negative")

func test_mood_state_thresholds():
	behavior_system.mood = 80.0
	_assert_equal(
		behavior_system.get_mood_state(),
		CatBehaviorSystem.MoodState.HAPPY,
		"mood_state_happy"
	)

	behavior_system.mood = 50.0
	_assert_equal(
		behavior_system.get_mood_state(),
		CatBehaviorSystem.MoodState.NEUTRAL,
		"mood_state_neutral"
	)

	behavior_system.mood = 20.0
	_assert_equal(
		behavior_system.get_mood_state(),
		CatBehaviorSystem.MoodState.GRUMPY,
		"mood_state_grumpy"
	)

func test_energy_modification():
	behavior_system.energy = 50.0
	behavior_system.modify_energy(30)
	_assert_equal(behavior_system.energy, 80.0, "energy_modification")

func test_affection_modification():
	behavior_system.affection = 50.0
	behavior_system.modify_affection(25)
	_assert_equal(behavior_system.affection, 75.0, "affection_modification")

func test_emotion_clamping():
	behavior_system.mood = 50.0
	behavior_system.modify_mood(100)
	_assert_equal(behavior_system.mood, 100.0, "mood_clamp_max")

	behavior_system.modify_mood(-200)
	_assert_equal(behavior_system.mood, 0.0, "mood_clamp_min")

# ============================================
# 记忆系统测试
# ============================================

func test_interaction_recording():
	behavior_system.interaction_history.clear()
	behavior_system.record_interaction("head_pat", {"test": true})

	_assert_true(
		behavior_system.interaction_history.size() == 1,
		"interaction_recorded"
	)
	_assert_equal(
		behavior_system.interaction_history[0]["type"],
		"head_pat",
		"interaction_type_correct"
	)

func test_interaction_history_limit():
	behavior_system.interaction_history.clear()

	# 添加超过限制的记录
	for i in range(150):
		behavior_system.record_interaction("test_" + str(i))

	_assert_true(
		behavior_system.interaction_history.size() <= CatBehaviorSystem.MAX_HISTORY_SIZE,
		"history_limit_enforced"
	)

func test_interaction_stats():
	behavior_system.interaction_stats["head_pat"] = 0
	behavior_system.record_interaction("head_pat")
	behavior_system.record_interaction("head_pat")

	_assert_equal(
		behavior_system.interaction_stats["head_pat"],
		2,
		"interaction_stats_counted"
	)

# ============================================
# 学习系统测试
# ============================================

func test_behavior_reinforcement():
	behavior_system.behavior_weights["test_action"] = 10.0
	behavior_system.reinforce_behavior("test_action", true)

	_assert_true(
		behavior_system.behavior_weights["test_action"] > 10.0,
		"positive_reinforcement"
	)

	var before = behavior_system.behavior_weights["test_action"]
	behavior_system.reinforce_behavior("test_action", false)

	_assert_true(
		behavior_system.behavior_weights["test_action"] < before,
		"negative_reinforcement"
	)

func test_weight_clamping():
	behavior_system.behavior_weights["clamp_test"] = 10.0

	# 尝试超过最大值
	for i in range(100):
		behavior_system.reinforce_behavior("clamp_test", true)

	_assert_true(
		behavior_system.behavior_weights["clamp_test"] <= CatBehaviorSystem.WEIGHT_MAX,
		"weight_clamp_max"
	)

	# 尝试低于最小值
	for i in range(200):
		behavior_system.reinforce_behavior("clamp_test", false)

	_assert_true(
		behavior_system.behavior_weights["clamp_test"] >= CatBehaviorSystem.WEIGHT_MIN,
		"weight_clamp_min"
	)

func test_weighted_selection():
	var actions = ["idle_stand", "walk", "roll"]
	var selected = behavior_system.select_weighted_behavior(actions)

	_assert_true(
		selected in actions,
		"weighted_selection_valid"
	)

func test_adjusted_weights():
	behavior_system.mood = 80.0  # HAPPY
	behavior_system.energy = 80.0  # ENERGETIC

	var adjusted = behavior_system.get_adjusted_weights()

	# HAPPY 状态下 roll 权重应该增加
	_assert_true(
		adjusted.get("roll", 0) >= behavior_system.behavior_weights.get("roll", 0),
		"adjusted_weights_mood_effect"
	)

# ============================================
# 状态链系统测试
# ============================================

func test_chain_start():
	behavior_system.current_chain = ""
	var result = behavior_system.start_chain("pounce_sequence")

	_assert_true(result, "chain_start_success")
	_assert_equal(
		behavior_system.current_chain,
		"pounce_sequence",
		"chain_name_set"
	)
	_assert_equal(behavior_system.chain_index, 0, "chain_index_zero")

func test_chain_interruption():
	behavior_system.start_chain("pounce_sequence")
	behavior_system.interrupt_chain()

	_assert_equal(behavior_system.current_chain, "", "chain_interrupted")

func test_chain_completion():
	behavior_system.start_chain("pounce_sequence")

	# 模拟时间流逝完成状态链
	var chain = CatBehaviorSystem.STATE_CHAINS["pounce_sequence"]
	var total_duration = 0.0
	for d in chain.durations:
		if d > 0:
			total_duration += d

	# 更新足够长的时间
	behavior_system.update_chain(total_duration + 1.0)

	_assert_equal(behavior_system.current_chain, "", "chain_completed")

# ============================================
# 时间感知测试
# ============================================

func test_time_of_day():
	var time = behavior_system.get_time_of_day()
	var valid_times = ["morning", "afternoon", "evening", "night"]

	_assert_true(time in valid_times, "time_of_day_valid")

	var modifier = behavior_system.get_time_behavior_modifier()
	_assert_true(modifier.has("energy_mod"), "time_modifier_has_energy")
	_assert_true(modifier.has("activity_mod"), "time_modifier_has_activity")

# ============================================
# 数据持久化测试
# ============================================

func test_save_load_data():
	# 设置测试数据
	behavior_system.mood = 75.0
	behavior_system.energy = 60.0
	behavior_system.affection = 45.0
	behavior_system.total_play_time = 1234.5

	# 保存
	var save_data = behavior_system.get_save_data()

	# 重置
	behavior_system.mood = 0.0
	behavior_system.energy = 0.0
	behavior_system.affection = 0.0
	behavior_system.total_play_time = 0.0

	# 加载
	behavior_system.load_save_data(save_data)

	_assert_equal(behavior_system.mood, 75.0, "save_load_mood")
	_assert_equal(behavior_system.energy, 60.0, "save_load_energy")
	_assert_equal(behavior_system.affection, 45.0, "save_load_affection")
	_assert_equal(behavior_system.total_play_time, 1234.5, "save_load_playtime")

# ============================================
# 测试辅助函数
# ============================================

func _assert_equal(actual, expected, test_name: String):
	if actual == expected:
		test_results.append({"name": test_name, "passed": true})
		tests_passed += 1
	else:
		test_results.append({
			"name": test_name,
			"passed": false,
			"expected": expected,
			"actual": actual
		})
		tests_failed += 1

func _assert_true(condition: bool, test_name: String):
	if condition:
		test_results.append({"name": test_name, "passed": true})
		tests_passed += 1
	else:
		test_results.append({
			"name": test_name,
			"passed": false,
			"expected": true,
			"actual": false
		})
		tests_failed += 1

func _print_results():
	print("")
	print("========== 测试结果 ==========")
	print("通过: ", tests_passed)
	print("失败: ", tests_failed)
	print("总计: ", tests_passed + tests_failed)
	print("")

	if tests_failed > 0:
		print("失败的测试:")
		for result in test_results:
			if not result["passed"]:
				print("  ❌ ", result["name"])
				print("     期望: ", result["expected"])
				print("     实际: ", result["actual"])
	else:
		print("✅ 所有测试通过!")

	print("==============================")
