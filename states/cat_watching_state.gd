class_name CatWatchingState
extends CatStateBase

## 注视鼠标状态

@export var watch_duration: float = 2.0

var _timer: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	play_animation("watch_focus")
	_timer = 0.0

func update(delta: float) -> void:
	_timer += delta
	face_toward(get_mouse_position())

	if _timer >= watch_duration:
		transition_to(CatStates.IDLE)
