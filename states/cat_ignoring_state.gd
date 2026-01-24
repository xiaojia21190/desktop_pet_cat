class_name CatIgnoringState
extends CatStateBase

## 昂首无视状态

@export var ignore_duration: float = 3.0

var _timer: float = 0.0

func enter(_msg: Dictionary = {}) -> void:
	play_animation("idle_stand")
	_timer = 0.0

func update(delta: float) -> void:
	_timer += delta

	# 朝向远离鼠标的方向
	var mouse_pos := get_mouse_position()
	var away_direction := (cat.global_position - mouse_pos).normalized()
	cat.look_at(cat.global_position + away_direction * 100)

	if _timer >= ignore_duration:
		transition_to(CatStates.IDLE)
