# P9 离线成长（正向结算）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 读档时一次性正向结算离线时间——猫睡觉补精力，离线 ≥1 小时用性格化分档台词迎接；短离线行为不变。

**Architecture:** 纯静态函数 `OfflineSettlement.settle(elapsed, energy, personality)` 返回 `{energy_gain, welcome_tier, line}`；main 在猫/气泡/SMART 就绪之后、`session_resume` 之前调用；长离线跳过 `session_resume` 以免与 SMART `welcome_back` 叠句。

**Tech Stack:** Godot 4.7 / GDScript；测试 headless tscn 断言式；端到端 Godot MCP。

**设计文档:** `docs/superpowers/specs/2026-08-19-p9-offline-growth-design.md`

---

## 执行前置

- `"$GODOT"` = `/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- 既有 13 套 348 断言；本计划新增第 14 套 `test_offline_settlement`（约 12 断言）
- **已核实代码事实**：
  - `meta.saved_at` 读写已四点贯通（save_manager.gd:17/69/123/186）；`main.gd:86` 已读 `meta`
  - `main.gd:128` `_record_smart_event("session_resume")` 在 `_setup_smart_pet_controller` / `smart_line_bubble` / `_setup_daily_quests` 之后——结算插在 127 与 128 之间
  - `cat.behavior_system.modify_energy(delta)` 内部 `clamp(0, 100)`（cat_behavior_system.gd:66-68）
  - 性格在 `settings["personality"]`（load_data 后的 settings 字典，main.gd:88）
  - `ENERGY_RECOVERY = 2.0/秒` **不要用**（在线睡觉瞬时速率；离线按该值 1 小时瞬间满）
  - P7 教训：测试禁 `await`；P8 教训：服务先于会触发 save 的面板
  - 首次启动 `saved_at=0` → elapsed 当 0 → 无仪式，不与 FirstGuide 抢气泡

## 文件结构总览

- Task 1 — OfflineSettlement 纯函数 + 测试
- Task 2 — main 接线（补能 + 气泡 + 跳过 session_resume）
- Task 3 — 全量回归 + MCP 端到端 + 文档收尾

---

### Task 1: OfflineSettlement 纯函数

**Files:**
- Create: `components/engagement/offline_settlement.gd`
- Create: `tests/test_offline_settlement.gd` + `tests/test_offline_settlement.tscn`

- [ ] **Step 1: 写失败测试 tests/test_offline_settlement.gd**

```gdscript
extends Node

## P9 离线正向结算测试

const SettlementScript = preload("res://components/engagement/offline_settlement.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	_test_short_offline_noop()
	_test_hourly_gain_and_cap()
	_test_welcome_tiers()
	_test_personality_lines()
	_test_negative_elapsed()
	_print_summary()
	get_tree().quit(0 if _failed == 0 else 1)

func _test_short_offline_noop() -> void:
	# <5 分钟：无增益无台词
	var r: Dictionary = SettlementScript.settle(120, 50.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", -1.0)), 0.0), "short_zero_gain")
	_assert_equal(int(r.get("welcome_tier", -1)), 0, "short_tier0")
	_assert_equal(String(r.get("line", "x")), "", "short_no_line")

func _test_hourly_gain_and_cap() -> void:
	# 1 小时 energy=50 → +8, tier=1
	var r: Dictionary = SettlementScript.settle(3600, 50.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", 0.0)), 8.0), "1h_gain_8")
	_assert_equal(int(r.get("welcome_tier", 0)), 1, "1h_tier1")
	# 12 小时 energy=80 → 理论 +96，封顶只补 20
	r = SettlementScript.settle(12 * 3600, 80.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", 0.0)), 20.0), "cap_to_100")
	# 不满整小时零头不计：3599 秒仍 0 增益（且 <1h 无仪式）
	r = SettlementScript.settle(3599, 50.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", -1.0)), 0.0), "partial_hour_no_gain")

func _test_welcome_tiers() -> void:
	_assert_equal(int(SettlementScript.settle(3600, 50.0, "tsundere").get("welcome_tier", 0)), 1, "tier_1h")
	_assert_equal(int(SettlementScript.settle(25 * 3600, 50.0, "tsundere").get("welcome_tier", 0)), 2, "tier_1d")
	_assert_equal(int(SettlementScript.settle(73 * 3600, 50.0, "tsundere").get("welcome_tier", 0)), 3, "tier_3d")

func _test_personality_lines() -> void:
	var tsun: String = String(SettlementScript.settle(3600, 50.0, "tsundere").get("line", ""))
	var gent: String = String(SettlementScript.settle(3600, 50.0, "gentle").get("line", ""))
	var play: String = String(SettlementScript.settle(3600, 50.0, "playful").get("line", ""))
	_assert_true(not tsun.is_empty() and not gent.is_empty() and not play.is_empty(), "lines_nonempty")
	_assert_true(tsun != gent and gent != play and tsun != play, "lines_differ")
	# 未知性格走傲娇
	var unk: String = String(SettlementScript.settle(3600, 50.0, "unknown").get("line", ""))
	_assert_equal(unk, tsun, "unknown_falls_to_tsundere")
	# 三天档台词不同于一小时档
	var long_line: String = String(SettlementScript.settle(73 * 3600, 50.0, "tsundere").get("line", ""))
	_assert_true(long_line != tsun and not long_line.is_empty(), "tier3_differs")

func _test_negative_elapsed() -> void:
	var r: Dictionary = SettlementScript.settle(-100, 50.0, "tsundere")
	_assert_true(is_equal_approx(float(r.get("energy_gain", -1.0)), 0.0), "negative_zero_gain")
	_assert_equal(int(r.get("welcome_tier", -1)), 0, "negative_tier0")

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
	print("========== offline_settlement tests ==========")
	print("passed: %d" % _passed)
	print("failed: %d" % _failed)
	for f in _failures:
		print("  FAIL: " + f)
```

- [ ] **Step 2: 创建 tests/test_offline_settlement.tscn**

```text
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/test_offline_settlement.gd" id="1"]

[node name="OfflineSettlementTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 3: 跑测试确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_offline_settlement.tscn`
Expected: FAIL（offline_settlement.gd 不存在，Parse Error）

- [ ] **Step 4: 实现 components/engagement/offline_settlement.gd**

```gdscript
class_name OfflineSettlement
extends RefCounted

## P9 离线正向结算：纯静态函数，不挂节点
## 你不在时猫在睡觉——回来补精力 + 按离线时长分档迎接（零惩罚）

const MIN_ELAPSED_SEC := 300          # 5 分钟内关开不结算
const HOUR_SEC := 3600
const DAY_SEC := 86400
const ENERGY_PER_HOUR := 8.0
const ENERGY_CAP := 100.0
const TIER_1H := 3600
const TIER_1D := 86400
const TIER_3D := 3 * 86400

## personality → {tier: line}；未知性格走 tsundere
const LINES := {
	"tsundere": {
		1: "哼，可算回来了。",
		2: "一天不见，还记得我？",
		3: "以为你不回来了呢……",
	},
	"gentle": {
		1: "欢迎回来。",
		2: "好久不见，我好想你。",
		3: "等了你好久，还好你回来了。",
	},
	"playful": {
		1: "你回来啦！",
		2: "你终于回来啦你回来啦！",
		3: "呜哇你去哪了！想死我了！",
	},
}

static func settle(elapsed_sec: int, energy_now: float, personality: String) -> Dictionary:
	## 返回 {energy_gain: float, welcome_tier: int, line: String}
	if elapsed_sec < 0:
		elapsed_sec = 0
	if elapsed_sec < MIN_ELAPSED_SEC:
		return {"energy_gain": 0.0, "welcome_tier": 0, "line": ""}
	var hours := int(elapsed_sec / HOUR_SEC)
	var raw_gain := float(hours) * ENERGY_PER_HOUR
	var room := maxf(ENERGY_CAP - energy_now, 0.0)
	var gain := minf(raw_gain, room)
	var tier := 0
	if elapsed_sec >= TIER_3D:
		tier = 3
	elif elapsed_sec >= TIER_1D:
		tier = 2
	elif elapsed_sec >= TIER_1H:
		tier = 1
	var persona := personality if LINES.has(personality) else "tsundere"
	var line := ""
	if tier > 0:
		line = String(LINES[persona].get(tier, ""))
	return {"energy_gain": gain, "welcome_tier": tier, "line": line}
```

注意：`int(elapsed_sec / HOUR_SEC)` 是整数除法——贴一行 `@warning_ignore("integer_division")` 在该 `var hours` 上一行（P7 教训：注解必须紧贴目标语句）。

- [ ] **Step 5: 跑测试通过**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_offline_settlement.tscn`
Expected: `passed: 14  failed: 0`

- [ ] **Step 6: Commit**

```bash
git add components/engagement/offline_settlement.gd tests/test_offline_settlement.gd tests/test_offline_settlement.tscn tests/test_offline_settlement.gd.uid 2>/dev/null || git add components/engagement/offline_settlement.gd tests/test_offline_settlement.gd tests/test_offline_settlement.tscn
git commit -m "feat: 离线正向结算纯函数与测试"
```

---

### Task 2: main 接线

**Files:**
- Modify: `main.gd`

- [ ] **Step 1: `_ready` 中 session_resume 前插入结算**

`main.gd:127` `_setup_quick_action_menu()` 之后、`_record_smart_event("session_resume")` 之前插入：

```gdscript
	var skip_resume := _apply_offline_settlement(meta, settings)
	if not skip_resume:
		_record_smart_event("session_resume")
```

删除原 128 行无条件 `_record_smart_event("session_resume")`。

文件头 preload 区（`DAILY_QUEST_SCRIPT` 附近）加：

```gdscript
const OFFLINE_SETTLEMENT_SCRIPT := preload("res://components/engagement/offline_settlement.gd")
```

在 `_setup_daily_quests` 附近加函数：

```gdscript
func _apply_offline_settlement(meta: Dictionary, settings: Dictionary) -> bool:
	## P9：读档后一次性正向结算。返回 true = 已播回归仪式，跳过 session_resume
	var saved_at := int(meta.get("saved_at", 0))
	var elapsed := 0
	if saved_at > 0:
		elapsed = int(Time.get_unix_time_from_system()) - saved_at
	var energy_now := 80.0
	if cat and cat.behavior_system:
		energy_now = cat.behavior_system.energy
	var personality := String(settings.get("personality", "tsundere"))
	var result: Dictionary = OFFLINE_SETTLEMENT_SCRIPT.settle(elapsed, energy_now, personality)
	var gain := float(result.get("energy_gain", 0.0))
	if gain > 0.0 and cat and cat.behavior_system:
		cat.behavior_system.modify_energy(gain)
	var tier := int(result.get("welcome_tier", 0))
	var line := String(result.get("line", ""))
	if tier >= 1 and not line.is_empty():
		if cat and smart_line_bubble:
			smart_line_bubble.show_line(line, cat.global_position, _cached_screen_size)
		if cat and cat.has_method("play_animation"):
			cat.play_animation("tail_wag")
		return true
	return false
```

- [ ] **Step 2: headless 冒烟**

Run: `timeout 20 "$GODOT" --headless --path . res://main.tscn 2>&1 | grep -E "启动成功|SCRIPT ERROR|Parse" | head -4`
Expected: `桌面宠物猫启动成功`，无 SCRIPT ERROR（短离线/首次启动走 skip_resume=false，session_resume 仍发）

- [ ] **Step 3: 回归两套**

```bash
timeout 90 "$GODOT" --headless --path . res://tests/test_offline_settlement.tscn && \
timeout 90 "$GODOT" --headless --path . res://tests/test_presence_level.tscn
```
Expected: 双绿（presence 含 welcome_back 用例，短离线路径未改）

- [ ] **Step 4: Commit**

```bash
git add main.gd
git commit -m "feat: 启动离线结算补能与分档迎接"
```

---

### Task 3: 全量回归 + MCP 端到端 + 文档收尾

- [ ] **Step 1: 14 套全量测试**

```bash
for t in test_behavior_system test_focus_session_mode test_sprite_manifest_loader test_objective_system test_activity_classifier test_foreground_app_monitor test_focus_charge_engine test_smart_modules test_bond_system test_presence_level test_first_guide test_daily_quests test_ui_theme test_offline_settlement; do
  echo "=== $t ==="
  timeout 90 "$GODOT" --headless --path . res://tests/$t.tscn 2>&1 | grep -E "passed:|failed:|通过:" | tail -2
done
```
Expected: 全绿；offline_settlement ≈14；总计 ≈362

- [ ] **Step 2: MCP 端到端**

- 备份 `Desktop Pet Cat/save_data.cfg`
- 把 `saved_at` 改成当前 unix - 7200（2 小时前）→ `run_project` → 气泡应是档 1 台词（傲娇默认「哼，可算回来了。」），无 SCRIPT ERROR
- `stop_project`；把 `saved_at` 改成当前 unix - 30 → 启动无新仪式（短离线），`[SMART/policy] 哼，终于想起我了。` 类 welcome_back 仍可出现
- 还原备份

- [ ] **Step 3: 勾选本计划 + 主文档追加 P9 完成记录**

`docs/plans/2026-08-17-smart-companion-redesign.md` 末尾追加 P9 完成记录（对齐 P8 格式）。

- [ ] **Step 4: Commit 收尾**

```bash
git add docs/plans/2026-08-17-smart-companion-redesign.md docs/superpowers/plans/2026-08-19-p9-offline-growth.md
git commit -m "docs: P9 完成记录"
```

---

## 附：执行提示

- Task 1-2 强顺序；Task 3 依赖接线完成
- `integer_division` 警告注解必须紧贴 `var hours` 那一行
- 首次启动 saved_at=0 走 elapsed=0，不与 FirstGuide 抢气泡
- presence 的 welcome_back 用例依赖 session_resume——短离线路径必须仍发该事件（Task 2 回归专门覆盖）
