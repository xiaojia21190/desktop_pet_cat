# P2 感知升级 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 猫知道你在用什么应用——新增前台应用监测（进程名级、本地、默认关闭）、活动分类器、感知数据接入 SMART 管线、设置页"感知"分区与存档链路。

**Architecture:** 三件套组合：`ForegroundAppMonitor`（Windows 下用 PowerShell 子进程每 N 秒取前台进程名，失败静默降级为 "unknown"）→ `ActivityClassifier`（纯函数：进程名 → 活动类别，用户可扩展规则表）→ `ContextCollector` 扩展（快照新增 `foreground_app`/`activity`/`activity_seconds` 字段）。SMART 管线零改动即可消费新字段（tags 构建加"看视频/写代码"标签）。隐私三原则：默认关闭、仅进程名不读窗口标题、数据不出本地（LLM 只收类别不收进程名）。

**Tech Stack:** Godot 4.7 / GDScript；`OS.execute("powershell.exe", ...)`；测试沿用 headless tscn 模式。

**设计文档:** `docs/plans/2026-08-17-smart-companion-redesign.md`（感知升级节）

---

## 执行前置

- Godot 可执行文件：`"$GODOT"` = `/d/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe`
- 测试命令模板：`timeout 60 "$GODOT" --headless --path . res://tests/<name>.tscn`，期望 `failed: 0`
- 每任务收尾跑全部六套测试：`test_behavior_system` / `test_focus_session_mode` / `test_smart_modules` / `test_sprite_manifest_loader` / `test_objective_system` / 本计划新增套件
- 新增 headless class_name 缓存问题：新建 `.gd` 带 `class_name` 后必须先 `timeout 90 "$GODOT" --headless --path . --import` 再跑测试，否则报 "Could not find type"

## 文件结构总览

**Task 1** — 活动分类器 `components/perception/activity_classifier.gd`（纯逻辑 + 8 测试）
**Task 2** — 前台应用监测 `components/perception/foreground_app_monitor.gd`（Windows 实现 + 可注入源 + 6 测试）
**Task 3** — ContextCollector 扩展（快照 3 新字段 + 分类规则注入 + 4 测试）
**Task 4** — 感知开关与存档链路（save_manager + customization_service + smart_pet_controller 接线）
**Task 5** — 设置页"感知"分区（settings_panel.tscn 加控件 + gd 读写）
**Task 6** — SMART 管线消费感知（habit_profile_service 加活动标签 + main.gd 启动接线 + MCP 端到端）

---

### Task 1: ActivityClassifier 活动分类器

纯静态函数：进程名 → 类别。类别集合：`coding` / `browsing` / `video` / `social` / `game` / `music` / `reading` / `office` / `design` / `other`。内置默认规则（可被用户规则覆盖：用户规则优先匹配）。

**Files:**
- Create: `components/perception/activity_classifier.gd`
- Create: `tests/test_activity_classifier.gd` + `tests/test_activity_classifier.tscn`

- [ ] **Step 1: 写失败测试**

`tests/test_activity_classifier.gd`：

```gdscript
extends Node

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	# 默认规则分类
	_assert_equal(ActivityClassifier.classify("Code.exe"), "coding", "vscode_coding")
	_assert_equal(ActivityClassifier.classify("godot"), "coding", "godot_coding")
	_assert_equal(ActivityClassifier.classify("chrome.exe"), "browsing", "chrome_browsing")
	_assert_equal(ActivityClassifier.classify("PotPlayerMini64.exe"), "video", "potplayer_video")
	_assert_equal(ActivityClassifier.classify("QQ.exe"), "social", "qq_social")
	_assert_equal(ActivityClassifier.classify("WeChat.exe"), "social", "wechat_social")
	_assert_equal(ActivityClassifier.classify("excel.exe"), "office", "excel_office")
	_assert_equal(ActivityClassifier.classify("totally_unknown_app"), "other", "unknown_other")

	# 大小写不敏感
	_assert_equal(ActivityClassifier.classify("CHROME.EXE"), "browsing", "case_insensitive")

	# 用户规则优先于默认规则
	var custom: Array[Dictionary] = [
		{"match": "mycompany", "activity": "coding"}
	]
	_assert_equal(ActivityClassifier.classify("MyCompanyIDE.exe", custom), "coding", "custom_rule_wins")
	_assert_equal(ActivityClassifier.classify("chrome.exe", custom), "browsing", "custom_not_break_default")

	# 默认规则可整体禁用（只留用户规则）
	_assert_equal(ActivityClassifier.classify("chrome.exe", custom, false), "other", "defaults_disabled")

	# 类别集合完整
	var cats := ActivityClassifier.CATEGORIES
	for expected in ["coding", "browsing", "video", "social", "game", "music", "reading", "office", "design", "other"]:
		_assert_true(cats.has(expected), "category_has_" + expected)

	_print_summary()
	get_tree().quit(1 if _failed > 0 else 0)

func _assert_true(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)

func _assert_equal(actual, expected, test_name: String) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	_failures.append("%s (actual=%s expected=%s)" % [test_name, str(actual), str(expected)])

func _print_summary() -> void:
	print("")
	print("========== activity_classifier tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		for name in _failures:
			print(" - ", name)
```

`tests/test_activity_classifier.tscn`：

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://tests/test_activity_classifier.gd" id="1"]

[node name="ActivityClassifierTest" type="Node"]
script = ExtResource("1")
```

- [ ] **Step 2: 运行确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_activity_classifier.tscn`
Expected: 挂起或报 "Could not find type ActivityClassifier"（先 kill 挂起进程）

- [ ] **Step 3: 实现分类器**

`components/perception/activity_classifier.gd`：

```gdscript
class_name ActivityClassifier
extends RefCounted

## 前台应用活动分类：进程名 → 活动类别。纯函数，无状态。
## 隐私边界：只处理进程名，永不接触窗口标题。

const CATEGORIES := [
	"coding", "browsing", "video", "social", "game",
	"music", "reading", "office", "design", "other"
]

# 默认规则：按进程名（小写包含匹配）归类。用户规则优先。
const DEFAULT_RULES := [
	{"match": "code", "activity": "coding"},
	{"match": "godot", "activity": "coding"},
	{"match": "devenv", "activity": "coding"},
	{"match": "idea", "activity": "coding"},
	{"match": "pycharm", "activity": "coding"},
	{"match": "webstorm", "activity": "coding"},
	{"match": "vim", "activity": "coding"},
	{"match": "neovide", "activity": "coding"},
	{"match": "terminal", "activity": "coding"},
	{"match": "windowsterminal", "activity": "coding"},
	{"match": "powershell", "activity": "coding"},
	{"match": "cmd", "activity": "coding"},
	{"match": "windsurf", "activity": "coding"},
	{"match": "cursor", "activity": "coding"},

	{"match": "chrome", "activity": "browsing"},
	{"match": "msedge", "activity": "browsing"},
	{"match": "firefox", "activity": "browsing"},
	{"match": "opera", "activity": "browsing"},
	{"match": "vivaldi", "activity": "browsing"},

	{"match": "potplayer", "activity": "video"},
	{"match": "vlc", "activity": "video"},
	{"match": "mpv", "activity": "video"},
	{"match": "bilibili", "activity": "video"},
	{"match": "iqiyi", "activity": "video"},
	{"match": "mpc-hc", "activity": "video"},
	{"match": "movies", "activity": "video"},

	{"match": "qq", "activity": "social"},
	{"match": "wechat", "activity": "social"},
	{"match": "dingtalk", "activity": "social"},
	{"match": "telegram", "activity": "social"},
	{"match": "discord", "activity": "social"},
	{"match": "slack", "activity": "social"},

	{"match": "steam", "activity": "game"},
	{"match": "epicgames", "activity": "game"},
	{"match": "game", "activity": "game"},

	{"match": "spotify", "activity": "music"},
	{"match": "cloudmusic", "activity": "music"},
	{"match": "qqmusic", "activity": "music"},
	{"match": "kugoo", "activity": "music"},
	{"match": "foobar2000", "activity": "music"},

	{"match": "sumatrapdf", "activity": "reading"},
	{"match": "acrobat", "activity": "reading"},
	{"match": "foxit", "activity": "reading"},
	{"match": "calibre", "activity": "reading"},

	{"match": "excel", "activity": "office"},
	{"match": "winword", "activity": "office"},
	{"match": "powerpnt", "activity": "office"},
	{"match": "onenote", "activity": "office"},
	{"match": "outlook", "activity": "office"},
	{"match": "wps", "activity": "office"},

	{"match": "photoshop", "activity": "design"},
	{"match": "illustrator", "activity": "design"},
	{"match": "figma", "activity": "design"},
	{"match": "blender", "activity": "design"},
	{"match": "clipstudio", "activity": "design"}
]

static func classify(process_name: String, custom_rules: Array[Dictionary] = [], use_defaults: bool = true) -> String:
	var normalized := process_name.to_lower().strip_edges()
	if normalized.is_empty():
		return "other"

	for rule in custom_rules:
		var match_key := String(rule.get("match", "")).to_lower()
		var activity := String(rule.get("activity", "other"))
		if not match_key.is_empty() and normalized.contains(match_key):
			return activity

	if use_defaults:
		for rule in DEFAULT_RULES:
			var match_key := String(rule.get("match", ""))
			var activity := String(rule.get("activity", "other"))
			if normalized.contains(match_key):
				return activity

	return "other"

static func normalize_rules(raw_rules: Array) -> Array[Dictionary]:
	## 存档里的规则数组（无类型）→ 强类型规则数组；非法项剔除
	var normalized: Array[Dictionary] = []
	for raw in raw_rules:
		if not (raw is Dictionary):
			continue
		var match_key := String(raw.get("match", "")).strip_edges()
		var activity := String(raw.get("activity", "")).strip_edges()
		if match_key.is_empty() or not CATEGORIES.has(activity):
			continue
		normalized.append({"match": match_key, "activity": activity})
	return normalized
```

- [ ] **Step 4: 刷新类缓存并跑测试**

Run: `timeout 90 "$GODOT" --headless --path . --import` 然后 `timeout 60 "$GODOT" --headless --path . res://tests/test_activity_classifier.tscn`
Expected: `passed: 14  failed: 0`

- [ ] **Step 5: Commit**

```bash
git add components/perception/activity_classifier.gd tests/test_activity_classifier.gd tests/test_activity_classifier.tscn
git commit -m "feat: 新增前台应用活动分类器"
```

---

### Task 2: ForegroundAppMonitor 前台应用监测

轮询前台进程名（Windows：PowerShell 一行命令），经注入的分类器回调输出 `{app, activity}`。**轮询与命令执行可注入**：测试用假源，不真跑 PowerShell。设计要点：
- 采集开关 `enabled`（默认 **false**，隐私优先）
- 轮询间隔 `poll_interval`（默认 2.0 秒），命令经 `_process` 计时触发
- `OS.execute` 阻塞主线程数毫秒可接受（设计文档已评估 <1ms）；失败/超时输出 `unknown`
- `OS.get_name() != "Windows"` 时自动禁用（macOS/Linux 留待后续）

**Files:**
- Create: `components/perception/foreground_app_monitor.gd`
- Create: `tests/test_foreground_app_monitor.gd` + `tests/test_foreground_app_monitor.tscn`

- [ ] **Step 1: 写失败测试**

`tests/test_foreground_app_monitor.gd`：

```gdscript
extends Node

const MonitorScript = preload("res://components/perception/foreground_app_monitor.gd")

var _passed: int = 0
var _failed: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var monitor = MonitorScript.new()
	add_child(monitor)

	# 默认关闭：不采集、快照为空
	_assert_true(not monitor.enabled, "disabled_by_default")
	_assert_equal(monitor.get_snapshot().get("app", ""), "", "no_app_when_disabled")

	# 注入假采集源：轮询产生快照
	var fake_source := FakeSource.new()
	fake_source.next_name = "Code.exe"
	monitor.set_source(fake_source)
	monitor.enabled = true
	monitor.poll_interval = 0.05
	await get_tree().create_timer(0.3).timeout
	var snap: Dictionary = monitor.get_snapshot()
	_assert_equal(String(snap.get("app", "")), "Code.exe", "fake_app_reported")
	_assert_equal(String(snap.get("activity", "")), "coding", "activity_classified")
	_assert_true(float(snap.get("activity_seconds", 0.0)) >= 0.0, "seconds_valid")

	# 切换应用后 activity_seconds 归零重计、历史保留
	fake_source.next_name = "chrome.exe"
	await get_tree().create_timer(0.2).timeout
	snap = monitor.get_snapshot()
	_assert_equal(String(snap.get("app", "")), "chrome.exe", "app_switch_detected")
	_assert_equal(String(snap.get("activity", "")), "browsing", "activity_switched")
	_assert_true(snap.has("history"), "history_present")

	# 采集源失败 → unknown 降级
	fake_source.fail_mode = true
	await get_tree().create_timer(0.2).timeout
	snap = monitor.get_snapshot()
	_assert_equal(String(snap.get("app", "")), "unknown", "failure_degrades_to_unknown")

	# 关闭后不再更新
	monitor.enabled = false
	fake_source.fail_mode = false
	fake_source.next_name = "potplayer.exe"
	await get_tree().create_timer(0.2).timeout
	_assert_equal(String(monitor.get_snapshot().get("app", "")), "unknown", "no_update_when_disabled")

	monitor.queue_free()
	_print_summary()
	get_tree().quit(1 if _failed > 0 else 1)

func _assert_true(condition: bool, test_name: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		_failures.append(test_name)

func _assert_equal(actual, expected, test_name: String) -> void:
	if actual == expected:
		_passed += 1
		return
	_failed += 1
	_failures.append("%s (actual=%s expected=%s)" % [test_name, str(actual), str(expected)])

func _print_summary() -> void:
	print("")
	print("========== foreground_app_monitor tests ==========")
	print("passed: ", _passed)
	print("failed: ", _failed)
	if not _failures.is_empty():
		for name in _failures:
			print(" - ", name)

class FakeSource:
	extends RefCounted
	var next_name := ""
	var fail_mode := false
	func query() -> String:
		return "unknown" if fail_mode else next_name
```

（注意：`get_tree().quit(1 if _failed > 0 else 1)` 最后一个参数应为 `0`，写测试时直接写对：`get_tree().quit(1 if _failed > 0 else 0)`）

`tests/test_foreground_app_monitor.tscn`（同 Task 1 结构，根节点名 ForegroundAppMonitorTest）。

- [ ] **Step 2: 运行确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_foreground_app_monitor.tscn`
Expected: 挂起（preload 不存在）——kill 后继续

- [ ] **Step 3: 实现监测器**

`components/perception/foreground_app_monitor.gd`：

```gdscript
class_name ForegroundAppMonitor
extends Node

## 前台应用监测：轮询前台进程名 → 活动分类 → 快照。
## 隐私：默认关闭；只取进程名（不读窗口标题）；数据仅本地消费。
## Windows 实现走 PowerShell；测试注入假源（set_source）。

signal foreground_app_changed(app_name: String, activity: String)

const MAX_HISTORY := 60
const UNKNOWN := "unknown"

@export var enabled: bool = false:
	set(value):
		enabled = value
		if not value:
			_current_app = ""
			_current_activity = ""
			_activity_seconds = 0.0
@export var poll_interval: float = 2.0

var _source  # 采集源：query() -> String（进程名），失败返回空
var _timer: float = 0.0
var _current_app := ""
var _current_activity := ""
var _activity_seconds: float = 0.0
var _last_poll_unix: int = 0
var _history: Array[Dictionary] = []  # [{app, activity, started_unix}]
var _custom_rules: Array[Dictionary] = []
var _use_default_rules := true

func _ready() -> void:
	if OS.get_name() == "Windows":
		_source = PowerShellSource.new()

func set_source(source) -> void:
	_source = source

func set_rules(custom_rules: Array[Dictionary], use_defaults: bool) -> void:
	_custom_rules = custom_rules
	_use_default_rules = use_defaults

func _process(delta: float) -> void:
	if not enabled or _source == null:
		return

	_activity_seconds += delta
	_timer += delta
	if _timer < poll_interval:
		return

	_timer = 0.0
	var app_name := _source.query()
	if app_name.is_empty():
		app_name = UNKNOWN

	if app_name != _current_app:
		_on_app_changed(app_name)

func get_snapshot() -> Dictionary:
	return {
		"app": _current_app,
		"activity": _current_activity,
		"activity_seconds": _activity_seconds,
		"history": _history.duplicate(true)
	}

func _on_app_changed(app_name: String) -> void:
	var now := Time.get_unix_time_from_system()
	if not _current_app.is_empty():
		_history.append({
			"app": _current_app,
			"activity": _current_activity,
			"started_unix": _last_poll_unix
		})
		if _history.size() > MAX_HISTORY:
			_history.pop_front()

	_current_app = app_name
	_current_activity = ActivityClassifier.classify(app_name, _custom_rules, _use_default_rules)
	_activity_seconds = 0.0
	_last_poll_unix = now
	foreground_app_changed.emit(app_name, _current_activity)

## Windows 前台进程采集：GetForegroundWindow → PID → 进程名。
## 只取进程名；不读窗口标题。
class PowerShellSource:
	extends RefCounted

	const PS_SCRIPT := "(Get-Process -Id (Get-CimInstance Win32_Process -Filter \"ProcessId=$((Get-CimInstance Win32_Process -Filter \"ProcessId=$ pid\").ParentProcessId)\").ProcessId).ProcessName"

	func query() -> String:
		# 简化可靠路径：appactivate 方式取前台窗口进程
		var script := "$add = Add-Type '[DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow();' -Name U32 -PassThru; " \
			+ "$hwnd = $add::GetForegroundWindow(); " \
			+ "$pid2 = (Get-Process | Where-Object { $_.MainWindowHandle -eq $hwnd }).Id; " \
			+ "if ($pid2) { (Get-Process -Id $pid2).ProcessName }"
		var output := []
		var exit_code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", script], output, true)
		if exit_code != 0 or output.is_empty():
			return ""
		return String(output[0]).strip_edges()
```

（**执行注意**：PowerShellSource 的 query 脚本以实际运行验证为准——Task 6 的 MCP 端到端会在真机跑通它；若 `Get-Process | Where-Object` 方案慢（遍历进程表），改用两段式：先 `GetForegroundWindow` 句柄，再单查。允许执行时微调脚本内容，但**不得**改接口 `query() -> String` 与隐私边界。）

- [ ] **Step 4: 刷新缓存并跑测试**

Run: `timeout 90 "$GODOT" --headless --path . --import` 然后 `timeout 60 "$GODOT" --headless --path . res://tests/test_foreground_app_monitor.tscn`
Expected: `passed: 9  failed: 0`

- [ ] **Step 5: Commit**

```bash
git add components/perception/foreground_app_monitor.gd tests/test_foreground_app_monitor.gd tests/test_foreground_app_monitor.tscn
git commit -m "feat: 新增前台应用监测组件"
```

---

### Task 3: ContextCollector 扩展感知字段

快照新增 `foreground_app` / `activity` / `activity_seconds`，由外部喂入（collector 不持有 monitor，保持无依赖）。同时新增活动类别秒数累计（本会话各类别用时），供 P4 记忆深化。

**Files:**
- Modify: `context_collector.gd`
- Test: `tests/test_smart_modules.gd`（追加用例）

- [ ] **Step 1: 写失败测试（追加到 test_smart_modules.gd 的 _run 尾部）**

在 `tests/test_smart_modules.gd` 中找到 `_print_summary()` 调用前，追加：

```gdscript
	# —— ContextCollector 感知字段扩展 ——
	var collector2 = ContextCollectorScript.new()
	add_child(collector2)

	# 未喂入时快照字段为空默认值
	var snap2: Dictionary = collector2.get_snapshot()
	_assert_equal(String(snap2.get("foreground_app", "x")), "", "collector_default_app_empty")
	_assert_equal(String(snap2.get("activity", "x")), "", "collector_default_activity_empty")

	# 喂入监测数据
	collector2.update_foreground("Code.exe", "coding")
	await get_tree().create_timer(0.12).timeout
	snap2 = collector2.get_snapshot()
	_assert_equal(String(snap2.get("foreground_app")), "Code.exe", "collector_app_reported")
	_assert_equal(String(snap2.get("activity")), "coding", "collector_activity_reported")
	_assert_true(float(snap2.get("activity_seconds", -1.0)) >= 0.1, "collector_seconds_accumulate")

	# 切换应用累计到 activity_totals
	collector2.update_foreground("chrome.exe", "browsing")
	await get_tree().create_timer(0.1).timeout
	snap2 = collector2.get_snapshot()
	var totals: Dictionary = snap2.get("activity_totals", {})
	_assert_true(float(totals.get("coding", 0.0)) >= 0.1, "coding_total_accumulated")
	_assert_equal(String(snap2.get("activity")), "browsing", "activity_switched")

	collector2.queue_free()
```

（若 test_smart_modules.gd 的 `_run` 不是 async 或无 `await` 支持，在其函数声明确认 `func _run() -> void:` 内已有 await；现有文件开头 `call_deferred("_run")` 模式支持。）

- [ ] **Step 2: 运行确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_smart_modules.tscn`
Expected: FAIL——`update_foreground` 方法不存在（SCRIPT ERROR）

- [ ] **Step 3: 实现 collector 扩展**

`context_collector.gd`：
1. 成员变量区（:12 附近）追加：

```gdscript
var _fg_app := ""
var _fg_activity := ""
var _fg_activity_started_at: float = 0.0
var _fg_last_update_unix: int = 0
var _activity_totals: Dictionary = {}  # activity -> 累计秒
```

2. `update_context`（:24）**之后**新增公开方法：

```gdscript
func update_foreground(app_name: String, activity: String) -> void:
	## 由外部（main/monitor 接线）喂入前台应用感知数据
	var now_ms := Time.get_unix_time_from_system()
	if _fg_activity_started_at > 0.0 and not _fg_activity.is_empty() and activity != _fg_activity:
		var elapsed := now_ms - _fg_last_update_unix
		if elapsed > 0:
			_activity_totals[_fg_activity] = float(_activity_totals.get(_fg_activity, 0.0)) + float(elapsed)
	_fg_app = app_name
	_fg_activity = activity
	_fg_last_update_unix = now_ms
	if _fg_activity_started_at <= 0.0:
		_fg_activity_started_at = now_ms
```

3. `get_snapshot()`（:69）返回字典追加三个键（放在 "state_change_count" 之后）：

```gdscript
		"foreground_app": _fg_app,
		"activity": _fg_activity,
		"activity_seconds": (Time.get_unix_time_from_system() - _fg_last_update_unix) if not _fg_activity.is_empty() else 0.0,
		"activity_totals": _activity_totals.duplicate(true)
```

- [ ] **Step 4: 跑全部六套测试**

Run: 六套 tscn 逐一跑（含 Task 1/2 新增两套）
Expected: 全部 `failed: 0`

- [ ] **Step 5: Commit**

```bash
git add context_collector.gd tests/test_smart_modules.gd
git commit -m "feat: 上下文采集器新增前台应用感知字段"
```

---

### Task 4: 感知开关与存档链路

设置键：`perception_enabled`（默认 **false**）、`perception_default_rules`（默认 true）。custom 规则表本期不做 UI 编辑（YAGNI），只留设置键与接线。

**Files:**
- Modify: `save_manager.gd`（:70 settings 写入段 + `_gather_current_data`）
- Modify: `customization_service.gd`
- Modify: `smart_pet_controller.gd`
- Test: `tests/test_smart_modules.gd`（追加断言）

- [ ] **Step 1: 写失败测试（追加）**

```gdscript
	# —— 感知设置链路 ——
	var custom2 = CustomizationServiceScript.new()
	custom2.apply_settings({"perception_enabled": true, "perception_default_rules": false})
	_assert_equal(bool(custom2.perception_enabled), true, "custom_perception_enabled")
	_assert_equal(bool(custom2.perception_default_rules), false, "custom_perception_defaults_off")
	var dict2: Dictionary = custom2.to_settings_dict()
	_assert_equal(bool(dict2.get("perception_enabled")), true, "dict_perception_enabled")
	custom2.queue_free()
```

（`CustomizationServiceScript` 常量若测试文件里没有，在文件头加 `const CustomizationServiceScript = preload("res://customization_service.gd")`。）

- [ ] **Step 2: 确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_smart_modules.tscn`
Expected: FAIL——`perception_enabled` 属性不存在

- [ ] **Step 3: 实现三处链路**

1. `customization_service.gd` 成员（:12 quiet_hours 附近）加：

```gdscript
var perception_enabled: bool = false
var perception_default_rules: bool = true
```

`apply_settings`（:19）加两行：

```gdscript
	perception_enabled = bool(settings.get("perception_enabled", perception_enabled))
	perception_default_rules = bool(settings.get("perception_default_rules", perception_default_rules))
```

`to_settings_dict()`（:39）加两键。

2. `save_manager.gd` `_write_config`（:70 附近）加：

```gdscript
	config.set_value("settings", "perception_enabled", settings.get("perception_enabled", false))
	config.set_value("settings", "perception_default_rules", settings.get("perception_default_rules", true))
```

`_gather_current_data`（:187）里 settings 快照同样补这两键（执行时读该函数内 settings 构造段，按现有键的模式加，默认值相同）。

3. `smart_pet_controller.gd`：`configure()`（:54）已把 settings 传给 `apply_settings`，无需改动；但 `get_settings_snapshot()` 需返回新键——`to_settings_dict` 补键后自动生效，验证即可。

- [ ] **Step 4: 跑 test_smart_modules + test_behavior_system**

Expected: `failed: 0`

- [ ] **Step 5: Commit**

```bash
git add save_manager.gd customization_service.gd tests/test_smart_modules.gd
git commit -m "feat: 感知开关设置键与存档链路"
```

---

### Task 5: 设置页"感知"分区

设置面板加分组：开关"感知前台应用（本地，默认关）"+ 说明文案 + "使用默认分类规则"开关。样式沿用现有 aurora 分区模式（SectionAI 前插入 SectionPerception）。

**Files:**
- Modify: `settings_panel.tscn`（SmartModeCheck 与 Sep3 之间插节点）
- Modify: `settings_panel.gd`

- [ ] **Step 1: tscn 加节点**

在 `settings_panel.tscn` 的 `[node name="Sep3" ...]` 之前插入（照抄 SectionAI 的 label 样式行，锚点结构一致）：

```
[node name="SectionPerception" type="Label" parent="ScrollContainer/VBoxContainer"]
offset_left = 16.0
offset_top = XXXX.0
offset_right = 344.0
offset_bottom = XXXX.0
theme_override_colors/font_color = Color(1, 0.85, 0.6, 1)
theme_override_font_sizes/font_size = 16
text = "感知"

[node name="PerceptionCheck" type="CheckBox" parent="ScrollContainer/VBoxContainer"]
offset_left = 16.0
offset_top = XXXX.0
offset_right = 344.0
offset_bottom = XXXX.0
text = "感知前台应用（仅进程名，本地使用）"

[node name="PerceptionDefaultRulesCheck" type="CheckBox" parent="ScrollContainer/VBoxContainer"]
offset_left = 16.0
offset_top = XXXX.0
offset_right = 344.0
offset_bottom = XXXX.0
text = "使用默认分类规则"
```

（**执行时 XXXX 用实际累加值**：VBoxContainer 子节点 offset 会被容器自动排布，照抄相邻 Sep3/SmartModeCheck 的 offset 差值递增即可；`load_steps` 数值 +0——不新增资源只加节点无需改。）

- [ ] **Step 2: settings_panel.gd 接线**

1. `@onready` 区（:13 附近）加：

```gdscript
@onready var perception_check: CheckBox = $ScrollContainer/VBoxContainer/PerceptionCheck
@onready var perception_default_rules_check: CheckBox = $ScrollContainer/VBoxContainer/PerceptionDefaultRulesCheck
```

2. 加载（:72 `smart_mode_check.button_pressed = ...` 后）：

```gdscript
	perception_check.button_pressed = bool(settings.get("perception_enabled", false))
	perception_default_rules_check.button_pressed = bool(settings.get("perception_default_rules", true))
```

3. 信号连接（:95 后）：

```gdscript
	perception_check.toggled.connect(_on_perception_toggled)
	perception_default_rules_check.toggled.connect(_on_perception_toggled)
```

4. 回调（放 `_on_smart_mode_toggled` 旁）：

```gdscript
func _on_perception_toggled(_enabled: bool) -> void:
	_apply_smart_settings()
	SaveManager.save_data()
```

5. `_apply_smart_settings()`（:343）的 configure 字典加两键：

```gdscript
		"perception_enabled": perception_check.button_pressed,
		"perception_default_rules": perception_default_rules_check.button_pressed,
```

- [ ] **Step 3: MCP 冒烟验证 UI**

Run: MCP `run_project` → `get_debug_output`
Expected: 无 SCRIPT ERROR；（设置面板需手动打开验证布局——headless 无法断言 UI，人工确认开关存在即可）

- [ ] **Step 4: 跑六套测试 + Commit**

```bash
git add settings_panel.tscn settings_panel.gd
git commit -m "feat: 设置页新增感知分区"
```

---

### Task 6: SMART 管线消费感知 + main 接线 + 端到端

三件事：① habit_profile_service 基于快照 `activity` 字段加标签（watching_video / coding_now / browsing_now）；② main.gd 创建 monitor 并接到 collector；③ MCP 端到端真机验证 PowerShell 采集源。

**Files:**
- Modify: `habit_profile_service.gd`（build_tags :22）
- Modify: `main.gd`（`_setup_smart_pet_controller` :283 附近）
- Test: `tests/test_smart_modules.gd`（追加）

- [ ] **Step 1: 写失败测试（追加）**

```gdscript
	# —— 活动标签 ——
	var profile2 = HabitProfileServiceScript.new()
	add_child(profile2)
	var snap3 := {
		"hour": 14, "typing_per_min": 5.0, "continuous_active_seconds": 60.0,
		"idle_seconds": 5.0, "activity": "video", "activity_seconds": 900.0
	}
	var tags3: Array[String] = profile2.build_tags(snap3, [])
	_assert_true(tags3.has("watching_video"), "tag_watching_video")

	snap3["activity"] = "coding"
	snap3["activity_seconds"] = 1200.0
	tags3 = profile2.build_tags(snap3, [])
	_assert_true(tags3.has("coding_now"), "tag_coding_now")

	# SMART 决策喂入含 activity 的快照不报错（管线兼容）
	var policy3 = ReactionPolicyEngineScript.new()
	add_child(policy3)
	var decision3: Dictionary = policy3.evaluate(
		{"hour": 14, "fullscreen": false, "continuous_active_seconds": 100.0, "activity": "video"},
		[], [], {"personality": "tsundere", "reminder_intensity": "medium"})
	_assert_true(decision3.has("react"), "policy_tolerates_activity_field")
	profile2.queue_free()
	policy3.queue_free()
```

（HabitProfileServiceScript / ReactionPolicyEngineScript 常量按测试文件头部现有 preload 补齐——执行时先 grep。）

- [ ] **Step 2: 确认失败**

Run: `timeout 60 "$GODOT" --headless --path . res://tests/test_smart_modules.tscn`
Expected: FAIL——`watching_video` 标签不存在

- [ ] **Step 3: 实现标签**

`habit_profile_service.gd` `build_tags`（:22）在 `if tags.is_empty():` 之前加：

```gdscript
	var activity := String(snapshot.get("activity", ""))
	var activity_seconds := float(snapshot.get("activity_seconds", 0.0))
	if activity == "video" and activity_seconds >= 600.0:
		tags.append("watching_video")
	elif activity == "coding" and activity_seconds >= 600.0:
		tags.append("coding_now")
	elif activity == "browsing" and activity_seconds >= 600.0:
		tags.append("browsing_now")
```

- [ ] **Step 4: main.gd 接线**

`_setup_smart_pet_controller(settings)`（:283）末尾追加：

```gdscript
	# 感知接线：monitor → collector（经 controller）
	if settings.get("perception_enabled", false):
		_setup_perception(settings)

func _setup_perception(settings: Dictionary) -> void:
	if foreground_app_monitor:
		return
	foreground_app_monitor = ForegroundAppMonitor.new()
	foreground_app_monitor.name = "ForegroundAppMonitor"
	add_child(foreground_app_monitor)
	foreground_app_monitor.enabled = true
	var use_defaults := bool(settings.get("perception_default_rules", true))
	foreground_app_monitor.set_rules([], use_defaults)
	foreground_app_monitor.foreground_app_changed.connect(_on_foreground_app_changed)

func _on_foreground_app_changed(app_name: String, activity: String) -> void:
	if smart_pet_controller and smart_pet_controller._context_collector:
		smart_pet_controller._context_collector.update_foreground(app_name, activity)
```

成员变量区加 `var foreground_app_monitor`（`var smart_pet_controller` 旁）。

- [ ] **Step 5: 全量测试 + MCP 端到端（真机验证 PowerShell 源）**

1. 六套测试全绿
2. MCP `run_project`，等待 15 秒（覆盖数次轮询）
3. `get_debug_output`：无 ERROR；为验证采集，在 `_on_foreground_app_changed` 首次触发时打印一行（`if _last_fg_log_unix == 0: print("[Perception] foreground: ", app_name, " -> ", activity)`，加成员 `var _last_fg_log_unix := 0` 并在打印后置 `Time.get_unix_time_from_system()`）——**真机跑通后移除该 print 再提交**
4. 验证 PowerShell 源：若 `[Perception]` 行 60 秒内未出现，按 Task 3 注记排查脚本（优先换两段式查询）；修好再继续
5. 渲染验证：截图 + 橙色像素聚类（复用 P1 验证流程）

- [ ] **Step 6: 移除调试打印 + 最终提交**

```bash
git add habit_profile_service.gd main.gd tests/test_smart_modules.gd
git commit -m "feat: SMART 管线接入前台应用感知"
```

设计文档追加 "P2 完成记录" 小节（实际 PowerShell 脚本方案、验证输出摘录）。

---

## 自检记录（Self-Review）

1. **Spec 覆盖**：ForegroundAppMonitor（Task 2）、活动分类器+用户规则（Task 1）、ContextCollector 扩展（Task 3）、设置页感知分区+开关（Task 5）、存档链路（Task 4）、SMART 消费（Task 6）。设计文档"感知升级"节全覆盖；自定义规则 UI 编辑明确排除（YAGNI，P4 再议）。
2. **占位符**：Task 5 tscn 的 offset XXXX 是"照抄相邻节点差值"的机械指令；Task 2 PowerShell 脚本标注允许真机微调但接口锁定——均为有界执行细节，非未设计内容。
3. **类型一致性**：`classify(process_name, custom_rules, use_defaults)` / `set_source` / `set_rules(custom_rules, use_defaults)` / `update_foreground(app_name, activity)` / `get_snapshot().{app,activity,activity_seconds,history}` 各任务间签名一致；Task 3 测试引用的键名与 Task 3 实现的快照键一致。
