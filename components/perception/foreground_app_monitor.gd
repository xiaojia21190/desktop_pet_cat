class_name ForegroundAppMonitor
extends Node

## 前台应用监测：轮询前台进程名 → 活动分类 → 快照。
## 隐私：默认关闭；只取进程名（不读窗口标题）；数据仅本地消费。
## Windows 实现走 PowerShell 后台线程；测试注入假源（set_source）。

signal foreground_app_changed(app_name: String, activity: String)

const MAX_HISTORY := 60
const UNKNOWN := "unknown"
const POLL_TIMEOUT_FALLBACK := 15.0  # 后台线程超过此秒数未响应则视为 unknown

@export var enabled: bool = false:
	set(value):
		enabled = value
		if not value:
			_current_app = ""
			_current_activity = ""
			_activity_seconds = 0.0
@export var poll_interval: float = 5.0
## headless/测试环境置 false，不挂系统采集源
@export var use_system_source: bool = true

var _source  # 采集源：query() -> String（进程名），失败返回空
var _thread: Thread
var _thread_result: String = ""
var _thread_busy := false
var _thread_started_unix: int = 0
var _timer: float = 0.0
var _current_app := ""
var _current_activity := ""
var _activity_seconds: float = 0.0
var _last_change_unix: int = 0
var _history: Array[Dictionary] = []  # [{app, activity, started_unix}]
var _custom_rules: Array[Dictionary] = []
var _use_default_rules := true

func _ready() -> void:
	if use_system_source and OS.get_name() == "Windows":
		_source = PowerShellSource.new()

func _exit_tree() -> void:
	_join_thread()

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
	_process_thread_result()
	if _timer < poll_interval:
		return

	_timer = 0.0
	if bool(_source.get("is_slow")):
		_collect_via_thread()
	else:
		_apply_app_name(String(_source.query()))

func _collect_via_thread() -> void:
	# 慢源（PowerShell 约 1.1 秒）在后台线程执行，不阻塞主线程
	if _thread_busy:
		var elapsed := Time.get_unix_time_from_system() - _thread_started_unix
		if elapsed > POLL_TIMEOUT_FALLBACK:
			_apply_app_name(UNKNOWN)
			_thread_busy = false
			_join_thread()
		return

	_join_thread()
	_thread_result = ""
	_thread_busy = true
	_thread_started_unix = Time.get_unix_time_from_system()
	_thread = Thread.new()
	var source = _source
	_thread.start(func() -> void:
		_thread_result = source.query()
	, Thread.PRIORITY_LOW)

func _process_thread_result() -> void:
	# 每帧检查线程是否完成（结果经 _thread_result 传递）
	if not _thread_busy:
		return
	if _thread and _thread.is_started():
		return  # 仍在跑，下帧再看
	_finish_thread_cycle()

func _finish_thread_cycle() -> void:
	_thread_busy = false
	_apply_app_name(_thread_result)

func _join_thread() -> void:
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	_thread = null

func _apply_app_name(app_name: String) -> void:
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
			"started_unix": _last_change_unix
		})
		if _history.size() > MAX_HISTORY:
			_history.pop_front()

	_current_app = app_name
	_current_activity = ActivityClassifier.classify(app_name, _custom_rules, _use_default_rules)
	_activity_seconds = 0.0
	_last_change_unix = now
	foreground_app_changed.emit(app_name, _current_activity)

## Windows 前台进程采集：GetForegroundWindow 句柄 → 主窗口进程。
## 只取进程名；不读窗口标题。真机实测约 1.1 秒，只在后台线程运行。
class PowerShellSource:
	extends RefCounted

	const is_slow := true
	const PS_SCRIPT := "$src = @'\nusing System;\nusing System.Runtime.InteropServices;\npublic static class U32 {\n    [DllImport(\"user32.dll\")] public static extern IntPtr GetForegroundWindow();\n}\n'@; Add-Type -TypeDefinition $src; $hwnd = [U32]::GetForegroundWindow(); if ($hwnd -ne [IntPtr]::Zero) { $p = Get-Process | Where-Object { $_.MainWindowHandle -eq $hwnd } | Select-Object -First 1; if ($p) { $p.ProcessName } }"

	func query() -> String:
		var output := []
		var exit_code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command", PS_SCRIPT], output, true)
		if exit_code != 0 or output.is_empty():
			return ""
		return String(output[0]).strip_edges()
