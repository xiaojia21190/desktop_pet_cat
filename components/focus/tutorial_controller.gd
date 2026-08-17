class_name FocusTutorialController
extends Node

## 专注会话新手教程：按步骤时长推进，通过 set_text 回调写文案。纯逻辑，无 UI。

var active: bool = false

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
	if _steps.is_empty():
		return ""
	var step := _steps[_index]
	return "[Guide] " + String(step.get("text", ""))

func _current_duration() -> float:
	if _steps.is_empty():
		return 0.0
	var step := _steps[_index]
	return float(step.get("duration", 4.0))

static func default_steps() -> Array[Dictionary]:
	return [
		{"text": "Goal: survive for 30 minutes without focus collapse.", "duration": 4.0},
		{"text": "Typing attacks reduce Focus and increase Chaos.", "duration": 4.0},
		{"text": "Use items from the menu to calm the cat.", "duration": 4.0},
		{"text": "Complete objective cards for bonus recovery.", "duration": 4.0}
	]
