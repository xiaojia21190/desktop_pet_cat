# P3 会话重塑 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 专注会话玩法反转——从"你照顾猫"（被动衰减、必败）变为"猫陪你工作"（真实工作状态自动充能、可胜），并补上托盘菜单入口。

**Architecture:** 三条主线：① 数值反转——被动衰减改为基于真实工作信号的自动充能（会话订阅 typing/点击/感知活动事件），闲置才缓慢衰减，猫状态只做小幅度氛围影响；② 充能引擎独立成组件 `FocusChargeEngine`（纯逻辑，输入工作信号流，输出 focus 增减），FocusSessionMode 每秒驱动它；③ 托盘菜单加"专注会话"开关项，经信号接 main → focus_session_mode。数值目标：纯工作（持续打字）状态下 30 分钟会话必然胜利；纯摸鱼（无任何输入）约 8-10 分钟失败（有反馈但不惩罚勤奋者）。

**Tech Stack:** Godot 4.7 / GDScript；测试 headless tscn；端到端 Godot MCP。

**设计文档:** `docs/plans/2026-08-17-smart-companion-redesign.md`（专注会话重塑节）

---

## 执行前置

- `"$GODOT"` = `/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- 测试：`timeout 60 "$GODOT" --headless --path . res://tests/<name>.tscn`，期望 `failed: 0`
- 新建带 `class_name` 的 .gd 后必须先 `timeout 90 "$GODOT" --headless --path . --import`
- 每任务收尾跑七套测试：behavior_system / focus_session_mode / smart_modules / sprite_manifest_loader / objective_system / activity_classifier / foreground_app_monitor（+ 本计划新增套件）

## 文件结构总览

**Task 1** — `components/focus/focus_charge_engine.gd` 充能引擎（纯逻辑 + 9 断言）
**Task 2** — FocusSessionMode 数值反转（接充能引擎、重调事件影响、胜利条件微调 + 测试改写）
**Task 3** — 托盘"专注会话"入口（tray_controller 加菜单项 + main 接线）
**Task 4** — 会话时长可配（30/60/15 分钟档位，经托盘子菜单；数值回归快测模式 5 分钟档）
**Task 5** — 全量回归 + MCP 端到端（模拟打字流验证可胜）+ 收尾

---

### Task 1: FocusChargeEngine 充能引擎

纯逻辑组件：输入每秒的"工作信号强度"（该秒内打字数/点击数/是否专注活动），输出 focus 变化量。设计核心公式：

- `work_score` = min(typing_events * 0.6, 4.0) + min(click_events * 0.3, 2.0) + (is_focus_activity ? 1.5 : 0.0)
- 充能：`work_score >= 1.0` 时 focus += `work_score * 1.2`（下限保底 +0.8/秒）
- 闲置衰减：`work_score < 1.0` 时 focus -= 0.35/秒（慢衰，8-10 分钟归零的量级由 start=85 推出：85/0.35≈243 秒太短，故闲置衰减取 0.18：85/0.18≈470 秒≈8 分钟 ✓）
- 专注活动（coding 类）即使无键入也给 1.5 底薪——"看着代码思考"也算工作

**Files:**
- Create: `components/focus/focus_charge_engine.gd`
- Create: `tests/test_focus_charge_engine.gd` + `tests/test_focus_charge_engine.tscn`

- [x] **Step 1: 写失败测试**

`tests/test_focus_charge_engine.gd`：

```gdscript
extends Node

const EngineScript = preload("res://components/focus/focus_charge_engine.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var engine = EngineScript.new()

	# 纯打字：每秒 10 次键入 → 显著充能
	var delta_f: float = engine.compute_focus_delta({"typing": 10, "clicks": 0, "focus_activity": false})
	_assert_true(delta_f > 3.0, "typing_charges_focus")

	# 纯点击：每秒 5 次 → 温和充能
	delta_f = engine.compute_focus_delta({"typing": 0, "clicks": 5, "focus_activity": false})
	_assert_true(delta_f > 0.5, "clicks_charge_mildly")

	# 专注活动无键入（看代码思考）：底薪充能
	delta_f = engine.compute_focus_delta({"typing": 0, "clicks": 0, "focus_activity": true})
	_assert_true(delta_f >= 1.0, "focus_activity_floor_charge")

	# 完全闲置：慢衰减
	delta_f = engine.compute_focus_delta({"typing": 0, "clicks": 0, "focus_activity": false})
	_assert_true(is_equal_approx(delta_f, -0.18), "idle_slow_drain")

	# 高强度打字封顶（防炸服）
	delta_f = engine.compute_focus_delta({"typing": 100, "clicks": 50, "focus_activity": true})
	_assert_true(delta_f <= 10.0, "charge_capped")

	# 30 分钟可持续性数学验证：普通工作节奏（每秒 2 键 + 专注活动）
	# work_score = 1.2+1.5=2.7 → 每秒 +3.24，远超无损线 → 30 分钟必然胜利
	var normal_work: float = engine.compute_focus_delta({"typing": 2, "clicks": 0, "focus_activity": true})
	_assert_true(normal_work > 1.0, "normal_work_sustainable")

	# 闲置归零时间验证：85 起、-0.18/秒 → 85/0.18≈472 秒（约 8 分钟）
	var seconds_to_zero: int = int(85.0 / 0.18)
	_assert_true(seconds_to_zero > 420 and seconds_to_zero < 600, "idle_fail_in_eight_to_ten_min")

	# get_work_score 公开（HUD 可显示工作强度）
	var score: float = engine.get_work_score({"typing": 3, "clicks": 1, "focus_activity": true})
	_assert_true(score >= 1.0, "work_score_exposed")

	engine.free()
	_print_summary()
	get_tree().quit(1 if _failed > 0 else 0)

func _assert_true(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)

func _print_summary() -> void:
	print("")
	print("========== focus_charge_engine tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		for name in _failures:
			print(" - ", name)
```

`tests/test_focus_charge_engine.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/test_focus_charge_engine.gd" id="1"]

[node name="FocusChargeEngineTest" type="Node"]
script = ExtResource("1")
```

- [x] **Step 2: 运行确认失败**

Run: `timeout 30 "$GODOT" --headless --path . res://tests/test_focus_charge_engine.tscn`
Expected: 挂起（preload 不存在）——kill 后继续

- [x] **Step 3: 实现引擎**

`components/focus/focus_charge_engine.gd`：

```gdscript
class_name FocusChargeEngine
extends RefCounted

## 专注会话充能引擎：把真实工作信号翻译成 focus 增减。纯逻辑无状态。
##
## 玩法反转的核心：勤奋工作 → focus 上升；闲置 → 缓慢下降（约 8 分钟失败）；
## 猫的干扰事件不再大幅扣 focus（会话侧重另有小系数处理）。

const TYPING_WEIGHT := 0.6       # 每次键入的工作分
const TYPING_CAP := 4.0          # 键入分封顶
const CLICK_WEIGHT := 0.3
const CLICK_CAP := 2.0
const FOCUS_ACTIVITY_BONUS := 1.5  # 专注类活动（coding 等）底薪
const CHARGE_MULTIPLIER := 1.2   # 工作分 → focus 增益倍率
const CHARGE_FLOOR := 0.8        # 达标时最低充能
const IDLE_DRAIN := -0.18        # 完全闲置每秒衰减（85 → 0 约 8 分钟）
const WORK_SCORE_THRESHOLD := 1.0
const MAX_DELTA := 10.0          # 单秒增减封顶

func compute_focus_delta(signal: Dictionary) -> float:
	## signal: {typing: int, clicks: int, focus_activity: bool}
	## 返回该秒的 focus 变化量
	var score := get_work_score(signal)
	var delta := 0.0
	if score >= WORK_SCORE_THRESHOLD:
		delta = maxf(score * CHARGE_MULTIPLIER, CHARGE_FLOOR)
	else:
		delta = IDLE_DRAIN
	return clampf(delta, -MAX_DELTA, MAX_DELTA)

func get_work_score(signal: Dictionary) -> float:
	var typing := float(signal.get("typing", 0))
	var clicks := float(signal.get("clicks", 0))
	var focus_activity := bool(signal.get("focus_activity", false))
	var score := minf(typing * TYPING_WEIGHT, TYPING_CAP)
	score += minf(clicks * CLICK_WEIGHT, CLICK_CAP)
	if focus_activity:
		score += FOCUS_ACTIVITY_BONUS
	return score
```

**注意**：`signal` 是 GDScript 关键字，参数名改用 `work_signal`。实现时用：

```gdscript
func compute_focus_delta(work_signal: Dictionary) -> float:
	var score := get_work_score(work_signal)
	...

func get_work_score(work_signal: Dictionary) -> float:
	var typing := float(work_signal.get("typing", 0))
	...
```

（测试调用侧不变——按参数位置传 Dictionary。）

- [x] **Step 4: 刷新缓存并跑测试**

Run: `timeout 90 "$GODOT" --headless --path . --import` 然后 `timeout 30 "$GODOT" --headless --path . res://tests/test_focus_charge_engine.tscn`
Expected: `passed: 8  failed: 0`

- [x] **Step 5: Commit**

```bash
git add components/focus/focus_charge_engine.gd tests/test_focus_charge_engine.gd tests/test_focus_charge_engine.tscn
git commit -m "feat: 新增专注会话充能引擎"
```

---

### Task 2: FocusSessionMode 数值反转

三处改动：① `_apply_passive_changes` 换成充能引擎驱动（信号由会话自己统计）；② 事件影响系数整体缩小（猫的干扰从"致命"变"氛围"）；③ 会话新增 `record_work_input(typing, clicks)` 喂入口（main 从 keyboard/mouse 接线，感知活动从 collector 快照读）。胜利条件不变（撑满时长）；失败条件不变（focus 归零/chaos 满 100——但 chaos 增速大幅调低）。

**Files:**
- Modify: `focus_session_mode.gd`（:333 `_apply_passive_changes`、:259 `on_typing_attack`、:288 `on_cat_state_changed` 数值区）
- Modify: `main.gd`（工作信号接线）
- Test: `tests/test_focus_session_mode.gd`（数值断言改写）

- [x] **Step 1: 改写测试（先定义新行为预期）**

`tests/test_focus_session_mode.gd` 中 `mode.start_session()` 断言块后追加/修改：

```gdscript
	# —— 数值反转（P3）：工作充能、闲置慢衰、猫干扰温和化 ——
	mode2 = FOCUS_SESSION_MODE_SCRIPT.new()
	mode2.show_tutorial_on_start = false
	add_child(mode2)
	await get_tree().process_frame
	mode2.start_session()
	var focus_at_start: float = float(mode2.focus_value)

	# 模拟 60 秒高强度打字：focus 应显著上升
	for i in range(60):
		mode2.record_work_input({"typing": 8, "clicks": 1, "focus_activity": true})
		mode2._tick_one_second()
	_assert_true(float(mode2.focus_value) > focus_at_start + 20.0, "working_charges_focus")

	# 模拟 300 秒纯闲置：focus 应下降但未归零（慢衰）
	var focus_before_idle: float = float(mode2.focus_value)
	for i in range(300):
		mode2.record_work_input({"typing": 0, "clicks": 0, "focus_activity": false})
		mode2._tick_one_second()
	_assert_true(float(mode2.focus_value) < focus_before_idle, "idle_drains_focus")
	_assert_true(float(mode2.focus_value) > 0.0, "idle_300s_not_dead_yet")

	# 猫状态干扰温和化：Blocking 从 -5 降为 -1.2 量级
	var focus_before_block: float = float(mode2.focus_value)
	mode2.on_cat_state_changed(&"Blocking")
	_assert_true(float(mode2.focus_value) > focus_before_block - 2.5, "blocking_mild_penalty")

	mode2.queue_free()
```

（`mode2` 需在 `_run` 开头声明：`var mode2`。`_tick_one_second()` 是新增测试辅助——把 `_process` 的每秒逻辑抽成可单步调用的方法，见 Step 3。）

- [x] **Step 2: 确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_focus_session_mode.tscn`
Expected: FAIL——`record_work_input` / `_tick_one_second` 不存在

- [x] **Step 3: 实现数值反转**

`focus_session_mode.gd`：

1. 成员区加（`var _tutorial` 附近）：

```gdscript
var _charge_engine := FocusChargeEngine.new()
var _work_signal_buffer := {"typing": 0, "clicks": 0, "focus_activity": false}
```

2. 新增喂入口与单步方法（`start_session` 后）：

```gdscript
func record_work_input(work_signal: Dictionary) -> void:
	## main 从键盘/鼠标/感知接线喂入；会话未运行时忽略
	if not _running:
		return
	_work_signal_buffer["typing"] = int(work_signal.get("typing", 0))
	_work_signal_buffer["clicks"] = int(work_signal.get("clicks", 0))
	_work_signal_buffer["focus_activity"] = bool(work_signal.get("focus_activity", false))

func _tick_one_second() -> void:
	## 每秒核心滴答：抽自 _process 便于测试单步驱动
	_elapsed_seconds += 1
	_remaining_seconds = max(_remaining_seconds - 1, 0)
	_current_objective_tier = _current_difficulty_tier()
	_apply_passive_changes()
	_consume_demo_events()
	if _objective_system.check_timeout(_objective_timer, focus_value, affection_value, chaos_value):
		_apply_delta(-4.0, -3.0, 6.0, "Objective failed. Penalty applied.")
		_record_event("objective_failed", {
			"id": _objective_system.get_objective_key(),
			"target": _objective_system.get_objective_target()
		})
		_roll_objective()
	_check_end_condition()
	_check_recording_target()
	# 用完清零，等待下一秒新信号
	_work_signal_buffer["typing"] = 0
	_work_signal_buffer["clicks"] = 0
```

3. `_process` 的 while 循环体替换为 `_tick_one_second()` 调用（保留 `_time_accumulator` 逻辑与 `if not _running: break`）：

```gdscript
	while _time_accumulator >= 1.0:
		_time_accumulator -= 1.0
		_tick_one_second()
		if not _running:
			break
```

4. `_apply_passive_changes`（:333）整体替换：

```gdscript
func _apply_passive_changes() -> void:
	# P3 玩法反转：真实工作信号充能，闲置慢衰
	var focus_delta := _charge_engine.compute_focus_delta(_work_signal_buffer)
	focus_value = clampf(focus_value + focus_delta, MIN_VALUE, MAX_VALUE)
	# chaos 慢慢自然回落；affection 随工作缓慢增长（猫喜欢陪你干活）
	chaos_value = clampf(chaos_value - 0.5, MIN_VALUE, MAX_VALUE)
	var affection_shift := 0.1
	if focus_delta > 0.0:
		affection_shift = 0.2
	affection_value = clampf(affection_value + affection_shift, MIN_VALUE, MAX_VALUE)

	if _objective_system.check_progress(focus_value, affection_value, chaos_value):
		_apply_delta(3.0, 4.0, -4.0, "Objective completed. Bonus applied.")
		_record_event("objective_completed", {
			"id": _objective_system.get_objective_key(),
			"target": _objective_system.get_objective_target()
		})
		_roll_objective()
```

5. 事件影响温和化（`on_typing_attack` :259 与 `on_cat_state_changed` :288 的 match 数值）：

```gdscript
func on_typing_attack() -> void:
	if not _running:
		return
	# P3：打字攻击改为小幅度 chaos 波动（打字本身是工作，不该惩罚）
	_apply_delta(0.0, -0.5, 3.0, "Cat pounced on your keyboard!")
	_record_event("typing_attack")
	_check_end_condition()
```

`on_cat_state_changed` 的 match 块数值改为：

```gdscript
	match to_state:
		&"Blocking":
			_apply_delta(-1.2, -0.3, 2.5, "Blocking state triggered.")
		&"Chasing":
			_apply_delta(-1.0, 0.0, 2.0, "Chasing state triggered.")
		&"Pouncing":
			_apply_delta(-0.8, 0.0, 1.8, "Pouncing state triggered.")
		&"TailWagging":
			_apply_delta(0.5, 1.0, -1.0, "Tail wagging improved mood.")
		&"Watching":
			_apply_delta(-0.3, 0.3, 0.5, "Cat is watching your cursor.")
		_:
			return
```

6. `main.gd` 接线（`_on_keyboard_typing_for_smart` :324 附近加会话喂入；新增每秒聚合作）：

```gdscript
func _on_keyboard_typing_for_smart(_event: InputEvent) -> void:
	if smart_pet_controller:
		smart_pet_controller.record_typing()
	# P3：会话工作信号计数（每秒聚合后由 _process 喂入）
	if focus_session_mode and focus_session_mode._running:
		_session_typing_count += 1
```

main 成员区加：

```gdscript
var _session_typing_count := 0
var _session_click_count := 0
var _session_signal_timer := 0.0
```

main `_process`（悬浮面板更新附近）加：

```gdscript
	# 每秒聚合工作信号喂给专注会话
	if focus_session_mode and focus_session_mode._running:
		_session_signal_timer += delta
		if _session_signal_timer >= 1.0:
			_session_signal_timer = 0.0
			var focus_activity := false
			if smart_pet_controller and smart_pet_controller._context_collector:
				var snap: Dictionary = smart_pet_controller._context_collector.get_snapshot()
				focus_activity = String(snap.get("activity", "")) == "coding"
			focus_session_mode.record_work_input({
				"typing": _session_typing_count,
				"clicks": _session_click_count,
				"focus_activity": focus_activity
			})
			_session_typing_count = 0
			_session_click_count = 0
```

（点击计数：本期先只接 typing——鼠标点击流暂无全局监听，YAGNI，`clicks` 留 0。）

- [x] **Step 4: 跑测试（含既有套件防回归）**

Run: 七套 + 新 charge_engine 套
Expected: 全部 `failed: 0`。重点看 `test_focus_session_mode` 的旧断言 `typing_event_reduces_focus` ——**该断言基于旧数值语义（demo typing 事件扣 focus），P3 后 demo "typing" 事件走 `_apply_demo_event` → `on_typing_attack` → 新语义不再减 focus**。若失败：把该断言改为验证 chaos 上升（`mode.chaos_value > chaos_before`），断言名改 `typing_event_bumps_chaos`。

- [x] **Step 5: Commit**

```bash
git add focus_session_mode.gd main.gd tests/test_focus_session_mode.gd components/focus/focus_charge_engine.gd
git commit -m "feat: 专注会话玩法反转为工作充能制"
```

---

### Task 3: 托盘"专注会话"入口

托盘菜单加开关项"专注会话"，点击切换开始/结束，菜单文本随状态变。

**Files:**
- Modify: `components/desktop/tray_controller.gd`
- Modify: `main.gd`

- [x] **Step 1: tray_controller 加菜单项**

`components/desktop/tray_controller.gd`：

1. 信号区加：

```gdscript
signal toggle_focus_session_requested
```

2. 成员区加：

```gdscript
var _focus_index := -1
var _focus_active := false
```

3. `_build_menu()`（:30）在"设置"项后加：

```gdscript
	_focus_index = NativeMenu.add_item(
		_menu,
		_focus_label(),
		Callable(self, "_on_toggle_focus_session")
	)
```

4. 新增方法（`update_menu_label` 附近）：

```gdscript
func set_focus_session_active(active: bool) -> void:
	_focus_active = active
	if _menu.is_valid() and _focus_index >= 0:
		NativeMenu.set_item_text(_menu, _focus_index, _focus_label())

func _on_toggle_focus_session() -> void:
	toggle_focus_session_requested.emit()

func _focus_label() -> String:
	return "结束专注会话" if _focus_active else "开始专注会话"
```

- [x] **Step 2: main 接线**

`main.gd` `_setup_tray()`（信号连接区）加：

```gdscript
	tray_controller.toggle_focus_session_requested.connect(_on_tray_toggle_focus_session)
```

新增方法（`_on_tray_open_settings` 附近）：

```gdscript
func _on_tray_toggle_focus_session() -> void:
	if not focus_session_mode:
		return
	if focus_session_mode._running:
		focus_session_mode.stop_session("tray_toggle")
	else:
		focus_session_mode.start_session()
	if tray_controller:
		tray_controller.set_focus_session_active(focus_session_mode._running)
```

`focus_session_mode.gd` 加公开停止方法（`start_session` 后）：

```gdscript
func stop_session(reason: String = "manual_stop") -> void:
	## 手动结束会话：按当前剩余时间给出结算，不发 failure 事件
	if not _running:
		return
	var summary := {
		"focus": focus_value,
		"affection": affection_value,
		"chaos": chaos_value,
		"remaining_seconds": _remaining_seconds,
		"stopped_reason": reason
	}
	_running = false
	_finished = true
	_hud.hide_hud()
	_hud.show_result("Session Paused", "Keep it up! F5 restart | tray to resume.")
	_record_event("session_stopped", summary)
```

会话自然结束时 main 也要刷新托盘文本——`_on_focus_session_finished`（main.gd :530 附近）开头加：

```gdscript
	if tray_controller:
		tray_controller.set_focus_session_active(false)
```

- [x] **Step 3: 七套测试 + MCP 冒烟**

Run: 七套 tscn 全绿；MCP `run_project` 启动无 SCRIPT ERROR（托盘菜单在 OS 层，headless 无法断言其内容——冒烟只验证脚本不炸）

- [x] **Step 4: Commit**

```bash
git add components/desktop/tray_controller.gd main.gd focus_session_mode.gd
git commit -m "feat: 托盘新增专注会话开关入口"
```

---

### Task 4: 会话时长档位

托盘"开始专注会话"默认 30 分钟；本期加 15/30/60 三档——**用子菜单**（NativeMenu submenu）或循环切换。选最简实现：托盘菜单项点击开始（30 分钟默认），Ctrl+点击或长按不做（YAGNI）——**改为设置面板加档位下拉**（设置已有 OptionButton 模式，成本低且可存档）。

**Files:**
- Modify: `settings_panel.tscn`（感知分区后加"专注时长"OptionButton）
- Modify: `settings_panel.gd`
- Modify: `save_manager.gd`（四点白名单：default/load/write/gather）
- Modify: `focus_session_mode.gd`（session_duration_seconds 可运行时改）

- [x] **Step 1: tscn 加节点（Sep3 前）**

```
[node name="FocusDurationLabel" type="Label" parent="ScrollContainer/VBoxContainer"]
layout_mode = 2
theme_override_colors/font_color = Color(0.9, 0.88, 0.95, 1)
text = "专注会话时长"

[node name="FocusDurationOption" type="OptionButton" parent="ScrollContainer/VBoxContainer"]
layout_mode = 2
item_count = 3
popup/item_0/text = "15 分钟"
popup/item_1/text = "30 分钟"
popup/item_2/text = "60 分钟"
selected = 1
```

- [x] **Step 2: settings_panel.gd 接线**

1. `@onready` 加：

```gdscript
@onready var focus_duration_option: OptionButton = $ScrollContainer/VBoxContainer/FocusDurationOption
```

2. 加载段加：

```gdscript
	var focus_duration_index := int(settings.get("focus_duration_index", 1))
	focus_duration_option.select(clampi(focus_duration_index, 0, 2))
```

3. 信号连接段加：

```gdscript
	focus_duration_option.item_selected.connect(_on_focus_duration_selected)
```

4. 回调（`_on_perception_toggled` 后）：

```gdscript
const FOCUS_DURATION_SECONDS := [15 * 60, 30 * 60, 60 * 60]

func _on_focus_duration_selected(_index: int) -> void:
	SaveManager.save_data()
	_apply_focus_duration()

func _apply_focus_duration() -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if main and main.focus_session_mode:
		main.focus_session_mode.session_duration_seconds = FOCUS_DURATION_SECONDS[clampi(focus_duration_option.selected, 0, 2)]
```

5. `_apply_smart_settings()` 末尾加 `_apply_focus_duration()` 调用（启动时恢复档位）。

- [x] **Step 3: save_manager 四点白名单**

`_get_default_data` settings 字典加 `"focus_duration_index": 1`；
`load_data` 加 `settings["focus_duration_index"] = config.get_value("settings", "focus_duration_index", settings["focus_duration_index"])`；
`_write_config` 加 `config.set_value("settings", "focus_duration_index", settings.get("focus_duration_index", 1))`；
`_gather_current_data` 面板读取段加：

```gdscript
		var focus_duration_option = panel.get_node_or_null("VBoxContainer/FocusDurationOption")
		if focus_duration_option:
			settings["focus_duration_index"] = focus_duration_option.selected
```

- [x] **Step 4: 七套测试 + MCP 冒烟 + Commit**

```bash
git add settings_panel.tscn settings_panel.gd save_manager.gd
git commit -m "feat: 专注会话时长档位设置"
```

---

### Task 5: 全量回归 + MCP 端到端 + 收尾

- [x] **Step 1: 八套测试全绿**（七套 + charge_engine）

- [x] **Step 2: MCP 端到端（可胜性验证）**

1. 写临时存档开启感知；MCP `run_project`
2. 由于 headless 无法模拟真实键盘流，**用 demo 通道验证**：在 debug 输出确认——临时给 main 加 30 行调试代码（`_process` 里检测会话运行时每 2 秒 print focus 值），真机观察 60 秒内 focus 从 85 走高（本机此时在敲终端命令 = typing 信号真实流入）→ **验证后删除调试代码**
3. 若 focus 不升：检查 `_on_keyboard_typing_for_smart` 是否被触发（keyboard_listener 挂在主场景？grep main.tscn 确认节点存在）、`_session_typing_count` 聚合是否进 `record_work_input`
4. 渲染验证：截图 + 橙色像素聚类（复用既有流程）

- [x] **Step 3: 收尾提交与文档**

```bash
git add -A
git commit -m "feat: P3 会话重塑完成"
```

设计文档追加 "P3 完成记录"：数值表（充能/衰减/干扰新旧对照）、托盘入口、时长档位、可胜性验证输出摘录。

---

## 自检记录（Self-Review）

1. **Spec 覆盖**：玩法反转（Task 1+2）、托盘入口（Task 3）、数值可胜（Task 1 数学验证 + Task 2 事件温和化 + Task 5 端到端）、时长档位（Task 4，计划细化）。设计文档"专注会话重塑"节全覆盖。
2. **占位符**：Task 5 Step 2 的"临时调试代码"给了具体做法（每 2 秒 print focus）；Task 2 Step 4 的旧断言改写给了明确替代（`typing_event_bumps_chaos`）。
3. **类型一致性**：`compute_focus_delta(work_signal: Dictionary) -> float` / `get_work_score` / `record_work_input` / `_tick_one_second` / `stop_session(reason)` / `set_focus_session_active(active)` / `toggle_focus_session_requested` 各任务签名一致；Task 1 测试与 Task 2 会话测试用同一 signal 字典结构 `{typing, clicks, focus_activity}`。
