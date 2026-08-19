extends Node

## P10 动画流畅度测试

const AnimCompScript = preload("res://components/cat_animation_component.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_oneshot_table()
	_test_play_lock()
	_test_frame_curve()
	_test_state_lock()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_oneshot_table() -> void:
	# 语义表：互动关键动作在一次性集合；循环动作不在
	_assert_true(AnimCompScript.ONESHOT_ACTIONS.has("eat"), "eat_oneshot")
	_assert_true(AnimCompScript.ONESHOT_ACTIONS.has("pounce_attack"), "pounce_oneshot_despite_tres_loop")
	_assert_true(AnimCompScript.ONESHOT_ACTIONS.has("greet"), "greet_oneshot")
	_assert_true(not AnimCompScript.ONESHOT_ACTIONS.has("idle_stand"), "idle_not_oneshot")
	_assert_true(not AnimCompScript.ONESHOT_ACTIONS.has("walk"), "walk_not_oneshot")

func _make_anim_comp() -> Node:
	# 构造带真实 SpriteFrames 的组件（加载 orange_tabby tres）
	var comp = AnimCompScript.new()
	add_child(comp)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	add_child(sprite)
	comp.animated_sprite = sprite
	var sf := load("res://resources/animations/orange_tabby.tres") as SpriteFrames
	if sf:
		sprite.sprite_frames = sf
	return comp

func _test_play_lock() -> void:
	var comp = _make_anim_comp()
	# 一次性动作播放 → 锁 true
	comp.play("eat")
	_assert_true(comp.is_action_locked(), "eat_locks")
	# 手动触发 animation_finished → 解锁
	comp._on_animation_finished()
	_assert_true(not comp.is_action_locked(), "finished_unlocks")
	# 循环动作不锁
	comp.play("idle_stand")
	_assert_true(not comp.is_action_locked(), "loop_no_lock")
	comp.queue_free()

func _test_frame_curve() -> void:
	# 帧时长曲线：由 tools/tune_anim_speeds.py 写入 tres（Godot 4.7 无运行时 set_frame_duration）
	# 此处验证一次性动作至少播放时长为正、循环动画 duration 均匀
	var comp = _make_anim_comp()
	comp.play("eat")
	var sf: SpriteFrames = comp.animated_sprite.sprite_frames
	var frames := sf.get_frame_count("eat")
	_assert_true(frames >= 3, "eat_has_frames")
	var total := 0.0
	for i in frames:
		total += sf.get_frame_duration("eat", i)
	_assert_true(total > 0.0, "eat_positive_duration")
	comp.play("walk")
	var wfirst: float = sf.get_frame_duration("walk", 0)
	_assert_true(is_equal_approx(wfirst, 1.0), "loop_stays_uniform")
	comp.queue_free()

const StateMachineScript = preload("res://components/state_machine.gd")
const StateScript = preload("res://components/state.gd")

func _test_state_lock() -> void:
	# 状态机锁排队：动画锁定期 transition_to 不切换、缓存 pending；
	# urgent 立即切；解锁信号后 pending 自动执行
	var sm := StateMachineScript.new()
	add_child(sm)
	var s1 := StateScript.new(); s1.name = "One"
	var s2 := StateScript.new(); s2.name = "Two"
	sm.add_child(s1); sm.add_child(s2)
	# 夹具：真实场景状态是 tscn 静态子节点（_ready 时已在树）；
	# 动态添加不触发重扫——手动注册（照 _ready 的注册逻辑）
	s1.state_machine = sm
	s2.state_machine = sm
	sm.states[s1.name] = s1
	sm.states[s2.name] = s2
	s1.process_mode = Node.PROCESS_MODE_DISABLED
	s2.process_mode = Node.PROCESS_MODE_DISABLED
	sm.current_state = s1
	s1.process_mode = Node.PROCESS_MODE_INHERIT
	# 伪造动画锁：注入 locked provider
	sm.anim_lock_provider = func() -> bool: return true
	sm.transition_to(&"Two")
	_assert_equal(String(sm.get_current_state_name()), "One", "locked_no_switch")
	# urgent 豁免
	sm.transition_to(&"Two", {"urgent": true})
	_assert_equal(String(sm.get_current_state_name()), "Two", "urgent_switches")
	# pending 自动执行：先回 One、锁、排 Two、解锁
	sm.transition_to(&"One", {"urgent": true})
	sm.transition_to(&"Two")  # 被锁 → pending
	sm.anim_lock_provider = func() -> bool: return false
	sm.notify_anim_unlocked()
	_assert_equal(String(sm.get_current_state_name()), "Two", "pending_executes")
	sm.queue_free()

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
	print("========== anim_flow tests ==========")
	print("passed: %d" % _passed)
	print("failed: %d" % _failed)
	for f in _failures:
		print("  FAIL: " + f)
