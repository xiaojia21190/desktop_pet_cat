class_name ForegroundAppMonitor
extends Node

## 前台应用监测：轮询前台进程名 → 活动分类 → 快照。
## 隐私：默认关闭；只取进程名（不读窗口标题）；数据仅本地消费。
## Windows 实现：PowerShell 经 execute_with_pipe 非阻塞管道（-EncodedCommand）；测试注入假源。

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
var _pipe_stdio = null  # 非阻塞管道的 FileAccess（慢源）
var _pipe_pid := -1
var _pipe_buffer := ""
var _pipe_started_unix: int = 0
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
	if _pipe_pid > 0 and OS.is_process_running(_pipe_pid):
		OS.kill(_pipe_pid)
	_pipe_pid = -1
	_pipe_stdio = null

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
	# 在途管道吸数据（慢源状态机）
	if _pipe_pid > 0:
		_poll_pipe()
	if _timer < poll_interval:
		return

	_timer = 0.0
	if bool(_source.get("is_slow")):
		_poll_pipe()
	else:
		_apply_app_name(String(_source.query()))

func _poll_pipe() -> void:
	# 慢源（PowerShell 约 1 秒）：管道轮询状态机
	# 状态1：无在途进程 → 发起新采集
	if _pipe_pid <= 0:
		var result: Dictionary = _source.launch()
		if result.is_empty():
			_apply_app_name(UNKNOWN)
			return
		_pipe_stdio = result.get("stdio")
		_pipe_pid = int(result.get("pid", -1))
		_pipe_buffer = ""
		_pipe_started_unix = int(Time.get_unix_time_from_system())
		return

	# 状态2：在途 → 每帧吸走 stdout；退出即完成
	if _pipe_stdio and _pipe_stdio.is_open():
		while true:
			var chunk: PackedByteArray = _pipe_stdio.get_buffer(4096)
			if chunk.size() == 0:
				break
			_pipe_buffer += chunk.get_string_from_utf8()
	if OS.is_process_running(_pipe_pid) == false:
		var app_name := _pipe_buffer.strip_edges()
		_pipe_pid = -1
		_pipe_stdio = null
		_apply_app_name(app_name)
		return

	# 超时保护：进程卡死则杀掉并降级
	if Time.get_unix_time_from_system() - _pipe_started_unix > POLL_TIMEOUT_FALLBACK:
		OS.kill(_pipe_pid)
		_pipe_pid = -1
		_pipe_stdio = null
		_apply_app_name(UNKNOWN)

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
	var now := int(Time.get_unix_time_from_system())
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

	## Add-Type 单行 MemberDefinition：GetForegroundWindow → 主窗口进程名
	const PS_SCRIPT := """Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();' -Name U32 -Namespace Win32
$hwnd = [Win32.U32]::GetForegroundWindow()
if ($hwnd -ne [IntPtr]::Zero) { $p = Get-Process | Where-Object { $_.MainWindowHandle -eq $hwnd } | Select-Object -First 1
if ($p) { Write-Output $p.ProcessName } }"""

	static func encode_command(script: String) -> String:
		## PowerShell -EncodedCommand 要求 UTF-16LE 的 Base64（规避多层引号转义）
		return Marshalls.raw_to_base64(script.to_utf16_buffer())

	func launch() -> Dictionary:
		## 非阻塞启动采集：返回 {stdio, pid}，调用方每帧轮询 stdio
		var encoded: String = encode_command(PS_SCRIPT)
		return OS.execute_with_pipe(
			"powershell.exe",
			["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded],
			false)

	func query() -> String:
		## 阻塞式兼容接口（仅调试路径）；正常流程走 launch + 轮询
		var output := []
		var encoded: String = encode_command(PS_SCRIPT)
		var exit_code := OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-EncodedCommand", encoded], output, true)
		if exit_code != 0 or output.is_empty():
			return ""
		return String(output[0]).strip_edges()
