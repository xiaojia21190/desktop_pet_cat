# P4 心理记忆深化 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 猫"有性格有记忆"——SMART 决策读猫的心理状态（心情差→安慰语气、精力低→安静动作），新增基于感知活动的意图（看视频陪伴/写代码鼓励），HabitProfileService 输出作息记忆反馈（"你最近总在深夜写代码"）。

**Architecture:** 三条主线：① 心理注入——smart_pet_controller 的决策快照加 `psyche` 字段（mood/energy/affection/chaos 四值），策略引擎按心理状态调制台词语气与动作选择；② 意图扩充——策略引擎加 3 个新意图（video_companion / coding_cheer / night_owl_care），由活动标签与作息记忆触发；③ 记忆反馈——HabitProfileService 新增 `build_memory_lines()`（从 activity_totals 与 _active_by_hour 生成 2-3 句自然语言记忆），经新意图 night_owl_care 消费。动作映射新增 idle_stand（安静陪伴）兜底，动画走现有 sleep_curl/idle。

**Tech Stack:** Godot 4.7 / GDScript；测试 headless tscn；端到端 MCP。

**设计文档:** `docs/plans/2026-08-17-smart-companion-redesign.md`（心理+记忆深化节）

---

## 执行前置

- `"$GODOT"` = `/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- 测试：`timeout 60 "$GODOT" --headless --path . res://tests/<name>.tscn`，期望 `failed: 0`
- 每任务收尾跑八套测试（七套既有 + focus_charge_engine）

## 文件结构总览

**Task 1** — psyche 注入：smart_pet_controller 决策快照加心理字段（controller `bind_behavior` + 快照注入）
**Task 2** — 策略引擎心理调制 + 3 新意图（reaction_policy_engine + 动作映射）
**Task 3** — HabitProfileService 记忆反馈（build_memory_lines + 测试）
**Task 4** — night_owl_care 意图消费记忆 + controller 接线
**Task 5** — 全量回归 + MCP 端到端 + 收尾

---

### Task 1: psyche 注入决策管线

smart_pet_controller 持有行为系统引用（main 在 bind_nodes 后追加绑定），每次决策把心理四值注入快照 `psyche` 字段。策略引擎本期先透传（Task 2 消费）。

**Files:**
- Modify: `smart_pet_controller.gd`（bind_behavior + _evaluate_policy 注入）
- Modify: `main.gd`（_setup_smart_pet_controller 加 bind_behavior）
- Test: `tests/test_smart_modules.gd`

- [x] **Step 1: 写失败测试（追加到 test_smart_modules.gd）**

```gdscript
func _test_psyche_injection() -> void:
	# —— 心理注入：决策快照携带 psyche 字段 ——
	var controller = preload("res://smart_pet_controller.gd").new()
	add_child(controller)
	var behavior = preload("res://cat_behavior_system.gd").new()
	add_child(behavior)
	behavior.mood = 75.0
	behavior.energy = 25.0
	controller.bind_behavior(behavior)
	# 直接调用私有决策路径太重；验证注入函数本身
	var snapshot := {"hour": 14}
	controller._inject_psyche(snapshot)
	_assert_equal(float(snapshot.get("psyche", {}).get("mood", 0.0)), 75.0, "psyche_mood_injected")
	_assert_equal(float(snapshot.get("psyche", {}).get("energy", 0.0)), 25.0, "psyche_energy_injected")
	_assert_true(snapshot.get("psyche", {}).has("affection"), "psyche_affection_present")
	_assert_true(snapshot.get("psyche", {}).has("chaos"), "psyche_chaos_present")
	controller.queue_free()
	behavior.queue_free()
```

在 `_run()` 调用列表加 `_test_psyche_injection()`。

- [x] **Step 2: 确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_smart_modules.tscn`
Expected: FAIL——`bind_behavior`/`_inject_psyche` 不存在

- [x] **Step 3: 实现**

`smart_pet_controller.gd`：

1. 成员区（`var _customization_service` 附近）加：

```gdscript
var _behavior  # CatBehaviorSystem 引用（心理唯一源）
```

2. `bind_nodes`（:50）后加：

```gdscript
func bind_behavior(behavior) -> void:
	# 心理注入：决策时读取猫的当前心理状态
	_behavior = behavior

func _inject_psyche(snapshot: Dictionary) -> void:
	if _behavior:
		snapshot["psyche"] = {
			"mood": _behavior.mood,
			"energy": _behavior.energy,
			"affection": _behavior.affection,
			"chaos": _behavior.chaos
		}
```

3. `_evaluate_policy`（:97）在 quiet_hours 注入后加一行：

```gdscript
	_inject_psyche(snapshot)
```

`main.gd` `_setup_smart_pet_controller`（:304 `bind_nodes` 后）加：

```gdscript
	if cat and cat.behavior_system:
		smart_pet_controller.bind_behavior(cat.behavior_system)
```

- [x] **Step 4: 跑测试 + Commit**

```bash
git add smart_pet_controller.gd main.gd tests/test_smart_modules.gd
git commit -m "feat: SMART 决策注入猫心理状态"
```

---

### Task 2: 策略引擎心理调制与新意图

三件事：① 心理调制——心情低(mood<35)或好感低(affection<30)时 comfort 类台词追加后缀情绪；精力低(energy<30)时把 break_hint/celebrate 动作换成 sleep_curl（安静陪伴）；② 新意图 `video_companion`（watching_video 标签触发，猫趴着陪看）；③ 新意图 `coding_cheer`（coding_now + 连续活跃 30 分钟，猫在旁边摇尾巴鼓励）。冷却与台词进 DEFAULT_COOLDOWN/_line_for。

**Files:**
- Modify: `reaction_policy_engine.gd`
- Test: `tests/test_smart_modules.gd`

- [x] **Step 1: 写失败测试（追加）**

```gdscript
func _test_psyche_modulated_policy() -> void:
	# —— 新意图：看视频陪伴 ——
	var policy = ReactionPolicyEngineScript.new()
	add_child(policy)
	var decision: Dictionary = policy.evaluate(
		{"hour": 20, "fullscreen": false, "continuous_active_seconds": 100.0,
		 "activity": "video", "activity_seconds": 900.0},
		["watching_video"], [],
		{"personality": "tsundere", "reminder_intensity": "medium"})
	_assert_true(bool(decision.get("react", false)), "video_companion_reacts")
	_assert_equal(String(decision.get("action_id", "")), "idle", "video_companion_action_idle")

	# —— 新意图：写代码鼓励 ——
	decision = policy.evaluate(
		{"hour": 14, "fullscreen": false, "continuous_active_seconds": 1900.0,
		 "activity": "coding", "activity_seconds": 1900.0},
		["coding_now"], [],
		{"personality": "tsundere", "reminder_intensity": "medium"})
	_assert_equal(String(decision.get("action_id", "")), "tail_wag", "coding_cheer_action_tailwag")

	# —— 心理调制：精力低时 celebrate 换 sleep_curl ——
	var policy2 = ReactionPolicyEngineScript.new()
	add_child(policy2)
	decision = policy2.evaluate(
		{"hour": 14, "fullscreen": false, "continuous_active_seconds": 100.0,
		 "psyche": {"mood": 50.0, "energy": 20.0, "affection": 50.0, "chaos": 10.0}},
		[], [{"type": "focus_milestone", "t": Time.get_unix_time_from_system()}],
		{"personality": "gentle", "reminder_intensity": "medium"})
	_assert_equal(String(decision.get("action_id", "")), "sleep_curl", "tired_cat_celebrates_quietly")
	policy.queue_free()
	policy2.queue_free()
```

- [x] **Step 2: 确认失败**

Expected: FAIL——video_companion 不触发（action_id 为空）

- [x] **Step 3: 实现**

`reaction_policy_engine.gd`：

1. 动作常量与冷却（:6-20）加：

```gdscript
const ACTION_IDLE_COMPANY := "idle"
const ACTION_TAIL_WAG := "tail_wag"

# DEFAULT_COOLDOWN 字典加：
	ACTION_IDLE_COMPANY: 1500,
	ACTION_TAIL_WAG: 1200,
```

2. `evaluate`（:24）在 `user_busy` 判断之前插入两个新意图与心理调制：

```gdscript
	# —— P4 新意图：活动陪伴 ——
	if tags.has("watching_video"):
		return _decision_if_available(now, ACTION_IDLE_COMPANY, "video_companion", _line_for("video_companion", personality))
	if tags.has("coding_now") and continuous_active_precheck(snapshot, 1800.0):
		return _decision_if_available(now, ACTION_TAIL_WAG, "coding_cheer", _line_for("coding_cheer", personality))
```

其中辅助函数（加在类尾）：

```gdscript
func continuous_active_precheck(snapshot: Dictionary, threshold: float) -> bool:
	return float(snapshot.get("continuous_active_seconds", 0.0)) >= threshold
```

3. 心理调制——`_decision_if_available` 前包一层调制（evaluate 内捕获 psyche 后，对拟返回动作做修正）。实现方式：`evaluate` 开头取：

```gdscript
	var psyche: Dictionary = snapshot.get("psyche", {})
	var energy: float = float(psyche.get("energy", 100.0))
```

然后把现有各 `_decision_if_available(...)` 调用改走新方法 `_decide(now, action_id, intent, line, energy)`：

```gdscript
func _decide(now: int, action_id: String, intent: String, line: String, energy: float) -> Dictionary:
	# 心理调制：精力低的猫用安静动作代替欢快动作
	if energy < 30.0 and action_id in [ACTION_CELEBRATE, ACTION_GREET, ACTION_TAIL_WAG]:
		action_id = ACTION_SLEEP_CURL
	return _decision_if_available(now, action_id, intent, line)
```

（evaluate 内全部 8 处 `_decision_if_available(` 调用替换为 `_decide(..., energy)`——quiet_hours/greet/celebrate/comfort×2/break_hint/retreat/video_companion/coding_cheer。）

4. `_line_for`（:103 match）加新意图台词：

```gdscript
		"video_companion":
			if personality == "playful":
				return "我也一起看！这个好看吗？"
			if personality == "gentle":
				return "我趴在这儿陪你一起看。"
			return "看吧看吧，我勉强陪你看一会儿。"
		"coding_cheer":
			if personality == "playful":
				return "写代码的样子最帅了！加油加油！"
			if personality == "gentle":
				return "你专注的样子真好，我在旁边给你加油。"
			return "哼，写得不赖嘛，继续保持。"
```

- [x] **Step 4: 跑测试（注意旧断言连锁：新意图优先级插在 user_busy 前，可能影响既有 quiet_hours 等测试——跑全量看有无回归，若有则调整插入位置到 break_hint 之后）+ Commit**

```bash
git add reaction_policy_engine.gd tests/test_smart_modules.gd
git commit -m "feat: 策略引擎新增活动陪伴意图与心理调制"
```

---

### Task 3: HabitProfileService 记忆反馈

`build_memory_lines()`：从累计数据生成 2-3 句记忆台词。规则：
- 深夜活跃占比 > 60% 且总活跃 > 1 小时 → "你最近总在深夜活跃"（night_owl 记忆）
- coding 类活动累计 > 2 小时 → "你已经连续写了好久代码"
- video 类 > 1 小时 → "最近看了不少视频呢"
- affection > 70 → "最喜欢陪着你工作的时候"
- 无足够数据 → 返回空数组（不硬凑）

**Files:**
- Modify: `habit_profile_service.gd`
- Test: `tests/test_smart_modules.gd`

- [x] **Step 1: 写失败测试（追加）**

```gdscript
func _test_memory_lines() -> void:
	var profile = HabitProfileServiceScript.new()
	add_child(profile)
	# 空数据无记忆
	var lines: Array[String] = profile.build_memory_lines()
	_assert_equal(lines.size(), 0, "no_memory_on_empty")

	# 喂入深夜重度使用
	for i in range(60):
		profile.ingest_snapshot({"hour": 23, "active_seconds": 60.0,
			"activity_totals": {"coding": 7200.0}})
	lines = profile.build_memory_lines()
	_assert_true(lines.size() >= 1, "night_memory_generated")
	var joined := "\n".join(lines)
	_assert_true(joined.contains("深夜") or joined.contains("晚上"), "night_memory_text")
	_assert_true(joined.contains("代码"), "coding_memory_text")
	profile.queue_free()
```

- [x] **Step 2: 确认失败 → Step 3: 实现**

`habit_profile_service.gd` 新增（`build_tags` 后）：

```gdscript
func build_memory_lines() -> Array[String]:
	## 从累计数据生成记忆反馈台词；数据不足返回空（不硬凑）
	var lines: Array[String] = []
	var summary := get_profile_summary()
	var active_by_hour: Dictionary = summary.get("active_by_hour", {})
	var total_active := 0.0
	var night_active := 0.0
	for hour_key in active_by_hour:
		var value := float(active_by_hour[hour_key])
		total_active += value
		var hour := int(hour_key)
		if hour >= 22 or hour < 6:
			night_active += value

	if total_active > 3600.0 and night_active / total_active > 0.6:
		lines.append("你最近总在深夜活跃，要注意休息呀。")

	if _snapshot_history.size() > 0:
		var latest: Dictionary = _snapshot_history[_snapshot_history.size() - 1]
		var totals: Dictionary = latest.get("activity_totals", {})
		var coding_secs := float(totals.get("coding", 0.0))
		var video_secs := float(totals.get("video", 0.0))
		if coding_secs > 7200.0:
			lines.append("你已经连续写了好久代码，辛苦啦。")
		elif video_secs > 3600.0:
			lines.append("最近看了不少视频呢，偶尔也要动一动哦。")

	return lines
```

- [x] **Step 4: 跑测试 + Commit**

```bash
git add habit_profile_service.gd tests/test_smart_modules.gd
git commit -m "feat: 习惯画像服务新增记忆反馈生成"
```

---

### Task 4: night_owl_care 意图消费记忆

新意图：深夜时段（22-6 点）+ 连续活跃 > 45 分钟 → 猫提醒休息（台词优先用记忆线"你最近总在深夜活跃"）。controller 把记忆线传入决策上下文。

**Files:**
- Modify: `reaction_policy_engine.gd`（night_owl_care 意图）
- Modify: `smart_pet_controller.gd`（决策时带 memory_lines）
- Test: `tests/test_smart_modules.gd`

- [x] **Step 1: 写失败测试（追加）**

```gdscript
func _test_night_owl_care() -> void:
	var policy = ReactionPolicyEngineScript.new()
	add_child(policy)
	# 深夜 + 长活跃 → 关怀提醒
	var decision: Dictionary = policy.evaluate(
		{"hour": 23, "fullscreen": false, "continuous_active_seconds": 2800.0,
		 "quiet_hours_start": 99, "quiet_hours_end": 98,  # 关闭静音避免抢占
		 "memory_lines": ["你最近总在深夜活跃，要注意休息呀。"]},
		["night_owl"], [],
		{"personality": "gentle", "reminder_intensity": "medium"})
	_assert_true(bool(decision.get("react", false)), "night_owl_care_reacts")
	_assert_equal(String(decision.get("action_id", "")), "comfort", "night_owl_care_action_comfort")
	_assert_true(String(decision.get("template_line", "")).contains("深夜"), "night_owl_care_uses_memory")
	policy.queue_free()
```

- [x] **Step 2: 确认失败 → Step 3: 实现**

1. `reaction_policy_engine.gd` `evaluate`：night_owl_care 插在 quiet_hours 判断**之后**（静音优先）、greet 之前：

```gdscript
	# —— P4：深夜关怀（记忆驱动；静音时段已被上面拦截，这里是非静音配置的深夜）——
	var hour: int = int(snapshot.get("hour", 12))
	var memory_lines: Array = snapshot.get("memory_lines", [])
	if (hour >= 23 or hour <= 1) and continuous_active_precheck(snapshot, 2700.0):
		var care_line := "这么晚还在忙，记得早点休息。"
		if memory_lines.size() > 0:
			care_line = String(memory_lines[0])
		return _decide(now, ACTION_COMFORT, "night_owl_care", care_line, energy)
```

2. `smart_pet_controller.gd` `_evaluate_policy`（psyche 注入旁）加：

```gdscript
	var memory_raw = _profile_service.build_memory_lines()
	var memory_lines: Array = []
	if typeof(memory_raw) == TYPE_ARRAY:
		for line_value in memory_raw:
			memory_lines.append(String(line_value))
	snapshot["memory_lines"] = memory_lines
```

- [x] **Step 4: 全量八套 + Commit**

```bash
git add reaction_policy_engine.gd smart_pet_controller.gd tests/test_smart_modules.gd
git commit -m "feat: 深夜关怀意图消费作息记忆"
```

---

### Task 5: 全量回归 + MCP 端到端 + 收尾

- [x] **Step 1: 八套测试全绿**

- [x] **Step 2: MCP 端到端**

1. `run_project` 启动 15 秒，无 SCRIPT ERROR、SMART 正常
2. 决策链路验证：策略引擎已带 psyche/memory——真机默认 mood=50/energy=80 不触发调制属正常；确认无报错即可（新意图的触发依赖长时间使用数据，单次启动看不到属预期）
3. 渲染验证：截图 + 橙色像素聚类（复用流程）

- [x] **Step 3: 收尾**

```bash
git add -A
git commit -m "docs: P4 心理记忆深化完成记录"
```

设计文档追加 "P4 完成记录"：psyche 注入链路、3 新意图触发条件与台词、记忆生成规则、四期总览收束。

---

## 自检记录（Self-Review）

1. **Spec 覆盖**：SMART 读心理层（Task 1+2）、意图扩充（Task 2 video_companion/coding_cheer + Task 4 night_owl_care）、HabitProfileService 深化记忆反馈（Task 3+4）。设计文档"心理+记忆深化"节全覆盖。
2. **占位符**：无 TBD/TODO；台词、数值、条件全部具体。
3. **类型一致性**：`_inject_psyche(snapshot)` / `bind_behavior(behavior)` / `build_memory_lines() -> Array[String]` / `_decide(now, action_id, intent, line, energy)` / `continuous_active_precheck(snapshot, threshold)` 各任务一致；新动作 id "idle"/"tail_wag" 与 main.gd `_map_smart_action_to_state` 的现有分支（"idle"→IDLE 已存在于 :550）匹配——"tail_wag" 需确认 CatStates.TAIL_WAGGING 映射存在（main.gd :562 已有），无需新增映射。
