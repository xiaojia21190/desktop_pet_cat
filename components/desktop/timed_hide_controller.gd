class_name TimedHideController
extends Node

## 定时隐藏控制器：到点自动隐藏宠物窗口
## 从 main.gd 拆出的自包含块；可见性切换与事件上报经回调注入

signal hide_timeout  ## 定时到点，main 负责隐藏窗口与记录事件
signal option_changed(option_index: int)  ## 选项变化（超时归零时同步面板）

const DURATIONS := [0, 15 * 60, 30 * 60, 60 * 60, 120 * 60]

var option_index := 0
var end_time := 0

var _timer: Timer
var _on_save_requested: Callable  ## main 注入：超时后触发存档

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_on_timeout)
	add_child(_timer)

func bind_save_request(callback: Callable) -> void:
	_on_save_requested = callback

func apply_settings(settings: Dictionary) -> void:
	var index = int(settings.get("timed_hide_option", 0))
	var saved_end = int(settings.get("timed_hide_end_time", 0))
	if _duration_of(index) <= 0:
		_reset()
		return
	var remaining = saved_end - Time.get_unix_time_from_system()
	if remaining <= 0:
		_reset()
		return
	option_index = index
	end_time = saved_end
	_start(float(remaining))

func select_option(index: int) -> void:
	var duration = _duration_of(index)
	if duration <= 0:
		_reset()
		return
	option_index = index
	end_time = int(Time.get_unix_time_from_system()) + duration
	_start(float(duration))

func get_remaining_seconds() -> int:
	if end_time <= 0:
		return 0
	return maxi(int(end_time - Time.get_unix_time_from_system()), 0)

func get_save_data() -> Dictionary:
	return {
		"timed_hide_option": option_index,
		"timed_hide_end_time": end_time
	}

func _start(duration_seconds: float) -> void:
	if not _timer:
		return
	_timer.stop()
	_timer.wait_time = duration_seconds
	_timer.start()

func _reset() -> void:
	option_index = 0
	end_time = 0
	if _timer:
		_timer.stop()

func _duration_of(index: int) -> int:
	if index < 0 or index >= DURATIONS.size():
		return 0
	return DURATIONS[index]

func _on_timeout() -> void:
	end_time = 0
	var had_option := option_index != 0
	if had_option:
		option_index = 0
		option_changed.emit(option_index)
		if _on_save_requested.is_valid():
			_on_save_requested.call()
	hide_timeout.emit()
