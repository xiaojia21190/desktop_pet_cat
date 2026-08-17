class_name CatIgnoringState
extends CatStateBase

## 昂首无视状态

@export var ignore_duration: float = 3.0

var _timer: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	play_animation("retreat")
	_timer = 0.0
	# 背对鼠标
	var mouse_pos := get_mouse_position()
	if cat:
		face_direction(-(mouse_pos.x - cat.global_position.x))

func update(delta: float) -> void:
	_timer += delta
	if _timer >= ignore_duration:
		transition_to(CatStates.IDLE)
