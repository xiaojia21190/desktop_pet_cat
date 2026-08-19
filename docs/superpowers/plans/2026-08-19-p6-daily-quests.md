# P6 每日任务/隐式签到 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 猫用 4 个全自动好习惯任务（专注会话/久坐起身/饭点响应/摸摸猫）+ 开机隐式签到陪伴用户建立健康节奏，奖励喂进亲密度（bond），零打卡零弹窗。

**Architecture:** 新建纯逻辑服务 `DailyQuestService`（components/engagement/），从 `context_collector.record_event` 新增的 `event_recorded` 信号订阅全部事件（覆盖 main 与 smart_pet_controller 两个来源），提醒→响应类任务开时间窗由 main 每分钟轮询快照判定闲置；完成经信号到 main 播气泡 + `bond_system.add_bond` 发奖；存档走 save_manager 新 `daily_quests` 区块四点贯通；设置面板加「今日任务」区块（轮询渲染，与亲密度进度条同模式）。

**Tech Stack:** Godot 4.7 / GDScript；测试 headless tscn 断言式；端到端 Godot MCP。

**设计文档:** `docs/superpowers/specs/2026-08-19-p6-daily-quests-design.md`

---

## 执行前置

- `"$GODOT"` = `/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- 单套测试：`timeout 60 "$GODOT" --headless --path . res://tests/<name>.tscn`，期望末尾 `failed: 0`
- 既有 11 套测试全名：`test_behavior_system` `test_focus_session_mode` `test_sprite_manifest_loader` `test_objective_system` `test_activity_classifier` `test_foreground_app_monitor` `test_focus_charge_engine` `test_smart_modules` `test_bond_system` `test_presence_level` `test_first_guide`
- 本计划新增第 12 套 `test_daily_quests`（Task 1 创建）
- 存档四点贯通（P2 教训）：新键必须同时补 `_get_default_data` + `load_data` + `_write_config` + `_gather_current_data`
- **关键事实（设计自审已核实，写码前不要再猜）**：
  - `focus_session_mode._record_event`（focus_session_mode.gd:509）仅录制模式生效——**不要**用它作为任务判定源；专注任务判定用 `focus_milestone` 事件（main.gd:586 victory 分支发出）
  - `smart_decision` 事件在 smart_pet_controller.gd:199 `_rule_track_fire` 内经 `record_event` 直达 collector，**不经过** main 的 `_record_smart_event`——所以挂接点必须在 `context_collector.record_event`
  - long_focus / meal_hint 提醒的 intent 字符串在 smart_decision 事件的 `intent` payload 键里（smart_pet_controller.gd:199 `{"action_id": ..., "intent": String(decision.get("policy_intent", ""))}`）
  - main.gd `_process`（235 行起）已有 `_check_invite_ignored(delta)` 分钟级聚合计时器模式可照抄
  - 面板任务区块照抄 `settings_panel.gd:194-233` 亲密度进度区模式（`_ensure_bond_ui` / `refresh_bond_ui`，代码构建 + visible 才刷）

## 文件结构总览

- Task 1 — context_collector `event_recorded` 信号 + 测试文件骨架（签到用例先行）
- Task 2 — DailyQuestService 核心：签到结算（streak/奖励）
- Task 3 — 任务判定：事件直达类（focus_session/interact_once）
- Task 4 — 任务判定：提醒→响应窗口类（stand_up/meal_on_time）
- Task 5 — 存档 roundtrip + 跨天刷新 + 异常兜底
- Task 6 — save_manager 四点贯通（daily_quests 区块）
- Task 7 — main.gd 挂载接线（事件订阅/轮询/气泡/发奖）
- Task 8 — bond_system 新增益类型 + 面板「今日任务」区块
- Task 9 — 全量回归 + MCP 端到端验收 + 文档收尾

---

### Task 1: event_recorded 信号 + 测试骨架（签到失败用例）

**Files:**
- Modify: `context_collector.gd`（signal 声明 + record_event 尾部 emit）
- Create: `tests/test_daily_quests.gd`
- Create: `tests/test_daily_quests.tscn`

- [ ] **Step 1: 写测试骨架与首批失败用例 tests/test_daily_quests.gd**

```gdscript
extends Node

## P6 每日任务/隐式签到测试

const CollectorScript = preload("res://context_collector.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_event_recorded_signal()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_event_recorded_signal() -> void:
	# record_event 尾部应发 event_recorded(type, payload) 信号（P6 任务系统数据源）
	var collector = CollectorScript.new()
	add_child(collector)
	var received: Array = []
	collector.event_recorded.connect(func(event_type, payload): received.append([event_type, payload]))
	collector.record_event("item_used", {"item_type": "food"})
	_assert_true(received.size() == 1, "signal_fired_once")
	_assert_equal(String(received[0][0]), "item_used", "signal_carries_type")
	_assert_equal(String(received[0][1].get("item_type", "")), "food", "signal_carries_payload")
	# payload 带 type/t 元数据键（collector 记录格式），不破坏既有消费方
	_assert_true(received[0][1].has("t"), "payload_has_timestamp")
	collector.queue_free()

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
	print("========== daily_quests tests ==========")
	print("passed: %d" % _passed)
	print("failed: %d" % _failed)
	for f in _failures:
		print("  FAIL: " + f)
```

- [ ] **Step 2: 创建 tests/test_daily_quests.tscn**

```text
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/test_daily_quests.gd" id="1"]

[node name="DailyQuestsTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 3: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（`event_recorded` 信号不存在，脚本解析错误或 signal_fired_once FAIL）

- [ ] **Step 4: context_collector.gd 加信号**

`class_name ContextCollector` 声明区（`extends Node` 下、`const MAX_EVENT_HISTORY` 上）加：

```gdscript
signal event_recorded(event_type: String, payload: Dictionary)
```

`record_event`（context_collector.gd:57）尾部 `_events.pop_front()` 之后加：

```gdscript
	event_recorded.emit(event_type, event_payload)
```

- [ ] **Step 5: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 4  failed: 0`

- [ ] **Step 6: 回归 collector 消费方（smart_modules）**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_smart_modules.tscn`
Expected: `failed: 0`（新信号零影响）

- [ ] **Step 7: Commit**

```bash
git add context_collector.gd tests/test_daily_quests.gd tests/test_daily_quests.tscn tests/test_daily_quests.gd.uid 2>/dev/null || git add context_collector.gd tests/test_daily_quests.gd tests/test_daily_quests.tscn
git commit -m "feat: 事件流信号event_recorded与任务测试骨架"
```

---

### Task 2: DailyQuestService 签到结算

**Files:**
- Create: `components/engagement/daily_quest_service.gd`
- Modify: `tests/test_daily_quests.gd`

- [ ] **Step 1: 追加签到失败用例（_run 中 `_test_event_recorded_signal()` 后追加调用）**

```gdscript
const QuestServiceScript = preload("res://components/engagement/daily_quest_service.gd")

func _test_checkin() -> void:
	# 隐式签到：load_from_save 触发结算——首日 streak=1；连续 +1；断签归 1；同日不重复计
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	_assert_equal(svc.streak_days, 1, "first_day_streak_1")
	_assert_equal(svc.today_checked_in, true, "checked_in_today")
	# 同日重复 load 不重复计
	var saved: Dictionary = svc.get_save_data()
	svc.load_from_save(saved)
	_assert_equal(svc.streak_days, 1, "same_day_no_double")
	# 连续：昨日 last_checkin → +1
	var yesterday_key: String = svc._shift_date_key(-1)
	svc.load_from_save({"streak_days": 3, "last_checkin_key": yesterday_key, "today_key": yesterday_key})
	_assert_equal(svc.streak_days, 4, "consecutive_plus_one")
	# 断签（5 天前）→ 归 1
	svc.load_from_save({"streak_days": 7, "last_checkin_key": svc._shift_date_key(-5), "today_key": svc._shift_date_key(-5)})
	_assert_equal(svc.streak_days, 1, "broken_streak_resets")
	# 奖励公式 min(10 + streak*2, 30)：streak=1 → 12；streak=15 → 30 封顶
	_assert_equal(svc._checkin_reward(1), 12, "reward_day1")
	_assert_equal(svc._checkin_reward(15), 30, "reward_capped")
	svc.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（daily_quest_service.gd 不存在）

- [ ] **Step 3: 实现 components/engagement/daily_quest_service.gd**

```gdscript
class_name DailyQuestService
extends Node

## P6 每日任务/隐式签到：全自动好习惯任务 + 开机签到
## 数据源：context_collector.event_recorded 信号 + main 分钟级快照轮询
## 原则：不催不领不挽损——完成才庆贺，次日自动刷新

signal quest_completed(quest_id: String, reward_bond: float)
signal checkin_done(streak_days: int, reward_bond: float)

## 签到奖励：min(10 + streak × 2, 30)
const CHECKIN_BASE := 10.0
const CHECKIN_STEP := 2.0
const CHECKIN_CAP := 30.0

var streak_days: int = 0
var today_checked_in: bool = false
var _today_key := ""
var _last_checkin_key := ""
var _completed: Dictionary = {}   # quest_id -> true（当日已完成）

## 注意：_ready 不签到——签到结算只在 load_from_save 驱动。
## 若 _ready 先 roll，挂载即用空状态签到（streak=1、today_key=今天），
## 随后 load_from_save 的跨天分支会因"今日已签"直接 return，吞掉昨日档的 streak+1。

func load_from_save(data: Dictionary) -> void:
	## 读档注入 + 签到结算（每日首次启动即签到）
	_last_checkin_key = String(data.get("last_checkin_key", ""))
	var saved_streak := int(data.get("streak_days", 0))
	var saved_today := String(data.get("today_key", ""))
	var saved_completed: Array = data.get("completed", [])
	for q in saved_completed:
		_completed[String(q)] = true
	if saved_today == _date_key():
		# 同日重启：恢复状态不重复签到
		streak_days = saved_streak
		today_checked_in = true
		_today_key = saved_today
		return
	_roll_day()

func _roll_day() -> void:
	## 跨天/首启：刷新任务 + 结算签到
	var key := _date_key()
	if key == _today_key and today_checked_in:
		return
	_today_key = key
	_completed = {}
	today_checked_in = true
	if _last_checkin_key == _shift_date_key(-1):
		streak_days += 1
	else:
		streak_days = 1
	_last_checkin_key = key
	checkin_done.emit(streak_days, _checkin_reward(streak_days))

func _checkin_reward(streak: int) -> float:
	return minf(CHECKIN_BASE + float(streak) * CHECKIN_STEP, CHECKIN_CAP)

func is_completed(quest_id: String) -> bool:
	return bool(_completed.get(quest_id, false))

func _complete(quest_id: String, reward: float) -> void:
	## 任务完成唯一入口：拦截重复、发信号（bond 发放在 main 侧）
	if _completed.has(quest_id):
		return
	_completed[quest_id] = true
	quest_completed.emit(quest_id, reward)

func get_save_data() -> Dictionary:
	var completed: Array = []
	for q in _completed.keys():
		completed.append(q)
	return {
		"today_key": _today_key,
		"completed": completed,
		"streak_days": streak_days,
		"last_checkin_key": _last_checkin_key,
	}

func _date_key() -> String:
	var d := Time.get_date_dict_from_system()
	return "%04d%02d%02d" % [d["year"], d["month"], d["day"]]

func _shift_date_key(days: int) -> String:
	## 相对今天的日期键（测试与断签判定用；用 unix 秒偏移避免日历库）
	var offset_unix: int = int(Time.get_unix_time_from_system()) + days * 86400
	var d := Time.get_datetime_dict_from_unix_time(offset_unix)
	return "%04d%02d%02d" % [d["year"], d["month"], d["day"]]
```

- [ ] **Step 4: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 13  failed: 0`（4 + 9）

- [ ] **Step 5: Commit**

```bash
git add components/engagement/daily_quest_service.gd tests/test_daily_quests.gd
git commit -m "feat: 每日任务服务与隐式签到结算"
```

---

### Task 3: 事件直达任务判定（focus_session / interact_once）

**Files:**
- Modify: `components/engagement/daily_quest_service.gd`
- Modify: `tests/test_daily_quests.gd`

- [ ] **Step 1: 追加失败用例（_run 追加 `_test_event_quests()`）**

```gdscript
func _test_event_quests() -> void:
	# focus_session：focus_milestone 事件完成；focus_failed 不完成
	var svc = QuestServiceScript.new()
	add_child(svc)
	var fired: Array = []
	svc.quest_completed.connect(func(qid, reward): fired.append([qid, reward]))
	svc.notify_event("focus_milestone", {})
	_assert_true(svc.is_completed("focus_session"), "focus_milestone_completes")
	_assert_equal(fired.size(), 1, "focus_fires_once")
	_assert_true(is_equal_approx(float(fired[0][1]), 15.0), "focus_reward_15")
	# 重复事件不重复发
	svc.notify_event("focus_milestone", {})
	_assert_equal(fired.size(), 1, "no_double_fire")
	svc.queue_free()

	var svc2 = QuestServiceScript.new()
	add_child(svc2)
	svc2.notify_event("focus_failed", {})
	_assert_true(not svc2.is_completed("focus_session"), "failure_no_complete")
	svc2.queue_free()

	# interact_once：item_used / petting_started / cat_clicked 任一完成
	var svc3 = QuestServiceScript.new()
	add_child(svc3)
	var fired3: Array = []
	svc3.quest_completed.connect(func(qid, reward): fired3.append([qid, reward]))
	svc3.notify_event("item_used", {"item_type": "food"})
	_assert_true(svc3.is_completed("interact_once"), "item_used_completes")
	_assert_true(is_equal_approx(float(fired3[0][1]), 8.0), "interact_reward_8")
	svc3.queue_free()

	var svc4 = QuestServiceScript.new()
	add_child(svc4)
	svc4.notify_event("petting_started", {})
	_assert_true(svc4.is_completed("interact_once"), "petting_completes")
	svc4.queue_free()

	var svc5 = QuestServiceScript.new()
	add_child(svc5)
	svc5.notify_event("cat_clicked", {})
	_assert_true(svc5.is_completed("interact_once"), "click_completes")
	svc5.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（notify_event 不存在）

- [ ] **Step 3: 实现 notify_event 与任务定义表**

daily_quest_service.gd 在 `const CHECKIN_CAP` 后加任务定义与事件映射：

```gdscript
## 任务定义：id → {title, reward}；判定逻辑在 notify_event/poll_snapshot 内联
const QUEST_DEFS := {
	"focus_session": {"title": "专注一刻", "reward": 15.0},
	"stand_up": {"title": "起来动动", "reward": 10.0},
	"meal_on_time": {"title": "按时吃饭", "reward": 10.0},
	"interact_once": {"title": "摸摸我吧", "reward": 8.0},
}

## 互动类事件 → interact_once
const INTERACT_EVENTS := ["item_used", "petting_started", "cat_clicked"]

func notify_event(event_type: String, payload: Dictionary = {}) -> void:
	## 事件驱动判定（main 连接 context_collector.event_recorded 后自动喂入）
	if is_completed("focus_session") and is_completed("interact_once"):
		return
	if event_type == "focus_milestone":
		_complete("focus_session", float(QUEST_DEFS["focus_session"]["reward"]))
	elif event_type in INTERACT_EVENTS:
		_complete("interact_once", float(QUEST_DEFS["interact_once"]["reward"]))
```

- [ ] **Step 4: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 23  failed: 0`（13 + 10）

- [ ] **Step 5: Commit**

```bash
git add components/engagement/daily_quest_service.gd tests/test_daily_quests.gd
git commit -m "feat: 专注与互动任务事件判定"
```

---

### Task 4: 提醒→响应窗口任务（stand_up / meal_on_time）

**Files:**
- Modify: `components/engagement/daily_quest_service.gd`
- Modify: `tests/test_daily_quests.gd`

- [ ] **Step 1: 追加失败用例（_run 追加 `_test_window_quests()`）**

```gdscript
func _test_window_quests() -> void:
	# stand_up：long_focus 提醒开 5 分钟窗，窗口内 idle>=120s 完成
	var svc = QuestServiceScript.new()
	add_child(svc)
	var fired: Array = []
	svc.quest_completed.connect(func(qid, reward): fired.append([qid, reward]))
	# 提醒事件（smart_decision 带 intent）
	svc.notify_event("smart_decision", {"intent": "long_focus"})
	# 窗口内轮询：闲置 2 分钟达标
	svc.poll_snapshot({"idle_seconds": 130.0})
	_assert_true(svc.is_completed("stand_up"), "standup_after_reminder")
	_assert_true(is_equal_approx(float(fired[0][1]), 10.0), "standup_reward_10")
	svc.queue_free()

	# 窗口过期：提醒后超过 5 分钟才闲置 → 不完成
	var svc2 = QuestServiceScript.new()
	add_child(svc2)
	svc2.notify_event("smart_decision", {"intent": "long_focus"})
	svc2._window_deadline["stand_up"] = int(Time.get_unix_time_from_system()) - 1
	svc2.poll_snapshot({"idle_seconds": 300.0})
	_assert_true(not svc2.is_completed("stand_up"), "expired_window_no_complete")
	svc2.queue_free()

	# 无提醒直接闲置 → 不完成（防白拿）
	var svc3 = QuestServiceScript.new()
	add_child(svc3)
	svc3.poll_snapshot({"idle_seconds": 600.0})
	_assert_true(not svc3.is_completed("stand_up"), "no_reminder_no_complete")
	svc3.queue_free()

	# meal_on_time：meal_hint 提醒开 30 分钟窗，窗口内 idle>=300s 完成
	var svc4 = QuestServiceScript.new()
	add_child(svc4)
	svc4.notify_event("smart_decision", {"intent": "meal_hint"})
	svc4.poll_snapshot({"idle_seconds": 320.0})
	_assert_true(svc4.is_completed("meal_on_time"), "meal_after_reminder")
	# 窗口内但闲置不够 → 不完成
	var svc5 = QuestServiceScript.new()
	add_child(svc5)
	svc5.notify_event("smart_decision", {"intent": "meal_hint"})
	svc5.poll_snapshot({"idle_seconds": 60.0})
	_assert_true(not svc5.is_completed("meal_on_time"), "insufficient_idle_no_complete")
	svc5.queue_free()
	svc4.queue_free()

	# 其他 intent 不开窗
	var svc6 = QuestServiceScript.new()
	add_child(svc6)
	svc6.notify_event("smart_decision", {"intent": "weather_smalltalk"})
	svc6.poll_snapshot({"idle_seconds": 600.0})
	_assert_true(not svc6.is_completed("stand_up"), "other_intent_no_window")
	svc6.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（poll_snapshot / _window_deadline 不存在）

- [ ] **Step 3: 实现窗口机制**

daily_quest_service.gd 加成员与两个方法（notify_event 的 smart_decision 分支 + poll_snapshot）：

```gdscript
## 提醒→响应窗口：intent → [任务id, 窗口秒, 需闲置秒]
const WINDOW_QUESTS := {
	"long_focus": {"quest": "stand_up", "window": 300.0, "need_idle": 120.0},
	"meal_hint": {"quest": "meal_on_time", "window": 1800.0, "need_idle": 300.0},
}
var _window_deadline: Dictionary = {}  # quest_id -> unix 截止时间
```

notify_event 顶部早退条件改为四任务全完成，并追加 smart_decision 分支：

```gdscript
func notify_event(event_type: String, payload: Dictionary = {}) -> void:
	var all_done := true
	for qid in QUEST_DEFS:
		if not is_completed(qid):
			all_done = false
			break
	if all_done:
		return
	if event_type == "smart_decision":
		var intent := String(payload.get("intent", ""))
		if WINDOW_QUESTS.has(intent):
			var quest_id: String = WINDOW_QUESTS[intent]["quest"]
			if not is_completed(quest_id):
				_window_deadline[quest_id] = int(Time.get_unix_time_from_system() + float(WINDOW_QUESTS[intent]["window"]))
		return
	if event_type == "focus_milestone":
		_complete("focus_session", float(QUEST_DEFS["focus_session"]["reward"]))
	elif event_type in INTERACT_EVENTS:
		_complete("interact_once", float(QUEST_DEFS["interact_once"]["reward"]))

func poll_snapshot(snapshot: Dictionary) -> void:
	## main 每分钟调用：窗口内闲置达标即完成；过期静默清除
	if _window_deadline.is_empty():
		return
	var now := int(Time.get_unix_time_from_system())
	var idle := float(snapshot.get("idle_seconds", 0.0))
	var expired_or_done: Array = []
	for quest_id in _window_deadline.keys():
		if is_completed(String(quest_id)) or now > int(_window_deadline[quest_id]):
			expired_or_done.append(quest_id)
			continue
		var need := 0.0
		for intent in WINDOW_QUESTS:
			if String(WINDOW_QUESTS[intent]["quest"]) == String(quest_id):
				need = float(WINDOW_QUESTS[intent]["need_idle"])
		if idle >= need:
			expired_or_done.append(quest_id)
			_complete(String(quest_id), float(QUEST_DEFS[quest_id]["reward"]))
	for quest_id in expired_or_done:
		_window_deadline.erase(quest_id)
```

- [ ] **Step 4: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 31  failed: 0`（23 + 8）

- [ ] **Step 5: Commit**

```bash
git add components/engagement/daily_quest_service.gd tests/test_daily_quests.gd
git commit -m "feat: 久坐与饭点提醒响应窗口任务"
```

---

### Task 5: 存档 roundtrip + 跨天刷新 + 异常兜底

**Files:**
- Modify: `components/engagement/daily_quest_service.gd`
- Modify: `tests/test_daily_quests.gd`

- [ ] **Step 1: 追加失败用例（_run 追加 `_test_save_and_roll()` 与 `_test_summary()`）**

```gdscript
func _test_save_and_roll() -> void:
	# roundtrip：completed 状态与 streak 恢复
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	svc.notify_event("item_used", {})
	var saved: Dictionary = svc.get_save_data()
	var svc2 = QuestServiceScript.new()
	add_child(svc2)
	svc2.load_from_save(saved)
	_assert_true(svc2.is_completed("interact_once"), "roundtrip_completed")
	_assert_equal(svc2.streak_days, svc.streak_days, "roundtrip_streak")

	# 跨天：伪造昨日档 → load 后任务清空重新计数
	var stale: Dictionary = saved.duplicate(true)
	stale["today_key"] = svc._shift_date_key(-1)
	stale["last_checkin_key"] = svc._shift_date_key(-1)
	var svc3 = QuestServiceScript.new()
	add_child(svc3)
	svc3.load_from_save(stale)
	_assert_true(not svc3.is_completed("interact_once"), "cross_day_resets_quests")
	_assert_equal(svc3.streak_days, svc.streak_days + 1, "cross_day_streak_plus")

	# 异常兜底：空档/缺字段不崩
	var svc4 = QuestServiceScript.new()
	add_child(svc4)
	svc4.load_from_save({"streak_days": "abc", "completed": "not_array"})
	_assert_equal(svc4.streak_days, 1, "garbage_fallback_streak1")
	svc.queue_free()
	svc2.queue_free()
	svc3.queue_free()
	svc4.queue_free()

func _test_summary() -> void:
	# 面板数据：get_today_summary 返回任务列表与签到天数
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	svc.notify_event("item_used", {})
	var summary: Dictionary = svc.get_today_summary()
	var quests: Array = summary.get("quests", [])
	_assert_equal(quests.size(), 4, "summary_has_4_quests")
	var interact: Dictionary = {}
	for q in quests:
		if String(q.get("id", "")) == "interact_once":
			interact = q
	_assert_equal(bool(interact.get("completed", false)), true, "summary_marks_completed")
	_assert_equal(String(interact.get("title", "")), "摸摸我吧", "summary_carries_title")
	_assert_true(int(summary.get("streak_days", 0)) >= 1, "summary_has_streak")
	svc.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（get_today_summary 不存在；garbage_fallback 断言失败——streak_days 非法字符串 `int("abc")` 转换不报错得 0 走归 1 分支，但 completed 非 Array 时 for 循环可能崩）

- [ ] **Step 3: 加 get_today_summary 并加固 load_from_save**

daily_quest_service.gd 加：

```gdscript
func get_today_summary() -> Dictionary:
	## 面板渲染数据：任务列表（按定义顺序）+ 签到天数
	var quests: Array = []
	for qid in QUEST_DEFS:
		quests.append({
			"id": qid,
			"title": String(QUEST_DEFS[qid]["title"]),
			"completed": is_completed(qid),
		})
	return {"quests": quests, "streak_days": streak_days}
```

load_from_save 开头加固（`_last_checkin_key` 赋值后）：

```gdscript
	var saved_completed_raw = data.get("completed", [])
	if typeof(saved_completed_raw) == TYPE_ARRAY:
		for q in saved_completed_raw:
			_completed[String(q)] = true
```

（同时删除原来未经类型检查的 `for q in saved_completed: _completed[String(q)] = true` 两行。）

- [ ] **Step 4: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 41  failed: 0`（31 + 10）

- [ ] **Step 5: Commit**

```bash
git add components/engagement/daily_quest_service.gd tests/test_daily_quests.gd
git commit -m "feat: 任务存档往返跨天刷新与面板摘要"
```

---

### Task 6: save_manager 四点贯通（daily_quests 区块）

**Files:**
- Modify: `save_manager.gd`
- Modify: `tests/test_daily_quests.gd`

- [ ] **Step 1: 追加失败用例（_run 追加 `_test_save_manager_section()`）**

```gdscript
func _test_save_manager_section() -> void:
	# daily_quests 区块默认值 + 写档（写真实 user:// 路径——测试环境 SAVE_PATH 可写；跑完不清理，save_data.cfg 是测试环境产物）
	var sm = preload("res://save_manager.gd").new()
	add_child(sm)
	var defaults: Dictionary = sm._get_default_data()
	var dq: Dictionary = defaults.get("daily_quests", {})
	_assert_equal(int(dq.get("streak_days", -1)), 0, "default_streak_0")
	_assert_equal(String(dq.get("today_key", "x")), "", "default_today_empty")
	# _write_config 真实落盘（验证 ConfigFile 序列化 Array 不崩）
	var data := defaults.duplicate(true)
	data["daily_quests"] = {"today_key": "20260819", "completed": ["interact_once"], "streak_days": 3, "last_checkin_key": "20260819"}
	var err: int = sm._write_config(data)
	_assert_equal(err, 0, "write_config_ok")
	sm.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（default_streak_0 断言失败——daily_quests 区块不存在）

- [ ] **Step 3: save_manager.gd 四点实现**

1. `_get_default_data`（save_manager.gd:14）`"behavior": {}` 行后加：

```gdscript
		,
		"daily_quests": {
			"today_key": "",
			"completed": [],
			"streak_days": 0,
			"last_checkin_key": ""
		}
```

（注意 Godot 字典字面量尾逗号规则：写成 `"behavior": {},` 后接新键。）

2. `_write_config`（save_manager.gd:62）`config.set_value("settings", "first_interaction_done", ...)` 行后加：

```gdscript
	var dq = data.get("daily_quests", {})
	config.set_value("daily_quests", "today_key", String(dq.get("today_key", "")))
	config.set_value("daily_quests", "completed", dq.get("completed", []))
	config.set_value("daily_quests", "streak_days", int(dq.get("streak_days", 0)))
	config.set_value("daily_quests", "last_checkin_key", String(dq.get("last_checkin_key", "")))
```

3. `load_data`（save_manager.gd:112）`data["behavior"] = behavior_data` 行后加：

```gdscript
	# P6：每日任务区块（独立 section，缺省走默认值）
	var dq_data: Dictionary = data.get("daily_quests", {})
	dq_data["today_key"] = String(config.get_value("daily_quests", "today_key", dq_data.get("today_key", "")))
	dq_data["completed"] = config.get_value("daily_quests", "completed", dq_data.get("completed", []))
	dq_data["streak_days"] = int(config.get_value("daily_quests", "streak_days", dq_data.get("streak_days", 0)))
	dq_data["last_checkin_key"] = String(config.get_value("daily_quests", "last_checkin_key", dq_data.get("last_checkin_key", "")))
	data["daily_quests"] = dq_data
```

4. `_gather_current_data`（save_manager.gd:211）`data["behavior"] = behavior_data` 行前加（注意：`main.get("daily_quests_save_data")` 返回的是 Callable/方法引用真值检查——与 first_interaction_done 的属性 get 不同，方法存在性用 has_method 判定更稳）：

```gdscript
	# P6：每日任务状态（main 持有 service，has_method 同 get_timed_hide_save_data 模式）
	if main and main.has_method("daily_quests_save_data"):
		data["daily_quests"] = main.daily_quests_save_data()
```

- [ ] **Step 4: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 44  failed: 0`（41 + 3）

- [ ] **Step 5: Commit**

```bash
git add save_manager.gd tests/test_daily_quests.gd
git commit -m "feat: 存档每日任务区块四点贯通"
```

---

### Task 7: main.gd 挂载接线

**Files:**
- Modify: `main.gd`

- [ ] **Step 1: main.gd 声明与挂载**

`const FIRST_GUIDE_SCRIPT` 行（main.gd:47）后加：

```gdscript
const DAILY_QUEST_SCRIPT := preload("res://components/engagement/daily_quest_service.gd")
```

`var first_guide_controller` 行（main.gd:48）后加：

```gdscript
var daily_quest_service  # P6：每日任务/隐式签到
var _quest_poll_timer: float = 0.0  # 分钟级快照轮询
```

`_ready` 中 `_setup_first_guide(settings)` 行（main.gd:113）后加：

```gdscript
	_setup_daily_quests(data)
```

文件任意函数区（`_setup_first_guide` 之后）加：

```gdscript
func _setup_daily_quests(data: Dictionary) -> void:
	# P6：挂载服务 + 读档 + 事件订阅 + 完成信号接线
	if daily_quest_service:
		return
	daily_quest_service = DAILY_QUEST_SCRIPT.new()
	daily_quest_service.name = "DailyQuestService"
	add_child(daily_quest_service)
	daily_quest_service.load_from_save(data.get("daily_quests", {}))
	daily_quest_service.checkin_done.connect(_on_checkin_done)
	daily_quest_service.quest_completed.connect(_on_quest_completed)
	# 事件流总订阅：collector 是 main 与 smart_pet_controller 两个来源的汇点
	if smart_pet_controller and smart_pet_controller._context_collector:
		smart_pet_controller._context_collector.event_recorded.connect(
			func(event_type, payload): daily_quest_service.notify_event(event_type, payload))

func _on_checkin_done(streak: int, reward: float) -> void:
	# 隐式签到：首日播一句；奖励直发（无需庆祝动作）
	if cat and smart_line_bubble and streak == 1:
		smart_line_bubble.show_line("今天也要好好相处哦", cat.global_position, _cached_screen_size)
	_grant_quest_bond(reward)

func _on_quest_completed(quest_id: String, reward: float) -> void:
	# 任务完成：台词气泡 + bond 发放（猫做庆祝动作；greet 是 Lv2 解锁，
	# 新用户首日 play_animation 播放虽无解锁拦截但语义不敬——用基础动作 tail_wag）
	var line := _quest_line(quest_id)
	if cat and smart_line_bubble:
		smart_line_bubble.show_line(line, cat.global_position, _cached_screen_size)
	if cat and cat.has_method("play_animation"):
		cat.play_animation("tail_wag")
	_grant_quest_bond(reward)

func _grant_quest_bond(reward: float) -> void:
	if cat and cat.bond_system:
		cat.bond_system.add_bond("quest_reward", reward)

func _quest_line(quest_id: String) -> String:
	# 任务完成台词（傲娇基底；性格化润色留给 LLM 轨道）
	match quest_id:
		"focus_session":
			return "一起专注的感觉还不赖嘛。"
		"stand_up":
			return "站起来晃晃，对身体好。"
		"meal_on_time":
			return "吃饱了才有力气陪我玩。"
		"interact_once":
			return "哼，勉强算你有良心。"
	return "做得不错。"

func daily_quests_save_data() -> Dictionary:
	# SaveManager._gather_current_data 经 main provider 读取
	if daily_quest_service:
		return daily_quest_service.get_save_data()
	return {}
```

- [ ] **Step 2: 点击猫事件埋点**

`_on_cat_left_clicked`（main.gd:775）`quick_action_menu.show_at(pos)` 后加一行：

```gdscript
	_record_smart_event("cat_clicked", {"pos": pos})
```

（cat_clicked 经 event_recorded 信号喂给任务服务；同时入事件流供未来画像使用。）

- [ ] **Step 3: 分钟级轮询接线**

`_process`（main.gd:235）`_check_invite_ignored(delta)` 行后加：

```gdscript
	_poll_daily_quests(delta)
```

`_check_invite_ignored` 函数后加：

```gdscript
func _poll_daily_quests(delta: float) -> void:
	# P6：窗口类任务每分钟轮询快照闲置（与 _check_invite_ignored 同聚合模式）
	if not daily_quest_service or not smart_pet_controller:
		return
	_quest_poll_timer += delta
	if _quest_poll_timer < 60.0:
		return
	_quest_poll_timer = 0.0
	daily_quest_service.poll_snapshot(smart_pet_controller._context_collector.get_snapshot())
	daily_quest_service._roll_day()  # 运行中跨天：刷新任务与签到
```

- [ ] **Step 4: 冒烟（headless 启动无脚本错误）**

Run: `timeout 20 "$GODOT" --headless --path . res://main.tscn 2>&1 | head -20`
Expected: 含 `桌面宠物猫启动成功`、无 SCRIPT ERROR（挂载失败会打 Parse Error / 连接失败）

- [ ] **Step 5: 回归三套核心**

```bash
timeout 90 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn && \
timeout 90 "$GODOT" --headless --path . res://tests/test_smart_modules.tscn && \
timeout 90 "$GODOT" --headless --path . res://tests/test_presence_level.tscn
```
Expected: 三绿

- [ ] **Step 6: Commit**

```bash
git add main.gd
git commit -m "feat: 主场景挂载每日任务服务与发奖接线"
```

---

### Task 8: bond 增益类型 + 面板今日任务区块

**Files:**
- Modify: `components/bond_system.gd`
- Modify: `settings_panel.gd`
- Modify: `tests/test_daily_quests.gd`

- [ ] **Step 1: 追加失败用例（_run 追加 `_test_quest_bond_gain()`）**

```gdscript
func _test_quest_bond_gain() -> void:
	# quest_reward 增益类型：显式 amount 直加，不受同类递减影响
	var bond = preload("res://components/bond_system.gd").new()
	add_child(bond)
	bond.bond = 0.0
	var g1: float = bond.add_bond("quest_reward", 15.0)
	var g2: float = bond.add_bond("quest_reward", 10.0)
	_assert_true(is_equal_approx(g1, 15.0), "quest_gain_15")
	_assert_true(is_equal_approx(g2, 10.0), "no_decay_on_quest")
	_assert_true(is_equal_approx(bond.bond, 25.0), "bond_total_25")
	bond.queue_free()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（quest_reward 不在 BOND_GAINS，add_bond 首行拦截返回 0）

- [ ] **Step 3: bond_system.gd 加增益类型（免递减）**

BOND_GAINS 字典（components/bond_system.gd:21）末尾加一行：

```gdscript
	"quest_reward": 0.0,   # P6：任务/签到奖励，amount 显式传入（占位键通过白名单校验）
```

`add_bond`（components/bond_system.gd:85）同类递减判定行改为（quest_reward 豁免递减——签到+任务奖励同日多次发放，若走递减机制会被打折）：

```gdscript
	# 同类连续重复递减（任务奖励豁免：amount 显式的系统发放不打折）
	if interaction_type != "quest_reward" \
			and interaction_type == _last_gain_type and now - _last_gain_time < REPEAT_WINDOW:
```

（Task 8 用例 `no_decay_on_quest` 正是验证这一豁免。）

- [ ] **Step 4: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 47  failed: 0`（44 + 3）

- [ ] **Step 5: settings_panel.gd 加今日任务区块**

`refresh_bond_ui` 函数后加（照抄亲密度区模式）：

```gdscript
## P6：今日任务区块（任务列表 + 连续签到），代码构建 + visible 才刷
var _quest_title_label: Label
var _quest_rows: Array = []  # [{label: Label, quest_id: String}]
var _quest_streak_label: Label

func _ensure_quest_ui() -> void:
	if _quest_title_label:
		return
	var vbox = get_node_or_null("ScrollContainer/VBoxContainer")
	if not vbox:
		return
	_quest_title_label = Label.new()
	_quest_title_label.name = "QuestTitleLabel"
	_quest_title_label.text = "今日任务"
	_quest_title_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(_quest_title_label)
	var main = get_tree().get_root().get_node_or_null("Main")
	var quest_defs: Dictionary = {}
	if main and main.daily_quest_service:
		quest_defs = main.daily_quest_service.QUEST_DEFS
	for qid in quest_defs:
		var row = Label.new()
		row.name = "QuestRow_" + String(qid)
		row.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		vbox.add_child(row)
		_quest_rows.append({"label": row, "quest_id": String(qid)})
	_quest_streak_label = Label.new()
	_quest_streak_label.name = "QuestStreakLabel"
	_quest_streak_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vbox.add_child(_quest_streak_label)

func refresh_quest_ui() -> void:
	_ensure_quest_ui()
	if not _quest_title_label:
		return
	var main = get_tree().get_root().get_node_or_null("Main")
	if not main or not main.daily_quest_service:
		return
	var summary: Dictionary = main.daily_quest_service.get_today_summary()
	for row in _quest_rows:
		var quest_id: String = row["quest_id"]
		var title := ""
		var done := false
		for q in summary.get("quests", []):
			if String(q.get("id", "")) == quest_id:
				title = String(q.get("title", ""))
				done = bool(q.get("completed", false))
		row["label"].text = ("✓ " if done else "○ ") + title
	_quest_streak_label.text = "陪伴 · 连续签到 %d 天" % int(summary.get("streak_days", 0))
```

`_on_visibility_changed`（settings_panel.gd:183）`refresh_bond_ui()` 行后加：

```gdscript
		refresh_quest_ui()
```

- [ ] **Step 6: 面板冒烟 + 回归**

```bash
timeout 20 "$GODOT" --headless --path . res://main.tscn 2>&1 | head -20 && \
timeout 90 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn
```
Expected: 启动无 SCRIPT ERROR；测试 `failed: 0`

- [ ] **Step 7: Commit**

```bash
git add components/bond_system.gd settings_panel.gd tests/test_daily_quests.gd
git commit -m "feat: 任务奖励增益类型与面板今日任务区块"
```

注意：bond_system 豁免递减改动会影响 test_bond_system 既有断言吗——不会，既有用例只用 food_given/wand_given/play_success 等互动类型，不涉及 quest_reward。但需回归 test_bond_system 确认：

Run: `timeout 90 "$GODOT" --headless --path . res://tests/test_bond_system.tscn`
Expected: `failed: 0`

---

### Task 9: 全量回归 + MCP 端到端 + 文档收尾

- [ ] **Step 1: 全部 12 套测试**

```bash
for t in test_behavior_system test_focus_session_mode test_sprite_manifest_loader test_objective_system test_activity_classifier test_foreground_app_monitor test_focus_charge_engine test_smart_modules test_bond_system test_presence_level test_first_guide test_daily_quests; do
  echo "=== $t ==="
  timeout 90 "$GODOT" --headless --path . res://tests/$t.tscn 2>&1 | tail -3
done
```
Expected: 每套 `failed: 0`（11 套既有断言只增不减：合计 244；test_daily_quests 新增 47）

- [ ] **Step 2: MCP 端到端验收**

- 备份存档：`cp "$USERPROFILE/AppData/Roaming/Godot/app_userdata/桌面宠物猫/save_data.cfg" /tmp/save_backup.cfg`（路径若不符，用 `SaveManager.SAVE_PATH` 打印确认）
- 删档启动 → `run_project`：
  - 启动零 ERROR；首日签到（streak=1，无气泡打扰或仅首日一句）
  - 快捷菜单投食 → interact_once 完成气泡「哼，勉强算你有良心。」+ `亲密度 +8` 轻提示
  - 等待/注入 long_focus 提醒（临时把 presence 调高档位加速）后停手 2 分钟 → stand_up 完成
  - 设置面板打开 → 「今日任务」区块 4 行渲染、✓/○ 状态正确、连续签到天数显示
  - `stop_project` → 重启 → completed 与 streak 保持（读档恢复）
- 还原存档备份

- [ ] **Step 3: 更新主计划文档**

`docs/plans/2026-08-17-smart-companion-redesign.md` 末尾追加 P6 完成记录（对齐 P5 格式：交付表 + 验证证据 + 数字）

- [ ] **Step 4: Commit 收尾**

```bash
git add docs/plans/2026-08-17-smart-companion-redesign.md docs/superpowers/plans/2026-08-19-p6-daily-quests.md
git commit -m "docs: P6 完成记录"
```

---

## 附：执行提示

- Task 1-8 强顺序（信号 → 服务 → 判定 → 存档 → 接线 → UI）；Task 8 的 bond 增益类型依赖 Task 7 的 `_grant_quest_bond` 已接线
- `int("abc")` 在 GDScript 返回 0 不报错——异常兜底用例断言的是"不崩且落到默认值"，不是类型校验
- main.gd 的 lambda 连接（Task 7 Step 1）注意缩进：Godot 4 lambda 多行体需整体右缩一层
- 每任务结束 `git status` 应 clean（.godot/.claude 例外）
- MCP 端到端若 stand_up 窗口验证耗时过长（等真实 long_focus 提醒），允许临时把 quiet_hours 外的 presence_level 设为 3（高频）并在测试存档里预置 `continuous_active_seconds`，验收后还原
