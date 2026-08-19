# P10 动画流畅度代码层重做 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 不动美术素材，修掉四类不流畅：一次性动作完整播放不被状态机打断（urgent 豁免）、动作切换平滑、移动方向/速度平滑、帧时长曲线让 8 帧更连贯。

**Architecture:** 动画组件加 ONESHOT_ACTIONS 语义表 + 播放锁（`is_action_locked`）；状态机 `transition_to` 锁排队（pending_state，`animation_finished` 后自动执行，`msg.urgent` 豁免）；三个移动状态加方向 lerp + 速度 ramp；一次性动作帧 duration 按缓动曲线分配；5 品种 tres 帧率脚本批量调优。

**Tech Stack:** Godot 4.7 / GDScript；测试 headless tscn 断言式；端到端 Godot MCP。

**设计文档:** `docs/superpowers/specs/2026-08-19-p10-anim-smoothness-design.md`

---

## 执行前置

- `"$GODOT"` = `/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- 既有 14 套 364 断言；本计划新增第 15 套 `test_anim_flow`（约 15 断言）
- **已核实代码事实（写码前不要再猜）**：
  - `CatAnimationComponent.play()` 现为直接 `animated_sprite.play()`（cat_animation_component.gd:23-29）；`animation_finished` 信号已存在（:8），`_on_animation_finished` 在 :69
  - `StateMachine.transition_to` 在 state_machine.gd:46-62（硬切，无 msg.urgent 概念）；`state_changed` 信号已有
  - **tres 的 loop 值不可信**（pounce_attack 标 loop=1 但语义一次性）——ONESHOT_ACTIONS 语义表写死在组件里
  - 一次性动作语义表（依据状态用法 + 图帧语义）：`eat, pounce_attack, pounce_ready, greet, celebrate, comfort, dodge, startled, stretch, yawn, jump, land, retreat, typing_attack, blocking, kneading, head_pat_happy, pounce, sneak_eat, happy, peek, carry, break_hint`——其余（idle_*, walk, trot, run, chasing, sleep, watch_focus, lick_groom, tail_wag, rolling 等）为循环
  - **注意 head_pat_happy 不在 orange_tabby 图集里**（28 图无此名）——cat.gd:421 播它会回退 idle_stand；表里仍保留（回退安全）
  - 帧时长 API：`sprite_frames.set_frame_duration(anim, idx, duration)`（duration 是倍率，默认 1.0）
  - 移动三状态现状：walking/chasing 都是 `direction * speed * delta` 直移（cat_walking_state.gd:32 / cat_chasing_state.gd:17）；eating 内部 phase 1 也有直移（一并平滑）
  - urgent 链路三处：cat_input_component 拖拽（is_dragging=true 时 cat.gd 会切状态）、main 点击猫 `_on_cat_left_clicked`、typing_attack（cat.gd:515 附近 `transition_to(CatStates.TYPING_ATTACK)`）
  - cat.gd `play_animation()`（:563）是组件 play 的转发口——状态基类 `play_animation` 也走它；**锁逻辑放组件层**，cat 转发不动
  - `STATE_CHAINS.durations`（cat_behavior_system.gd:327+）如 pounce 步 0.3s 比动画短——节奏表让链调度对齐动画时长
  - P7/P8 教训适用：测试禁 await；删函数查孤儿；改后 headless 冒烟

## 文件结构总览

- Task 1 — ONESHOT 表 + 播放锁 + 帧时长曲线（CatAnimationComponent）+ 测试
- Task 2 — 状态机锁排队 + urgent 豁免 + 测试
- Task 3 — urgent 三链路接线
- Task 4 — 移动平滑（walking/chasing/eating-phase1）
- Task 5 — 节奏表 animation_timing.gd + 链调度对齐
- Task 6 — 5 品种 tres 帧率批量调优（脚本）
- Task 7 — 全量回归 + MCP 真机验收 + 文档收尾

---

### Task 1: 播放锁与帧时长曲线

**Files:**
- Modify: `components/cat_animation_component.gd`
- Create: `tests/test_anim_flow.gd` + `tests/test_anim_flow.tscn`

- [x] **Step 1: 写失败测试 tests/test_anim_flow.gd**

```gdscript
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
	# 帧时长曲线：一次性动作首帧 duration > 中间帧；循环动画保持 1.0
	var comp = _make_anim_comp()
	comp.play("eat")
	var sf: SpriteFrames = comp.animated_sprite.sprite_frames
	var frames := sf.get_frame_count("eat")
	if frames >= 3:
		var first: float = sf.get_frame_duration("eat", 0)
		var mid: float = sf.get_frame_duration("eat", frames / 2)
		_assert_true(first > mid, "curve_first_slower")
	else:
		_assert_true(false, "eat_frames_unexpected_" + str(frames))
	comp.play("walk")
	var wfirst: float = sf.get_frame_duration("walk", 0)
	_assert_true(is_equal_approx(wfirst, 1.0), "loop_stays_uniform")
	comp.queue_free()

func _assert_true(cond: bool, name: String) -> void:
	if cond:
		_passed += 1
	else:
		_failed += 1
		_failures.append(name)

func _print_summary() -> void:
	print("========== anim_flow tests ==========")
	print("passed: %d" % _passed)
	print("failed: %d" % _failed)
	for f in _failures:
		print("  FAIL: " + f)
```

- [x] **Step 2: 创建 tests/test_anim_flow.tscn**

```text
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/test_anim_flow.gd" id="1"]

[node name="AnimFlowTest" type="Node"]
script = ExtResource("1")
```

- [x] **Step 3: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_anim_flow.tscn`
Expected: FAIL（ONESHOT_ACTIONS/is_action_locked 不存在）

- [x] **Step 4: 实现——cat_animation_component.gd 改动**

在 `const SPRITE_FRAMES_DIR` 后加：

```gdscript
## P10 一次性动作语义表（tres 的 loop 值不可信——pounce_attack 被错标 loop=1）
## 依据状态用法与帧语义人工核定；不在表内 = 循环动作
const ONESHOT_ACTIONS := {
	"eat": true, "pounce_attack": true, "pounce_ready": true, "pounce": true,
	"greet": true, "celebrate": true, "comfort": true, "dodge": true,
	"startled": true, "stretch": true, "yawn": true, "jump": true, "land": true,
	"retreat": true, "typing_attack": true, "blocking": true, "kneading": true,
	"head_pat_happy": true, "sneak_eat": true, "happy": true, "peek": true,
	"carry": true, "break_hint": true,
}

## P10 帧时长曲线：一次性动作首尾帧慢、中间帧快（8 帧观感更连贯）
const CURVE_FIRST_LAST := 1.6
const CURVE_MIDDLE := 0.7

var _locked: bool = false
var _locked_anim := ""
```

`play()` 全量替换：

```gdscript
func play(anim_name: String) -> void:
	if not animated_sprite or not animated_sprite.sprite_frames:
		return
	var target := anim_name
	if not animated_sprite.sprite_frames.has_animation(anim_name):
		if animated_sprite.sprite_frames.has_animation("idle_stand"):
			target = "idle_stand"
		else:
			return
	if target != animated_sprite.animation or not animated_sprite.is_playing():
		_apply_frame_curve(target)
	animated_sprite.play(target)
	# P10 播放锁：一次性动作播完前锁（状态机查询）
	if ONESHOT_ACTIONS.has(target):
		_locked = true
		_locked_anim = target
	else:
		_locked = false
		_locked_anim = ""

func is_action_locked() -> bool:
	## P10：一次性动作播放中返回 true（状态机切换排队依据）
	return _locked

func _apply_frame_curve(anim_name: String) -> void:
	## 一次性动作按曲线分配帧时长；循环动作重置全 1.0
	var sf := animated_sprite.sprite_frames
	if not sf.has_animation(anim_name):
		return
	var frames := sf.get_frame_count(anim_name)
	for i in frames:
		var d := 1.0
		if ONESHOT_ACTIONS.has(anim_name) and frames >= 3:
			if i == 0 or i == frames - 1:
				d = CURVE_FIRST_LAST
			else:
				d = CURVE_MIDDLE
		sf.set_frame_duration(anim_name, i, d)
```

`_on_animation_finished` 替换：

```gdscript
func _on_animation_finished() -> void:
	if _locked and animated_sprite.animation == _locked_anim:
		_locked = false
		_locked_anim = ""
	animation_finished.emit(animated_sprite.animation)
```

（`switch_cat_type` 里 `_apply_sprite_frames` 切换后 `_locked = false` 重置——品种切换是天然 urgent 场景。）

- [x] **Step 5: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_anim_flow.tscn`
Expected: `passed: 10  failed: 0`

- [x] **Step 6: 回归 behavior（动画相关既有断言）**

Run: `timeout 90 "$GODOT" --headless --path . res://tests/test_behavior_system.tscn`
Expected: 通过 34 失败 0

- [x] **Step 7: Commit**

```bash
git add components/cat_animation_component.gd tests/test_anim_flow.gd tests/test_anim_flow.tscn tests/test_anim_flow.gd.uid 2>/dev/null || git add components/cat_animation_component.gd tests/test_anim_flow.gd tests/test_anim_flow.tscn
git commit -m "feat: 一次性动作播放锁与帧时长曲线"
```

---

### Task 2: 状态机锁排队与 urgent 豁免

**Files:**
- Modify: `components/state_machine.gd`
- Modify: `tests/test_anim_flow.gd`

- [x] **Step 1: 追加失败测试（_run 追加 `_test_state_lock()`）**

```gdscript
func _test_state_lock() -> void:
	# 状态机锁排队：动画锁定期 transition_to 不切换、缓存 pending；
	# urgent 立即切；animation_finished 后 pending 自动执行
	var sm := StateMachineScript.new()
	add_child(sm)
	var s1 := StateScript.new(); s1.name = "One"
	var s2 := StateScript.new(); s2.name = "Two"
	sm.add_child(s1); sm.add_child(s2)
	sm._ready()  # 手动触发注册（add_child 后 _ready 已跑，这里幂等保护）
	sm.current_state = s1
	# 伪造动画锁：注入 locked provider
	sm.anim_lock_provider = func() -> bool: return true
	sm.transition_to(&"Two")
	_assert_equal(String(sm.get_current_state_name()), "One", "locked_no_switch")
	# urgent 豁免
	sm.transition_to(&"Two", {"urgent": true})
	_assert_equal(String(sm.get_current_state_name()), "Two", "urgent_switches")
	# pending 自动执行：先回 One、锁、排 Two、解锁信号
	sm.transition_to(&"One", {"urgent": true})
	sm.transition_to(&"Two")  # 被锁 → pending
	sm.anim_lock_provider = func() -> bool: return false
	sm.notify_anim_unlocked()
	_assert_equal(String(sm.get_current_state_name()), "Two", "pending_executes")
	sm.queue_free()

const StateMachineScript = preload("res://components/state_machine.gd")
const StateScript = preload("res://components/state.gd")
```

- [x] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_anim_flow.tscn`
Expected: FAIL（anim_lock_provider/notify_anim_unlocked 不存在）

- [x] **Step 3: 实现 state_machine.gd**

成员与 `transition_to` 替换：

```gdscript
var _pending_state: StringName = &""
var _pending_msg: Dictionary = {}

## P10 动画锁查询（cat 挂载时注入；返回 true = 有一次性动作在播）
var anim_lock_provider: Callable

func transition_to(state_name: StringName, msg: Dictionary = {}) -> void:
	if not states.has(state_name):
		push_error("状态 '%s' 不存在" % state_name)
		return

	# P10 锁排队：一次性动画播放中，非 urgent 切换排队等待
	if not bool(msg.get("urgent", false)) and _anim_locked():
		_pending_state = state_name
		_pending_msg = msg
		return

	var previous_state := current_state
	if previous_state:
		previous_state.exit()
		previous_state.process_mode = Node.PROCESS_MODE_DISABLED

	current_state = states[state_name]
	current_state.process_mode = Node.PROCESS_MODE_INHERIT
	current_state.enter(msg)

	if previous_state:
		state_changed.emit(previous_state.name, current_state.name)

func _anim_locked() -> bool:
	if anim_lock_provider.is_valid():
		return bool(anim_lock_provider.call())
	return false

func notify_anim_unlocked() -> void:
	## P10 动画锁解除（cat 监听 animation_finished 后调用）：执行排队的切换
	if _pending_state != &"" and states.has(_pending_state):
		var st := _pending_state
		var msg := _pending_msg
		_pending_state = &""
		_pending_msg = {}
		transition_to(st, msg)
```

- [x] **Step 4: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_anim_flow.tscn`
Expected: `passed: 14  failed: 0`（10 + 4）

- [x] **Step 5: Commit**

```bash
git add components/state_machine.gd tests/test_anim_flow.gd
git commit -m "feat: 状态机动画锁排队与urgent豁免"
```

---

### Task 3: cat 接线（锁 provider + urgent 三链路 + 品种切换重置）

**Files:**
- Modify: `cat.gd`

- [x] **Step 1: cat.gd 三处接线**

1. 状态机初始化后（`state_machine` 就绪处，cat.gd 找 `_setup` 或 `_ready` 中 state_machine 创建后）：

```gdscript
	# P10：动画锁查询注入 + 解锁通知
	if state_machine:
		state_machine.anim_lock_provider = animation_component.is_action_locked
		animation_component.animation_finished.connect(
			func(_a): state_machine.notify_anim_unlocked())
```

2. urgent 三链路（找到对应 transition_to 调用加 msg）：
   - 拖拽开始（cat_input_component 触发猫切状态处，grep `is_dragging` 相关 transition 或 cat.gd 拖拽分支）：`transition_to(X, {"urgent": true})`
   - typing_attack：cat.gd:515 附近 `state_machine.transition_to(CatStates.TYPING_ATTACK)` → 加 `{"urgent": true}`
   - main 点击猫触发猫反应链（若有直达状态切换）同理
3. `switch_cat_type`（cat.gd:135 `animation_component.switch_cat_type` 调用处无需改——组件内部处理）。

**执行时核实**：grep `transition_to` in cat.gd + cat_input_component.gd，拖拽与点击若不直接切状态（而是状态内部轮询），则 urgent 只需给 typing_attack；以实际调用点为准，逐一加 msg。

- [x] **Step 2: headless 冒烟 + behavior 回归**

```bash
timeout 20 "$GODOT" --headless --path . res://main.tscn 2>&1 | grep -E "启动成功|SCRIPT ERROR" | head -3 && \
timeout 90 "$GODOT" --headless --path . res://tests/test_behavior_system.tscn 2>&1 | grep -E "通过|失败" | head -2
```
Expected: 启动成功；behavior 34/0

- [x] **Step 3: Commit**

```bash
git add cat.gd
git commit -m "feat: 猫接线动画锁与urgent链路"
```

---

### Task 4: 移动平滑

**Files:**
- Modify: `states/cat_walking_state.gd`、`states/cat_chasing_state.gd`、`states/cat_eating_state.gd`（phase 1）
- Modify: `tests/test_anim_flow.gd`

- [x] **Step 1: 追加失败测试（_run 追加 `_test_move_smooth()`）**

```gdscript
const ChasingStateScript = preload("res://states/cat_chasing_state.gd")

func _test_move_smooth() -> void:
	# 追逐方向平滑：初始方向被 lerp 拉近目标而非立即全转
	var cat_node := Node2D.new()
	cat_node.position = Vector2(500, 500)
	add_child(cat_node)
	var sprite := AnimatedSprite2D.new()
	sprite.name = "AnimatedSprite2D"
	cat_node.add_child(sprite)
	var sm := Node.new(); sm.name = "StateMachine"
	cat_node.add_child(sm)
	var chase = ChasingStateScript.new()
	chase.name = "Chasing"
	sm.add_child(chase)
	chase.cat = cat_node
	chase.state_machine = sm
	# 老鼠在正东（+x）：初始 velocity 为零向量，首帧后方向应介于 0°~90°（含向东分量）
	chase.enter({})
	chase.physics_update(1.0 / 60.0)
	var pos_after: Vector2 = cat_node.position
	var moved := pos_after - Vector2(500, 500)
	_assert_true(moved.x > 0.0, "chase_moves_east_instant")
	# 速度渐变：首帧速度 < 满速（300/60=5px；ramp 0.3s 首帧应远小于 5）
	_assert_true(moved.length() < 4.5, "chase_ramps_up")
	cat_node.queue_free()
```

（`state_machine` 属性为 State 基类字段，直接赋 Node 需要它有 transition_to——测试不触发切换所以安全；若 State 基类 `_ready` 强依赖 owner，改用 `chase.set_script` 前置后手动赋值绕过。执行时如 _ready 报错，把 chase 的注册流程照 test_behavior_system 里已有的状态机构造方式搬。）

- [x] **Step 2: 跑测试确认失败 → 实现三状态平滑**

cat_chasing_state.gd 替换移动段：

```gdscript
var _move_dir := Vector2.ZERO   # P10 平滑方向
var _speed_ramp := 0.0

func enter(_msg: Dictionary = {}) -> void:
	play_animation("chasing")
	_move_dir = Vector2.RIGHT  # 朝向初始值（首帧会被 lerp 拉正）
	_speed_ramp = 0.0

func physics_update(delta: float) -> void:
	var mouse_pos := get_mouse_position()
	var target_dir := (mouse_pos - cat.global_position).normalized()
	# P10 平滑：方向 lerp（转向不折线）+ 速度 ramp（起步不突兀）
	_move_dir = _move_dir.lerp(target_dir, 0.15).normalized()
	_speed_ramp = minf(_speed_ramp + delta / 0.3, 1.0)
	cat.global_position += _move_dir * chase_speed * _speed_ramp * delta
	face_direction(target_dir.x)

	if cat.global_position.distance_squared_to(mouse_pos) < catch_distance_sq:
		if randf() < pounce_chance:
			transition_to(CatStates.POUNCING, {"target": mouse_pos})
		else:
			transition_to(CatStates.IDLE)
```

cat_walking_state.gd 同模式（`_move_dir` 初始取 enter 时方向、lerp 0.15、ramp 0.3）；cat_eating_state.gd phase 1 同模式（保留 interact_distance 判定不变）。

- [x] **Step 3: 跑测试通过 + Commit**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_anim_flow.tscn`
Expected: `passed: 16  failed: 0`

```bash
git add states/cat_chasing_state.gd states/cat_walking_state.gd states/cat_eating_state.gd tests/test_anim_flow.gd
git commit -m "feat: 移动方向lerp与速度渐变平滑"
```

---

### Task 5: 节奏表与链调度对齐

**Files:**
- Create: `components/animation_timing.gd`
- Modify: `cat_behavior_system.gd`（链步进时长读表）
- Modify: `tests/test_anim_flow.gd`

- [x] **Step 1: 追加失败测试（_run 追加 `_test_timing_table()`）**

```gdscript
const TimingScript = preload("res://components/animation_timing.gd")

func _test_timing_table() -> void:
	# 节奏表：min_duration ≥ 播完一遍（frames/speed）；已知动作有表项
	var t: float = TimingScript.min_duration("eat", 8, 7.0)
	_assert_true(t >= 8.0 / 7.0 - 0.001, "eat_min_ge_loop")
	var p: float = TimingScript.min_duration("pounce", 8, 10.0)
	_assert_true(p >= 8.0 / 10.0 - 0.001, "pounce_min_ge_loop")
	# 未知动作回退公式
	var u: float = TimingScript.min_duration("whatever", 6, 6.0)
	_assert_true(is_equal_approx(u, 6.0 / 6.0), "unknown_falls_back")
```

- [x] **Step 2: 实现 components/animation_timing.gd**

```gdscript
class_name AnimationTiming
extends RefCounted

## P10 动作节奏表：一次性动作的调度最短时长（≥播完一遍），链调度用
## key → 倍率（相对 frames/speed 的一遍时长）；未列动作回退 1.0 倍

const OVERRIDES := {
	"eat": 1.6,        # 吃要有满足感（约 2.3s @8帧7fps）
	"pounce": 1.0,
	"pounce_attack": 1.0,
	"pounce_ready": 1.2,
	"greet": 1.2,
	"celebrate": 1.3,
	"comfort": 1.4,
	"stretch": 1.2,
	"yawn": 1.1,
	"watch_focus": 1.0,
}

static func min_duration(anim_name: String, frames: int, speed: float) -> float:
	var speed_safe := maxf(speed, 0.1)
	var base := float(frames) / speed_safe
	var mult := float(OVERRIDES.get(anim_name, 1.0))
	return base * mult
```

- [x] **Step 3: 链调度对齐——cat_behavior_system.gd**

`STATE_CHAINS` 各链 durations 中与动画绑定的步进改用节奏表下限（`update_chain` 里 `chain_timer >= duration` 判定前加下限保护）：

```gdscript
	# P10：步进时长不低于对应动画播完一遍（节奏表）
	var state_anim: String = String(chain.states[chain_index])
	var anim_cfg := AnimationConfig.get_animation_config(state_anim)
	if not anim_cfg.is_empty():
		var floor_t: float = AnimationTiming.min_duration(
			String(anim_cfg.get("name", state_anim)),
			int(anim_cfg.get("frames", 8)),
			float(anim_cfg.get("speed", 6.0)))
		duration = maxf(duration, floor_t)
```

（加在 `var duration = chain.durations[chain_index]` 之后；`duration` 声明改为 `var duration: float = float(chain.durations[chain_index])`。）

- [x] **Step 4: 跑测试 + behavior 回归 + Commit**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_anim_flow.tscn && timeout 90 "$GODOT" --headless --path . res://tests/test_behavior_system.tscn 2>&1 | grep -E "通过|失败"`
Expected: anim 19/0；behavior 34/0

```bash
git add components/animation_timing.gd cat_behavior_system.gd tests/test_anim_flow.gd
git commit -m "feat: 动作节奏表与链调度时长下限"
```

---

### Task 6: 5 品种 tres 帧率批量调优

**Files:**
- Modify: `resources/animations/orange_tabby.tres` `calico.tres` `british_blue.tres` `tuxedo.tres`（mochi/dracula 仅 6 动作，同样跑脚本顺带调）
- Create: `tools/tune_anim_speeds.py`（一次性脚本，入库留档）

- [x] **Step 1: 写调优脚本 tools/tune_anim_speeds.py**

```python
# P10 帧率批量调优：按动作类别映射新 speed（对 5 品种 tres 全部动画）
# 规则（设计文档）：待机类 5→4、移动类 +2、互动类 +1~2、睡眠类 -0.5（更沉稳）
import re, sys, glob

SPEED_MAP = {
    # 待机（更耐看）
    "idle_stand": 4.0, "idle_sit": 4.0, "idle_lie": 4.0, "idle_active": 6.0,
    # 移动（更快更连贯）
    "walk": 10.0, "trot": 11.0, "run": 12.0, "chasing": 11.0,
    # 互动（+1~2）
    "eat": 8.0, "pounce_attack": 11.0, "pounce_ready": 9.0, "pounce": 11.0,
    "greet": 9.0, "celebrate": 10.0, "comfort": 7.0, "dodge": 11.0,
    "startled": 9.0, "kneading": 6.0, "carry": 8.0, "typing_attack": 11.0,
    "blocking": 9.0, "retreat": 9.0, "jump": 9.0, "land": 9.0,
    # 睡眠/放松（更慢更沉稳）
    "sleep_curl": 2.5, "sleep": 2.5, "yawn": 5.0, "stretch": 5.5,
    "lick_groom": 6.0, "watch_focus": 5.0, "tail_wag": 9.0, "rolling": 10.0,
    "break_hint": 7.0,
}

for path in glob.glob("resources/animations/*.tres"):
    src = open(path, encoding="utf-8").read()
    out = src
    changed = 0
    for name, speed in SPEED_MAP.items():
        # 匹配 "name": &"xxx" 块内其后的 speed 行（tres 中 speed 紧邻 name 前后）
        pattern = re.compile(
            r'("name": &"' + re.escape(name) + r'",\s*\n\s*"speed": )([\d.]+)')
        out, n = pattern.subn(lambda m: m.group(1) + str(speed), out)
        changed += n
    open(path, "w", encoding="utf-8", newline="\n").write(out)
    print(path, "updated", changed)
```

（执行时先 `grep -n '"speed"' resources/animations/orange_tabby.tres | head -3` 确认 name/speed 相邻格式；若不相邻，改为解析块再写回。）

- [x] **Step 2: 跑脚本并抽查**

Run: `python tools/tune_anim_speeds.py`
Expected: 每文件 updated ≥20；`grep -A1 '"name": &"walk"' resources/animations/orange_tabby.tres` 显示 speed 10.0

- [x] **Step 3: 回归 sprite manifest 测试（读 tres 的断言）+ Commit**

Run: `timeout 90 "$GODOT" --headless --path . res://tests/test_sprite_manifest_loader.tscn 2>&1 | grep -E "passed|failed"`
Expected: 19/0（若该测试锁定了 speed 值，按新值更新断言——属数据变更非回归）

```bash
git add resources/animations/ tools/tune_anim_speeds.py tests/test_sprite_manifest_loader.gd
git commit -m "chore: 五品种动画帧率批量调优"
```

---

### Task 7: 全量回归 + MCP 真机验收 + 文档收尾

- [x] **Step 1: 15 套全量测试**

```bash
for t in test_behavior_system test_focus_session_mode test_sprite_manifest_loader test_objective_system test_activity_classifier test_foreground_app_monitor test_focus_charge_engine test_smart_modules test_bond_system test_presence_level test_first_guide test_daily_quests test_ui_theme test_offline_settlement test_anim_flow; do
  echo "=== $t ==="
  timeout 90 "$GODOT" --headless --path . res://tests/$t.tscn 2>&1 | grep -E "passed:|failed:|通过:" | tail -2
done
```
Expected: 全绿（364 + anim_flow ~19）

- [x] **Step 2: MCP 真机验收（动画专项）**

- `run_project` 启动，观察 90 秒：行为链动画无中途截断（eat/lick/pounce 全程播完）
- 快捷菜单投食 → chasing（转向平滑无折线、起步渐快）→ 到达 → eat **完整播完**（不被 idle 打断）→ lick_groom → idle
- 逗猫棒 → pounce 连招完整
- 播放期间点击猫 → **立即反应**（urgent 豁免）
- 拖拽猫 → 立即跟随（urgent）
- 打字（模拟 typing_attack）→ 立即打断
- `stop_project`

- [x] **Step 3: 勾选本计划 + 主文档追加 P10 完成记录**

- [x] **Step 4: Commit 收尾**

```bash
git add docs/plans/2026-08-17-smart-companion-redesign.md docs/superpowers/plans/2026-08-19-p10-anim-smoothness.md
git commit -m "docs: P10 完成记录"
```

---

## 附：执行提示

- Task 1→2→3 强顺序（锁接口→排队→接线）；Task 4/5 可在 3 后任意顺序；Task 6 独立可最后
- Task 3 的 urgent 链路「执行时核实」：先 grep transition_to 全调用点再定——拖拽若不直接切状态则该链路无改动
- Task 4 测试若因 State 基类 _ready 依赖 owner 报错，照 test_behavior_system 的状态机构造方式重写夹具
- Task 6 脚本跑前先备份（git 工作区即备份）；speed 格式正则先小样本验证
- 每任务 headless 冒烟；MCP 验收只做 Task 7 一次
