# P8 周任务/成就系统 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 DailyQuestService 上扩展周任务（累计式 ×3）与成就系统（里程碑 ×8 + 可佩戴称号），数据全部来自既有任务完成事件，面板任务页扩三区。

**Architecture:** `_complete()` 完成链扩展三叉（当日标记/周计数/终身累计+成就扫描）；成就定义表独立 `achievement_defs.gd`；存档 `daily_quests` 加 2 键 + 新 `achievements` 区块；UI 在「任务·亲密度」页加本周任务区与成就徽章墙（含称号佩戴）。

**Tech Stack:** Godot 4.7 / GDScript；测试 headless tscn 断言式；端到端 Godot MCP。

**设计文档:** `docs/superpowers/specs/2026-08-19-p8-weekly-achievements-design.md`

---

## 执行前置

- `"$GODOT"` = `/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- 既有 13 套 315 断言；本计划在 `test_daily_quests`（现 42 断言）追加约 20 断言，合计 14 套 ~335
- **已核实代码事实**：
  - `_complete(quest_id: String, reward: float)` 现两参（daily_quest_service.gd:133）——加第三参 `source_event: String = ""`
  - **`notify_event` 顶部 `all_done` 早退（daily_quest_service.gd:94-100）会拦掉全部后续事件——必须改造**：周计数需要当日任务全完成后继续累计（如 week_interact ×7），早退只能拦"完成判定"，不能拦"周计数喂入"。改法见 Task 2 Step 3
  - `notify_event` 两个 `_complete` 调用点（focus_milestone / INTERACT_EVENTS 分支）需传 source_event
  - bond_changed 信号在 bond_system.gd:8（`bond_changed(bond, level)`），cat.gd:90 已自连——main 侧直连 `cat.bond_system.bond_changed` 即可拿到等级
  - 面板任务区模式：`_quest_rows` 数组 + `refresh_quest_ui()`（settings_panel.gd:471-502 现成可照抄）
  - save_manager `daily_quests` 写入在 save_manager.gd:104-108，读取在 ~184-188，默认值在 ~52-58，采集走 `main.daily_quests_save_data()`
  - GDScript 无内置 ISO 周算法——`_week_key()` 手写：unix 秒 → 当前周一首 0 点的日期键
  - P7 教训：测试协程内禁 `await`（会被 quit 截断静默丢断言）；删函数检查孤儿语句；`@warning_ignore` 紧贴目标行

## 文件结构总览

- Task 1 — 成就定义表 `achievement_defs.gd` + 周任务表（纯常量）
- Task 2 — 服务扩展：周计数 + notify_event 早退改造 + source_event 链
- Task 3 — 终身累计 + 成就扫描 + 信号 + notify_bond_level
- Task 4 — 存档：daily_quests 加 2 键 + achievements 新区块四点贯通
- Task 5 — 称号佩戴 + get_weekly_summary/get_achievements_summary 接口
- Task 6 — main 接线（三信号 + bond_changed 转发 + 气泡台词）
- Task 7 — 面板三区 UI（本周任务 + 徽章墙 + 佩戴选择 + 标题显示）
- Task 8 — 全量回归 + MCP 端到端 + 文档收尾

---

### Task 1: 成就定义表

**Files:**
- Create: `components/engagement/achievement_defs.gd`
- Modify: `tests/test_daily_quests.gd`

- [x] **Step 1: 追加失败测试（_run 追加 `_test_achievement_defs()`）**

```gdscript
const AchDefsScript = preload("res://components/engagement/achievement_defs.gd")

func _test_achievement_defs() -> void:
	# 定义表完整性：8 成就含必需字段；3 周任务含 target
	var defs: Dictionary = AchDefsScript.ACHIEVEMENTS
	_assert_equal(defs.size(), 8, "eight_achievements")
	for id in defs:
		var d: Dictionary = defs[id]
		_assert_true(d.has("name") and d.has("need") and d.has("stat") and d.has("reward"), "def_complete_" + id)
	_assert_equal(String(defs["focus_10"]["title"]), "专注搭档", "focus10_title")
	_assert_true(is_equal_approx(float(defs["checkin_30"]["reward"]), 150.0), "checkin30_reward")
	var weekly: Dictionary = AchDefsScript.WEEKLY_QUESTS
	_assert_equal(weekly.size(), 3, "three_weekly")
	_assert_equal(int(weekly["week_focus"]["target"]), 3, "weekfocus_target")
```

- [x] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（achievement_defs.gd 不存在）

- [x] **Step 3: 实现 components/engagement/achievement_defs.gd**

```gdscript
class_name AchievementDefs
extends RefCounted

## P8 成就与周任务定义表（纯常量）：id → 定义
## 成就判定源 stat 键对应 lifetime_totals；need 为累计阈值

## 周任务：quest → {title, target(次数), quest_id(计数的每日任务), reward}
const WEEKLY_QUESTS := {
	"week_focus": {"title": "专注搭档之路", "quest_id": "focus_session", "target": 3, "reward": 30.0},
	"week_stand": {"title": "起身活动周", "quest_id": "stand_up", "target": 5, "reward": 25.0},
	"week_interact": {"title": "每日一见", "quest_id": "interact_once", "target": 7, "reward": 25.0},
}

## 成就：id → {name, stat(累计键), need(阈值), reward, title(称号，空=无称号)}
const ACHIEVEMENTS := {
	"focus_10": {"name": "初入专注", "stat": "focus_session", "need": 10, "reward": 50.0, "title": "专注搭档"},
	"focus_50": {"name": "专注大师", "stat": "focus_session", "need": 50, "reward": 150.0, "title": "深度工作之魂"},
	"pet_100": {"name": "百次撸猫", "stat": "pet_count", "need": 100, "reward": 80.0, "title": "撸猫圣手"},
	"week_all": {"name": "完美一周", "stat": "week_all", "need": 1, "reward": 60.0, "title": "完美一周"},
	"checkin_7": {"name": "一周之约", "stat": "checkin_days", "need": 7, "reward": 40.0, "title": "一周之约"},
	"checkin_30": {"name": "月度挚友", "stat": "checkin_days", "need": 30, "reward": 150.0, "title": "月度挚友"},
	"interact_50": {"name": "破冰之交", "stat": "interact_total", "need": 50, "reward": 40.0, "title": "破冰之交"},
	"bond_lv5": {"name": "挚友认证", "stat": "bond_level", "need": 5, "reward": 100.0, "title": "挚友认证"},
}
```

- [x] **Step 4: 跑测试通过并提交**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 54  failed: 0`（42 + 12）

```bash
git add components/engagement/achievement_defs.gd tests/test_daily_quests.gd
git commit -m "feat: 成就与周任务定义表"
```

---

### Task 2: 周计数与 notify_event 改造

**Files:**
- Modify: `components/engagement/daily_quest_service.gd`
- Modify: `tests/test_daily_quests.gd`

- [x] **Step 1: 追加失败测试（_run 追加 `_test_weekly_counts()`）**

```gdscript
func _test_weekly_counts() -> void:
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	# 周计数：interact_once 完成 3 次（不同事件源）——当日只发 1 次但周计数累计
	# 注意：interact_once 当日一次后 _complete 拦截重复——周计数必须挂在拦截之前
	svc.notify_event("item_used", {})
	svc.notify_event("petting_started", {})
	svc.notify_event("cat_clicked", {})
	var wc: Dictionary = svc.get_save_data().get("week_counts", {})
	_assert_equal(int(wc.get("interact_once", 0)), 3, "week_counts_accumulate_past_daily")
	# 周任务达标：week_interact target=7 不够 3 次 → 未发
	var fired: Array = []
	svc.weekly_quest_completed.connect(func(qid, reward): fired.append([qid, reward]))
	for i in range(4):
		svc.notify_event("item_used", {})
	_assert_equal(fired.size(), 1, "weekly_fires_at_target")
	_assert_equal(String(fired[0][0]), "week_interact", "weekly_id_correct")
	_assert_true(is_equal_approx(float(fired[0][1]), 25.0), "weekly_reward_25")
	# 达标后继续互动不重复发
	svc.notify_event("item_used", {})
	_assert_equal(fired.size(), 1, "weekly_no_double")
	svc.queue_free()
```

- [x] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（week_counts/weekly_quest_completed 不存在）

- [x] **Step 3: 实现周计数与早退改造**

daily_quest_service.gd 头部追加（signal 区下；注意变量名用 `_current_week` 避免与 `_week_key()` 函数重名）：

```gdscript
signal weekly_quest_completed(quest_id: String, reward_bond: float)

const AchDefsScript = preload("res://components/engagement/achievement_defs.gd")

var _current_week := ""                # 当前周标识（周一日期键）
var _week_counts: Dictionary = {}      # 每日任务id -> 次数
var _week_quests_done: Dictionary = {} # 周任务id -> true（本周已发）
```

周键算法与初始化（文件尾部 `_date_key` 附近加）：

```gdscript
func _week_key() -> String:
	## 当前周一的日期键（周一为一周之始；unix 秒算法不依赖日历库）
	var now_unix := int(Time.get_unix_time_from_system())
	var d := Time.get_datetime_dict_from_unix_time(now_unix)
	# Time 的 weekday：0=周日..6=周六 → 转"周一为0"偏移
	var weekday_from_monday := (int(d["weekday"]) + 6) % 7
	var monday_unix := now_unix - weekday_from_monday * 86400 \
		- int(d["hour"]) * 3600 - int(d["minute"]) * 60 - int(d["second"])
	var md := Time.get_datetime_dict_from_unix_time(monday_unix)
	return "%04d%02d%02d" % [md["year"], md["month"], md["day"]]

func _roll_week_if_needed() -> void:
	var key := _week_key()
	if key != _current_week:
		_current_week = key
		_week_counts = {}
		_week_quests_done = {}
```

`notify_event` 全量替换（早退只拦完成判定，周计数与窗口开在前）：

```gdscript
func notify_event(event_type: String, payload: Dictionary = {}) -> void:
	## 事件驱动判定（main 连接 context_collector.event_recorded 后自动喂入）
	_roll_week_if_needed()
	var all_done := true
	for qid in QUEST_DEFS:
		if not is_completed(qid):
			all_done = false
			break
	if event_type == "smart_decision" and not all_done:
		var intent := String(payload.get("intent", ""))
		if WINDOW_QUESTS.has(intent):
			var quest_id: String = WINDOW_QUESTS[intent]["quest"]
			if not is_completed(quest_id):
				_window_deadline[quest_id] = int(Time.get_unix_time_from_system() + float(WINDOW_QUESTS[intent]["window"]))
		return
	if event_type == "focus_milestone":
		_count_weekly("focus_session")
		if not all_done:
			_complete("focus_session", float(QUEST_DEFS["focus_session"]["reward"]), event_type)
	elif event_type in INTERACT_EVENTS:
		_count_weekly("interact_once", event_type)
		if not all_done:
			_complete("interact_once", float(QUEST_DEFS["interact_once"]["reward"]), event_type)
```

`_complete` 加第三参与周计数挂钩：

```gdscript
func _complete(quest_id: String, reward: float, source_event: String = "") -> void:
	## 任务完成唯一入口：拦截重复、发信号（bond 发放在 main 侧）
	if _completed.has(quest_id):
		return
	_completed[quest_id] = true
	quest_completed.emit(quest_id, reward)

func _count_weekly(quest_id: String, source_event: String = "") -> void:
	## 周计数（无论当日任务是否已完成都累计——周任务数据源）
	_roll_week_if_needed()
	_week_counts[quest_id] = int(_week_counts.get(quest_id, 0)) + 1
	_check_weekly_quests(quest_id)
```

`_check_weekly_quests`：

```gdscript
func _check_weekly_quests(_quest_id: String) -> void:
	for wid in AchDefsScript.WEEKLY_QUESTS:
		if _week_quests_done.has(wid):
			continue
		var w: Dictionary = AchDefsScript.WEEKLY_QUESTS[wid]
		var count := int(_week_counts.get(String(w["quest_id"]), 0))
		if count >= int(w["target"]):
			_week_quests_done[wid] = true
			weekly_quest_completed.emit(String(wid), float(w["reward"]))
```

`get_save_data` 追加 2 键（return 字典内）：

```gdscript
		"week_key": _current_week,
		"week_counts": _week_counts.duplicate(true),
		"weekly_done": _week_quests_done.keys(),
```

`load_from_save` 恢复周状态（`_completed` 恢复块后）：

```gdscript
	var saved_week := String(data.get("week_key", ""))
	var saved_week_counts_raw = data.get("week_counts", {})
	if typeof(saved_week_counts_raw) == TYPE_DICTIONARY:
		_week_counts = saved_week_counts_raw.duplicate(true)
	var saved_weekly_done_raw = data.get("weekly_done", [])
	if typeof(saved_weekly_done_raw) == TYPE_ARRAY:
		for w in saved_weekly_done_raw:
			_week_quests_done[String(w)] = true
	# 周跨过期：week_key 非本周 → 清零重计
	_roll_week_if_needed()
```

（`_roll_week_if_needed` 内比对 `_current_week`，不匹配即 `_set_week` 清零——saved_week 变量仅用于可读性，实际判定在 roll 内。）

`poll_snapshot` 内两处 `_complete` 调用补第三参（source 传空——窗口类任务无细分源）。

- [x] **Step 4: 跑测试通过并提交**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 61  failed: 0`（54 + 7）

```bash
git add components/engagement/daily_quest_service.gd tests/test_daily_quests.gd
git commit -m "feat: 周任务计数与达标信号"
```

---

### Task 3: 终身累计 + 成就扫描

**Files:**
- Modify: `components/engagement/daily_quest_service.gd`
- Modify: `tests/test_daily_quests.gd`

- [x] **Step 1: 追加失败测试（_run 追加 `_test_achievements()`）**

```gdscript
func _test_achievements() -> void:
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({"streak_days": 6, "last_checkin_key": svc._shift_date_key(-1), "today_key": svc._shift_date_key(-1)})
	# streak=7 → checkin_7 解锁
	var unlocked: Array = []
	svc.achievement_unlocked.connect(func(aid, title): unlocked.append([aid, title]))
	svc.notify_event("item_used", {})  # 触发一次成就扫描
	_assert_true(unlocked.size() >= 1, "checkin7_unlocked")
	var found := false
	for u in unlocked:
		if String(u[0]) == "checkin_7":
			found = true
	_assert_true(found, "checkin7_id")
	# 重复事件不重复解锁
	unlocked.clear()
	svc.notify_event("cat_clicked", {})
	var again := false
	for u in unlocked:
		if String(u[0]) == "checkin_7":
			again = true
	_assert_true(not again, "no_double_unlock")

	# focus_10 边界：预置 9 次再完成 1 次 → 解锁
	var svc2 = QuestServiceScript.new()
	add_child(svc2)
	svc2.load_from_save({})
	var unlocked2: Array = []
	svc2.achievement_unlocked.connect(func(aid, title): unlocked2.append(aid))
	svc2._lifetime_totals["focus_session"] = 9
	svc2.notify_event("focus_milestone", {})
	var f10 := false
	for u in unlocked2:
		if String(u) == "focus_10":
			f10 = true
	_assert_true(f10, "focus10_at_boundary")
	svc.queue_free()
	svc2.queue_free()

func _test_bond_level_achievement() -> void:
	# bond_lv5：notify_bond_level(5) 解锁
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	var unlocked: Array = []
	svc.achievement_unlocked.connect(func(aid, title): unlocked.append(aid))
	svc.notify_bond_level(5)
	_assert_true(unlocked.has("bond_lv5"), "bondlv5_unlocked")
	svc.queue_free()
```

（`_test_bond_level_achievement` 也加入 `_run()`。）

- [x] **Step 2: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: FAIL（achievement_unlocked/_lifetime_totals/notify_bond_level 不存在）

- [x] **Step 3: 实现累计与扫描**

daily_quest_service.gd 追加：

```gdscript
signal achievement_unlocked(achievement_id: String, title_text: String)

var _lifetime_totals: Dictionary = {}   # stat 键 -> 累计值
var _unlocked: Dictionary = {}          # 成就id -> true
var _notified_bond_level := 0
```

`_count_weekly` 尾部追加累计分支：

```gdscript
	# —— 终身累计（成就判定源）——
	match quest_id:
		"focus_session":
			_lifetime_totals["focus_session"] = int(_lifetime_totals.get("focus_session", 0)) + 1
		"interact_once":
			_lifetime_totals["interact_total"] = int(_lifetime_totals.get("interact_total", 0)) + 1
			if source_event in ["petting_started", "cat_clicked"]:
				_lifetime_totals["pet_count"] = int(_lifetime_totals.get("pet_count", 0)) + 1
	# 单周全勤：四每日任务本周各≥1
	var all_weekly := true
	for qid in QUEST_DEFS:
		if int(_week_counts.get(String(qid), 0)) < 1:
			all_weekly = false
			break
	if all_weekly:
		_lifetime_totals["week_all"] = maxi(int(_lifetime_totals.get("week_all", 0)), 1)
	_scan_achievements()
```

签到喂累计（`_roll_day` 签到结算尾部、`checkin_done.emit` 前加）：

```gdscript
	_lifetime_totals["checkin_days"] = streak_days
	_scan_achievements()
```

扫描与外部喂入：

```gdscript
func _scan_achievements() -> void:
	for aid in AchDefsScript.ACHIEVEMENTS:
		if _unlocked.has(aid):
			continue
		var a: Dictionary = AchDefsScript.ACHIEVEMENTS[aid]
		var stat := String(a["stat"])
		var value := 0
		if stat == "bond_level":
			value = _notified_bond_level
		else:
			value = int(_lifetime_totals.get(stat, 0))
		if value >= int(a["need"]):
			_unlocked[aid] = true
			achievement_unlocked.emit(String(aid), String(a["title"]))

func notify_bond_level(level: int) -> void:
	## main 在 bond_system.bond_changed 时调用（bond_lv5 成就数据源）
	_notified_bond_level = maxi(_notified_bond_level, level)
	_scan_achievements()
```

`get_achievements_save_data()` / 成就恢复（`load_from_save` 尾部加）：

```gdscript
	var saved_totals_raw = data.get("lifetime_totals", {})
	if typeof(saved_totals_raw) == TYPE_DICTIONARY:
		for k in saved_totals_raw:
			_lifetime_totals[String(k)] = int(saved_totals_raw[k])
	var saved_unlocked_raw = data.get("unlocked", [])
	if typeof(saved_unlocked_raw) == TYPE_ARRAY:
		for u in saved_unlocked_raw:
			_unlocked[String(u)] = true
```

```gdscript
func get_achievements_save_data() -> Dictionary:
	var unlocked: Array = []
	for u in _unlocked.keys():
		unlocked.append(u)
	return {
		"lifetime_totals": _lifetime_totals.duplicate(true),
		"unlocked": unlocked,
		"equipped_title": _equipped_title,
	}
```

（`_equipped_title` 变量 Task 5 实现；本任务先声明 `var _equipped_title := ""` 并在 `load_from_save` 恢复 `data.get("equipped_title", "")`，佩戴 API 留 Task 5。）

- [x] **Step 4: 跑测试通过并提交**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 70  failed: 0`（61 + 9）

```bash
git add components/engagement/daily_quest_service.gd tests/test_daily_quests.gd
git commit -m "feat: 终身累计与成就解锁扫描"
```

---

### Task 4: 存档贯通

**Files:**
- Modify: `save_manager.gd`
- Modify: `main.gd`（daily_quests_save_data 扩展 + 新 achievements_save_data）
- Modify: `tests/test_daily_quests.gd`

- [x] **Step 1: 追加失败测试（_run 追加 `_test_achievements_save_section()`）**

```gdscript
func _test_achievements_save_section() -> void:
	var sm = preload("res://save_manager.gd").new()
	add_child(sm)
	var defaults: Dictionary = sm._get_default_data()
	var ach: Dictionary = defaults.get("achievements", {})
	_assert_equal(ach.get("unlocked", null) if typeof(ach.get("unlocked", null)) == TYPE_ARRAY else null, [], "default_unlocked_empty")
	_assert_equal(String(ach.get("equipped_title", "x")), "", "default_title_empty")
	var data := defaults.duplicate(true)
	data["achievements"] = {"lifetime_totals": {"focus_session": 3}, "unlocked": ["checkin_7"], "equipped_title": "一周之约"}
	var err: int = sm._write_config(data)
	_assert_equal(err, 0, "write_ach_ok")
	sm.queue_free()
```

- [x] **Step 2: 跑测试确认失败 → 实现四点**

save_manager.gd：
1. `_get_default_data` daily_quests 字典加 `"week_key": ""` / `"week_counts": {}` / `"weekly_done": []`，同级加：

```gdscript
		,
		"achievements": {
			"lifetime_totals": {},
			"unlocked": [],
			"equipped_title": ""
		}
```

2. `_write_config` daily_quests 区块追加：

```gdscript
	config.set_value("daily_quests", "week_key", String(dq.get("week_key", "")))
	config.set_value("daily_quests", "week_counts", dq.get("week_counts", {}))
	config.set_value("daily_quests", "weekly_done", dq.get("weekly_done", []))
	var ach = data.get("achievements", {})
	config.set_value("achievements", "lifetime_totals", ach.get("lifetime_totals", {}))
	config.set_value("achievements", "unlocked", ach.get("unlocked", []))
	config.set_value("achievements", "equipped_title", String(ach.get("equipped_title", "")))
```

3. `load_data` daily_quests 读取块追加 + achievements 块：

```gdscript
	dq_data["week_key"] = String(config.get_value("daily_quests", "week_key", ""))
	dq_data["week_counts"] = config.get_value("daily_quests", "week_counts", {})
	dq_data["weekly_done"] = config.get_value("daily_quests", "weekly_done", [])
	var ach_data: Dictionary = data.get("achievements", {})
	ach_data["lifetime_totals"] = config.get_value("achievements", "lifetime_totals", {})
	ach_data["unlocked"] = config.get_value("achievements", "unlocked", [])
	ach_data["equipped_title"] = String(config.get_value("achievements", "equipped_title", ""))
	data["achievements"] = ach_data
```

4. `_gather_current_data`：main provider 链扩展（has_method 判定）：

main.gd `daily_quests_save_data` 返回改为合并两块：

```gdscript
func daily_quests_save_data() -> Dictionary:
	if daily_quest_service:
		var dq: Dictionary = daily_quest_service.get_save_data()
		dq.merge(daily_quest_service.get_achievements_save_data(), true)
		return dq
	return {}
```

（合并进 daily_quests 区块——achievements 键挂在同一 section 下写档，`_write_config` 读 `data["daily_quests"]` 里的 achievements 三键。**改 Step 2-2 的写入源**：`var ach = dq.get("achievements", {})`——即 daily_quests 区块含全部键。执行时统一：**不建独立 achievements section，全部并入 daily_quests**——比设计文档的独立区块少一处四点贯通，结构更简单，键不冲突。）

（相应地 save_manager 默认值/load_data 也全并入 daily_quests 字典，不出现第二个 section；测试断言 `defaults.get("daily_quests").get("unlocked")`。**Step 1 测试按此改**：`var ach: Dictionary = defaults.get("daily_quests", {})` 后断言 unlocked/equipped_title。）

main.gd `_setup_daily_quests` 读档注入不变（`data.get("daily_quests", {})` 已含新键）；`load_from_save` 里新增的恢复逻辑读同名键即可。

- [x] **Step 3: 跑测试通过并提交**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 74  failed: 0`（70 + 4，含 Step 1 改后断言数）

```bash
git add save_manager.gd main.gd tests/test_daily_quests.gd
git commit -m "feat: 周计数成就存档并入每日任务区块"
```

---

### Task 5: 称号佩戴 + 面板数据接口

**Files:**
- Modify: `components/engagement/daily_quest_service.gd`
- Modify: `tests/test_daily_quests.gd`

- [x] **Step 1: 追加失败测试（_run 追加 `_test_title_equip()` 与 `_test_summaries()`）**

```gdscript
func _test_title_equip() -> void:
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	# 未解锁不可佩戴
	_assert_true(not svc.equip_title("专注搭档"), "locked_title_rejected")
	# 解锁后可佩戴/卸下
	svc._unlocked["focus_10"] = true
	_assert_true(svc.equip_title("专注搭档"), "unlocked_title_ok")
	_assert_equal(svc._equipped_title, "专注搭档", "equipped_stored")
	_assert_true(svc.equip_title(""), "unequip_ok")
	_assert_equal(svc._equipped_title, "", "unequipped")
	# 不存在的称号拒绝
	_assert_true(not svc.equip_title("宇宙霸主"), "unknown_title_rejected")
	svc.queue_free()

func _test_summaries() -> void:
	var svc = QuestServiceScript.new()
	add_child(svc)
	svc.load_from_save({})
	var ws: Dictionary = svc.get_weekly_summary()
	_assert_equal(ws.get("quests", []).size(), 3, "weekly_summary_3")
	var as_: Dictionary = svc.get_achievements_summary()
	_assert_equal(as_.get("achievements", []).size(), 8, "ach_summary_8")
	# 每条成就含 unlocked/progress 字段
	var first: Dictionary = as_["achievements"][0]
	_assert_true(first.has("unlocked") and first.has("progress"), "ach_fields")
	_assert_true(as_.has("equipped_title"), "summary_has_title")
	svc.queue_free()
```

- [x] **Step 2: 跑测试确认失败 → 实现**

```gdscript
func equip_title(title_text: String) -> bool:
	## 佩戴/卸下称号：空串卸下；须为已解锁成就的称号
	if title_text == "":
		_equipped_title = ""
		return true
	for aid in _unlocked:
		if String(AchDefsScript.ACHIEVEMENTS.get(aid, {}).get("title", "")) == title_text:
			_equipped_title = title_text
			return true
	return false

func get_weekly_summary() -> Dictionary:
	var quests: Array = []
	for wid in AchDefsScript.WEEKLY_QUESTS:
		var w: Dictionary = AchDefsScript.WEEKLY_QUESTS[wid]
		var count := int(_week_counts.get(String(w["quest_id"]), 0))
		quests.append({
			"id": String(wid),
			"title": String(w["title"]),
			"count": count,
			"target": int(w["target"]),
			"done": bool(_week_quests_done.get(wid, false)) or count >= int(w["target"]),
		})
	return {"quests": quests}

func get_achievements_summary() -> Dictionary:
	var achievements: Array = []
	for aid in AchDefsScript.ACHIEVEMENTS:
		var a: Dictionary = AchDefsScript.ACHIEVEMENTS[aid]
		var stat := String(a["stat"])
		var value := _notified_bond_level if stat == "bond_level" else int(_lifetime_totals.get(stat, 0))
		achievements.append({
			"id": String(aid),
			"name": String(a["name"]),
			"unlocked": bool(_unlocked.has(aid)),
			"progress": clampf(float(value) / float(maxi(int(a["need"]), 1)), 0.0, 1.0),
			"cur": value,
			"need": int(a["need"]),
			"title": String(a["title"]),
		})
	return {"achievements": achievements, "equipped_title": _equipped_title}
```

`load_from_save` 恢复 equipped_title（已有占位行改为真恢复）。

- [x] **Step 3: 跑测试通过并提交**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn`
Expected: `passed: 84  failed: 0`（74 + 10）

```bash
git add components/engagement/daily_quest_service.gd tests/test_daily_quests.gd
git commit -m "feat: 称号佩戴与周度成就摘要接口"
```

---

### Task 6: main 接线

**Files:**
- Modify: `main.gd`

- [x] **Step 1: 三信号接线（`_setup_daily_quests` 内 quest_completed 连接后加）**

```gdscript
	daily_quest_service.weekly_quest_completed.connect(_on_weekly_quest_completed)
	daily_quest_service.achievement_unlocked.connect(_on_achievement_unlocked)
	# bond 等级喂入（bond_lv5 成就数据源）
	if cat and cat.bond_system:
		cat.bond_system.bond_changed.connect(
			func(_bond, level): daily_quest_service.notify_bond_level(level))
```

- [x] **Step 2: 两 handler（`_on_quest_completed` 后加）**

```gdscript
func _on_weekly_quest_completed(quest_id: String, reward: float) -> void:
	# 周任务完成：气泡 + 发奖（与每日任务同链路）
	var title := "本周约定"
	var defs: Dictionary = preload("res://components/engagement/achievement_defs.gd").WEEKLY_QUESTS
	if defs.has(quest_id):
		title = String(defs[quest_id]["title"])
	if cat and smart_line_bubble:
		smart_line_bubble.show_line("🏆 本周完成：%s" % title, cat.global_position, _cached_screen_size)
	_grant_quest_bond(reward)
	if settings_panel and settings_panel.visible and settings_panel.has_method("refresh_quest_ui"):
		settings_panel.refresh_quest_ui()

func _on_achievement_unlocked(achievement_id: String, title_text: String) -> void:
	# 成就解锁：气泡 + bond + 面板刷新
	var defs: Dictionary = preload("res://components/engagement/achievement_defs.gd").ACHIEVEMENTS
	var name := String(defs.get(achievement_id, {}).get("name", achievement_id))
	var reward := float(defs.get(achievement_id, {}).get("reward", 0.0))
	if cat and smart_line_bubble:
		var line := "🏆 解锁成就「%s」" % name
		if not title_text.is_empty():
			line += "，获得称号「%s」" % title_text
		smart_line_bubble.show_line(line, cat.global_position, _cached_screen_size)
	_grant_quest_bond(reward)
	if settings_panel and settings_panel.visible and settings_panel.has_method("refresh_quest_ui"):
		settings_panel.refresh_quest_ui()
```

- [x] **Step 3: 冒烟 + 回归 + 提交**

```bash
timeout 20 "$GODOT" --headless --path . res://main.tscn 2>&1 | grep -E "启动成功|SCRIPT ERROR|Parse" | head -3 && \
timeout 90 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn 2>&1 | grep -E "passed|failed"
git add main.gd
git commit -m "feat: 周任务成就信号接线与气泡"
```
Expected: 启动成功；`failed: 0`

---

### Task 7: 面板三区 UI

**Files:**
- Modify: `settings_panel.gd`

- [x] **Step 1: `_build_page_progress` 尾部追加两区（_quest_streak_label 之后）**

```gdscript
	# —— P8 本周任务区 ——
	var weekly_title := Label.new()
	weekly_title.text = "本周任务"
	UiThemeScript.tint_label(weekly_title, "section")
	page.add_child(weekly_title)
	if main and main.daily_quest_service:
		for wid in AchievementDefsScript.WEEKLY_QUESTS:
			var wrow := Label.new()
			UiThemeScript.tint_label(wrow, "body")
			page.add_child(wrow)
			_weekly_rows.append({"label": wrow, "weekly_id": String(wid)})

	# —— P8 成就徽章墙 ——
	var ach_title := Label.new()
	ach_title.text = "成就"
	UiThemeScript.tint_label(ach_title, "section")
	page.add_child(ach_title)

	_title_option = _make_option(page)
	_title_option.item_selected.connect(_on_title_selected)

	var ach_grid := GridContainer.new()
	ach_grid.columns = 4
	ach_grid.add_theme_constant_override("h_separation", UiThemeScript.SPACE_S)
	ach_grid.add_theme_constant_override("v_separation", UiThemeScript.SPACE_S)
	page.add_child(ach_grid)
	for aid in AchievementDefsScript.ACHIEVEMENTS:
		var badge := Label.new()
		badge.custom_minimum_size = Vector2(150, 30)
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ach_grid.add_child(badge)
		_badges.append({"label": badge, "achievement_id": String(aid)})
```

（文件头加 `const AchievementDefsScript = preload("res://components/engagement/achievement_defs.gd")`；成员变量区加 `var _weekly_rows: Array = []` / `var _badges: Array = []` / `var _title_option: OptionButton`。）

- [x] **Step 2: `refresh_quest_ui` 尾部追加两区刷新 + 称号选择器重建**

```gdscript
	# —— P8 本周任务 ——
	var ws: Dictionary = main.daily_quest_service.get_weekly_summary()
	for row in _weekly_rows:
		var wid: String = row["weekly_id"]
		for q in ws.get("quests", []):
			if String(q.get("id", "")) == wid:
				var txt := "%s　%d/%d" % [String(q.get("title", "")), int(q.get("count", 0)), int(q.get("target", 0))]
				row["label"].text = ("✓ " if bool(q.get("done", false)) else "○ ") + txt
	# —— P8 成就徽章墙 ——
	var as_: Dictionary = main.daily_quest_service.get_achievements_summary()
	for badge in _badges:
		var aid: String = badge["achievement_id"]
		for a in as_.get("achievements", []):
			if String(a.get("id", "")) == aid:
				var label: Label = badge["label"]
				if bool(a.get("unlocked", false)):
					label.text = "🏅 " + String(a.get("name", ""))
					label.add_theme_color_override("font_color", UiThemeScript.PRIMARY)
				else:
					label.text = "🔒 %d/%d" % [int(a.get("cur", 0)), int(a.get("need", 0))]
					label.add_theme_color_override("font_color", UiThemeScript.TEXT_DIM)
				label.tooltip_text = "%s：%d/%d" % [String(a.get("name", "")), int(a.get("cur", 0)), int(a.get("need", 0))]
	# —— 称号佩戴选择器（重建选项） ——
	_rebuild_title_options(main, String(as_.get("equipped_title", "")))

func _rebuild_title_options(main, equipped: String) -> void:
	_title_option.clear()
	_title_option.add_item("不佩戴称号")
	_title_option.set_item_metadata(0, "")
	var select_idx := 0
	var idx := 1
	var as_: Dictionary = main.daily_quest_service.get_achievements_summary()
	for a in as_.get("achievements", []):
		if bool(a.get("unlocked", false)) and not String(a.get("title", "")).is_empty():
			_title_option.add_item(String(a["title"]))
			_title_option.set_item_metadata(idx, String(a["title"]))
			if String(a["title"]) == equipped:
				select_idx = idx
			idx += 1
	_title_option.select(select_idx)

func _on_title_selected(_index: int) -> void:
	var main = get_tree().get_root().get_node_or_null("Main")
	if not main or not main.daily_quest_service:
		return
	var title_text := String(_title_option.get_item_metadata(_index))
	main.daily_quest_service.equip_title(title_text)
	SaveManager.save_data()
	_apply_title_to_header(title_text)

func _apply_title_to_header(title_text: String) -> void:
	# 佩戴称号显示在面板标题（_header_title_label 由 _build_layout 的局部 title 提为成员变量）
	if title_text.is_empty():
		_header_title_label.text = "🐾 设置"
	else:
		_header_title_label.text = "🐾 设置 · " + title_text
```

（**前置改动**：`_build_layout` 中 `var title := Label.new()` 改为成员变量——文件头声明 `var _header_title_label: Label`，构建处 `_header_title_label = Label.new(); _header_title_label.text = "🐾 设置"; ...`，本函数直接刷它。）

- [x] **Step 3: 冒烟 + 回归 + 提交**

```bash
timeout 20 "$GODOT" --headless --path . res://main.tscn 2>&1 | grep -E "启动成功|SCRIPT ERROR|Parse" | head -3 && \
timeout 90 "$GODOT" --headless --path . res://tests/test_daily_quests.tscn 2>&1 | grep -E "passed|failed" && \
timeout 90 "$GODOT" --headless --path . res://tests/test_ui_theme.tscn 2>&1 | grep -E "passed|failed"
git add settings_panel.gd
git commit -m "feat: 面板本周任务与成就徽章墙"
```
Expected: 启动成功；两套测试绿

---

### Task 8: 全量回归 + MCP 端到端 + 文档收尾

- [x] **Step 1: 13 套全量测试（14 套合一——daily_quests 已含新断言）**

```bash
for t in test_behavior_system test_focus_session_mode test_sprite_manifest_loader test_objective_system test_activity_classifier test_foreground_app_monitor test_focus_charge_engine test_smart_modules test_bond_system test_presence_level test_first_guide test_daily_quests test_ui_theme; do
  echo "=== $t ==="
  timeout 90 "$GODOT" --headless --path . res://tests/$t.tscn 2>&1 | grep -E "passed:|failed:|通过:" | tail -2
done
```
Expected: 全绿；test_daily_quests ≈ 84 断言；总计 ≈ 357

- [x] **Step 2: MCP 端到端**

- 伪造存档预置：手动编辑 `Desktop Pet Cat/save_data.cfg` 的 daily_quests 区块加 `streak_days=6` + `last_checkin_key=昨日` → 启动 → 签到 streak=7 → `🏆 解锁成就「一周之约」` 气泡出现
- 设置面板 → 任务·亲密度页 → 本周任务 3 行渲染、成就徽章墙 8 格（1 个点亮）、称号下拉可选「一周之约」→ 佩戴 → 面板标题变「🐾 设置 · 一周之约」
- 投食 → interact 计数 +1（面板重开可见）
- 还原存档

- [x] **Step 3: 更新主计划文档 + 勾选本计划**

`docs/plans/2026-08-17-smart-companion-redesign.md` 追加 P8 完成记录；本文件勾选。

- [x] **Step 4: Commit 收尾**

```bash
git add docs/plans/2026-08-17-smart-companion-redesign.md docs/superpowers/plans/2026-08-19-p8-weekly-achievements.md
git commit -m "docs: P8 完成记录"
```

---

## 附：执行提示

- Task 1-7 强顺序；Task 4 存档有「并入 daily_quests 区块」的简化决策（较设计文档的独立 achievements section 更简单，键不冲突）——执行时按 Task 4 内说明统一
- Task 2 的 `_week_key` 变量/函数重名陷阱已标注（变量用 `_current_week`）
- 面板标题 Label 提成员变量（Task 7 Step 2 注意事项）在改 `_build_layout` 时一并做
- P7 教训复用：无 await、删函数查孤儿、warning_ignore 贴行
- 每任务 headless 冒烟，MCP 端到端只做 Task 8 一次
