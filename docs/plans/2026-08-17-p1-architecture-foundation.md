# P1 架构地基 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 行为不变的纯重构——心理数据统一到 CatBehaviorSystem、focus_session_mode.gd（1887 行）拆为单一职责组件、main.gd（962 行）瘦身，全程测试绿。

**Architecture:** 拆分采用"组合而非继承"：FocusSessionMode 保留为门面（信号与公共 API 不变，main.gd 零感知），内部委托给四个子组件（会话状态机/目标卡系统/HUD 视图/教程）；录制回放整体搬至 tests/debug_tools/ 仅调试场景加载。心理统一走"适配层"路线：CatBehaviorSystem 新增 chaos 维度，专注会话数值代理到它，行为外观（状态选择、动画）不变。

**Tech Stack:** Godot 4.7 / GDScript。测试：headless 运行 tests/*.tscn；端到端：Godot MCP（run_project + get_debug_output + 橙色像素截图验证）。

**设计文档:** `docs/plans/2026-08-17-smart-companion-redesign.md`

---

## 执行前置

- Godot 可执行文件：`D:/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`（下文以 `$GODOT` 指代）
- 测试命令：`"$GODOT" --headless --path . res://tests/<name>.tscn`，期望输出 `failed: 0`
- 每个任务收尾必须跑通全部三套 tscn 测试：`test_focus_session_mode` / `test_smart_modules` / `test_sprite_manifest_loader`
- 拆分类放 `components/focus/` 目录；调试设施放 `tests/debug_tools/`
- 本计划所有行号基于 2026-08-17 工作区（commit e8bf00a 后）

## 文件结构总览

**Task 1** — 修 `tests/test_behavior_system.gd`（headless 退出）
**Task 2** — `cat_behavior_system.gd` 加 chaos 维度（心理唯一源准备）
**Task 3** — 拆 `components/focus/objective_system.gd`（目标卡，纯逻辑无 UI）
**Task 4** — 拆 `components/focus/focus_hud.gd`（HUD 构建+刷新）
**Task 5** — 拆 `components/focus/tutorial_controller.gd`（教程）
**Task 6** — 拆 `components/focus/session_recorder.gd`（录制/回放/文件管理，整体搬 tests/debug_tools/）
**Task 7** — 心理统一：FocusSessionMode 数值代理到 CatBehaviorSystem
**Task 8** — main.gd 瘦身第一刀：托盘+鼠标穿透拆出
**Task 9** — main.gd 瘦身第二刀：SMART 气泡+悬浮面板拆出
**Task 10** — 全量回归 + MCP 端到端验证 + 收尾

---

### Task 1: 修复 test_behavior_system.gd headless 不退出

历史遗留：测试跑完无 `quit()`，headless 挂起。P1 大量依赖行为系统测试，先修。

**Files:**
- Modify: `tests/test_behavior_system.gd`
- Create: `tests/test_behavior_system.tscn`

- [ ] **Step 1: 创建测试场景文件**

`tests/test_behavior_system.tscn`（与 test_focus_session_mode.tscn 同构）：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/test_behavior_system.gd" id="1"]

[node name="BehaviorSystemTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 给测试加退出逻辑**

`tests/test_behavior_system.gd` 的 `_ready()` 末尾（原第 21 行 `_print_results()` 之后）改为：

```gdscript
func _ready():
	print("========== 行为系统单元测试 ==========")
	behavior_system = CatBehaviorSystem.new()
	add_child(behavior_system)

	_run_all_tests()
	_print_results()
	# headless 模式必须显式退出：失败退出码 1，供 CI 判定
	get_tree().quit(1 if tests_failed > 0 else 0)
```

- [ ] **Step 3: 运行验证**

Run: `"$GODOT" --headless --path . res://tests/test_behavior_system.tscn`
Expected: 输出 `通过: N 失败: 0`（N≈18）后**进程退出**，不再挂起

- [ ] **Step 4: Commit**

```bash
git add tests/test_behavior_system.gd tests/test_behavior_system.tscn
git commit -m "test: 行为系统测试支持 headless 退出"
```

---

### Task 2: CatBehaviorSystem 新增 chaos 维度

心理唯一源的第一步：行为系统补上 chaos（混乱度），接口仿照现有 mood/energy/affection。**本任务只加维度，不改任何调用方**。

**Files:**
- Modify: `cat_behavior_system.gd`
- Test: `tests/test_behavior_system.gd`

- [ ] **Step 1: 写失败测试**

在 `tests/test_behavior_system.gd` 的 `_run_all_tests()` 情绪系统测试块（`test_emotion_clamping()` 调用后）加两行调用：

```gdscript
	test_chaos_modification()
	test_chaos_clamping()
```

文件尾部（`_print_results` 前）加测试函数：

```gdscript
func test_chaos_modification():
	behavior_system.chaos = 20.0
	behavior_system.modify_chaos(15)
	_assert_equal(behavior_system.chaos, 35.0, "chaos_modification")

func test_chaos_clamping():
	behavior_system.chaos = 90.0
	behavior_system.modify_chaos(50)
	_assert_equal(behavior_system.chaos, 100.0, "chaos_clamp_max")

	behavior_system.modify_chaos(-200)
	_assert_equal(behavior_system.chaos, 0.0, "chaos_clamp_min")
```

- [ ] **Step 2: 运行确认失败**

Run: `"$GODOT" --headless --path . res://tests/test_behavior_system.tscn`
Expected: FAIL——`chaos` 属性不存在（脚本解析报错或运行时报错）

- [ ] **Step 3: 实现 chaos 维度**

`cat_behavior_system.gd` 第 21-24 行情绪属性块加一行：

```gdscript
var chaos: float = 20.0       # 混乱度：影响猫闹腾程度（0-100）
```

`modify_affection()`（第 71 行）之后加：

```gdscript
func modify_chaos(delta: float):
	var old = chaos
	chaos = clamp(chaos + delta, 0, 100)
	if chaos != old:
		chaos_changed.emit(chaos, old)
```

signal 声明区（第 53-56 行附近）加：

```gdscript
signal chaos_changed(new_chaos: float, old_chaos: float)
```

`get_save_data()`（第 536 行）字典加 `"chaos": chaos,`；
`load_save_data()`（第 549 行）加 `chaos = data.get("chaos", 20.0)`。
**注意：`update()`（第 482 行）不加 chaos 衰减——chaos 由事件驱动（专注会话/猫状态），不随时间自然变化。**

- [ ] **Step 4: 运行验证通过**

Run: `"$GODOT" --headless --path . res://tests/test_behavior_system.tscn`
Expected: `失败: 0`

- [ ] **Step 5: Commit**

```bash
git add cat_behavior_system.gd tests/test_behavior_system.gd
git commit -m "feat: 行为系统新增 chaos 心理维度"
```

---

### Task 3: 拆出 ObjectiveSystem（目标卡系统）

纯逻辑、无 UI、无 Godot 节点依赖——最适合先拆。从 focus_session_mode.gd 抽出目标卡的数据与判定（原 :949-1096 的 `_roll_new_objective` / `_pick_objective_card` / `_current_difficulty_tier` / `_cards_for_tier` / `_weighted_pick` / `_sample_target` / `_check_objective_progress` / `_check_objective_timeout` / `_is_objective_completed` / `_objective_progress` 及常量 OBJECTIVE_* 与 :1591 默认卡组）。

**Files:**
- Create: `components/focus/objective_system.gd`
- Modify: `focus_session_mode.gd`（删被移代码，改为委托调用）
- Create: `tests/test_objective_system.gd` + `tests/test_objective_system.tscn`

- [ ] **Step 1: 写失败测试**

`tests/test_objective_system.gd`：

```gdscript
extends Node

const ObjectiveSystemScript = preload("res://components/focus/objective_system.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var sys = ObjectiveSystemScript.new()
	add_child(sys)

	sys.set_cards([
		{"id": "keep_focus", "target_min": 40.0, "target_max": 60.0,
		 "weight": 1.0, "tier_min": 1, "tier_max": 3},
		{"id": "reduce_chaos", "target_min": 2.0, "target_max": 10.0,
		 "weight": 1.0, "tier_min": 1, "tier_max": 3}
	])

	# 初始无目标
	_assert_true(sys.get_objective_key().is_empty(), "no_objective_initially")

	# roll 出目标后 key 合法、target 在区间
	sys.roll_new_objective(1, 50.0, 45.0, 20.0)
	_assert_true(not sys.get_objective_key().is_empty(), "objective_rolled")
	var target: float = sys.get_objective_target()
	_assert_true(target >= 2.0 and target <= 60.0, "target_in_range")

	# keep_focus 完成：focus 抬到 95
	if sys.get_objective_key() == "keep_focus":
		_assert_true(sys.is_completed(95.0, 45.0, 20.0), "keep_focus_completed")
	# reduce_chaos 完成：chaos 压到 0
	if sys.get_objective_key() == "reduce_chaos":
		_assert_true(sys.is_completed(50.0, 45.0, 0.0), "reduce_chaos_completed")

	# 进度值合法
	var progress: float = sys.progress(50.0, 45.0, 10.0)
	_assert_true(progress >= 0.0 and progress <= 1.0, "progress_valid")

	# 重新 roll 可换新目标
	sys.roll_new_objective(2, 50.0, 45.0, 10.0)
	_assert_true(not sys.get_objective_key().is_empty(), "reroll_works")

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
	print("========== objective_system tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		for name in _failures:
			print(" - ", name)
```

`tests/test_objective_system.tscn`（同 Task 1 结构，ext_resource 指向本测试脚本，根节点名 ObjectiveSystemTest）。

- [ ] **Step 2: 运行确认失败**

Run: `"$GODOT" --headless --path . res://tests/test_objective_system.tscn`
Expected: FAIL——文件不存在，加载报错

- [ ] **Step 3: 实现 ObjectiveSystem**

`components/focus/objective_system.gd`：

```gdscript
class_name FocusObjectiveSystem
extends Node

## 专注会话目标卡系统：卡组管理、按难度抽卡、完成/超时判定。纯逻辑，无 UI。

signal objective_completed(objective_id: String, target: float)
signal objective_failed(objective_id: String, target: float)
signal objective_rolled(objective_id: String, target: float, tier: int)

const OBJECTIVE_KEEP_FOCUS := "keep_focus"
const OBJECTIVE_REDUCE_CHAOS := "reduce_chaos"
const OBJECTIVE_BUILD_AFFECTION := "build_affection"

var _cards: Array[Dictionary] = []
var _current_key: String = ""
var _current_target: float = 0.0
var _current_tier: int = 1
var _start_focus: float = 0.0
var _start_affection: float = 0.0
var _start_chaos: float = 0.0
var _forced_sequence: Array[String] = []
var _forced_cursor: int = 0

func set_cards(cards: Array[Dictionary]) -> void:
	var normalized: Array[Dictionary] = []
	for card in cards:
		if not card.has("id"):
			continue
		normalized.append({
			"id": String(card.get("id", "")),
			"target_min": float(card.get("target_min", 0.0)),
			"target_max": float(card.get("target_max", 100.0)),
			"weight": float(card.get("weight", 1.0)),
			"tier_min": int(card.get("tier_min", 1)),
			"tier_max": int(card.get("tier_max", 3))
		})
	if normalized.is_empty():
		return
	_cards = normalized

func set_forced_sequence(ids: Array[String]) -> void:
	_forced_sequence = ids
	_forced_cursor = 0

func roll_new_objective(tier: int, focus: float, affection: float, chaos: float) -> void:
	if _cards.is_empty():
		return
	_current_tier = tier
	var card := {}
	for _i in range(8):
		card = _pick_card(tier)
		_current_key = String(card.get("id", ""))
		_current_target = _sample_target(_current_key, card, focus, affection, chaos)
		if not is_completed(focus, affection, chaos):
			break
	_start_focus = focus
	_start_affection = affection
	_start_chaos = chaos
	objective_rolled.emit(_current_key, _current_target, tier)

func get_objective_key() -> String:
	return _current_key

func get_objective_target() -> float:
	return _current_target

func is_completed(focus: float, affection: float, chaos: float) -> bool:
	match _current_key:
		OBJECTIVE_KEEP_FOCUS:
			return focus >= _current_target
		OBJECTIVE_REDUCE_CHAOS:
			return chaos <= _current_target
		OBJECTIVE_BUILD_AFFECTION:
			return affection >= _current_target
		_:
			return false

func progress(focus: float, affection: float, chaos: float) -> float:
	match _current_key:
		OBJECTIVE_KEEP_FOCUS:
			if _current_target <= 0.0:
				return 0.0
			return clampf(focus / _current_target, 0.0, 1.0)
		OBJECTIVE_REDUCE_CHAOS:
			var span := maxf(_start_chaos - _current_target, 0.01)
			return clampf((_start_chaos - chaos) / span, 0.0, 1.0)
		OBJECTIVE_BUILD_AFFECTION:
			var span_up := maxf(_current_target - _start_affection, 0.01)
			return clampf((affection - _start_affection) / span_up, 0.0, 1.0)
		_:
			return 0.0

func check_progress(focus: float, affection: float, chaos: float) -> bool:
	## 已完成返回 true（由调用方发奖励），并自动重 roll
	if _current_key.is_empty() or not is_completed(focus, affection, chaos):
		return false
	objective_completed.emit(_current_key, _current_target)
	return true

func check_timeout(timer_left: float, focus: float, affection: float, chaos: float) -> bool:
	## 超时未完成返回 true（由调用方发惩罚），并自动重 roll
	if timer_left > 0.0 or _current_key.is_empty():
		return false
	if is_completed(focus, affection, chaos):
		return false
	objective_failed.emit(_current_key, _current_target)
	return true

func _pick_card(tier: int) -> Dictionary:
	var cards := _cards_for_tier(tier)
	if cards.is_empty():
		cards = _cards
	if not _forced_sequence.is_empty():
		var idx := _forced_cursor % _forced_sequence.size()
		_forced_cursor += 1
		var wanted := _forced_sequence[idx]
		for card in cards:
			if String(card.get("id", "")) == wanted:
				return card
	return _weighted_pick(cards)

func _cards_for_tier(tier: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in _cards:
		if tier >= int(card.get("tier_min", 1)) and tier <= int(card.get("tier_max", 3)):
			result.append(card)
	return result

func _weighted_pick(cards: Array[Dictionary]) -> Dictionary:
	if cards.is_empty():
		return {}
	var total_weight := 0.0
	for card in cards:
		total_weight += maxf(float(card.get("weight", 1.0)), 0.01)
	var roll := randf_range(0.0, total_weight)
	var cursor := 0.0
	for card in cards:
		cursor += maxf(float(card.get("weight", 1.0)), 0.01)
		if roll <= cursor:
			return card
	return cards[cards.size() - 1]

func _sample_target(objective_id: String, card: Dictionary, focus: float, affection: float, chaos: float) -> float:
	var target := randf_range(float(card.get("target_min", 0.0)), float(card.get("target_max", 100.0)))
	match objective_id:
		OBJECTIVE_KEEP_FOCUS:
			if focus >= target:
				target = minf(95.0, focus + 6.0)
		OBJECTIVE_BUILD_AFFECTION:
			if affection >= target:
				target = minf(95.0, affection + 6.0)
		OBJECTIVE_REDUCE_CHAOS:
			if chaos <= target:
				target = maxf(2.0, chaos - 1.0)
		_:
			pass
	return target
```

- [ ] **Step 4: FocusSessionMode 改为委托**

`focus_session_mode.gd`：
1. 删除 :12-14 常量 OBJECTIVE_*、:47 `_objective_cards`、:39-44 目标相关状态变量、:952-1096 的目标函数、:1591 `_build_default_objective_cards`（默认卡组搬进 ObjectiveSystem 后由测试/门面喂入，见下）
2. 头部加 `const ObjectiveSystemScript = preload("res://components/focus/objective_system.gd")`，加成员 `var _objective_system`
3. `_ready()` 中 `_objective_cards = _build_default_objective_cards()` 替换为：

```gdscript
	_objective_system = ObjectiveSystemScript.new()
	_objective_system.name = "ObjectiveSystem"
	add_child(_objective_system)
	_objective_system.objective_completed.connect(_on_objective_completed)
	_objective_system.objective_failed.connect(_on_objective_failed)
```

4. 新增默认卡组喂入（内容照抄原 :1591 的三张卡）与事件桥接：

```gdscript
func _default_objective_cards() -> Array[Dictionary]:
	return [
		{"id": "keep_focus", "target_min": 55.0, "target_max": 80.0, "weight": 1.0, "tier_min": 1, "tier_max": 3},
		{"id": "reduce_chaos", "target_min": 8.0, "target_max": 18.0, "weight": 1.0, "tier_min": 1, "tier_max": 3},
		{"id": "build_affection", "target_min": 50.0, "target_max": 70.0, "weight": 1.0, "tier_min": 1, "tier_max": 3}
	]
```

（**执行时先读原 :1591-1600 的实际数值照抄，上面是结构示例。**）

```gdscript
func _on_objective_completed(objective_id: String, _target: float) -> void:
	_apply_delta(3.0, 4.0, -4.0, "Objective completed. Bonus applied.")
	_record_event("objective_completed", {"id": objective_id})
	_roll_objective()

func _on_objective_failed(objective_id: String, _target: float) -> void:
	_apply_delta(-4.0, -3.0, 6.0, "Objective failed. Penalty applied.")
	_record_event("objective_failed", {"id": objective_id})
	_roll_objective()

func _roll_objective() -> void:
	_objective_timer = float(objective_interval_seconds)
	_objective_system.roll_new_objective(_current_objective_tier, focus_value, affection_value, chaos_value)
```

5. `_process` 内 `_check_objective_timeout()` 与 `on_*` 内 `_check_objective_progress()` 改为调用 `_objective_system.check_timeout(_objective_timer, focus_value, affection_value, chaos_value)` / `check_progress(...)`（信号触发奖励，行为等价）；demo 模式的 `_demo_objective_cursor` 强制序列改为 `_objective_system.set_forced_sequence(...)`
6. `set_objective_cards()`（:237）保留为公共 API，内部转调 `_objective_system.set_cards(...)`
7. `_update_ui` 中 `_objective_progress()` / `_objective_key` / `_objective_target` 改读 `_objective_system.get_objective_key()` / `.get_objective_target()` / `.progress(focus_value, affection_value, chaos_value)`

- [ ] **Step 5: 跑全部测试**

Run: `"$GODOT" --headless --path . res://tests/test_objective_system.tscn` → `failed: 0`
Run: `"$GODOT" --headless --path . res://tests/test_focus_session_mode.tscn` → `failed: 0`
Run: `"$GODOT" --headless --path . res://tests/test_smart_modules.tscn` → `failed: 0`
Run: `"$GODOT" --headless --path . res://tests/test_sprite_manifest_loader.tscn` → `failed: 0`

- [ ] **Step 6: Commit**

```bash
git add components/focus/objective_system.gd focus_session_mode.gd tests/test_objective_system.gd tests/test_objective_system.tscn
git commit -m "refactor: 拆出目标卡系统组件"
```

---

### Task 4: 拆出 FocusHud（HUD 视图）

抽出 HUD 构建与刷新（原 :1264-1589 的 `_build_ui` HUD 部分、`_create_metric_bar`、`_update_ui`、`_objective_title_text`、`_objective_target_text`、`_format_seconds`、`_build_help_text` 及 UI 成员变量）。HUD 只读数值与文案输入，不写业务状态。

**Files:**
- Create: `components/focus/focus_hud.gd`
- Modify: `focus_session_mode.gd`

- [ ] **Step 1: 实现 FocusHud**

`components/focus/focus_hud.gd`：

```gdscript
class_name FocusHud
extends CanvasLayer

## 专注会话 HUD：三数值条 + 时间 + 目标卡 + 提示文案。纯视图，数值由外部喂入。

var root: Control
var hud_panel: PanelContainer
var time_label: Label
var objective_label: Label
var objective_progress_label: Label
var objective_progress_bar: ProgressBar
var focus_bar: ProgressBar
var affection_bar: ProgressBar
var chaos_bar: ProgressBar
var hint_label: Label
var help_label: Label
var result_panel: PanelContainer
var result_title: Label
var result_detail: Label

func _ready() -> void:
	layer = 100
	_build()

func show_hud() -> void:
	hud_panel.visible = true
	var vp := get_viewport().get_visible_rect().size
	hud_panel.position = Vector2((vp.x - 430) * 0.5, (vp.y - 260) * 0.5)

func hide_hud() -> void:
	hud_panel.visible = false

func show_result(title: String, detail: String) -> void:
	result_title.text = title
	result_detail.text = detail
	result_panel.visible = true

func hide_result() -> void:
	result_panel.visible = false

func set_hint(text: String) -> void:
	hint_label.text = text

func update_metrics(focus: float, affection: float, chaos: float,
		remaining_seconds: int, objective_title: String,
		objective_target_text: String, objective_progress: float,
		help_text: String) -> void:
	time_label.text = "TIME  " + _format_seconds(remaining_seconds)
	objective_label.text = objective_title
	objective_progress_label.text = objective_target_text
	objective_progress_bar.value = clampf(objective_progress * 100.0, 0.0, 100.0)
	focus_bar.value = focus
	affection_bar.value = affection
	chaos_bar.value = chaos
	help_label.text = help_text

func _build() -> void:
	# ——内容：把原 focus_session_mode.gd :1264-1589 中 HUD/结果面板的构建代码
	# 原样搬入此函数，_hint_label→hint_label 等成员重命名，样式 aurora 引用保持不变——
	pass
```

（**执行时：打开原文件 :1264-1589，将 `_build_ui` 中 HUD 相关段落、`_create_metric_bar`、`_format_seconds`、`_build_help_text` 原样迁移并重命名成员；这是机械搬移，不改逻辑。**）

- [ ] **Step 2: FocusSessionMode 换用 FocusHud**

1. 删除原 UI 成员变量（:82-104 中 HUD/result 相关）与 `_build_ui` 中对应构建段
2. `_ready()` 创建 `FocusHud` 实例（成员 `var _hud: FocusHud`），删除自身的 CanvasLayer UI（**FocusSessionMode 从 CanvasLayer 降为普通 Node**，`layer = 100` 移除）
3. `start_session()` 中 HUD 显示改 `_hud.show_hud()`；`_finish_session()` 改 `_hud.hide_hud()` + `_hud.show_result(...)`；`_update_ui()` 改为调 `_hud.update_metrics(...)`；`_hint_label.text = X` 全局替换为 `_hud.set_hint(X)`
4. 保留 `get_viewport()` 等调用路径可用性检查（FocusHud 是 CanvasLayer，挂在 FocusSessionMode 下即可）

- [ ] **Step 3: 跑全部测试（同 Task 3 Step 5 四条命令）**

Expected: 全部 `failed: 0`。注意 `test_focus_session_mode` 中直接引用 `mode._hint_label.text` 的断言（:63）需改为 `mode._hud.hint_label.text`。

- [ ] **Step 4: Commit**

```bash
git add components/focus/focus_hud.gd focus_session_mode.gd tests/test_focus_session_mode.gd
git commit -m "refactor: 拆出专注会话 HUD 组件"
```

---

### Task 5: 拆出 TutorialController（教程）

抽出教程状态机（原 :77-80 状态变量、:1222-1262 全部教程函数、:1601 默认步骤）。教程只驱动 hint 文案，依赖注入 Label 写入回调即可，不依赖 HUD 内部。

**Files:**
- Create: `components/focus/tutorial_controller.gd`
- Modify: `focus_session_mode.gd`

- [ ] **Step 1: 实现 TutorialController**

`components/focus/tutorial_controller.gd`：

```gdscript
class_name FocusTutorialController
extends Node

## 专注会话新手教程：按步骤时长推进，通过 set_text 回调写文案。纯逻辑。

var active: bool = false:
	set(value):
		active = value
		if not value:
			_finished.emit()

signal _finished

var _index: int = 0
var _time_left: float = 0.0
var _steps: Array[Dictionary] = []
var _set_text: Callable = Callable()

func setup(steps: Array[Dictionary], set_text: Callable) -> void:
	_steps = steps
	_set_text = set_text

func start(enabled: bool) -> void:
	if not enabled or _steps.is_empty():
		active = false
		return
	active = true
	_index = 0
	_time_left = _current_duration()
	_set_text.call(_current_text())

func update(delta: float) -> void:
	if not active:
		return
	_time_left -= delta
	if _time_left > 0.0:
		return
	_index += 1
	if _index >= _steps.size():
		active = false
		_set_text.call("Tutorial finished. Keep the bars stable.")
		return
	_time_left = _current_duration()
	_set_text.call(_current_text())

func skip() -> void:
	active = false
	_set_text.call("Tutorial skipped.")

func _current_text() -> String:
	var step := _steps[_index]
	return "[Guide] " + String(step.get("text", ""))

func _current_duration() -> float:
	var step := _steps[_index]
	return float(step.get("duration", 4.0))
```

- [ ] **Step 2: FocusSessionMode 换用**

1. 删 :77-80 教程变量与 :1222-1262 教程函数，`_build_default_tutorial_steps`（:1601，默认步骤内容）搬入 TutorialController 作为 `default_steps()` 静态返回（**执行时照抄原数组内容**）
2. `_setup_tutorial()` 改为 `_tutorial.setup(steps, func(t: String): _hud.set_hint(t))` + `_tutorial.start(show_tutorial_on_start)`
3. `_process` 的 `_update_tutorial(delta)` 改 `_tutorial.update(delta)`；F1 分支改 `_tutorial.skip()`（`:152-154`）

- [ ] **Step 3: 跑全部测试（四条命令，同 Task 3 Step 5）**
Expected: 全部 `failed: 0`

- [ ] **Step 4: Commit**

```bash
git add components/focus/tutorial_controller.gd focus_session_mode.gd
git commit -m "refactor: 拆出专注会话教程组件"
```

---

### Task 6: 录制/回放搬至 tests/debug_tools/（隔离调试设施）

录制、回放、垃圾桶、ops 面板、demo 控制面板（原 :24-27 导出变量、:54-75 状态、:272-780 录制/文件管理函数、:1621-1887 demo UI 回调）整体搬为独立组件 `SessionRecorder`，且**默认不加载**——只在测试场景与调试入口实例化。这是设计文档"调试设施仅 debug 构建加载"的落地。

**Files:**
- Create: `tests/debug_tools/session_recorder.gd`（从 focus_session_mode.gd 原样搬移）
- Modify: `focus_session_mode.gd`、`tests/test_focus_session_mode.gd`

- [ ] **Step 1: 搬移 SessionRecorder**

把原 :272-780（start/stop/export/replay/刷新列表/删除/恢复/垃圾清理/ops 日志）与 :1621-1887（demo 控制面板构建与回调）整体剪出为 `tests/debug_tools/session_recorder.gd`：

```gdscript
class_name SessionRecorder
extends CanvasLayer

## 专注会话录制/回放/垃圾桶/ops 面板 —— 调试设施，仅测试与调试入口加载。

signal recording_script_finished(output_path: String, summary: Dictionary)
# ...原 :272-780 与 :1621-1887 的函数原样搬入，self 引用改为本类成员...
```

- [ ] **Step 2: FocusSessionMode 与测试改造**

1. `focus_session_mode.gd` 删除全部录制/回放/垃圾桶/demo 面板代码、相关导出变量与 F2/F3/F4/F6/F7/F9/F12 快捷键分支（:144-204 中对应段落）
2. 保留对 demo 事件注入的最小钩子：`set_demo_events()` / `trigger_next_demo_event()` / `start_demo()` / `pause_demo()` / `set_demo_playback_speed()`（SMART 无关但测试在用——**执行时先 grep 测试实际用到的 API 再定保留集**）
3. `tests/test_focus_session_mode.gd`：录制相关用例（:33-68）改为先 `var recorder = SessionRecorderScript.new(); add_child(recorder)`，把原 `mode.start_recording_script(...)` 等调用改到 `recorder.` 上；recorder 需要会话引用则传 `recorder.bind_session(mode)`

- [ ] **Step 3: 跑全部测试**

Expected: 四套测试全部 `failed: 0`（含改造后的 test_focus_session_mode）

- [ ] **Step 4: Commit**

```bash
git add tests/debug_tools/session_recorder.gd focus_session_mode.gd tests/test_focus_session_mode.gd
git commit -m "refactor: 录制回放调试设施隔离至 debug_tools"
```

---

### Task 7: 心理统一——专注会话数值代理到 CatBehaviorSystem

核心任务。FocusSessionMode 删除自有三数值，全部读写 `cat.behavior_system`。**行为外观不变**：数值含义、增减时机、判定阈值原样保留，只是存储位置变了。chaos 直接映射；focus 映射为会话期临时值（会话结束不写回行为系统——focus 是"你这局的表现分"，不是猫的长期心理）；affection 双向同步。

**Files:**
- Modify: `focus_session_mode.gd`、`main.gd`、`cat.gd`、`cat_behavior_system.gd`
- Test: `tests/test_focus_session_mode.gd`、`tests/test_behavior_system.gd`

- [ ] **Step 1: 写失败测试（数值代理）**

`tests/test_focus_session_mode.gd` `_run()` 中 `mode.start_session()` 断言块后加：

```gdscript
	# 心理统一：会话开始时 affection 从行为系统同步，结束后写回
	var behavior = mode.behavior_proxy
	_assert_true(behavior != null, "behavior_proxy_bound")
	behavior.affection = 60.0
	mode.start_session()
	_assert_true(is_equal_approx(float(mode.affection_value), 60.0), "affection_synced_from_behavior")
	mode.on_item_used("food")  # +8 affection
	_assert_true(float(mode.affection_value) > 60.0, "affection_delta_writes_through")
```

- [ ] **Step 2: 确认失败**

Run: `"$GODOT" --headless --path . res://tests/test_focus_session_mode.tscn`
Expected: FAIL——`behavior_proxy` 不存在

- [ ] **Step 3: 实现代理**

`focus_session_mode.gd`：
1. 删 `var focus_value/affection_value/chaos_value`（:30-32）与 `focus_start/affection_start/chaos_start`（:17-19）
2. 加：

```gdscript
var behavior_proxy  # CatBehaviorSystem 引用，由 bind_behavior() 注入
var focus_value: float = 0.0  # 会话表现分，不写回行为系统

func bind_behavior(behavior) -> void:
	behavior_proxy = behavior

var affection_value: float:
	get:
		return behavior_proxy.affection if behavior_proxy else 0.0
	set(value):
		if behavior_proxy:
			behavior_proxy.modify_chaos(0.0)  # 触发信号链保持一致
			behavior_proxy.affection = clampf(value, 0.0, 100.0)

var chaos_value: float:
	get:
		return behavior_proxy.chaos if behavior_proxy else 0.0
	set(value):
		if behavior_proxy:
			behavior_proxy.chaos = clampf(value, 0.0, 100.0)
```

3. `start_session()` 中 `focus_value = focus_start` 等三行改为 `focus_value = 85.0`（常量 FOCUS_START）+ affection/chaos 保持现值（不再重置——**这是行为变更的唯一例外，执行时在 PR 描述中标注**）
4. `main.gd` `_setup_focus_session_mode()`（:272）加 `focus_session_mode.bind_behavior(cat.behavior_system)`
5. `cat.gd` `_init_behavior_system()`（:72-78）后确保 `behavior_system.chaos = 20.0` 初始值（Task 2 默认值已覆盖，验证即可）

- [ ] **Step 4: 跑测试通过 + 全量回归**

Run: 四套测试全部 `failed: 0`

- [ ] **Step 5: Commit**

```bash
git add focus_session_mode.gd main.gd cat.gd tests/test_focus_session_mode.gd
git commit -m "refactor: 专注会话心理数值统一到行为系统"
```

---

### Task 8: main.gd 瘦身第一刀——托盘 + 鼠标穿透拆出

main.gd 962 行按职责切两刀。第一刀：系统托盘（:691-785，~95 行）与鼠标穿透（:831-902，~72 行）。

**Files:**
- Create: `components/desktop/tray_controller.gd`
- Create: `components/desktop/passthrough_manager.gd`
- Modify: `main.gd`

- [ ] **Step 1: 实现 TrayController**

`components/desktop/tray_controller.gd`——把 :691-785 的 `_setup_tray/_build_tray_menu/_on_tray_pressed/_show_tray_menu/_on_tray_toggle_visibility/_on_tray_open_settings/_on_tray_exit/_toggle_pet_visibility/_set_pet_visible/_is_pet_visible/_update_tray_menu_label/_cleanup_tray` 原样搬入，接口：

```gdscript
class_name TrayController
extends Node

signal toggle_visibility_requested
signal open_settings_requested
signal exit_requested

var _indicator: StatusIndicator
var _menu: RID = RID()
var _menu_show_index := -1
var _last_click_time := 0
const DOUBLE_CLICK_MS := 400
const ICON_PATH := "res://icon.svg"

func setup(main_node: Node2D) -> void: ...
func update_menu_label(visible: bool) -> void: ...
func cleanup() -> void: ...
# 其余私有函数原样迁移；对外回调改为 emit 上列信号
```

- [ ] **Step 2: 实现 PassthroughManager**

`components/desktop/passthrough_manager.gd`——把 :831-902 的 `_update_mouse_passthrough_region/_build_mouse_capture_polygon/_should_capture_full_window/_build_full_window_polygon/_build_cat_hit_polygon/_build_circle_polygon` 原样搬入：

```gdscript
class_name PassthroughManager
extends Node

const CAT_HIT_RADIUS_MIN := 56.0
const CAT_HIT_RADIUS_MAX := 240.0

var _cache_hash: int = 0

func update(main_node: Node2D) -> void: ...
# 依赖注入：main_node 提供 settings_panel/popup_menu/hover_panel_visible/quick_action_menu/cat/_cached_screen_size
```

（**执行时按 main.gd 原实现把对 main 成员的引用改为经 main_node 读取，函数体逻辑不变。**）

- [ ] **Step 3: main.gd 接线**

1. 删除 :691-785 与 :831-902 及相关成员（:16-21、:40、:52-54）
2. `_ready()` 创建两组件实例；原 `_update_mouse_passthrough_region()` 调用点（:107/:166/:176/:500 等）改 `passthrough_manager.update(self)`
3. 托盘回调接信号：`toggle_visibility_requested.connect(...)` 等三行

- [ ] **Step 4: 跑全部测试 + MCP 冒烟**

四套测试 `failed: 0`；MCP run_project 启动无脚本错误、托盘可右键（get_debug_output 无 ERROR）

- [ ] **Step 5: Commit**

```bash
git add components/desktop/tray_controller.gd components/desktop/passthrough_manager.gd main.gd
git commit -m "refactor: 托盘与鼠标穿透拆出独立组件"
```

---

### Task 9: main.gd 瘦身第二刀——SMART 气泡 + 悬浮面板拆出

第二刀：SMART 台词气泡（:581-689，~108 行）与右缘悬浮面板（:391-500，~110 行）。

**Files:**
- Create: `components/ui/smart_line_bubble.gd`
- Create: `components/ui/hover_panel.gd`
- Modify: `main.gd`

- [ ] **Step 1: 实现 SmartLineBubble**

把 :581-689（`_setup_smart_line_bubble/_show_smart_line/_hide_smart_line/_get_smart_line_position` 与 SMART_LINE_BUBBLE_* 常量）搬为：

```gdscript
class_name SmartLineBubble
extends CanvasLayer

const BUBBLE_WIDTH := 320.0
const BUBBLE_HEIGHT := 88.0

func show_line(line: String) -> void: ...
func hide() -> void: ...
func reposition(anchor: Vector2, viewport_size: Vector2) -> void: ...
```

- [ ] **Step 2: 实现 HoverPanel**

把 :391-500（`_create_hover_panel/_update_hover_panel/_on_items_btn_pressed` 面板构建与滑动逻辑、EDGE_TRIGGER_DISTANCE/PANEL_SLIDE_SPEED 常量）搬为：

```gdscript
class_name DesktopHoverPanel
extends Node2D

signal items_requested
signal settings_requested

const EDGE_TRIGGER_DISTANCE := 20.0
const PANEL_SLIDE_SPEED := 800.0

func setup(screen_size: Vector2) -> void: ...
func update(delta: float, mouse_pos: Vector2, screen_size: Vector2) -> bool: ...
# 返回 hover_panel_visible 状态；按钮点击 emit 信号
```

- [ ] **Step 3: main.gd 接线**

删除对应段落与成员（:36-39、:42-47、:50-51），`_process` 中面板滑动与气泡定时改为组件调用；`_show_smart_line/_hide_smart_line` 调用点改 `smart_line_bubble.show_line(...)`。

- [ ] **Step 4: 跑全部测试 + MCP 冒烟（同 Task 8 Step 4）**

- [ ] **Step 5: Commit**

```bash
git add components/ui/smart_line_bubble.gd components/ui/hover_panel.gd main.gd
git commit -m "refactor: SMART 气泡与悬浮面板拆出独立组件"
```

---

### Task 10: 全量回归 + MCP 端到端 + 收尾

- [ ] **Step 1: 全量测试**

四套 headless 测试 + `tests/test_behavior_system.tscn` 全绿。

- [ ] **Step 2: 代码规模验收**

Run: `wc -l focus_session_mode.gd main.gd components/focus/*.gd components/desktop/*.gd components/ui/*.gd tests/debug_tools/*.gd`
Expected: focus_session_mode.gd ≤ 700 行；main.gd ≤ 500 行；每个新组件 ≤ 300 行（符合全局规范）

- [ ] **Step 3: MCP 端到端验证**

1. `run_project` 启动，等待 90 秒
2. `get_debug_output`：无 ERROR、无 `Focus session finished`、SMART 策略正常输出
3. 橙色像素截图验证猫正常渲染（复用本轮验证过的 PowerShell 截图 + Python 橙色聚类流程，脚本临时创建用完即删）

- [ ] **Step 4: 收尾提交与文档更新**

```bash
git add -A
git commit -m "refactor: P1 架构地基完成"
```

设计文档 `docs/plans/2026-08-17-smart-companion-redesign.md` 追加"P1 完成记录"小节：实际拆分结果、行数对比、行为变更例外清单（Task 7 的 affection 不重置）。

---

## 自检记录（Self-Review）

1. **Spec 覆盖**：心理统一（Task 2+7）、focus_session_mode 拆分（Task 3-6）、main.gd 瘦身（Task 8-9）、测试回归与 MCP 验证（Task 1+10）——P1 范围全覆盖；感知/会话重塑/记忆属于 P2-P4，不在本计划。
2. **占位符**：Task 3 Step 3 的默认卡组数值、Task 4 的 `_build()` 内容、Task 6 的搬移范围标注了"执行时照抄原文"——这些是原样搬移指令而非未设计内容，具体数值以原文件为准。
3. **类型一致性**：`FocusObjectiveSystem.set_cards/roll_new_objective/is_completed/progress` 在 Task 3 定义、Task 3 Step 4 委托处使用一致；`behavior_proxy/affection_value/chaos_value` getter/setter 命名与测试断言一致。
